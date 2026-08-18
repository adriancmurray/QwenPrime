import Foundation
import Darwin
import QwenPrimeCommandProtocol

public enum BoundedProcessRunner {
    private enum WaitOutcome: Sendable {
        case exited
        case timedOut
    }

    public static func run(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        timeoutSeconds: Double,
        maxOutputBytes: Int,
        environment: [String: String] = WorkspaceCommandPolicy.sanitizedEnvironment()
    ) async throws -> CommandExecutionResponse {
        guard timeoutSeconds > 0, timeoutSeconds <= 60,
              maxOutputBytes > 0, maxOutputBytes <= 1_048_576 else {
            throw CommandPolicyError.limitsExceeded
        }

        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let budget = SharedOutputBudget(maxBytes: maxOutputBytes)
        let stdout = OutputAccumulator()
        let stderr = OutputAccumulator()
        let termination = ProcessTerminationState()

        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let startedAt = Date()
        try process.run()
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        let stdoutTask = Task.detached {
            drain(stdoutPipe.fileHandleForReading, into: stdout, budget: budget) {
                terminate(process)
            }
        }
        let stderrTask = Task.detached {
            drain(stderrPipe.fileHandleForReading, into: stderr, budget: budget) {
                terminate(process)
            }
        }

        let outcome = await withTaskCancellationHandler {
            await withTaskGroup(of: WaitOutcome.self) { group in
                group.addTask {
                    process.waitUntilExit()
                    return .exited
                }
                group.addTask {
                    try? await Task.sleep(for: .seconds(timeoutSeconds))
                    guard !Task.isCancelled else { return .exited }
                    termination.markTimedOut()
                    terminate(process)
                    return .timedOut
                }
                let first = await group.next() ?? .exited
                group.cancelAll()
                return first
            }
        } onCancel: {
            termination.markCancelled()
            terminate(process)
        }

        _ = await stdoutTask.result
        _ = await stderrTask.result
        try Task.checkCancellation()

        return CommandExecutionResponse(
            id: UUID(),
            exitCode: process.terminationStatus,
            stdout: stdout.string,
            stderr: stderr.string,
            outputTruncated: budget.wasTruncated,
            timedOut: outcome == .timedOut || termination.timedOut,
            cancelled: termination.cancelled,
            durationSeconds: Date().timeIntervalSince(startedAt),
            errorMessage: nil
        )
    }

    private static func drain(
        _ handle: FileHandle,
        into accumulator: OutputAccumulator,
        budget: SharedOutputBudget,
        onLimit: @Sendable () -> Void
    ) {
        while true {
            let data = handle.readData(ofLength: 4096)
            if data.isEmpty { return }
            let accepted = budget.accept(data)
            accumulator.append(accepted)
            if accepted.count < data.count {
                onLimit()
            }
        }
    }

    private static func terminate(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        Task.detached {
            try? await Task.sleep(for: .seconds(1))
            if process.isRunning {
                _ = Darwin.kill(pid, SIGKILL)
            }
        }
    }
}

private final class ProcessTerminationState: @unchecked Sendable {
    private let lock = NSLock()
    private var _timedOut = false
    private var _cancelled = false

    func markTimedOut() { lock.withLock { _timedOut = true } }
    func markCancelled() { lock.withLock { _cancelled = true } }
    var timedOut: Bool { lock.withLock { _timedOut } }
    var cancelled: Bool { lock.withLock { _cancelled } }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private final class SharedOutputBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: Int
    private var truncated = false

    init(maxBytes: Int) {
        self.remaining = maxBytes
    }

    func accept(_ data: Data) -> Data {
        lock.lock()
        defer { lock.unlock() }
        guard remaining > 0 else {
            truncated = true
            return Data()
        }
        let count = min(remaining, data.count)
        remaining -= count
        if count < data.count { truncated = true }
        return data.prefix(count)
    }

    var wasTruncated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return truncated
    }
}

private final class OutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: data, as: UTF8.self)
    }
}
