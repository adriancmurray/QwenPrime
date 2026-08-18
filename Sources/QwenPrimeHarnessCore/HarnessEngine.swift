import Foundation
import Darwin
import QwenPrimeCommandCore
import QwenPrimeHarnessProtocol

public struct HarnessProcessInvocation: Sendable, Equatable {
    public let executableURL: URL
    public let arguments: [String]
    public let workingDirectory: URL
    public let environment: [String: String]
    public let timeoutSeconds: Double
    public let maxOutputBytes: Int

    public init(
        executableURL: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        timeoutSeconds: Double,
        maxOutputBytes: Int
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
        self.maxOutputBytes = maxOutputBytes
    }
}

public struct HarnessProcessResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let outputTruncated: Bool
    public let durationSeconds: Double

    public init(
        exitCode: Int32,
        stdout: String,
        stderr: String,
        outputTruncated: Bool,
        durationSeconds: Double
    ) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.outputTruncated = outputTruncated
        self.durationSeconds = durationSeconds
    }
}

public protocol HarnessProcessRunning: Sendable {
    func run(_ invocation: HarnessProcessInvocation) async throws -> HarnessProcessResult
}

public struct FoundationHarnessProcessRunner: HarnessProcessRunning {
    public init() {}

    public func run(_ invocation: HarnessProcessInvocation) async throws -> HarnessProcessResult {
        let response = try await BoundedProcessRunner.run(
            executableURL: invocation.executableURL,
            arguments: invocation.arguments,
            workingDirectory: invocation.workingDirectory,
            timeoutSeconds: invocation.timeoutSeconds,
            maxOutputBytes: invocation.maxOutputBytes,
            environment: invocation.environment
        )
        return HarnessProcessResult(
            exitCode: response.exitCode,
            stdout: response.stdout,
            stderr: response.stderr,
            outputTruncated: response.outputTruncated,
            durationSeconds: response.durationSeconds
        )
    }
}

public struct HarnessEngine: Sendable {
    private static let capabilities: [HarnessCapability] = [
        .selfTest, .swiftBuild, .swiftTest
    ]

    private let expectedCredential: String
    private let processRunner: any HarnessProcessRunning

    public init(
        expectedCredential: String,
        processRunner: any HarnessProcessRunning = FoundationHarnessProcessRunner()
    ) {
        self.expectedCredential = expectedCredential
        self.processRunner = processRunner
    }

