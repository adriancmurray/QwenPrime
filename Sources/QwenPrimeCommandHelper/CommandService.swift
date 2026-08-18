import Foundation
import QwenPrimeCommandCore
import QwenPrimeCommandProtocol

final class CommandService: NSObject, QwenPrimeCommandServiceProtocol, @unchecked Sendable {
    private let registry = CommandTaskRegistry()

    func executeCommand(
        requestData: Data,
        withReply reply: @escaping @Sendable (Data) -> Void
    ) {
        let request: CommandExecutionRequest
        do {
            request = try JSONDecoder().decode(CommandExecutionRequest.self, from: requestData)
        } catch {
            reply(Self.encodeFailure(id: UUID(), message: "Malformed command request."))
            return
        }

        registry.start(id: request.id) {
            let response = await Self.execute(request)
            reply((try? JSONEncoder().encode(response)) ?? Self.encodeFailure(
                id: request.id,
                message: "Could not encode command response."
            ))
        }
    }

    func cancelCommand(
        id: UUID,
        withReply reply: @escaping @Sendable (Bool) -> Void
    ) {
        reply(registry.cancel(id))
    }

    private static func execute(
        _ request: CommandExecutionRequest
    ) async -> CommandExecutionResponse {
        let startedAt = Date()
        do {
            try WorkspaceCommandPolicy.validate(
                command: request.command,
                arguments: request.arguments
            )
            guard request.timeoutSeconds > 0, request.timeoutSeconds <= 60,
                  request.maxOutputBytes > 0, request.maxOutputBytes <= 1_048_576 else {
                throw CommandPolicyError.limitsExceeded
            }

            var isStale = false
            let rootURL = try URL(
                resolvingBookmarkData: request.workspaceBookmark,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            _ = isStale
            defer {
                rootURL.stopAccessingSecurityScopedResource()
            }

            let workingDirectory = try resolveWorkingDirectory(
                rootURL: rootURL,
                relativePath: request.workingDirectory
            )
            let rawResult = try await BoundedProcessRunner.run(
                executableURL: try WorkspaceCommandPolicy.executableURL(for: request.command),
                arguments: request.arguments,
                workingDirectory: workingDirectory,
                timeoutSeconds: request.timeoutSeconds,
                maxOutputBytes: request.maxOutputBytes
            )
            return CommandExecutionResponse(
                id: request.id,
                exitCode: rawResult.exitCode,
                stdout: rawResult.stdout,
                stderr: rawResult.stderr,
                outputTruncated: rawResult.outputTruncated,
                timedOut: rawResult.timedOut,
                cancelled: rawResult.cancelled,
                durationSeconds: rawResult.durationSeconds,
                errorMessage: rawResult.errorMessage
            )
        } catch is CancellationError {
            return CommandExecutionResponse(
                id: request.id,
                exitCode: -1,
                stdout: "",
                stderr: "",
                outputTruncated: false,
                timedOut: false,
                cancelled: true,
                durationSeconds: Date().timeIntervalSince(startedAt),
                errorMessage: "Command cancelled."
            )
        } catch {
            return failure(
                id: request.id,
                message: error.localizedDescription,
                startedAt: startedAt
            )
        }
    }

    private static func resolveWorkingDirectory(
        rootURL: URL,
        relativePath: String
    ) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.utf8.contains(0) else {
            throw CommandPolicyError.pathEscape(relativePath)
        }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard !components.contains("..") else {
            throw CommandPolicyError.pathEscape(relativePath)
        }

        let resolvedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = components.reduce(resolvedRoot) { url, component in
            url.appendingPathComponent(String(component), isDirectory: true)
        }.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = resolvedRoot.path
        guard candidate.path == rootPath || candidate.path.hasPrefix(rootPath + "/") else {
            throw CommandPolicyError.pathEscape(relativePath)
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(
            atPath: candidate.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue else {
            throw CommandPolicyError.invalidArguments("working directory not found")
        }
        return candidate
    }

    private static func failure(
        id: UUID,
        message: String,
        startedAt: Date
    ) -> CommandExecutionResponse {
        CommandExecutionResponse(
            id: id,
            exitCode: -1,
            stdout: "",
            stderr: "",
            outputTruncated: false,
            timedOut: false,
            cancelled: false,
            durationSeconds: Date().timeIntervalSince(startedAt),
            errorMessage: message
        )
    }

    private static func encodeFailure(id: UUID, message: String) -> Data {
        let response = failure(id: id, message: message, startedAt: Date())
        return (try? JSONEncoder().encode(response)) ?? Data()
    }
}

private final class CommandTaskRegistry: @unchecked Sendable {
    private struct Entry {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let lock = NSLock()
    private var tasks: [UUID: Entry] = [:]

    func start(
        id: UUID,
        operation: @escaping @Sendable () async -> Void
    ) {
        lock.lock()
        let token = UUID()
        let task = Task { [weak self] in
            await operation()
            self?.remove(id, token: token)
        }
        let previous = tasks.updateValue(Entry(token: token, task: task), forKey: id)
        lock.unlock()
        previous?.task.cancel()
    }

    private func remove(_ id: UUID, token: UUID) {
        lock.lock()
        if tasks[id]?.token == token {
            tasks.removeValue(forKey: id)
        }
        lock.unlock()
    }

    func cancel(_ id: UUID) -> Bool {
        lock.lock()
        let task = tasks.removeValue(forKey: id)?.task
        lock.unlock()
        task?.cancel()
        return task != nil
    }
}
