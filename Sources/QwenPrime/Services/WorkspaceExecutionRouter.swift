import Foundation
import QwenPrimeCommandProtocol

public struct WorkspaceExecutionRouter: WorkspaceCommandExecuting, Sendable {
    public let commandExecutor: any WorkspaceCommandExecuting
    public let taskExecutor: (any WorkspaceCommandExecuting)?

    public init(
        commandExecutor: any WorkspaceCommandExecuting,
        taskExecutor: (any WorkspaceCommandExecuting)?
    ) {
        self.commandExecutor = commandExecutor
        self.taskExecutor = taskExecutor
    }

    public func prepare(
        _ proposal: WorkspaceCommandProposal
    ) async throws -> WorkspaceCommandProposal {
        if proposal.command == "swift" {
            guard let taskExecutor else {
                throw WorkspaceCommandClientError.transportFailure(
                    "QwenPrimeHarness self-test is unavailable."
                )
            }
            return try await taskExecutor.prepare(proposal)
        }
        return try await commandExecutor.prepare(proposal)
    }

    public func execute(
        _ proposal: WorkspaceCommandProposal
    ) async throws -> CommandExecutionResponse {
        if proposal.command == "swift" {
            guard let taskExecutor else {
                throw WorkspaceCommandClientError.transportFailure(
                    "QwenPrimeHarness self-test is unavailable."
                )
            }
            return try await taskExecutor.execute(proposal)
        }
        return try await commandExecutor.execute(proposal)
    }
}
