import Foundation
import QwenPrimeCommandProtocol

public enum ToolApprovalDecision: Sendable, Equatable {
    case approve
    case reject
}

public enum WorkspaceApprovalPayload: Sendable, Equatable {
    case mutation(WorkspaceMutationProposal)
    case command(WorkspaceCommandProposal)
    case externalTool(ExternalToolProposal)
}

public struct ExternalToolProposal: Sendable, Equatable {
    public let providerDisplayName: String
    public let toolName: String
    public let argumentsPreview: String

    public init(
        providerDisplayName: String,
        toolName: String,
        argumentsPreview: String
    ) {
        self.providerDisplayName = providerDisplayName
        self.toolName = toolName
        self.argumentsPreview = argumentsPreview
    }
}

public struct WorkspaceApprovalKey: Sendable, Hashable {
    public let conversationID: UUID
    public let callID: String

    public init(conversationID: UUID, callID: String) {
        self.conversationID = conversationID
        self.callID = callID
    }
}

public struct WorkspaceApprovalRequest: Identifiable, Sendable, Equatable {
    public let conversationID: UUID
    public let messageID: UUID
    public let callID: String
    public let toolName: String
    public let payload: WorkspaceApprovalPayload

    public var id: WorkspaceApprovalKey {
        WorkspaceApprovalKey(conversationID: conversationID, callID: callID)
    }

    public init(
        conversationID: UUID,
        messageID: UUID,
        callID: String,
        toolName: String,
        proposal: WorkspaceMutationProposal
    ) {
        self.conversationID = conversationID
        self.messageID = messageID
        self.callID = callID
        self.toolName = toolName
        self.payload = .mutation(proposal)
    }

    public init(
        conversationID: UUID,
        messageID: UUID,
        callID: String,
        toolName: String,
        commandProposal: WorkspaceCommandProposal
    ) {
        self.conversationID = conversationID
        self.messageID = messageID
        self.callID = callID
        self.toolName = toolName
        self.payload = .command(commandProposal)
    }

    public init(
        conversationID: UUID,
        messageID: UUID,
        callID: String,
        toolName: String,
        externalToolProposal: ExternalToolProposal
    ) {
        self.conversationID = conversationID
        self.messageID = messageID
        self.callID = callID
        self.toolName = toolName
        self.payload = .externalTool(externalToolProposal)
    }
}

public enum WorkspaceApprovalError: Error, Sendable, Equatable, LocalizedError {
    case duplicateRequest(WorkspaceApprovalKey)

    public var errorDescription: String? {
        switch self {
        case .duplicateRequest(let key):
            return "An approval is already pending for tool call \(key.callID)."
        }
    }
}
