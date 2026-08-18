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
}
