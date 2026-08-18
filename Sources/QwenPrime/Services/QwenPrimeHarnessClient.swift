import Foundation
import OSLog
import QwenPrimeCommandCore
import QwenPrimeHarnessProtocol

public struct HarnessClientInvocation: Sendable, Equatable {
    public let harnessURL: URL
    public let request: HarnessRequest
    public let environment: [String: String]

    public init(
        harnessURL: URL,
        request: HarnessRequest,
        environment: [String: String]
    ) {
        self.harnessURL = harnessURL
        self.request = request
        self.environment = environment
    }
}

public protocol HarnessClientProcessRunning: Sendable {
    func run(_ invocation: HarnessClientInvocation) async throws -> Data
}

public protocol QwenPrimeHarnessServing: Sendable {
    func isReady() async -> Bool
    func run(
        operation: HarnessOperation,
        taskRoot: URL,
        workingDirectory: String,
        filter: String?
    ) async throws -> HarnessResponse
}

public struct FoundationHarnessClientProcessRunner: HarnessClientProcessRunning {
    public init() {}

    public func run(_ invocation: HarnessClientInvocation) async throws -> Data {
        var input = try JSONEncoder().encode(invocation.request)
        input.append(0x0A)
        let result = try await BoundedProcessRunner.run(
            executableURL: invocation.harnessURL,
            arguments: [],
            workingDirectory: invocation.request.taskRoot.isEmpty
                ? FileManager.default.temporaryDirectory
                : URL(fileURLWithPath: invocation.request.taskRoot, isDirectory: true),
            timeoutSeconds: 190,
            maxOutputBytes: 1024 * 1024,
            standardInput: input,
            environment: invocation.environment
        )
        guard result.exitCode == 0 else {
            throw WorkspaceCommandClientError.transportFailure(
                result.stderr.isEmpty ? "QwenPrimeHarness exited with \(result.exitCode)." : result.stderr
            )
        }
        return Data(result.stdout.utf8)
    }
}

public actor QwenPrimeHarnessClient {
    private static let logger = Logger(
        subsystem: "app.dech.qwenprime",
        category: "workspace-harness"
    )

    private enum Readiness {
        case unknown
        case ready
        case unavailable
    }

    public static let shared = QwenPrimeHarnessClient()

    public let harnessURL: URL
    public let taskCacheURL: URL
    private let processRunner: any HarnessClientProcessRunning
    private let requestID: @Sendable () -> UUID
    private let credential: String
    private var readiness: Readiness = .unknown

    public init(
        harnessURL: URL = QwenPrimeHarnessClient.defaultHarnessURL(),
        taskCacheURL: URL = QwenPrimeHarnessClient.defaultTaskCacheURL(),
        processRunner: any HarnessClientProcessRunning = FoundationHarnessClientProcessRunner(),
        requestID: @escaping @Sendable () -> UUID = UUID.init,
        credential: String = "\(UUID().uuidString)\(UUID().uuidString)"
    ) {
        self.harnessURL = harnessURL
        self.taskCacheURL = taskCacheURL
        self.processRunner = processRunner
        self.requestID = requestID
        self.credential = credential
    }

    public func isReady() async -> Bool {
        switch readiness {
        case .ready: return true
        case .unknown, .unavailable: break
        }
        do {
            try FileManager.default.createDirectory(
                at: taskCacheURL,
                withIntermediateDirectories: true
            )
            let response = try await send(HarnessRequest(
                protocolVersion: HarnessProtocolVersion.current,
                requestID: requestID(),
                credential: HarnessCredential(credential),
                operation: .selfTest,
                taskRoot: taskCacheURL.path,
                workingDirectory: ""
            ))
            let ready = response.status == .ready
                && response.capabilities.contains(.swiftBuild)
                && response.capabilities.contains(.swiftTest)
            readiness = ready ? .ready : .unavailable
            if ready {
                Self.logger.info("Swift workspace harness self-test passed.")
            } else {
                Self.logger.error("Swift workspace harness self-test failed.")
            }
            return ready
        } catch {
            readiness = .unavailable
            Self.logger.error(
                "Swift workspace harness self-test failed with error type: \(String(describing: type(of: error)), privacy: .public)"
            )
            return false
        }
    }

    public func send(_ request: HarnessRequest) async throws -> HarnessResponse {
        var environment = WorkspaceCommandPolicy.sanitizedEnvironment()
        environment["QWEN_PRIME_HARNESS_CREDENTIAL"] = credential
        let output = try await processRunner.run(HarnessClientInvocation(
            harnessURL: harnessURL,
            request: request,
            environment: environment
        ))
        let response = try JSONDecoder().decode(
            HarnessResponse.self,
            from: output.trimmingTrailingNewlines()
        )
        guard response.protocolVersion == HarnessProtocolVersion.current,
              response.requestID == request.requestID else {
            throw WorkspaceCommandClientError.invalidResponse
        }
        return response
    }

    public func makeRequest(
        operation: HarnessOperation,
        taskRoot: URL,
        workingDirectory: String,
        filter: String?
    ) -> HarnessRequest {
        HarnessRequest(
            protocolVersion: HarnessProtocolVersion.current,
            requestID: requestID(),
            credential: HarnessCredential(credential),
            operation: operation,
            taskRoot: taskRoot.path,
            workingDirectory: workingDirectory,
            filter: filter
        )
    }

    public func run(
        operation: HarnessOperation,
        taskRoot: URL,
        workingDirectory: String,
        filter: String?
    ) async throws -> HarnessResponse {
        guard await isReady() else {
            throw WorkspaceCommandClientError.transportFailure(
                "QwenPrimeHarness self-test is not ready."
            )
        }
        return try await send(makeRequest(
            operation: operation,
            taskRoot: taskRoot,
            workingDirectory: workingDirectory,
            filter: filter
        ))
    }

    public static func defaultHarnessURL() -> URL {
        Bundle.main.bundleURL
            .appendingPathComponent("Contents/Helpers/QwenPrimeHarness")
    }

    public static func defaultTaskCacheURL() -> URL {
        let base = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("QwenPrime", isDirectory: true)
            .appendingPathComponent("HarnessTasks", isDirectory: true)
    }
}

extension QwenPrimeHarnessClient: QwenPrimeHarnessServing {}

private extension Data {
    func trimmingTrailingNewlines() -> Data {
        var end = count
        while end > 0, self[index(startIndex, offsetBy: end - 1)] == 0x0A {
            end -= 1
        }
        return prefix(end)
    }
}
