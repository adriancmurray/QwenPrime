import Foundation
import Testing

@testable import QwenPrime

@Suite("MCP server management")
struct MCPServerManagementTests {
  private struct ProbeFailure: LocalizedError, Sendable {
    var errorDescription: String? { "Probe unavailable" }
  }

  actor ProbeClient: MCPClientServing {
    let tools: [MCPRemoteTool]
    let listToolsGate: TestExecutionGate?
    private(set) var didClose = false
    private(set) var didStartListing = false

    init(
      tools: [MCPRemoteTool],
      listToolsGate: TestExecutionGate? = nil
    ) {
      self.tools = tools
      self.listToolsGate = listToolsGate
    }

    func listTools() async throws -> [MCPRemoteTool] {
      didStartListing = true
      if let listToolsGate {
        await listToolsGate.wait()
      }
      return tools
    }

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
    defaults.set(
      true,
      forKey: AppState.UserDefaultsKey.isMCPServerEnabled.rawValue
    )
    defaults.set(
      "Legacy Tools",
      forKey: AppState.UserDefaultsKey.mcpServerDisplayName.rawValue
    )
    defaults.set(
      "http://localhost:9312/mcp",
      forKey: AppState.UserDefaultsKey.mcpServerEndpoint.rawValue
    )

    let appState = AppState(startServices: false, userDefaults: defaults)

    #expect(
      appState.mcpServers == [
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
      ),
    ]

    let reloaded = AppState(startServices: false, userDefaults: defaults)

    #expect(reloaded.mcpServers == appState.mcpServers)
    #expect(reloaded.enabledMCPServerConfigurations.map(\.id) == ["docs"])
  }

  @Test("Compatibility setters recreate and persist an empty server profile")
  @MainActor
  func compatibilitySettersRecreateEmptyProfile() throws {
    let suiteName = "QwenPrimeTests-MCPCompatibility-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    appState.mcpServers = []

    appState.mcpServerDisplayName = "Restored Tools"

    #expect(
      appState.mcpServers == [
        MCPServerProfile(
          id: "local",
          displayName: "Restored Tools"
        )
      ]
    )
    #expect(appState.mcpServerConnectionStates["local"] == .idle)
    let displayNameReload = AppState(
      startServices: false,
      userDefaults: defaults
    )
    #expect(displayNameReload.mcpServerDisplayName == "Restored Tools")

    displayNameReload.mcpServers = []
    displayNameReload.mcpServerEndpoint = "http://localhost:9312/mcp"

    #expect(displayNameReload.mcpServers.count == 1)
    #expect(
      displayNameReload.mcpServers.first?.endpoint
        == "http://localhost:9312/mcp"
    )
    #expect(displayNameReload.mcpServerConnectionStates["local"] == .idle)
    let endpointReload = AppState(
      startServices: false,
      userDefaults: defaults
    )
    #expect(endpointReload.mcpServers.count == 1)
    #expect(
      endpointReload.mcpServerEndpoint == "http://localhost:9312/mcp"
    )
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

  @Test("Editing a profile during its probe leaves connection state idle")
  @MainActor
  func concurrentProfileEditResetsProbeState() async throws {
    let suiteName = "QwenPrimeTests-MCPProbeEdit-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let profile = MCPServerProfile(
      id: "local",
      displayName: "Local MCP",
      endpoint: "http://127.0.0.1:3001/mcp",
      isEnabled: true
    )
    appState.mcpServers = [profile]
    let gate = TestExecutionGate()
    let client = ProbeClient(tools: [], listToolsGate: gate)
    let probeTask = Task {
      await appState.testMCPServer(id: profile.id) { _ in client }
    }

    do {
      try await AsyncCondition.wait(description: "MCP probe started") {
        await client.didStartListing
      }
    } catch {
      await gate.unblock()
      await probeTask.value
      throw error
    }
    #expect(appState.mcpServerConnectionStates[profile.id] == .testing)

    var editedProfile = profile
    editedProfile.displayName = "Edited During Probe"
    appState.updateMCPServer(editedProfile)

    #expect(appState.mcpServers == [editedProfile])
    #expect(appState.mcpServerConnectionStates[profile.id] == .idle)

    await gate.unblock()
    await probeTask.value

    #expect(appState.mcpServerConnectionStates[profile.id] == .idle)
    #expect(await client.didClose)
  }

  @Test("Connection failure records a user-facing failed state")
  @MainActor
  func connectionFailureRecordsFailedState() async throws {
    let suiteName = "QwenPrimeTests-MCPProbeFailure-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    appState.mcpServers = [MCPServerProfile(id: "local", isEnabled: true)]

    await appState.testMCPServer(id: "local") { _ in
      throw ProbeFailure()
    }

    #expect(
      appState.mcpServerConnectionStates["local"]
        == .failed(message: "Probe unavailable")
    )
  }

  @Test("Cancelled connection test returns the server to idle")
  @MainActor
  func cancelledConnectionReturnsToIdle() async throws {
    let suiteName = "QwenPrimeTests-MCPProbeCancellation-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    appState.mcpServers = [MCPServerProfile(id: "local", isEnabled: true)]
    appState.setMCPServerConnectionState(
      .failed(message: "Previous failure"),
      for: "local"
    )

    await appState.testMCPServer(id: "local") { _ in
      throw CancellationError()
    }

    #expect(appState.mcpServerConnectionStates["local"] == .idle)
  }

  @Test("Removing a server waits for explicit destructive confirmation")
  @MainActor
  func removeServerRequiresConfirmation() throws {
    let suiteName = "QwenPrimeTests-MCPRemoval-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let profile = MCPServerProfile(
      id: "local",
      displayName: "Local MCP",
      endpoint: "http://127.0.0.1:3001/mcp",
      isEnabled: false
    )
    appState.mcpServers = [profile]

    appState.requestRemoveMCPServer(id: profile.id)

    #expect(appState.mcpServers == [profile])
    #expect(
      appState.pendingConfirmation?.action
        == .removeMCPServer(profile.id)
    )

    appState.confirmPendingAction()

    #expect(appState.mcpServers.isEmpty)
    #expect(appState.pendingConfirmation == nil)
  }

  @Test("Removing an unknown server does not request confirmation")
  @MainActor
  func unknownServerRemovalIsNoOp() throws {
    let suiteName = "QwenPrimeTests-MCPUnknownRemoval-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let originalServers = appState.mcpServers

    appState.requestRemoveMCPServer(id: "missing-server")

    #expect(appState.pendingConfirmation == nil)
    #expect(appState.mcpServers == originalServers)
  }
}
