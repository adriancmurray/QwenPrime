import Foundation
import Testing
@testable import QwenPrime

@Suite("Resumable workspace approval coordinator")
struct WorkspaceApprovalCoordinatorTests {
    private func request(
        conversationID: UUID = UUID(),
        messageID: UUID = UUID(),
        callID: String = UUID().uuidString,
        path: String = "change.txt"
    ) -> WorkspaceApprovalRequest {
        WorkspaceApprovalRequest(
            conversationID: conversationID,
            messageID: messageID,
            callID: callID,
            toolName: "workspace_write_file",
            proposal: WorkspaceMutationProposal(
                operation: .writeFile,
                relativePath: path,
                expectedContent: nil,
                proposedContent: "hello\n",
                preview: "+hello"
            )
        )
    }

    @Test("Approval request suspends and resolves exactly once")
    @MainActor
    func suspendsAndResolvesExactlyOnce() async throws {
        let coordinator = WorkspaceApprovalCoordinator()
        let approval = request(callID: "call-once")
        let task = Task { try await coordinator.requestApproval(approval) }

        try await AsyncCondition.wait(description: "approval became pending") {
            coordinator.pendingRequests == [approval]
        }
        #expect(coordinator.resolve(approval.id, decision: .approve))
        #expect(!coordinator.resolve(approval.id, decision: .reject))
        #expect(try await task.value == .approve)
        #expect(coordinator.pendingRequests.isEmpty)
    }

    @Test("Cancelling a suspended request removes it and throws CancellationError")
    @MainActor
    func cancellationCleansUpContinuation() async throws {
        let coordinator = WorkspaceApprovalCoordinator()
        let approval = request(callID: "call-cancel")
        let task = Task { try await coordinator.requestApproval(approval) }

        try await AsyncCondition.wait(description: "approval became pending") {
            coordinator.pendingRequests == [approval]
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
        try await AsyncCondition.wait(description: "cancelled approval removed") {
            coordinator.pendingRequests.isEmpty
        }
        #expect(!coordinator.resolve(approval.id, decision: .approve))
    }

    @Test("Requests with the same call ID remain isolated by conversation")
    @MainActor
    func conversationRoutingIsIsolated() async throws {
        let coordinator = WorkspaceApprovalCoordinator()
        let conversationA = UUID()
        let conversationB = UUID()
        let requestA = request(conversationID: conversationA, callID: "shared", path: "a.txt")
        let requestB = request(conversationID: conversationB, callID: "shared", path: "b.txt")
        let taskA = Task { try await coordinator.requestApproval(requestA) }
        let taskB = Task { try await coordinator.requestApproval(requestB) }

        try await AsyncCondition.wait(description: "both approvals became pending") {
            coordinator.pendingRequests.count == 2
        }
        #expect(coordinator.resolve(requestB.id, decision: .reject))
        #expect(try await taskB.value == .reject)
        #expect(coordinator.pendingRequests == [requestA])
        #expect(coordinator.resolve(requestA.id, decision: .approve))
        #expect(try await taskA.value == .approve)
    }

    @Test("Approved mutation executes inside the broker and returns the real result")
    @MainActor
    func approvedMutationReturnsRealResult() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let coordinator = WorkspaceApprovalCoordinator()
        let conversationID = UUID()
        let messageID = UUID()
        let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
        let broker = WorkspaceToolBroker(
            readService: reader,
            mutationService: WorkspaceMutationService(readService: reader),
            approvalRequester: ConversationWorkspaceApprovalRequester(
                coordinator: coordinator,
                conversationID: conversationID,
                messageID: messageID
            )
        )
        let call = ToolCall(
            id: "write-approved",
            type: "function",
            function: .init(
                name: "workspace_write_file",
                arguments: #"{"path":"approved.txt","content":"approved\n"}"#
            )
        )
        let execution = Task { try await broker.execute(call) }

        try await AsyncCondition.wait(description: "write approval became pending") {
            coordinator.pendingRequests.count == 1
        }
        #expect(!FileManager.default.fileExists(atPath: fixture.rootURL.appendingPathComponent("approved.txt").path))
        let approval = try #require(coordinator.pendingRequests.first)
        #expect(coordinator.resolve(approval.id, decision: .approve))

        let result = try await execution.value
        #expect(result.isSuccess)
        #expect(result.approvalState == .approved)
        #expect(result.content == "Applied to approved.txt.")
        #expect(try String(contentsOf: fixture.rootURL.appendingPathComponent("approved.txt"), encoding: .utf8) == "approved\n")
    }