    public func handle(_ request: HarnessRequest) async -> HarnessResponse {
        guard request.protocolVersion == HarnessProtocolVersion.current else {
            return failure(request, status: .rejected, error: "Unsupported harness protocol version.")
        }
        guard request.credential.matches(expectedCredential) else {
            return failure(request, status: .rejected, error: "Harness credential rejected.")
        }

        let startedAt = Date()
        do {
            let taskRoot = try validateTaskRoot(request.taskRoot)
            let operation = try prepareOperation(request, taskRoot: taskRoot)
            defer { try? operation.cleanupURL.map(FileManager.default.removeItem) }

            let context = try SwiftTaskExecutionContext.create(
                id: request.requestID,
                temporaryRoot: taskRoot.appendingPathComponent(
                    "QwenPrimeCommandTasks",
                    isDirectory: true
                )
            )
            defer { try? context.remove() }

            let swiftURL = try WorkspaceCommandPolicy.executableURL(for: "swift")
            let environment = context.environment(
                base: try WorkspaceCommandPolicy.swiftTaskEnvironment(
                    executableURL: swiftURL,
                    base: WorkspaceCommandPolicy.sanitizedEnvironment()
                )
            )
            let swiftArguments = try WorkspaceCommandPolicy.launchArguments(
                command: "swift",
                arguments: operation.arguments,
                scratchPath: context.scratchURL.path
            )
            let result = try await processRunner.run(HarnessProcessInvocation(
                executableURL: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),
                arguments: [
                    "-p", HarnessSeatbeltProfile.make(taskRoot: taskRoot),
                    swiftURL.path
                ] + swiftArguments,
                workingDirectory: operation.workingDirectory,
                environment: environment,
                timeoutSeconds: 180,
                maxOutputBytes: 64 * 1024
            ))
            let succeeded = result.exitCode == 0
            return HarnessResponse(
                protocolVersion: HarnessProtocolVersion.current,
                requestID: request.requestID,
                status: request.operation == .selfTest && succeeded
                    ? .ready
                    : (succeeded ? .completed : .failed),
                capabilities: succeeded ? Self.capabilities : [],
                exitCode: result.exitCode,
                stdout: sanitize(result.stdout, taskRoot: taskRoot),
                stderr: sanitize(result.stderr, taskRoot: taskRoot),
                outputTruncated: result.outputTruncated,
                durationSeconds: result.durationSeconds,
                error: succeeded ? nil : "Harness operation failed."
            )
        } catch {
            return HarnessResponse(
                protocolVersion: HarnessProtocolVersion.current,
                requestID: request.requestID,
                status: .failed,
                capabilities: [],
                exitCode: nil,
                stdout: "",
                stderr: "",
                outputTruncated: false,
                durationSeconds: Date().timeIntervalSince(startedAt),
                error: sanitize(error.localizedDescription, taskRoot: nil)
            )
        }
    }

    private struct PreparedOperation {
        let arguments: [String]
        let workingDirectory: URL
        let cleanupURL: URL?
    }

    private func prepareOperation(
        _ request: HarnessRequest,
        taskRoot: URL
    ) throws -> PreparedOperation {
        switch request.operation {
        case .selfTest:
            let fixtureRoot = taskRoot
                .appendingPathComponent("HarnessSelfTest", isDirectory: true)
                .appendingPathComponent(request.requestID.uuidString, isDirectory: true)
            try createSelfTestFixture(at: fixtureRoot)
            return PreparedOperation(
                arguments: ["test"],
                workingDirectory: fixtureRoot,
                cleanupURL: fixtureRoot
            )
        case .swiftBuild:
            guard request.filter == nil else {
                throw CommandPolicyError.invalidArguments("swift_build does not accept a filter")
            }
            return PreparedOperation(
                arguments: ["build"],
                workingDirectory: try validateWorkingDirectory(
                    request.workingDirectory,
                    taskRoot: taskRoot
                ),
                cleanupURL: nil
            )
        case .swiftTest:
            let arguments = request.filter.map { ["test", "--filter", $0] } ?? ["test"]
            try WorkspaceCommandPolicy.validate(command: "swift", arguments: arguments)
            return PreparedOperation(
                arguments: arguments,
                workingDirectory: try validateWorkingDirectory(
                    request.workingDirectory,
                    taskRoot: taskRoot
                ),
                cleanupURL: nil
            )
        }
    }

    private func validateTaskRoot(_ path: String) throws -> URL {
        guard !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw CommandPolicyError.pathEscape(path)
        }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        var info = stat()
        guard lstat(url.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR else {
            throw CommandPolicyError.invalidArguments("task root is not a regular directory")
        }
        return url.resolvingSymlinksInPath()
    }

    private func validateWorkingDirectory(_ path: String, taskRoot: URL) throws -> URL {
        guard !path.hasPrefix("/"),
              !path.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            throw CommandPolicyError.pathEscape(path)
        }
        let candidate = taskRoot.appendingPathComponent(path, isDirectory: true)
            .standardizedFileURL.resolvingSymlinksInPath()
        guard candidate.path == taskRoot.path || candidate.path.hasPrefix(taskRoot.path + "/") else {
            throw CommandPolicyError.pathEscape(path)
        }
        var info = stat()
        guard lstat(candidate.path, &info) == 0,
              info.st_mode & S_IFMT == S_IFDIR else {
            throw CommandPolicyError.invalidArguments("working directory not found")
        }
        return candidate
    }

    private func createSelfTestFixture(at root: URL) throws {
        let source = root.appendingPathComponent("Sources/HarnessProbe", isDirectory: true)
        let tests = root.appendingPathComponent("Tests/HarnessProbeTests", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tests, withIntermediateDirectories: true)
        try """
        // swift-tools-version: 6.0
        import PackageDescription
        let package = Package(name: "HarnessProbe", targets: [
            .target(name: "HarnessProbe"),
            .testTarget(name: "HarnessProbeTests", dependencies: ["HarnessProbe"])
        ])
        """.write(to: root.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        try "public func harnessProbe() -> Int { 42 }\n".write(
            to: source.appendingPathComponent("HarnessProbe.swift"),
            atomically: true,
            encoding: .utf8
        )
        try """
        import Testing
        @testable import HarnessProbe
        @Test func harnessSelfTest() { #expect(harnessProbe() == 42) }
        """.write(
            to: tests.appendingPathComponent("HarnessProbeTests.swift"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func sanitize(_ value: String, taskRoot: URL?) -> String {
        guard let taskRoot else { return value }
        return value.replacingOccurrences(of: taskRoot.path, with: "<task_root>")
    }

    private func failure(
        _ request: HarnessRequest,
        status: HarnessResponseStatus,
        error: String
    ) -> HarnessResponse {
        HarnessResponse(
            protocolVersion: HarnessProtocolVersion.current,
            requestID: request.requestID,
            status: status,
            capabilities: [],
            exitCode: nil,
            stdout: "",
            stderr: "",
            outputTruncated: false,
            durationSeconds: 0,
            error: error
        )
    }
}
