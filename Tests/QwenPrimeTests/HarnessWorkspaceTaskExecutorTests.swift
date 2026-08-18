import Foundation
import Testing
import QwenPrimeCommandProtocol
import QwenPrimeHarnessProtocol
@testable import QwenPrime

actor RecordingHarnessService: QwenPrimeHarnessServing {
    struct Call: Sendable {
        let operation: HarnessOperation
        let taskRoot: URL
        let workingDirectory: String
        let filter: String?
    }

    private(set) var calls: [Call] = []

    func isReady() async -> Bool { true }

    func run(
        operation: HarnessOperation,
        taskRoot: URL,
        workingDirectory: String,
        filter: String?
    ) async throws -> HarnessResponse {
        calls.append(Call(
            operation: operation,
            taskRoot: taskRoot,
            workingDirectory: workingDirectory,
            filter: filter
        ))
        return HarnessResponse(
            protocolVersion: HarnessProtocolVersion.current,
            requestID: UUID(),
            status: .completed,
            capabilities: [.swiftBuild, .swiftTest],
            exitCode: 0,
            stdout: "passed",
            stderr: "",
            outputTruncated: false,
            durationSeconds: 0.5,
            error: nil
        )
    }

    func capturedCalls() -> [Call] { calls }
}

@Suite("Harness-backed workspace task executor")
struct HarnessWorkspaceTaskExecutorTests {
    @Test("Stages the package and sends only the staged task root to the harness")
    func stagesBeforeExecution() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "Fixture/Package.swift", content: "// package\n")
            try fixture.createFile(at: "Fixture/Sources/App.swift", content: "let value = 1\n")
            let cache = FileManager.default.temporaryDirectory
                .appendingPathComponent("qwen-harness-executor-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: cache) }
            let service = RecordingHarnessService()
            let executor = HarnessWorkspaceTaskExecutor(
                workspaceURL: fixture.rootURL,
                taskCacheURL: cache,
                harness: service
            )
            let proposal = WorkspaceCommandProposal(
                command: "swift",
                arguments: ["test", "--filter", "FixtureTests"],
                workingDirectory: "Fixture"
            )

            _ = try await executor.prepare(proposal)
            let response = try await executor.execute(proposal)

            #expect(response.isSuccess)
            let call = try #require(await service.capturedCalls().first)
            #expect(call.operation == .swiftTest)
            #expect(call.workingDirectory == "workspace")
            #expect(call.filter == "FixtureTests")
            #expect(!call.taskRoot.path.hasPrefix(fixture.rootURL.path))
            #expect(!FileManager.default.fileExists(atPath: call.taskRoot.path))
        }
    }
}
