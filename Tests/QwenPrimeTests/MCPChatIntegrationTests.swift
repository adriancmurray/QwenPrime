import Foundation
import Testing
@testable import QwenPrime

@Suite("MCP chat integration")
struct MCPChatIntegrationTests {
    actor ProviderFactoryTracker {
        private(set) var configurations: [MCPServerConfiguration] = []

        func record(_ configuration: MCPServerConfiguration) {
            configurations.append(configuration)
        }
    }

    enum TestFailure: Error {
        case unavailable
    }

    @Test("Enabled MCP provider is added beside native workspace tools")
    @MainActor
    func enabledProviderIsAddedToAgentRegistry() async throws {
        let (defaults, suiteName) = try ChatIntegrationTestHelpers.makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageFixture = try TemporaryStorageFixture()
        defer { storageFixture.tearDown() }

        let appState = AppState(
            startServices: false,
            userDefaults: defaults,
            storage: storageFixture.storage
        )
        appState.serverStatus = .connected(model: "qwen-test", latencyMs: 1)
        appState.runtimeSupportsStructuredToolCalls = true
        appState.isMCPServerEnabled = true
        appState.mcpServerDisplayName = "Project Tools"
        appState.mcpServerEndpoint = "http://127.0.0.1:9312/mcp"

        let conversation = Conversation(
            title: "MCP tools",
            projectPath: appState.sandboxDirectory.path
        )
        appState.conversations = [conversation]
        appState.selectedConversationId = conversation.id
        appState.setAgentMode(true, for: conversation.id)

        let inference = ScriptedAgentInference(turns: [[
            .contentDelta("Tools discovered."),
            .finished
        ]])
        let tracker = ProviderFactoryTracker()
        let executor = ScriptedAgentToolExecutor()
        let providerFactory: MCPToolProviderFactory = { configuration, _ in
            await tracker.record(configuration)
            return AgentToolProviderRegistration(
                id: "mcp.local",
                displayName: configuration.displayName,
                tools: [
                    AgentToolRegistration(
                        definition: ToolDefinition(
                            function: .init(
                                name: "mcp__local__lookup",
                                description: "Look up project metadata",
                                parameters: .object(["type": .string("object")])
                            )
                        ),
                        authorization: .userApproval
                    )
                ],
                executor: executor
            )
        }
        let viewModel = ChatViewModel(
            agentInference: inference,
            mcpToolProviderFactory: providerFactory
        )

        viewModel.inputText = "Discover tools"
        viewModel.sendMessage(appState: appState)
        try await AsyncCondition.wait(description: "MCP-enabled run completes") {
            !appState.isConversationGenerating(conversation.id)
        }

        let tools = try #require((await inference.getCapturedTools()).first ?? nil)
        #expect(tools.contains(where: { $0.function.name == "workspace_read_file" }))
        #expect(tools.contains(where: { $0.function.name == "mcp__local__lookup" }))
        #expect(await tracker.configurations.first?.displayName == "Project Tools")
        #expect(appState.mcpConnectionError == nil)
    }

    @Test("Explicit MCP tool requests advertise only the named tool")
    @MainActor
    func explicitMCPToolRequestNarrowsInferenceCatalog() async throws {
        let (defaults, suiteName) = try ChatIntegrationTestHelpers.makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageFixture = try TemporaryStorageFixture()
        defer { storageFixture.tearDown() }

        let appState = AppState(
            startServices: false,
            userDefaults: defaults,
            storage: storageFixture.storage
        )
        appState.serverStatus = .connected(model: "qwen-test", latencyMs: 1)
        appState.runtimeSupportsStructuredToolCalls = true
        appState.isMCPServerEnabled = true

        let conversation = Conversation(
            title: "Focused MCP tool",
            projectPath: appState.sandboxDirectory.path
        )
        appState.conversations = [conversation]
        appState.selectedConversationId = conversation.id
        appState.setAgentMode(true, for: conversation.id)

        let inference = ScriptedAgentInference(turns: [[.contentDelta("42"), .finished]])
        let executor = ScriptedAgentToolExecutor()
        let viewModel = ChatViewModel(
            agentInference: inference,
            mcpToolProviderFactory: { configuration, _ in
                AgentToolProviderRegistration(
                    id: "mcp.\(configuration.id)",
                    displayName: configuration.displayName,
                    tools: ["add_numbers", "test_audio", "test_sampling"].map { name in
                        AgentToolRegistration(
                            definition: ToolDefinition(
                                function: .init(
                                    name: "mcp__local__\(name)",
                                    parameters: .object(["type": .string("object")])
                                )
                            ),
                            authorization: .userApproval
                        )
                    },
                    executor: executor
                )
            }
        )

        viewModel.inputText = "Call mcp__local__add_numbers with 17 and 25."
        viewModel.sendMessage(appState: appState)
        try await AsyncCondition.wait(description: "focused MCP run completes") {
            !appState.isConversationGenerating(conversation.id)
        }

        let tools = try #require((await inference.getCapturedTools()).first ?? nil)
        #expect(tools.map(\.function.name) == ["mcp__local__add_numbers"])
    }

