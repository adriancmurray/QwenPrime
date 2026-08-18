import Foundation
import QwenPrimeCommandCore
import QwenPrimeCommandProtocol
import QwenPrimeHarnessProtocol

public struct HarnessWorkspaceTaskExecutor: WorkspaceCommandExecuting, Sendable {
    private let workspaceURL: URL
    private let taskCacheURL: URL
    private let harness: any QwenPrimeHarnessServing

    public init(
        workspaceURL: URL,
        taskCacheURL: URL,
        harness: any QwenPrimeHarnessServing = QwenPrimeHarnessClient.shared
    ) {
        self.workspaceURL = workspaceURL.standardizedFileURL
        self.taskCacheURL = taskCacheURL.standardizedFileURL
        self.harness = harness
    }

    public func prepare(
        _ proposal: WorkspaceCommandProposal
    ) async throws -> WorkspaceCommandProposal {
        guard proposal.command == "swift" else {
            throw CommandPolicyError.unsupportedCommand(proposal.command)
        }
        guard await harness.isReady() else {
            throw WorkspaceCommandClientError.transportFailure(
                "QwenPrimeHarness self-test is unavailable."
            )
        }
        try WorkspaceCommandPolicy.validate(
            command: proposal.command,
            arguments: proposal.arguments
        )
        _ = try ReadOnlyWorkspaceService.validateAndParseDirectoryPath(
            proposal.workingDirectory
        )
        return proposal
    }

    public func execute(
        _ proposal: WorkspaceCommandProposal
    ) async throws -> CommandExecutionResponse {
        _ = try await prepare(proposal)
        let stage = try await WorkspaceTaskStager.stage(
            workspaceURL: workspaceURL,
            relativePackagePath: proposal.workingDirectory,
            taskCacheURL: taskCacheURL,
            id: UUID()
        )
        defer { try? stage.remove() }

        let operation: HarnessOperation
        let filter: String?
        if proposal.arguments == ["build"] {
            operation = .swiftBuild
            filter = nil
        } else if proposal.arguments == ["test"] {
            operation = .swiftTest
            filter = nil
        } else if proposal.arguments.count == 3,
                  proposal.arguments[0] == "test",
                  proposal.arguments[1] == "--filter" {
            operation = .swiftTest
            filter = proposal.arguments[2]
        } else {
            throw CommandPolicyError.invalidArguments("unsupported Swift task proposal")
        }

        let response = try await harness.run(
            operation: operation,
            taskRoot: stage.taskRootURL,
            workingDirectory: "workspace",
            filter: filter
        )
        return CommandExecutionResponse(
            id: response.requestID,
            exitCode: response.exitCode ?? -1,
            stdout: response.stdout,
            stderr: response.stderr,
            outputTruncated: response.outputTruncated,
            timedOut: false,
            cancelled: false,
            durationSeconds: response.durationSeconds,
            errorMessage: response.error
        )
    }
}
