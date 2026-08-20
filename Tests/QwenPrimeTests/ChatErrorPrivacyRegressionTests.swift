import Foundation
import Testing

@testable import QwenPrime

@Suite("Chat error privacy regressions")
struct ChatErrorPrivacyRegressionTests {
  private static let genericFailure =
    "Unable to generate a response. Please try again."
  private static let assistantFailure =
    "⚠️ Error: Unable to generate a response. Please try again."

  private struct SensitiveFailure: LocalizedError, Sendable {
    let detail: String

    var errorDescription: String? { detail }
  }

  @Test("Direct-stream failures never expose transport details")
  @MainActor
  func directStreamFailureIsGeneric() async throws {
    let fixture = try makeAppState(testName: "DirectFailure")
    defer { fixture.cleanUp() }
    let sensitiveDetail = "api-key=private-direct-secret"
    let streamScope = MockSSEScope { _ in
      throw SensitiveFailure(detail: sensitiveDetail)
    }
    defer { streamScope.tearDown() }
    let conversation = Conversation(title: "Direct failure")
    fixture.appState.baseURL = streamScope.baseURL
    fixture.appState.serverStatus = .connected(model: "test", latencyMs: 1)
    fixture.appState.conversations = [conversation]
    fixture.appState.selectedConversationId = conversation.id
    let viewModel = ChatViewModel(
      client: QwenClient(session: streamScope.session)
    )
    viewModel.inputText = "Trigger direct failure"

    viewModel.sendMessage(appState: fixture.appState)
    try await waitForGeneration(
      conversationID: conversation.id,
      appState: fixture.appState
    )

    let assistant = try assistantMessage(
      conversationID: conversation.id,
      appState: fixture.appState
    )
    #expect(viewModel.errorMessage == Self.genericFailure)
    #expect(assistant.content == Self.assistantFailure)
    #expect(!assistant.content.contains(sensitiveDetail))
  }

  @Test("Agent failures never expose runtime details")
  @MainActor
  func agentFailureIsGeneric() async throws {
    let fixture = try makeAppState(testName: "AgentFailure")
    defer { fixture.cleanUp() }
    let sensitiveDetail = "workspace-token=private-agent-secret"
    let conversation = configuredAgentConversation(in: fixture.appState)
    let viewModel = ChatViewModel(
      agentRuntimeFactory: { _ in
        throw SensitiveFailure(detail: sensitiveDetail)
      }
    )
    viewModel.inputText = "Trigger agent failure"

    viewModel.sendMessage(appState: fixture.appState)
    try await waitForGeneration(
      conversationID: conversation.id,
      appState: fixture.appState
    )

    let assistant = try assistantMessage(
      conversationID: conversation.id,
      appState: fixture.appState
    )
    #expect(viewModel.errorMessage == Self.genericFailure)
    #expect(assistant.content == Self.assistantFailure)
    #expect(!assistant.content.contains(sensitiveDetail))
  }

  @Test("MCP provider failures expose only the server name")
  @MainActor
  func mcpProviderFailureIsGeneric() async throws {
    let fixture = try makeAppState(testName: "MCPFailure")
    defer { fixture.cleanUp() }
    let sensitiveDetail = "mcp-auth=private-provider-secret"
    let conversation = configuredAgentConversation(in: fixture.appState)
    let profile = MCPServerProfile(
      id: "private-provider",
      displayName: "Build Tools",
      endpoint: "http://127.0.0.1:9333/mcp",
      isEnabled: true
    )
    fixture.appState.mcpServers = [profile]
    let inference = ScriptedAgentInference(
      turns: [[.contentDelta("Ready."), .finished]]
    )
    let viewModel = ChatViewModel(
      agentInference: inference,
      mcpToolProviderFactory: { _, _ in
        throw SensitiveFailure(detail: sensitiveDetail)
      }
    )
    viewModel.inputText = "Trigger MCP connection"

    viewModel.sendMessage(appState: fixture.appState)
    try await waitForGeneration(
      conversationID: conversation.id,
      appState: fixture.appState
    )

    #expect(
      fixture.appState.mcpServerConnectionStates[profile.id]
        == .failed(message: "Could not connect to Build Tools.")
    )
  }

  @MainActor
  private func configuredAgentConversation(in appState: AppState) -> Conversation {
    appState.serverStatus = .connected(model: "test", latencyMs: 1)
    appState.runtimeSupportsStructuredToolCalls = true
    let conversation = Conversation(
      title: "Agent failure",
      projectPath: appState.sandboxDirectory.path
    )
    appState.conversations = [conversation]
    appState.selectedConversationId = conversation.id
    appState.setAgentMode(true, for: conversation.id)
    return conversation
  }

  @MainActor
  private func waitForGeneration(
    conversationID: UUID,
    appState: AppState
  ) async throws {
    try await AsyncCondition.wait(description: "private failure handling") {
      !appState.isConversationGenerating(conversationID)
    }
  }

  @MainActor
  private func assistantMessage(
    conversationID: UUID,
    appState: AppState
  ) throws -> ChatMessage {
    let conversation = try #require(
      appState.conversations.first(where: { $0.id == conversationID })
    )
    return try #require(
      conversation.messages.last(where: { $0.role == .assistant })
    )
  }

  @MainActor
  private func makeAppState(testName: String) throws -> AppStateFixture {
    let suiteName = "QwenPrimeTests-ChatPrivacy-\(testName)-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    return AppStateFixture(
      appState: AppState(startServices: false, userDefaults: defaults),
      defaults: defaults,
      suiteName: suiteName
    )
  }

  private struct AppStateFixture {
    let appState: AppState
    let defaults: UserDefaults
    let suiteName: String

    func cleanUp() {
      defaults.removePersistentDomain(forName: suiteName)
    }
  }
}