    @Test("Unavailable MCP provider does not disable native workspace tools")
    @MainActor
    func unavailableProviderDegradesLocally() async throws {
        let (defaults, suiteName) = try ChatIntegrationTestHelpers.makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageFixture = try TemporaryStorageFixture()
        defer { storageFixture.tearDown() }

        let appState = AppState(
            startServices: false,
            userDefaults: defaults,
            storage: storageFixture.storage
        )
        appState.serverStatus = .connected(model: "qwen-test", latencyMs: 1)
        appState.runtimeSupportsStructuredToolCalls = true
        appState.isMCPServerEnabled = true

        let conversation = Conversation(
            title: "MCP fallback",
            projectPath: appState.sandboxDirectory.path
        )
        appState.conversations = [conversation]
        appState.selectedConversationId = conversation.id
        appState.setAgentMode(true, for: conversation.id)

        let inference = ScriptedAgentInference(turns: [[
            .contentDelta("Native tools remain available."),
            .finished
        ]])
        let viewModel = ChatViewModel(
            agentInference: inference,
            mcpToolProviderFactory: { _, _ in throw TestFailure.unavailable }
        )

        viewModel.inputText = "Use native tools"
        viewModel.sendMessage(appState: appState)
        try await AsyncCondition.wait(description: "MCP fallback run completes") {
            !appState.isConversationGenerating(conversation.id)
        }

        let tools = try #require((await inference.getCapturedTools()).first ?? nil)
        #expect(tools.contains(where: { $0.function.name == "workspace_read_file" }))
        #expect(!tools.contains(where: { $0.function.name.hasPrefix("mcp__") }))
        #expect(appState.mcpConnectionError != nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("Every enabled MCP server is registered while disabled servers are skipped")
    @MainActor
    func multipleEnabledProvidersAreAddedToAgentRegistry() async throws {
        let (defaults, suiteName) = try ChatIntegrationTestHelpers.makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageFixture = try TemporaryStorageFixture()
        defer { storageFixture.tearDown() }

        let appState = AppState(
            startServices: false,
            userDefaults: defaults,
            storage: storageFixture.storage
        )
        appState.serverStatus = .connected(model: "qwen-test", latencyMs: 1)
        appState.runtimeSupportsStructuredToolCalls = true
        appState.mcpServers = [
            MCPServerProfile(
                id: "docs",
                displayName: "Docs",
                endpoint: "http://127.0.0.1:9312/mcp",
                isEnabled: true
            ),
            MCPServerProfile(
                id: "build",
                displayName: "Build",
                endpoint: "http://localhost:9313/mcp",
                isEnabled: true
            ),
            MCPServerProfile(
                id: "disabled",
                displayName: "Disabled",
                endpoint: "http://127.0.0.1:9314/mcp",
                isEnabled: false
            )
        ]

        let conversation = Conversation(
            title: "Multiple MCP tools",
            projectPath: appState.sandboxDirectory.path
        )
        appState.conversations = [conversation]
        appState.selectedConversationId = conversation.id
        appState.setAgentMode(true, for: conversation.id)

        let inference = ScriptedAgentInference(turns: [[.contentDelta("Ready."), .finished]])
        let tracker = ProviderFactoryTracker()
        let executor = ScriptedAgentToolExecutor()
        let viewModel = ChatViewModel(
            agentInference: inference,
            mcpToolProviderFactory: { configuration, _ in
                await tracker.record(configuration)
                return AgentToolProviderRegistration(
                    id: "mcp.\(configuration.id)",
                    displayName: configuration.displayName,
                    tools: [
                        AgentToolRegistration(
                            definition: ToolDefinition(
                                function: .init(
                                    name: "mcp__\(configuration.id)__status",
                                    description: nil,
                                    parameters: .object(["type": .string("object")])
                                )
                            ),
                            authorization: .userApproval
                        )
                    ],
                    executor: executor
                )
            }
        )

        viewModel.inputText = "Load both servers"
        viewModel.sendMessage(appState: appState)
        try await AsyncCondition.wait(description: "multi-MCP run completes") {
            !appState.isConversationGenerating(conversation.id)
        }

        let configurations = await tracker.configurations
        #expect(Set(configurations.map(\.id)) == Set(["docs", "build"]))
        let tools = try #require((await inference.getCapturedTools()).first ?? nil)
        #expect(tools.contains(where: { $0.function.name == "mcp__docs__status" }))
        #expect(tools.contains(where: { $0.function.name == "mcp__build__status" }))
        #expect(!tools.contains(where: { $0.function.name.contains("disabled") }))
    }
}
