import Foundation
import Testing
import QwenPrimeHarnessProtocol
@testable import QwenPrime

actor RecordingHarnessClientProcessRunner: HarnessClientProcessRunning {
    var invocations: [HarnessClientInvocation] = []
    let response: HarnessResponse

    init(response: HarnessResponse) {
        self.response = response
    }

    func run(_ invocation: HarnessClientInvocation) async throws -> Data {
        invocations.append(invocation)
        var data = try JSONEncoder().encode(response)
        data.append(0x0A)
        return data
    }

    func capturedInvocations() -> [HarnessClientInvocation] { invocations }
}

actor SequenceHarnessClientProcessRunner: HarnessClientProcessRunning {
    private var responses: [HarnessResponse]

    init(responses: [HarnessResponse]) {
        self.responses = responses
    }

    func run(_ invocation: HarnessClientInvocation) async throws -> Data {
        guard !responses.isEmpty else {
            throw WorkspaceCommandClientError.invalidResponse
        }
        var data = try JSONEncoder().encode(responses.removeFirst())
        data.append(0x0A)
        return data
    }
}

@Suite("Qwen Prime harness client")
struct QwenPrimeHarnessClientTests {
    @Test("Self-test readiness is capability gated and cached")
    func readinessGate() async throws {
        let requestID = UUID()
        let response = HarnessResponse(
            protocolVersion: HarnessProtocolVersion.current,
            requestID: requestID,
            status: .ready,
            capabilities: [.selfTest, .swiftBuild, .swiftTest],
            exitCode: 0,
            stdout: "passed",
            stderr: "",
            outputTruncated: false,
            durationSeconds: 0.1,
            error: nil
        )
        let runner = RecordingHarnessClientProcessRunner(response: response)
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen-harness-client-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        let client = QwenPrimeHarnessClient(
            harnessURL: URL(fileURLWithPath: "/tmp/QwenPrimeHarness"),
            taskCacheURL: cache,
            processRunner: runner,
            requestID: { requestID },
            credential: "credential"
        )

        #expect(await client.isReady())
        #expect(await client.isReady())
        let invocations = await runner.capturedInvocations()
        #expect(invocations.count == 1)
        #expect(invocations.first?.request.operation == .selfTest)
        #expect(invocations.first?.environment["QWEN_PRIME_HARNESS_CREDENTIAL"] == "credential")
    }

    @Test("Failed self-test never enables executable capabilities")
    func failedReadiness() async throws {
        let requestID = UUID()
        let runner = RecordingHarnessClientProcessRunner(response: HarnessResponse(
            protocolVersion: HarnessProtocolVersion.current,
            requestID: requestID,
            status: .failed,
            capabilities: [],
            exitCode: 1,
            stdout: "",
            stderr: "failure",
            outputTruncated: false,
            durationSeconds: 0.1,
            error: "failed"
        ))
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen-harness-client-failed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        let client = QwenPrimeHarnessClient(
            harnessURL: URL(fileURLWithPath: "/tmp/QwenPrimeHarness"),
            taskCacheURL: cache,
            processRunner: runner,
            requestID: { requestID },
            credential: "credential"
        )

        #expect(await client.isReady() == false)
    }

    @Test("A failed self-test is retried instead of disabling tasks for the app lifetime")
    func failedReadinessRetries() async throws {
        let requestID = UUID()
        let failed = HarnessResponse(
            protocolVersion: HarnessProtocolVersion.current,
            requestID: requestID,
            status: .failed,
            capabilities: [],
            exitCode: 1,
            stdout: "",
            stderr: "failure",
            outputTruncated: false,
            durationSeconds: 0.1,
            error: "failed"
        )
        let ready = HarnessResponse(
            protocolVersion: HarnessProtocolVersion.current,
            requestID: requestID,
            status: .ready,
            capabilities: [.selfTest, .swiftBuild, .swiftTest],
            exitCode: 0,
            stdout: "passed",
            stderr: "",
            outputTruncated: false,
            durationSeconds: 0.1,
            error: nil
        )
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen-harness-client-retry-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        let client = QwenPrimeHarnessClient(
            harnessURL: URL(fileURLWithPath: "/tmp/QwenPrimeHarness"),
            taskCacheURL: cache,
            processRunner: SequenceHarnessClientProcessRunner(responses: [failed, ready]),
            requestID: { requestID },
            credential: "credential"
        )

        #expect(await client.isReady() == false)
        #expect(await client.isReady())
    }
}
