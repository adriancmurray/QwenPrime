import Foundation
import Testing
@testable import QwenPrime

@Suite("Agent tool provider registry")
struct AgentToolRegistryTests {
    @Test("Workspace provider marks only mutating and executing tools as approval required")
    @MainActor
    func workspaceProviderAuthorizationMetadata() async throws {
        let fixture = try WorkspaceTestFixture()
        defer { fixture.tearDown() }
        let reader = try ReadOnlyWorkspaceService(rootURL: fixture.rootURL)
        let broker = WorkspaceToolBroker(
            readService: reader,
            mutationService: WorkspaceMutationService(readService: reader),
            approvalRequester: ConversationWorkspaceApprovalRequester(
                coordinator: WorkspaceApprovalCoordinator(),
                conversationID: UUID(),
                messageID: UUID()
            )
        )

        let provider = broker.providerRegistration
        let authorization: [String: AgentToolAuthorization] = Dictionary(
            uniqueKeysWithValues: provider.tools.map {
                ($0.definition.function.name, $0.authorization)
            }
        )

        #expect(provider.id == "workspace")
        #expect(authorization["workspace_read_file"] == .readOnly)
        #expect(authorization["workspace_search_text"] == .readOnly)
        #expect(authorization["workspace_write_file"] == .userApproval)
        #expect(authorization["workspace_apply_changes"] == .userApproval)
    }

    @Test("Catalog preserves provider identity and routes execution")
    func catalogAndRouting() async throws {
        let definition = toolDefinition(named: "fixture_read")
        let executor = ScriptedAgentToolExecutor(tools: [definition])
        await executor.registerResult(
            AgentToolResult(
                callId: "ignored",
                toolName: "fixture_read",
                content: "provider result",
                isSuccess: true
            ),
            forToolName: "fixture_read"
        )
        let registry = try AgentToolRegistry(
            providers: [
                AgentToolProviderRegistration(
                    id: "fixture",
                    displayName: "Fixture Tools",
                    tools: [
                        AgentToolRegistration(
                            definition: definition,
                            authorization: .readOnly
                        )
                    ],
                    executor: executor
                )
            ]
        )

        #expect(registry.tools == [definition])
        #expect(registry.catalog == [
            AgentToolCatalogEntry(
                providerID: "fixture",
                providerDisplayName: "Fixture Tools",
                definition: definition,
                authorization: .readOnly
            )
        ])

        let result = try await registry.execute(
            ToolCall(
                id: "call-1",
                function: .init(name: "fixture_read", arguments: "{}")
            )
        )
        #expect(result.callId == "call-1")
        #expect(result.content == "provider result")
        #expect(await executor.getExecutedCalls().map(\.id) == ["call-1"])
    }

    @Test("Duplicate tool names are rejected before inference")
    func rejectsDuplicateToolNames() {
        let definition = toolDefinition(named: "duplicate")
        let first = ScriptedAgentToolExecutor(tools: [definition])
        let second = ScriptedAgentToolExecutor(tools: [definition])

        #expect(throws: AgentToolRegistryError.duplicateToolName("duplicate")) {
            _ = try AgentToolRegistry(
                providers: [
                    provider(id: "first", definition: definition, executor: first),
                    provider(id: "second", definition: definition, executor: second)
                ]
            )
        }
    }

    @Test("Unknown tool calls fail without reaching a provider")
    func rejectsUnknownToolCalls() async throws {
        let definition = toolDefinition(named: "known")
        let executor = ScriptedAgentToolExecutor(tools: [definition])
        let registry = try AgentToolRegistry(
            providers: [provider(id: "fixture", definition: definition, executor: executor)]
        )

        let result = try await registry.execute(
            ToolCall(
                id: "missing-1",
                function: .init(name: "missing", arguments: "{}")
            )
        )

        #expect(!result.isSuccess)
        #expect(result.content == "Unknown tool: missing")
        #expect(await executor.getExecutedCalls().isEmpty)
    }

    private func provider(
        id: String,
        definition: ToolDefinition,
        executor: any AgentToolExecuting
    ) -> AgentToolProviderRegistration {
        AgentToolProviderRegistration(
            id: id,
            displayName: id,
            tools: [
                AgentToolRegistration(
                    definition: definition,
                    authorization: .readOnly
                )
            ],
            executor: executor
        )
    }

    private func toolDefinition(named name: String) -> ToolDefinition {
        ToolDefinition(
            function: .init(
                name: name,
                parameters: .object(["type": .string("object")])
            )
        )
    }
}
