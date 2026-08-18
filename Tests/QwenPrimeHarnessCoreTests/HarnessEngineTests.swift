import Foundation
import Testing
@testable import QwenPrimeHarnessCore
import QwenPrimeHarnessProtocol

actor RecordingHarnessProcessRunner: HarnessProcessRunning {
    private(set) var invocations: [HarnessProcessInvocation] = []
    let result: HarnessProcessResult

    init(result: HarnessProcessResult) {
        self.result = result
    }

    func run(_ invocation: HarnessProcessInvocation) async throws -> HarnessProcessResult {
        invocations.append(invocation)
        return result
    }

    func capturedInvocations() -> [HarnessProcessInvocation] { invocations }
}

@Suite("Qwen Prime harness engine")
struct HarnessEngineTests {
    @Test("Valid Swift test request becomes one sandboxed typed invocation")
    func swiftTestInvocation() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen-harness-engine-\(UUID().uuidString)", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingHarnessProcessRunner(result: HarnessProcessResult(
            exitCode: 0,
            stdout: "passed",
            stderr: "",
            outputTruncated: false,
            durationSeconds: 0.25
        ))
        let engine = HarnessEngine(expectedCredential: "credential", processRunner: runner)
        let request = HarnessRequest(
            protocolVersion: HarnessProtocolVersion.current,
            requestID: UUID(),
            credential: HarnessCredential("credential"),
            operation: .swiftTest,
            taskRoot: root.path,
            workingDirectory: "workspace",
            filter: "FixtureTests"
        )

        let response = await engine.handle(request)

        #expect(response.status == .completed)
        #expect(response.exitCode == 0)
        let invocation = try #require(await runner.capturedInvocations().first)
        #expect(invocation.executableURL.path == "/usr/bin/sandbox-exec")
        #expect(invocation.arguments.contains("test"))
        #expect(invocation.arguments.contains("--filter"))
        #expect(invocation.arguments.contains("FixtureTests"))
        #expect(invocation.workingDirectory == workspace)
        #expect(invocation.environment["SWIFTPM_MODULECACHE_OVERRIDE"]?.hasPrefix(root.path) == true)
    }

    @Test("Invalid credential is rejected before process execution")
    func invalidCredentialRejected() async throws {
        let runner = RecordingHarnessProcessRunner(result: HarnessProcessResult(
            exitCode: 0, stdout: "", stderr: "", outputTruncated: false, durationSeconds: 0
        ))
        let engine = HarnessEngine(expectedCredential: "expected", processRunner: runner)
        let response = await engine.handle(HarnessRequest(
            protocolVersion: HarnessProtocolVersion.current,
            requestID: UUID(),
            credential: HarnessCredential("wrong"),
            operation: .selfTest,
            taskRoot: "/tmp",
            workingDirectory: ""
        ))

        #expect(response.status == .rejected)
        #expect((await runner.capturedInvocations()).isEmpty)
    }

    @Test("Successful self-test reports ready capabilities")
    func selfTestReady() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwen-harness-self-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = RecordingHarnessProcessRunner(result: HarnessProcessResult(
            exitCode: 0, stdout: "passed", stderr: "", outputTruncated: false, durationSeconds: 0.1
        ))
        let engine = HarnessEngine(expectedCredential: "credential", processRunner: runner)

        let response = await engine.handle(HarnessRequest(
            protocolVersion: HarnessProtocolVersion.current,
            requestID: UUID(),
            credential: HarnessCredential("credential"),
            operation: .selfTest,
            taskRoot: root.path,
            workingDirectory: ""
        ))

        #expect(response.status == .ready)
        #expect(response.capabilities.contains(.swiftTest))
        #expect(response.capabilities.contains(.swiftBuild))
    }
}
