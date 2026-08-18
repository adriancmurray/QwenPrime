import Foundation
import Observation

@Observable
@MainActor
public final class WorkspaceApprovalCoordinator {
    private struct Entry {
        let request: WorkspaceApprovalRequest
        let continuation: CheckedContinuation<ToolApprovalDecision, Error>
    }

    public private(set) var pendingRequests: [WorkspaceApprovalRequest] = []
    @ObservationIgnored private var entries: [WorkspaceApprovalKey: Entry] = [:]

    public init() {}

    public func requestApproval(
        _ request: WorkspaceApprovalRequest
    ) async throws -> ToolApprovalDecision {
        try Task.checkCancellation()
        let key = request.id

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                guard entries[key] == nil else {
                    continuation.resume(
                        throwing: WorkspaceApprovalError.duplicateRequest(key)
                    )
                    return
                }
                entries[key] = Entry(request: request, continuation: continuation)
                pendingRequests.append(request)
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancel(key)
            }
        }
    }

    @discardableResult
    public func resolve(
        _ key: WorkspaceApprovalKey,
        decision: ToolApprovalDecision
    ) -> Bool {
        guard let entry = removeEntry(for: key) else { return false }
        entry.continuation.resume(returning: decision)
        return true
    }

    public func cancelAll(for conversationID: UUID) {
        let keys = pendingRequests
            .filter { $0.conversationID == conversationID }
            .map(\.id)
        for key in keys {
            cancel(key)
        }
    }

    private func cancel(_ key: WorkspaceApprovalKey) {
        guard let entry = removeEntry(for: key) else { return }
        entry.continuation.resume(throwing: CancellationError())
    }

    private func removeEntry(for key: WorkspaceApprovalKey) -> Entry? {
        guard let entry = entries.removeValue(forKey: key) else { return nil }
        pendingRequests.removeAll { $0.id == key }
        return entry
    }
}

public struct ConversationWorkspaceApprovalRequester: WorkspaceApprovalRequesting {
    public let coordinator: WorkspaceApprovalCoordinator
    public let conversationID: UUID
    public let messageID: UUID

    public init(
        coordinator: WorkspaceApprovalCoordinator,
        conversationID: UUID,
        messageID: UUID
    ) {
        self.coordinator = coordinator
        self.conversationID = conversationID
        self.messageID = messageID
    }

    public func requestApproval(
        call: ToolCall,
        payload: WorkspaceApprovalPayload
    ) async throws -> ToolApprovalDecision {
        let request: WorkspaceApprovalRequest
        switch payload {
        case .mutation(let proposal):
            request = WorkspaceApprovalRequest(
                conversationID: conversationID,
                messageID: messageID,
                callID: call.id,
                toolName: call.function.name,
                proposal: proposal
            )
        case .command(let proposal):
            request = WorkspaceApprovalRequest(
                conversationID: conversationID,
                messageID: messageID,
                callID: call.id,
                toolName: call.function.name,
                commandProposal: proposal
            )
        case .externalTool(let proposal):
            request = WorkspaceApprovalRequest(
                conversationID: conversationID,
                messageID: messageID,
                callID: call.id,
                toolName: call.function.name,
                externalToolProposal: proposal
            )
        }
        return try await coordinator.requestApproval(request)
    }
}
