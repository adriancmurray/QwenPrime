import Foundation
import Testing
@testable import QwenPrime

@Suite("Reviewed multi-file workspace changes")
struct WorkspaceChangeSetTests {
    @Test("A change set combines exact replacements into one review")
    func combinedReview() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "Sources/A.swift", content: "let value = \"alpha\"\n")
            try fixture.createFile(at: "Sources/B.swift", content: "let value = \"beta\"\n")
            let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let service = WorkspaceMutationService(readService: reader)

            let changeSet = try await service.prepareChangeSet(replacements: [
                WorkspaceTextReplacement(path: "Sources/A.swift", oldText: "alpha", newText: "ALPHA"),
                WorkspaceTextReplacement(path: "Sources/B.swift", oldText: "beta", newText: "BETA")
            ])

            #expect(changeSet.changes.count == 2)
            #expect(changeSet.reviewProposal.operation == .changeSet)
            #expect(changeSet.reviewProposal.relativePath == "2 files")
            #expect(changeSet.reviewProposal.preview.contains("Sources/A.swift"))
            #expect(changeSet.reviewProposal.preview.contains("Sources/B.swift"))
        }
    }

    @Test("A stale file prevents every change from being written")
    func stalePreflightPreventsPartialWrite() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "A.txt", content: "alpha\n")
            let staleURL = try fixture.createFile(at: "B.txt", content: "beta\n")
            let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let service = WorkspaceMutationService(readService: reader)
            let changeSet = try await service.prepareChangeSet(replacements: [
                WorkspaceTextReplacement(path: "A.txt", oldText: "alpha", newText: "ALPHA"),
                WorkspaceTextReplacement(path: "B.txt", oldText: "beta", newText: "BETA")
            ])
            try "changed elsewhere\n".write(to: staleURL, atomically: true, encoding: .utf8)

            await #expect(throws: WorkspaceMutationError.staleProposal(path: "B.txt")) {
                try await service.apply(changeSet)
            }
            #expect(try String(contentsOf: fixture.rootURL.appendingPathComponent("A.txt"), encoding: .utf8) == "alpha\n")
        }
    }

    @Test("One approval applies every reviewed replacement")
    @MainActor
    func oneApprovalAppliesAllChanges() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        try fixture.createFile(at: "A.txt", content: "alpha\n")
        try fixture.createFile(at: "B.txt", content: "beta\n")
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
        #expect(broker.tools.map(\.function.name).contains("workspace_apply_changes"))
        let call = ToolCall(
            id: "change-set-approved",
            type: "function",
            function: .init(
                name: "workspace_apply_changes",
                arguments: #"{"changes":[{"path":"A.txt","old_text":"alpha","new_text":"ALPHA"},{"path":"B.txt","old_text":"beta","new_text":"BETA"}]}"#
            )
        )
        let execution = Task { try await broker.execute(call) }

        try await AsyncCondition.wait(description: "change-set approval pending") {
            coordinator.pendingRequests.count == 1
        }
        let approval = try #require(coordinator.pendingRequests.first)
        guard case .mutation(let proposal) = approval.payload else {
            Issue.record("Expected mutation approval payload")
            return
        }
        #expect(proposal.operation == .changeSet)
        #expect(coordinator.resolve(approval.id, decision: .approve))

        let result = try await execution.value
        #expect(result.isSuccess)
        #expect(result.approvalState == .approved)
        #expect(result.mutationProposal == proposal)
        #expect(try String(contentsOf: fixture.rootURL.appendingPathComponent("A.txt"), encoding: .utf8) == "ALPHA\n")
        #expect(try String(contentsOf: fixture.rootURL.appendingPathComponent("B.txt"), encoding: .utf8) == "BETA\n")
        #expect(coordinator.pendingRequests.isEmpty)
    }

    @Test("Rejecting the combined review leaves every file unchanged")
    @MainActor
    func rejectionLeavesAllChangesUnapplied() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        try fixture.createFile(at: "A.txt", content: "alpha\n")
        try fixture.createFile(at: "B.txt", content: "beta\n")
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
            id: "change-set-rejected",
            type: "function",
            function: .init(
                name: "workspace_apply_changes",
                arguments: #"{"changes":[{"path":"A.txt","old_text":"alpha","new_text":"ALPHA"},{"path":"B.txt","old_text":"beta","new_text":"BETA"}]}"#
            )
        )
        let execution = Task { try await broker.execute(call) }

        try await AsyncCondition.wait(description: "change-set approval pending") {
            coordinator.pendingRequests.count == 1
        }
        let approval = try #require(coordinator.pendingRequests.first)
        #expect(coordinator.resolve(approval.id, decision: .reject))

        let result = try await execution.value
        #expect(!result.isSuccess)
        #expect(result.approvalState == .rejected)
        #expect(try String(contentsOf: fixture.rootURL.appendingPathComponent("A.txt"), encoding: .utf8) == "alpha\n")
        #expect(try String(contentsOf: fixture.rootURL.appendingPathComponent("B.txt"), encoding: .utf8) == "beta\n")
    }

    @Test("Change sets reject duplicate paths and more than eight replacements")
    func boundedAndUnique() async throws {
        try await WorkspaceTestFixture.withFixture { fixture in
            try fixture.createFile(at: "value.txt", content: "one\n")
            let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
            let service = WorkspaceMutationService(readService: reader)
            let replacement = WorkspaceTextReplacement(path: "value.txt", oldText: "one", newText: "two")

            await #expect(throws: WorkspaceMutationError.duplicateChangePath(path: "value.txt")) {
                try await service.prepareChangeSet(replacements: [replacement, replacement])
            }
            await #expect(throws: WorkspaceMutationError.duplicateChangePath(path: "value.txt")) {
                try await service.prepareChangeSet(replacements: [
                    replacement,
                    WorkspaceTextReplacement(path: "./value.txt", oldText: "one", newText: "three")
                ])
            }
            await #expect(throws: WorkspaceMutationError.tooManyChanges(maximum: 8)) {
                try await service.prepareChangeSet(replacements: Array(repeating: replacement, count: 9))
            }
        }
    }
}
