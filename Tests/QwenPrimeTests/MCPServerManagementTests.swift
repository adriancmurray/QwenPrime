import Foundation
import Testing
@testable import QwenPrime

@Suite("MCP server management")
struct MCPServerManagementTests {
    actor ProbeClient: MCPClientServing {
        let tools: [MCPRemoteTool]
        private(set) var didClose = false

        init(tools: [MCPRemoteTool]) {
            self.tools = tools
        }

        func listTools() async throws -> [MCPRemoteTool] { tools }

        func callTool(
            name: String,
            arguments: [String: JSONValue]
        ) async throws -> MCPRemoteToolResult {
            MCPRemoteToolResult(content: "unused", isError: false)
        }

        func close() async {
            didClose = true
        }
    }

    @Test("Legacy single-server defaults migrate into one editable profile")
    @MainActor
    func legacySettingsMigrate() throws {
        let suiteName = "QwenPrimeTests-MCPMigration-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: "isMCPServerEnabled")
        defaults.set("Legacy Tools", forKey: "mcpServerDisplayName")
        defaults.set("http://localhost:9312/mcp", forKey: "mcpServerEndpoint")

        let appState = AppState(startServices: false, userDefaults: defaults)

        #expect(appState.mcpServers == [
            MCPServerProfile(
                id: "local",
                displayName: "Legacy Tools",
                endpoint: "http://localhost:9312/mcp",
                isEnabled: true
            )
        ])
    }

    @Test("Multiple server profiles persist with independent enabled state")
    @MainActor
    func profilesPersist() throws {
        let suiteName = "QwenPrimeTests-MCPProfiles-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(startServices: false, userDefaults: defaults)
        appState.mcpServers = [
            MCPServerProfile(
                id: "docs",
                displayName: "Docs",
                endpoint: "http://127.0.0.1:3001/mcp",
                isEnabled: true
            ),
            MCPServerProfile(
                id: "build",
                displayName: "Build",
                endpoint: "http://localhost:3002/mcp",
                isEnabled: false
            )
        ]

        let reloaded = AppState(startServices: false, userDefaults: defaults)

        #expect(reloaded.mcpServers == appState.mcpServers)
        #expect(reloaded.enabledMCPServerConfigurations.map(\.id) == ["docs"])
    }

    @Test("Connection test records discovered tools and closes the probe client")
    @MainActor
    func testConnectionDiscoversTools() async throws {
        let suiteName = "QwenPrimeTests-MCPProbe-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let appState = AppState(startServices: false, userDefaults: defaults)
        appState.mcpServers = [
            MCPServerProfile(
                id: "local",
                displayName: "Local MCP",
                endpoint: "http://127.0.0.1:3001/mcp",
                isEnabled: true
            )
        ]
        let client = ProbeClient(tools: [
            MCPRemoteTool(
                name: "add_numbers",
                description: "Adds two numbers",
                inputSchema: .object(["type": .string("object")])
            )
        ])

        await appState.testMCPServer(id: "local") { _ in client }

        #expect(
            appState.mcpServerConnectionStates["local"]
                == .connected(tools: [
                    MCPDiscoveredTool(name: "add_numbers", description: "Adds two numbers")
                ])
        )
        #expect(await client.didClose)
    }
}
