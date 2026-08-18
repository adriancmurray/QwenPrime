import Foundation
import Testing
@testable import QwenPrime

@Suite("Workspace mutation proposal and application")
struct WorkspaceMutationServiceTests {
    @Test("Mutation tools produce approval proposals without changing the workspace")
    func mutationToolsOnlyProposeChanges() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "notes.txt", content: "before\n")
            let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let broker = WorkspaceToolBroker(
                readService: reader,
                mutationService: WorkspaceMutationService(readService: reader)
            )

            #expect(Set(broker.tools.map(\.function.name)) == [
                "workspace_list_directory",
                "workspace_read_file",
                "workspace_write_file",
                "workspace_apply_patch"
            ])

            let call = ToolCall(
                id: "write-1",
                type: "function",
                function: .init(
                    name: "workspace_write_file",
                    arguments: #"{"path":"created.txt","content":"hello\n"}"#
                )
            )
            let result = try await broker.execute(call)

            #expect(result.isSuccess)
            #expect(result.mutationProposal?.relativePath == "created.txt")
            #expect(result.mutationProposal?.operation == .writeFile)
            #expect(result.content.contains("review panel"))
            #expect(result.content.contains("Do not repeat the diff"))
            #expect(FileManager.default.fileExists(atPath: fixture.rootURL.appendingPathComponent("created.txt").path) == false)
        }
    }

    @Test("An approved new-file proposal writes exactly the reviewed content")
    func approvedWriteCreatesFile() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createDirectory(at: "Sources")
            let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let service = WorkspaceMutationService(readService: reader)
            let proposal = try await service.prepareWrite(
                relativePath: "Sources/New.swift",
                content: "struct New {}\n",
                overwrite: false
            )

            #expect(proposal.preview.contains("+struct New {}"))
            try await service.apply(proposal)

            let result = try await reader.readFile(relativePath: "Sources/New.swift")
            #expect(result.content == "struct New {}\n")
        }
    }

    @Test("Patch proposal requires one exact match and rejects stale files at approval time")
    func patchRequiresUniqueMatchAndFreshSnapshot() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let fileURL = try fixture.createFile(at: "config.txt", content: "alpha\nbeta\n")
            let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let service = WorkspaceMutationService(readService: reader)
            let proposal = try await service.preparePatch(
                relativePath: "config.txt",
                oldText: "beta",
                newText: "gamma"
            )

            #expect(proposal.preview.contains("-beta"))
            #expect(proposal.preview.contains("+gamma"))
            try "alpha\nchanged elsewhere\n".write(to: fileURL, atomically: true, encoding: .utf8)

            await #expect(throws: WorkspaceMutationError.staleProposal(path: "config.txt")) {
                try await service.apply(proposal)
            }
        }
    }

    @Test("Mutation proposals reject secret paths, traversal, symlinks, and oversized content")
    func mutationGuardrails() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let outside = FileManager.default.temporaryDirectory
                .appendingPathComponent("outside-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: outside) }
            try "outside".write(to: outside, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(
                at: fixture.rootURL.appendingPathComponent("linked.txt"),
                withDestinationURL: outside
            )

            let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let service = WorkspaceMutationService(
                readService: reader,
                limits: WorkspaceMutationLimits(maxWriteBytes: 8)
            )

            await #expect(throws: WorkspaceAccessError.self) {
                try await service.prepareWrite(relativePath: "../escape.txt", content: "x", overwrite: false)
            }
            await #expect(throws: WorkspaceAccessError.self) {
                try await service.prepareWrite(relativePath: ".env", content: "x", overwrite: false)
            }
            await #expect(throws: WorkspaceAccessError.self) {
                try await service.prepareWrite(relativePath: "linked.txt", content: "x", overwrite: true)
            }
            await #expect(throws: WorkspaceMutationError.contentTooLarge(maxBytes: 8)) {
                try await service.prepareWrite(relativePath: "large.txt", content: "123456789", overwrite: false)
            }
            await #expect(throws: WorkspaceAccessError.self) {
                try await service.prepareWrite(relativePath: "missing/child.txt", content: "x", overwrite: false)
            }
        }
    }

    @Test("Mutation proposals reject source files truncated by read limits")
    func truncatedSourceCannotBeMutated() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let content = (1...600).map { "line \($0)" }.joined(separator: "\n")
            try fixture.createFile(at: "long.txt", content: content)
            let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let service = WorkspaceMutationService(readService: reader)

            await #expect(throws: WorkspaceMutationError.sourceTruncated(path: "long.txt")) {
                try await service.preparePatch(
                    relativePath: "long.txt",
                    oldText: "line 1",
                    newText: "changed"
                )
            }
            await #expect(throws: WorkspaceMutationError.sourceTruncated(path: "long.txt")) {
                try await service.prepareWrite(
                    relativePath: "long.txt",
                    content: "replacement",
                    overwrite: true
                )
            }
        }
    }

    @Test("Replacing an existing text file preserves its POSIX permissions")
    func overwritePreservesPermissions() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let fileURL = try fixture.createFile(at: "script.sh", content: "echo before\n")
            #expect(chmod(fileURL.path, mode_t(0o755)) == 0)
            let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let service = WorkspaceMutationService(readService: reader)
            let proposal = try await service.prepareWrite(
                relativePath: "script.sh",
                content: "echo after\n",
                overwrite: true
            )

            try await service.apply(proposal)

            var info = stat()
            #expect(lstat(fileURL.path, &info) == 0)
            #expect(info.st_mode & mode_t(0o777) == mode_t(0o755))
        }
    }

    @Test("Applying the same reviewed proposal twice is idempotent")
    func repeatedApplyIsIdempotent() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let service = WorkspaceMutationService(readService: reader)
            let proposal = try await service.prepareWrite(
                relativePath: "once.txt",
                content: "one\n",
                overwrite: false
            )

            try await service.apply(proposal)
            try await service.apply(proposal)

            #expect(try String(contentsOf: fixture.rootURL.appendingPathComponent("once.txt"), encoding: .utf8) == "one\n")
        }
    }

    @Test("Projection preserves a pending mutation for an explicit UI decision")
    func projectionPreservesPendingApproval() {
        let proposal = WorkspaceMutationProposal(
            operation: .writeFile,
            relativePath: "new.txt",
            expectedContent: nil,
            proposedContent: "hello\n",
            preview: "--- /dev/null\n+++ new.txt\n+hello"
        )
        var projection = AgentMessageProjection(
            message: ChatMessage(role: .assistant, content: "", isStreaming: true)
        )
        projection.apply(.toolRequested(ToolCall(
            id: "write-2",
            type: "function",
            function: .init(name: "workspace_write_file", arguments: "{}")
        )))
        projection.apply(.toolCompleted(AgentToolResult(
            callId: "write-2",
            toolName: "workspace_write_file",
            content: "Approval required",
            isSuccess: true,
            mutationProposal: proposal
        )))

        #expect(projection.message.toolExecutions.first?.mutationProposal == proposal)
        #expect(projection.message.toolExecutions.first?.approvalState == .pending)
    }

    @Test("Native agent runtime preserves mutation proposal metadata in completion events")
    func runtimePreservesMutationProposal() async throws {
        let call = ToolCall(
            id: "proposal-call",
            type: "function",
            function: .init(name: "workspace_write_file", arguments: "{}")
        )
        let proposal = WorkspaceMutationProposal(
            operation: .writeFile,
            relativePath: "new.txt",
            expectedContent: nil,
            proposedContent: "hello",
            preview: "+hello"
        )
        let inference = ScriptedAgentInference(turns: [
            [.toolCall(call), .finished],
            [.contentDelta("Awaiting approval."), .finished]
        ])
        let executor = ScriptedAgentToolExecutor()
        await executor.registerResult(
            AgentToolResult(
                callId: call.id,
                toolName: call.function.name,
                content: "Approval required",
                isSuccess: true,
                mutationProposal: proposal
            ),
            forCallId: call.id
        )
        let runtime = NativeAgentRuntime(inference: inference, toolExecutor: executor)

        var completedProposal: WorkspaceMutationProposal?
        for try await event in runtime.run(history: [ChatMessage(role: .user, content: "write")]) {
            if case .toolCompleted(let result) = event {
                completedProposal = result.mutationProposal
            }
        }

        #expect(completedProposal == proposal)
    }

    @Test("Chat approval applies the persisted proposal and rejection leaves the workspace unchanged")
    @MainActor
    func chatApprovalAndRejection() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
            let storageFixture = try TemporaryStorageFixture()
            defer { storageFixture.tearDown() }
            let defaults = try #require(UserDefaults(suiteName: "MutationApproval.\(UUID().uuidString)"))
            let appState = AppState(
                startServices: false,
                workspaceAuthorizationService: WorkspaceAuthorizationService(
                    userDefaults: defaults,
                    bookmarker: TestWorkspaceBookmarker(),
                    scopeAccessor: TestWorkspaceSecurityScopeAccessor()
                ),
                userDefaults: defaults,
                storage: storageFixture.storage
            )

            let approvedProposal = WorkspaceMutationProposal(
                operation: .writeFile,
                relativePath: "approved.txt",
                expectedContent: nil,
                proposedContent: "approved\n",
                preview: "+approved"
            )
            let rejectedProposal = WorkspaceMutationProposal(
                operation: .writeFile,
                relativePath: "rejected.txt",
                expectedContent: nil,
                proposedContent: "rejected\n",
                preview: "+rejected"
            )
            let assistantID = UUID()
            let conversation = Conversation(
                title: "Mutation review",
                messages: [ChatMessage(
                    id: assistantID,
                    role: .assistant,
                    content: "",
                    toolExecutions: [
                        ToolExecution(
                            id: "approved-call",
                            toolName: "workspace_write_file",
                            input: "{}",
                            output: "Approval required",
                            isSuccess: true,
                            mutationProposal: approvedProposal,
                            approvalState: .pending
                        ),
                        ToolExecution(
                            id: "rejected-call",
                            toolName: "workspace_write_file",
                            input: "{}",
                            output: "Approval required",
                            isSuccess: true,
                            mutationProposal: rejectedProposal,
                            approvalState: .pending
                        )
                    ]
                )],
                projectPath: fixture.rootURL.path
            )
            appState.conversations = [conversation]
            appState.selectedConversationId = conversation.id
            appState.setConversationWorkspace(id: conversation.id, url: fixture.rootURL)

            let viewModel = ChatViewModel()
            appState.setConversation(conversation.id, isGenerating: true)
            await viewModel.approveWorkspaceMutation(
                conversationID: conversation.id,
                messageID: assistantID,
                executionID: "approved-call",
                appState: appState
            )
            #expect(FileManager.default.fileExists(atPath: fixture.rootURL.appendingPathComponent("approved.txt").path) == false)
            #expect(appState.selectedConversation?.messages.first?.toolExecutions[0].approvalState == .pending)

            appState.setConversation(conversation.id, isGenerating: false)
            await viewModel.approveWorkspaceMutation(
                conversationID: conversation.id,
                messageID: assistantID,
                executionID: "approved-call",
                appState: appState
            )
            await viewModel.approveWorkspaceMutation(
                conversationID: conversation.id,
                messageID: assistantID,
                executionID: "approved-call",
                appState: appState
            )
            viewModel.rejectWorkspaceMutation(
                conversationID: conversation.id,
                messageID: assistantID,
                executionID: "rejected-call",
                appState: appState
            )

            #expect(try String(contentsOf: fixture.rootURL.appendingPathComponent("approved.txt"), encoding: .utf8) == "approved\n")
            #expect(FileManager.default.fileExists(atPath: fixture.rootURL.appendingPathComponent("rejected.txt").path) == false)
            let updated = try #require(appState.selectedConversation?.messages.first)
            #expect(updated.toolExecutions[0].approvalState == .approved)
            #expect(updated.toolExecutions[1].approvalState == .rejected)
    }
}
