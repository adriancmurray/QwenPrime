import Foundation
import Testing
import QwenPrimeCommandProtocol
@testable import QwenPrime

@Suite("Workspace process tool approval")
struct WorkspaceCommandToolTests {
    actor MockCommandExecutor: WorkspaceCommandExecuting {
        private(set) var proposals: [WorkspaceCommandProposal] = []
        private(set) var stoppedIDs: [UUID] = []
        let response: CommandExecutionResponse
        let processID = UUID()

        init(response: CommandExecutionResponse) { self.response = response }

        func execute(_ proposal: WorkspaceCommandProposal) async throws -> CommandExecutionResponse {
            proposals.append(proposal)
            return response
        }

        func start(_ proposal: WorkspaceCommandProposal) async throws -> WorkspaceProcessSnapshot {
            proposals.append(proposal)
            return WorkspaceProcessSnapshot(id: processID, state: .running, result: nil, errorMessage: nil)
        }

        func status(id: UUID) async throws -> WorkspaceProcessSnapshot {
            WorkspaceProcessSnapshot(id: id, state: .running, result: nil, errorMessage: nil)
        }

        func stop(id: UUID) async throws -> WorkspaceProcessSnapshot {
            stoppedIDs.append(id)
            return WorkspaceProcessSnapshot(id: id, state: .stopped, result: nil, errorMessage: nil)
        }

        func callCount() -> Int { proposals.count }
        func stopCount() -> Int { stoppedIDs.count }
    }

    @Test("Generic process catalog replaces fixed command and Swift task tactics")
    func catalogIsGeneric() throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let executor = MockCommandExecutor(response: Self.successResponse())
        let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
        let broker = WorkspaceToolBroker(
            readService: reader,
            mutationService: WorkspaceMutationService(readService: reader),
            approvalRequester: AlwaysApproveWorkspaceRequester(),
            commandExecutor: executor
        )
        let names = Set(broker.tools.map(\.function.name))
        #expect(names.isSuperset(of: [
            "workspace_process_run", "workspace_process_start",
            "workspace_process_status", "workspace_process_stop"
        ]))
        #expect(names.isDisjoint(with: [
            "workspace_run_command", "workspace_list_tasks", "workspace_run_task"
        ]))
    }

    @Test("Approved generic command executes with its argv unchanged")
    @MainActor
    func approvedCommandResumesWithResult() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let coordinator = WorkspaceApprovalCoordinator()
        let executor = MockCommandExecutor(response: Self.successResponse(stdout: "built\n"))
        let broker = try makeBroker(fixture: fixture, coordinator: coordinator, executor: executor)
        let call = ToolCall(
            id: "command-approved", type: "function",
            function: .init(
                name: "workspace_process_run",
                arguments: #"{"command":"swift","arguments":["build","--product","HelloQwen"]}"#
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
        #expect(proposal.command == "swift")
        #expect(proposal.arguments == ["build", "--product", "HelloQwen"])
        #expect(coordinator.resolve(approval.id, decision: .approve))
        let result = try await task.value
        #expect(result.isSuccess)
        #expect(result.content.contains("built"))
        #expect(await executor.callCount() == 1)
    }

    @Test("Rejected process never reaches the executor")
    @MainActor
    func rejectedCommandDoesNotExecute() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let coordinator = WorkspaceApprovalCoordinator()
        let executor = MockCommandExecutor(response: Self.successResponse())
        let broker = try makeBroker(fixture: fixture, coordinator: coordinator, executor: executor)
        let call = ToolCall(
            id: "command-rejected", type: "function",
            function: .init(
                name: "workspace_process_run",
                arguments: #"{"command":"printf","arguments":["hello"]}"#
            )
        )
        let task = Task { try await broker.execute(call) }
        try await AsyncCondition.wait(description: "command approval pending") {
            coordinator.pendingRequests.count == 1
        }
        let approval = try #require(coordinator.pendingRequests.first)
        #expect(coordinator.resolve(approval.id, decision: .reject))
        let result = try await task.value
        #expect(result.approvalState == .rejected)
        #expect(await executor.callCount() == 0)
    }

    @Test("Start status and stop use one opaque process handle")
    func supervisedLifecycle() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let executor = MockCommandExecutor(response: Self.successResponse())
        let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
        let broker = WorkspaceToolBroker(
            readService: reader,
            mutationService: WorkspaceMutationService(readService: reader),
            approvalRequester: AlwaysApproveWorkspaceRequester(),
            commandExecutor: executor
        )
        let start = try await broker.execute(ToolCall(
            id: "start", type: "function",
            function: .init(
                name: "workspace_process_start",
                arguments: #"{"command":"./.build/debug/HelloQwen","arguments":[]}"#
            )
        ))
        #expect(start.isSuccess)
        #expect(start.content.contains(executor.processID.uuidString))

        let status = try await broker.execute(ToolCall(
            id: "status", type: "function",
            function: .init(
                name: "workspace_process_status",
                arguments: "{\"process_id\":\"" + executor.processID.uuidString + "\"}"
            )
        ))
        #expect(status.isSuccess)
        #expect(status.approvalState == nil)

        let stop = try await broker.execute(ToolCall(
            id: "stop", type: "function",
            function: .init(
                name: "workspace_process_stop",
                arguments: "{\"process_id\":\"" + executor.processID.uuidString + "\"}"
            )
        ))
        #expect(stop.isSuccess)
        #expect(stop.approvalState == .approved)
        #expect(await executor.stopCount() == 1)
    }

    @MainActor
    private func makeBroker(
        fixture: WorkspaceTestFixture,
        coordinator: WorkspaceApprovalCoordinator,
        executor: MockCommandExecutor
    ) throws -> WorkspaceToolBroker {
        let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
        return WorkspaceToolBroker(
            readService: reader,
            mutationService: WorkspaceMutationService(readService: reader),
            approvalRequester: ConversationWorkspaceApprovalRequester(
                coordinator: coordinator,
                conversationID: UUID(), messageID: UUID()
            ),
            commandExecutor: executor
        )
    }

    private static func successResponse(stdout: String = "") -> CommandExecutionResponse {
        CommandExecutionResponse(
            id: UUID(), exitCode: 0, stdout: stdout, stderr: "",
            outputTruncated: false, timedOut: false, cancelled: false,
            durationSeconds: 0, errorMessage: nil
        )
    }
}

private struct AlwaysApproveWorkspaceRequester: WorkspaceApprovalRequesting {
    func requestApproval(
        call: ToolCall,
        payload: WorkspaceApprovalPayload
    ) async throws -> ToolApprovalDecision { .approve }
}
