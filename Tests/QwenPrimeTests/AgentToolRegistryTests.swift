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

    @Test("An explicitly named tool is the only definition advertised to inference")
    func explicitToolMentionNarrowsAdvertisedCatalog() throws {
        let readDefinition = toolDefinition(named: "workspace_read_file")
        let mcpDefinition = toolDefinition(named: "mcp__local__add_numbers")
        let executor = ScriptedAgentToolExecutor(tools: [readDefinition, mcpDefinition])
        let registry = try AgentToolRegistry(
            providers: [
                provider(id: "workspace", definition: readDefinition, executor: executor),
                provider(id: "mcp.local", definition: mcpDefinition, executor: executor)
            ]
        )

        let narrowed = registry.advertisingExplicitToolMentions(
            in: "Call mcp__local__add_numbers with 17 and 25."
        )

        #expect(narrowed.tools.map(\.function.name) == ["mcp__local__add_numbers"])
    }

    @Test("Natural-language requests advertise only the most relevant bounded tool set")
    func semanticSelectionNarrowsAdvertisedCatalog() throws {
        let readDefinition = toolDefinition(
            named: "workspace_read_file",
            description: "Read UTF-8 text content from a file in the workspace."
        )
        let writeDefinition = toolDefinition(
            named: "workspace_write_file",
            description: "Create or replace a UTF-8 text file after user approval."
        )
        let mcpDefinition = toolDefinition(
            named: "mcp__local__add_numbers",
            description: "Add two integer numbers."
        )
        let executor = ScriptedAgentToolExecutor(tools: [readDefinition, writeDefinition, mcpDefinition])
        let registry = try AgentToolRegistry(
            providers: [
                provider(id: "workspace", definition: readDefinition, executor: executor),
                provider(id: "workspace", definition: writeDefinition, executor: executor),
                provider(id: "mcp.local", definition: mcpDefinition, executor: executor)
            ]
        )

        let selected = registry.selectingRelevantTools(
            for: "Read Package.swift and summarize its contents.",
            maximumCount: 1
        )

        #expect(selected.tools.map(\.function.name) == ["workspace_read_file"])
    }

    @Test("Semantic selection is stable and preserves the selected executor route")
    func semanticSelectionIsStableAndRoutable() async throws {
        let readDefinition = toolDefinition(
            named: "workspace_read_file",
            description: "Read UTF-8 text content from a file in the workspace."
        )
        let writeDefinition = toolDefinition(
            named: "workspace_write_file",
            description: "Create or replace a UTF-8 text file after user approval."
        )
        let executor = ScriptedAgentToolExecutor(tools: [readDefinition, writeDefinition])
        await executor.registerResult(
            AgentToolResult(
                callId: "ignored",
                toolName: "workspace_write_file",
                content: "proposal queued",
                isSuccess: true
            ),
            forToolName: "workspace_write_file"
        )
        let registry = try AgentToolRegistry(
            providers: [
                provider(id: "workspace", definition: readDefinition, executor: executor),
                provider(id: "workspace", definition: writeDefinition, executor: executor)
            ]
        )

        let first = registry.selectingRelevantTools(
            for: "Create a new text file named notes.txt.",
            maximumCount: 1
        )
        let second = registry.selectingRelevantTools(
            for: "Create a new text file named notes.txt.",
            maximumCount: 1
        )

        #expect(first.tools.map(\.function.name) == ["workspace_write_file"])
        #expect(second.tools == first.tools)

        let result = try await first.execute(
            ToolCall(
                id: "write-1",
                function: .init(name: "workspace_write_file", arguments: "{}")
            )
        )
        #expect(result.content == "proposal queued")
    }

    @Test("Selection telemetry reports a smaller advertised schema budget")
    func selectionTelemetryReportsSchemaReduction() throws {
        let definitions = [
            toolDefinition(named: "workspace_read_file", description: "Read a file."),
            toolDefinition(named: "workspace_write_file", description: "Create a file."),
            toolDefinition(named: "mcp__local__add_numbers", description: "Add numbers.")
        ]
        let executor = ScriptedAgentToolExecutor(tools: definitions)
        let registry = try AgentToolRegistry(
            providers: definitions.enumerated().map { index, definition in
                provider(id: "provider-\(index)", definition: definition, executor: executor)
            }
        )
        let selected = registry.selectingRelevantTools(
            for: "Read Package.swift.",
            maximumCount: 1
        )

        #expect(registry.estimatedSchemaTokens > selected.estimatedSchemaTokens)
        #expect(selected.estimatedSchemaTokens > 0)
    }

    @Test("Benchmark full-catalog mode bypasses semantic reduction")
    func fullCatalogBenchmarkModeBypassesReduction() throws {
        let definitions = [
            toolDefinition(named: "workspace_read_file", description: "Read a file."),
            toolDefinition(named: "workspace_write_file", description: "Create a file.")
        ]
        let executor = ScriptedAgentToolExecutor(tools: definitions)
        let registry = try AgentToolRegistry(
            providers: definitions.enumerated().map { index, definition in
                provider(id: "provider-\(index)", definition: definition, executor: executor)
            }
        )

        let selected = registry.selectingRelevantTools(
            for: "Read Package.swift.",
            maximumCount: 1,
            mode: .fullCatalog
        )

        #expect(selected.tools == registry.tools)
    }

    @Test("Natural-language workspace intents retain their required specialized tool")
    func naturalLanguageWorkspaceIntentsRetainRequiredTools() throws {
        let definitions = [
            ReadOnlyWorkspaceToolBroker.listDirectoryDefinition,
            ReadOnlyWorkspaceToolBroker.readFileDefinition,
            ReadOnlyWorkspaceToolBroker.findFilesDefinition,
            ReadOnlyWorkspaceToolBroker.searchTextDefinition,
            WorkspaceToolBroker.writeFileDefinition,
            WorkspaceToolBroker.applyPatchDefinition,
            WorkspaceToolBroker.applyChangesDefinition,
            WorkspaceToolBroker.runCommandDefinition,
            WorkspaceToolBroker.listTasksDefinition,
            WorkspaceToolBroker.runTaskDefinition
        ]
        let executor = ScriptedAgentToolExecutor(tools: definitions)
        let registry = try AgentToolRegistry(
            providers: definitions.enumerated().map { index, definition in
                provider(id: "workspace-\(index)", definition: definition, executor: executor)
            }
        )
        let cases: [(prompt: String, requiredTool: String)] = [
            ("Find files whose names contain WorkspaceToolBroker.", "workspace_find_files"),
            ("Search the Swift sources for the literal text workspace_search_text.", "workspace_search_text"),
            ("Create a new UTF-8 text file named notes.txt.", "workspace_write_file"),
            ("Replace one exact text occurrence in Package.swift.", "workspace_apply_patch"),
            ("Apply exact replacements across three existing files as one change.", "workspace_apply_changes"),
            ("Inspect the current Git branch metadata.", "workspace_run_command"),
            ("Discover the available fixed Swift build and test tasks.", "workspace_list_tasks"),
            ("Run the Swift test task for this package.", "workspace_run_task")
        ]

        for testCase in cases {
            let selectedNames = Set(
                registry.selectingRelevantTools(for: testCase.prompt).tools.map(\.function.name)
            )
            #expect(
                selectedNames.contains(testCase.requiredTool),
                "Expected \(testCase.requiredTool) for prompt: \(testCase.prompt); got \(selectedNames.sorted())"
            )
        }
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

    private func toolDefinition(named name: String, description: String? = nil) -> ToolDefinition {
        ToolDefinition(
            function: .init(
                name: name,
                description: description,
                parameters: .object(["type": .string("object")])
            )
        )
    }
}
