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
        let executionErrorMessage: String?
        let processID = UUID()

        init(
            response: CommandExecutionResponse,
            executionErrorMessage: String? = nil
        ) {
            self.response = response
            self.executionErrorMessage = executionErrorMessage
        }

        func execute(_ proposal: WorkspaceCommandProposal) async throws -> CommandExecutionResponse {
            proposals.append(proposal)
            if let executionErrorMessage {
                throw MockCommandExecutionError(message: executionErrorMessage)
            }
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
            ToolName.workspaceProcessRun,
            ToolName.workspaceProcessStart,
            ToolName.workspaceProcessStatus,
            ToolName.workspaceProcessStop,
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
                name: ToolName.workspaceProcessRun,
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

    @Test("Process tools reject escaping or malformed working directories")
    func invalidWorkingDirectoriesNeverReachExecutor() async throws {
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
        let invalidDirectories = [
            "/tmp",
            "nested/../../escape",
            "nested\u{0}escape"
        ]

        for toolName in [
            ToolName.workspaceProcessRun,
            ToolName.workspaceProcessStart
        ] {
            for workingDirectory in invalidDirectories {
                let result = try await broker.execute(try Self.processCall(
                    toolName: toolName,
                    workingDirectory: workingDirectory
                ))

                #expect(result.isSuccess == false)
                #expect(result.approvalState == nil)
            }
        }

        #expect(await executor.callCount() == 0)
    }

    @Test("Process output redacts workspace and task temporary paths")
    func processOutputSanitizesEveryResponseChannel() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let workspacePaths = WorkspacePathSanitizer.pathVariants(
            for: fixture.rootURL
        )
        let temporaryPaths = WorkspacePathSanitizer.pathVariants(
            for: FileManager.default.temporaryDirectory
        )
        let emittedPaths = [
            workspacePaths[0].lowercased(),
            workspacePaths[1].uppercased(),
            Self.alternatingPathCase(workspacePaths[2]),
            temporaryPaths[0].uppercased(),
            temporaryPaths[1].lowercased(),
            Self.alternatingPathCase(temporaryPaths[2]),
        ]
        let response = CommandExecutionResponse(
            id: UUID(),
            exitCode: 1,
            stdout: "stdout \(emittedPaths[0]) \(emittedPaths[3])",
            stderr: "stderr \(emittedPaths[1]) \(emittedPaths[4])",
            outputTruncated: false,
            timedOut: false,
            cancelled: false,
            durationSeconds: 0,
            errorMessage: "error \(emittedPaths[2]) \(emittedPaths[5])"
        )
        let executor = MockCommandExecutor(response: response)
        let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
        let broker = WorkspaceToolBroker(
            readService: reader,
            mutationService: WorkspaceMutationService(readService: reader),
            approvalRequester: AlwaysApproveWorkspaceRequester(),
            commandExecutor: executor
        )

        let result = try await broker.execute(try Self.processCall(
            toolName: ToolName.workspaceProcessRun,
            workingDirectory: ""
        ))
        let data = try #require(result.content.data(using: .utf8))
        let sanitized = try JSONDecoder().decode(
            CommandExecutionResponse.self,
            from: data
        )
        let output = [
            sanitized.stdout,
            sanitized.stderr,
            sanitized.errorMessage ?? ""
        ].joined(separator: " ")

        #expect(output.contains("<workspace_root>"))
        #expect(output.contains("<task_temp>"))
        for path in Set(emittedPaths) where !path.isEmpty {
            #expect(!output.contains(path))
        }
    }

    @Test("Thrown process errors redact workspace and task temporary paths")
    func processFailureSanitizesErrorContent() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let workspacePaths = WorkspacePathSanitizer.pathVariants(
            for: fixture.rootURL
        )
        let temporaryPaths = WorkspacePathSanitizer.pathVariants(
            for: FileManager.default.temporaryDirectory
        )
        let errorMessage = (workspacePaths + temporaryPaths).joined(
            separator: " | "
        )
        let executor = MockCommandExecutor(
            response: Self.successResponse(),
            executionErrorMessage: errorMessage
        )
        let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
        let broker = WorkspaceToolBroker(
            readService: reader,
            mutationService: WorkspaceMutationService(readService: reader),
            approvalRequester: AlwaysApproveWorkspaceRequester(),
            commandExecutor: executor
        )

        let result = try await broker.execute(try Self.processCall(
            toolName: ToolName.workspaceProcessRun,
            workingDirectory: ""
        ))

        #expect(result.isSuccess == false)
        #expect(result.content.contains("<workspace_root>"))
        #expect(result.content.contains("<task_temp>"))
        for path in Set(workspacePaths + temporaryPaths) where !path.isEmpty {
            #expect(!result.content.contains(path))
        }
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

    private static func alternatingPathCase(_ path: String) -> String {
        String(path.enumerated().map { index, character in
            index.isMultiple(of: 2)
                ? String(character).lowercased()
                : String(character).uppercased()
        }.joined())
    }

    private static func successResponse(stdout: String = "") -> CommandExecutionResponse {
        CommandExecutionResponse(
            id: UUID(), exitCode: 0, stdout: stdout, stderr: "",
            outputTruncated: false, timedOut: false, cancelled: false,
            durationSeconds: 0, errorMessage: nil
        )
    }

    private static func processCall(
        toolName: String,
        workingDirectory: String
    ) throws -> ToolCall {
        let arguments: [String: Any] = [
            "command": "swift",
            "arguments": ["--version"],
            "working_directory": workingDirectory
        ]
        let data = try JSONSerialization.data(withJSONObject: arguments)
        return ToolCall(
            id: UUID().uuidString,
            type: "function",
            function: .init(
                name: toolName,
                arguments: String(decoding: data, as: UTF8.self)
            )
        )
    }
}

private struct MockCommandExecutionError: LocalizedError, Sendable {
    let message: String

    var errorDescription: String? { message }
}

private struct AlwaysApproveWorkspaceRequester: WorkspaceApprovalRequesting {
    func requestApproval(
        call: ToolCall,
        payload: WorkspaceApprovalPayload
    ) async throws -> ToolApprovalDecision { .approve }
}