    @Test("Rejected mutation returns a tool result without changing the workspace")
    @MainActor
    func rejectedMutationReturnsResultWithoutWrite() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let coordinator = WorkspaceApprovalCoordinator()
        let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
        let broker = WorkspaceToolBroker(
            readService: reader,
            mutationService: WorkspaceMutationService(readService: reader),
            approvalRequester: ConversationWorkspaceApprovalRequester(
                coordinator: coordinator,
                conversationID: UUID(),
                messageID: UUID()
            )
        )
        let call = ToolCall(
            id: "write-rejected",
            type: "function",
            function: .init(
                name: "workspace_write_file",
                arguments: #"{"path":"rejected.txt","content":"no\n"}"#
            )
        )
        let execution = Task { try await broker.execute(call) }

        try await AsyncCondition.wait(description: "rejection became pending") {
            coordinator.pendingRequests.count == 1
        }
        let approval = try #require(coordinator.pendingRequests.first)
        #expect(coordinator.resolve(approval.id, decision: .reject))

        let result = try await execution.value
        #expect(!result.isSuccess)
        #expect(result.approvalState == .rejected)
        #expect(result.content.contains("Rejected by user"))
        #expect(!FileManager.default.fileExists(atPath: fixture.rootURL.appendingPathComponent("rejected.txt").path))
    }

    @Test("Agent loop resumes with applied result in the same transcript")
    @MainActor
    func runtimeResumesAfterApproval() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let coordinator = WorkspaceApprovalCoordinator()
        let conversationID = UUID()
        let call = ToolCall(
            id: "write-resume",
            type: "function",
            function: .init(
                name: "workspace_write_file",
                arguments: #"{"path":"resume.txt","content":"done\n"}"#
            )
        )
        let inference = ScriptedAgentInference(turns: [
            [.toolCall(call), .finished],
            [.contentDelta("Created and verified resume.txt."), .finished]
        ])
        let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
        let broker = WorkspaceToolBroker(
            readService: reader,
            mutationService: WorkspaceMutationService(readService: reader),
            approvalRequester: ConversationWorkspaceApprovalRequester(
                coordinator: coordinator,
                conversationID: conversationID,
                messageID: UUID()
            )
        )
        let runtime = NativeAgentRuntime(inference: inference, toolExecutor: broker)
        let run = Task { () throws -> [AgentEvent] in
            var events: [AgentEvent] = []
            for try await event in runtime.run(history: [ChatMessage(role: .user, content: "Create resume.txt")]) {
                events.append(event)
            }
            return events
        }

        try await AsyncCondition.wait(description: "runtime paused for approval") {
            coordinator.pendingRequests.count == 1
        }
        let approval = try #require(coordinator.pendingRequests.first)
        #expect(coordinator.resolve(approval.id, decision: .approve))
        let events = try await run.value

        #expect(events.contains(.contentDelta("Created and verified resume.txt.")))
        let transcripts = await inference.getCapturedTranscripts()
        #expect(transcripts.count == 2)
        #expect(transcripts[1].last?.role == .tool)
        #expect(transcripts[1].last?.content == "Applied to resume.txt.")
    }

    @Test("Stopping a conversation cancels its pending approval")
    @MainActor
    func stopGenerationCancelsPendingApproval() async throws {
        let coordinator = WorkspaceApprovalCoordinator()
        let conversation = Conversation(title: "Pending approval")
        let appState = AppState(startServices: false)
        appState.conversations = [conversation]
        appState.selectedConversationId = conversation.id
        appState.setConversation(conversation.id, isGenerating: true)
        let approval = request(conversationID: conversation.id, callID: "stop-me")
        let suspended = Task { try await coordinator.requestApproval(approval) }
        try await AsyncCondition.wait(description: "approval became pending") {
            coordinator.pendingRequests == [approval]
        }
        let viewModel = ChatViewModel(approvalCoordinator: coordinator)

        viewModel.stopGeneration(conversationID: conversation.id, appState: appState)

        await #expect(throws: CancellationError.self) {
            try await suspended.value
        }
        #expect(coordinator.pendingRequests.isEmpty)
    }
}
