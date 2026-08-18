import Foundation
import QwenPrimeCommandProtocol

/// Represents the normalized execution result of an agent tool call.
public struct AgentToolResult: Sendable, Equatable, Codable {
    public let callId: String
    public let toolName: String
    public let content: String
    public let isSuccess: Bool
    public let mutationProposal: WorkspaceMutationProposal?
    public let approvalState: ToolApprovalState?
    public let commandProposal: WorkspaceCommandProposal?

    public init(
        callId: String,
        toolName: String,
        content: String,
        isSuccess: Bool,
        mutationProposal: WorkspaceMutationProposal? = nil,
        approvalState: ToolApprovalState? = nil,
        commandProposal: WorkspaceCommandProposal? = nil
    ) {
        self.callId = callId
        self.toolName = toolName
        self.content = content
        self.isSuccess = isSuccess
        self.mutationProposal = mutationProposal
        self.approvalState = approvalState
        self.commandProposal = commandProposal
    }
}
