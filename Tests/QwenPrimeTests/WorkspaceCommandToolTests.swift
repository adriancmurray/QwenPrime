import Foundation
import Testing
import QwenPrimeCommandProtocol
@testable import QwenPrime

@Suite("Workspace command tool approval")
struct WorkspaceCommandToolTests {
    actor MockCommandExecutor: WorkspaceCommandExecuting {
        private(set) var proposals: [WorkspaceCommandProposal] = []
        let response: CommandExecutionResponse

        init(response: CommandExecutionResponse) {
            self.response = response
        }

        func execute(_ proposal: WorkspaceCommandProposal) async throws -> CommandExecutionResponse {
            proposals.append(proposal)
            return response
        }

        func callCount() -> Int { proposals.count }
    }

    @Test("Approved command executes once and returns structured output")
    @MainActor
    func approvedCommandResumesWithResult() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let coordinator = WorkspaceApprovalCoordinator()
        let response = CommandExecutionResponse(
            id: UUID(),
            exitCode: 0,
            stdout: "working tree clean\n",
            stderr: "",
            outputTruncated: false,
            timedOut: false,
            cancelled: false,
            durationSeconds: 0.2,
            errorMessage: nil
        )
        let executor = MockCommandExecutor(response: response)
        let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
        let broker = WorkspaceToolBroker(
            readService: reader,
            mutationService: WorkspaceMutationService(readService: reader),
            approvalRequester: ConversationWorkspaceApprovalRequester(
                coordinator: coordinator,
                conversationID: UUID(),
                messageID: UUID()
            ),
            commandExecutor: executor
        )
        #expect(broker.tools.map(\.function.name).contains("workspace_run_command"))
        let call = ToolCall(
            id: "command-approved",
            type: "function",
            function: .init(
                name: "workspace_run_command",
                arguments: #"{"command":"pwd","arguments":[],"working_directory":""}"#
            )
        )
        let task = Task { try await broker.execute(call) }

        try await AsyncCondition.wait(description: "command approval pending") {
            coordinator.pendingRequests.count == 1
        }
        let approval = try #require(coordinator.pendingRequests.first)
        guard case .command(let proposal) = approval.payload else {
            Issue.record("Expected command approval payload")
            return
        }
        #expect(proposal.command == "pwd")
        #expect(coordinator.resolve(approval.id, decision: .approve))

        let result = try await task.value
        #expect(result.isSuccess)
        #expect(result.approvalState == .approved)
        #expect(result.commandProposal == proposal)
        #expect(result.content.contains("working tree clean"))
        #expect(await executor.callCount() == 1)
    }

    @Test("Rejected command never reaches the command executor")
    @MainActor
    func rejectedCommandDoesNotExecute() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let coordinator = WorkspaceApprovalCoordinator()
        let executor = MockCommandExecutor(response: CommandExecutionResponse(
            id: UUID(), exitCode: 0, stdout: "", stderr: "",
            outputTruncated: false, timedOut: false, cancelled: false,
            durationSeconds: 0, errorMessage: nil
        ))
        let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
        let broker = WorkspaceToolBroker(
            readService: reader,
            mutationService: WorkspaceMutationService(readService: reader),
            approvalRequester: ConversationWorkspaceApprovalRequester(
                coordinator: coordinator,
                conversationID: UUID(),
                messageID: UUID()
            ),
            commandExecutor: executor
        )
        let call = ToolCall(
            id: "command-rejected",
            type: "function",
            function: .init(name: "workspace_run_command", arguments: #"{"command":"pwd","arguments":[]}"#)
        )
        let task = Task { try await broker.execute(call) }
        try await AsyncCondition.wait(description: "command approval pending") {
            coordinator.pendingRequests.count == 1
        }
        let approval = try #require(coordinator.pendingRequests.first)
        #expect(coordinator.resolve(approval.id, decision: .reject))

        let result = try await task.value
        #expect(!result.isSuccess)
        #expect(result.approvalState == .rejected)
        #expect(await executor.callCount() == 0)
    }

    @Test("Disallowed command fails before approval")
    @MainActor
    func disallowedCommandNeverRequestsApproval() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let coordinator = WorkspaceApprovalCoordinator()
        let executor = MockCommandExecutor(response: CommandExecutionResponse(
            id: UUID(), exitCode: 0, stdout: "", stderr: "",
            outputTruncated: false, timedOut: false, cancelled: false,
            durationSeconds: 0, errorMessage: nil
        ))
        let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
        let broker = WorkspaceToolBroker(
            readService: reader,
            mutationService: WorkspaceMutationService(readService: reader),
            approvalRequester: ConversationWorkspaceApprovalRequester(
                coordinator: coordinator,
                conversationID: UUID(),
                messageID: UUID()
            ),
            commandExecutor: executor
        )
        let result = try await broker.execute(ToolCall(
            id: "command-blocked",
            type: "function",
            function: .init(name: "workspace_run_command", arguments: #"{"command":"git","arguments":["push"]}"#)
        ))

        #expect(!result.isSuccess)
        #expect(result.content.contains("not allowed"))
        #expect(coordinator.pendingRequests.isEmpty)
        #expect(await executor.callCount() == 0)
    }
}
