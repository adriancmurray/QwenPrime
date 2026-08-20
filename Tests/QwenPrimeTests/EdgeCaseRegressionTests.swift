import Foundation
import Testing

@testable import QwenPrime

@Suite("Edge-case regressions")
struct EdgeCaseRegressionTests {
  @Test("Out-of-order command acknowledgement removes only its matching request")
  @MainActor
  func commandAcknowledgementSupportsOutOfOrderDelivery() throws {
    let fixture = try makeAppState(testName: "CommandAcknowledgement")
    defer { fixture.cleanUp() }
    let appState = fixture.appState
    let firstConversation = Conversation()
    let secondConversation = Conversation()
    appState.conversations = [firstConversation, secondConversation]
    appState.setConversation(firstConversation.id, isGenerating: true)
    appState.setConversation(secondConversation.id, isGenerating: true)

    appState.selectedConversationId = firstConversation.id
    appState.requestStopGeneration()
    appState.selectedConversationId = secondConversation.id
    appState.requestStopGeneration()

    let requests = appState.pendingCommandRequests
    #expect(requests.count == 2)
    let firstRequest = try #require(requests.first)
    let secondRequest = try #require(requests.last)

    appState.acknowledgeCommandRequest(id: secondRequest.id)
    #expect(appState.pendingCommandRequests == [firstRequest])
    #expect(appState.pendingCommandRequest == firstRequest)

    appState.acknowledgeCommandRequest(id: UUID())
    #expect(appState.pendingCommandRequests == [firstRequest])

    appState.acknowledgeCommandRequest(id: firstRequest.id)
    #expect(appState.pendingCommandRequests.isEmpty)
    #expect(appState.pendingCommandRequest == nil)
  }

  @Test("Sending is ignored when another path already marked the conversation generating")
  @MainActor
  func sendMessageHonorsAppStateGenerationGuard() throws {
    let fixture = try makeAppState(testName: "GenerationGuard")
    defer { fixture.cleanUp() }
    let appState = fixture.appState
    let conversation = Conversation()
    appState.conversations = [conversation]
    appState.selectedConversationId = conversation.id
    appState.setConversation(conversation.id, isGenerating: true)
    let viewModel = ChatViewModel()
    viewModel.inputText = "Do not duplicate this request"

    viewModel.sendMessage(appState: appState)

    #expect(appState.selectedConversation?.messages.isEmpty == true)
    #expect(viewModel.inputText == "Do not duplicate this request")
    #expect(appState.isConversationGenerating(conversation.id))
  }

  @Test("Current-project matching is normalized and case-insensitive")
  func projectScopeUsesStandardMacOSPathComparison() {
    let currentProject = URL(
      fileURLWithPath: "/Users/Example/Workspace/QwenPrime"
    )

    #expect(
      ProjectScope.currentProject.includes(
        projectPath: "/users/example/workspace/Parent/../QWENPRIME/.",
        currentProjectDirectory: currentProject
      )
    )
    #expect(
      !ProjectScope.currentProject.includes(
        projectPath: "/users/example/workspace/qwenprime-copy",
        currentProjectDirectory: currentProject
      )
    )
  }

  @Test("Current-project matching resolves real symbolic links")
  func projectScopeResolvesSymbolicLinks() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appendingPathComponent(
      "QwenPrimeTests-ProjectScope-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? fileManager.removeItem(at: root) }
    let project = root.appendingPathComponent(
      "ActualProject",
      isDirectory: true
    )
    let projectAlias = root.appendingPathComponent(
      "ProjectAlias",
      isDirectory: true
    )
    try fileManager.createDirectory(
      at: project,
      withIntermediateDirectories: true
    )
    try fileManager.createSymbolicLink(
      at: projectAlias,
      withDestinationURL: project
    )

    #expect(
      ProjectScope.currentProject.includes(
        projectPath: projectAlias.path,
        currentProjectDirectory: project
      )
    )
  }

  @Test("Conversation action availability is pinned for generation state")
  func conversationActionAvailability() {
    #expect(!ConversationActions.rename.isDisabled(isGenerating: false))
    #expect(!ConversationActions.rename.isDisabled(isGenerating: true))

    #expect(!ConversationActions.duplicate.isDisabled(isGenerating: false))
    #expect(ConversationActions.duplicate.isDisabled(isGenerating: true))

    #expect(!ConversationActions.delete.isDisabled(isGenerating: false))
    #expect(ConversationActions.delete.isDisabled(isGenerating: true))
  }

  @MainActor
  private func makeAppState(testName: String) throws -> AppStateFixture {
    let suiteName = "QwenPrimeTests-\(testName)-\(UUID().uuidString)"
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
