import Foundation
import Testing

@testable import QwenPrime

@Suite("Confirmation presentation scopes")
struct ConfirmationPresentationScopeTests {
  @Test("Settings and main requests coexist without blocking either window")
  @MainActor
  func requestsAreQueuedPerWindowScope() throws {
    let suiteName = "QwenPrimeTests-ConfirmationScope-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let conversation = Conversation()
    appState.conversations = [conversation]

    let profile = MCPServerProfile(
      id: "settings-server",
      displayName: "Settings Server",
      endpoint: "http://127.0.0.1:9333/mcp",
      isEnabled: false
    )
    appState.mcpServers = [profile]
    appState.requestRemoveMCPServer(
      id: profile.id,
      presentationScope: .settingsWindow
    )
    appState.requestDeleteConversation(id: conversation.id)

    let mainRequest = try #require(
      appState.pendingConfirmation(in: .mainWindow)
    )
    let settingsRequest = try #require(
      appState.pendingConfirmation(in: .settingsWindow)
    )
    #expect(mainRequest.shouldPresent(in: .mainWindow))
    #expect(!mainRequest.shouldPresent(in: .settingsWindow))
    #expect(settingsRequest.shouldPresent(in: .settingsWindow))
    #expect(!settingsRequest.shouldPresent(in: .mainWindow))

    appState.setConfirmationPresented(
      true,
      id: mainRequest.id,
      in: .mainWindow
    )
    #expect(appState.pendingConfirmation(in: .mainWindow) == mainRequest)

    appState.setConfirmationPresented(
      false,
      id: settingsRequest.id,
      in: .mainWindow
    )
    #expect(appState.pendingConfirmation(in: .mainWindow) == mainRequest)

    appState.setConfirmationPresented(
      false,
      id: mainRequest.id,
      in: .mainWindow
    )
    #expect(appState.pendingConfirmation(in: .mainWindow) == nil)
    #expect(appState.pendingConfirmation(in: .settingsWindow) == settingsRequest)

    appState.setConfirmationPresented(
      false,
      id: settingsRequest.id,
      in: .settingsWindow
    )
    #expect(appState.pendingConfirmation(in: .settingsWindow) == nil)
  }

  @Test("Failed mid-dialog confirmation dismisses safely and can be retried")
  @MainActor
  func failedConfirmationDismissesAndRequeues() throws {
    let suiteName = "QwenPrimeTests-ConfirmationEligibility-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let clearTarget = Conversation(
      title: "Clear target",
      messages: [ChatMessage(role: .user, content: "Keep until eligible")]
    )
    let deleteTarget = Conversation(title: "Delete target")
    appState.conversations = [clearTarget, deleteTarget]

    appState.setConversation(clearTarget.id, isGenerating: true)
    appState.requestClearConversationMessages(id: clearTarget.id)
    #expect(appState.pendingConfirmation(in: .mainWindow) == nil)

    appState.setConversation(clearTarget.id, isGenerating: false)
    appState.requestClearConversationMessages(id: clearTarget.id)
    let clearRequest = try #require(
      appState.pendingConfirmation(in: .mainWindow)
    )
    appState.setConversation(clearTarget.id, isGenerating: true)

    #expect(!appState.canConfirm(clearRequest))
    #expect(
      appState.confirmationMessage(for: clearRequest)
        .contains("Wait for the active response to finish")
    )
    let didClearWhileGenerating = appState.confirmPendingAction(
      id: clearRequest.id,
      in: .mainWindow
    )
    #expect(!didClearWhileGenerating)
    #expect(appState.pendingConfirmation(in: .mainWindow) == nil)
    #expect(
      appState.conversations.first(where: { $0.id == clearTarget.id })?
        .messages.count == 1
    )

    appState.setConfirmationPresented(
      false,
      id: clearRequest.id,
      in: .mainWindow
    )
    #expect(appState.pendingConfirmation(in: .mainWindow) == nil)

    appState.setConversation(clearTarget.id, isGenerating: false)
    appState.requestClearConversationMessages(id: clearTarget.id)
    let retryClearRequest = try #require(
      appState.pendingConfirmation(in: .mainWindow)
    )
    let didClear = appState.confirmPendingAction(
      id: retryClearRequest.id,
      in: .mainWindow
    )
    #expect(didClear)
    #expect(appState.pendingConfirmation(in: .mainWindow) == nil)
    #expect(
      appState.conversations.first(where: { $0.id == clearTarget.id })?
        .messages.isEmpty == true
    )

    appState.requestDeleteConversation(id: deleteTarget.id)
    let deleteRequest = try #require(
      appState.pendingConfirmation(in: .mainWindow)
    )
    appState.setConversation(deleteTarget.id, isGenerating: true)

    #expect(!appState.canConfirm(deleteRequest))
    let didDeleteWhileGenerating = appState.confirmPendingAction(
      id: deleteRequest.id,
      in: .mainWindow
    )
    #expect(!didDeleteWhileGenerating)
    #expect(appState.pendingConfirmation(in: .mainWindow) == nil)
    #expect(appState.conversations.contains(where: { $0.id == deleteTarget.id }))

    appState.dismissPendingConfirmation(
      id: deleteRequest.id,
      in: .mainWindow
    )
    #expect(appState.pendingConfirmation(in: .mainWindow) == nil)
    #expect(appState.conversations.contains(where: { $0.id == deleteTarget.id }))

    appState.setConversation(deleteTarget.id, isGenerating: false)
    appState.requestDeleteConversation(id: deleteTarget.id)
    let retryDeleteRequest = try #require(
      appState.pendingConfirmation(in: .mainWindow)
    )
    let didDelete = appState.confirmPendingAction(
      id: retryDeleteRequest.id,
      in: .mainWindow
    )
    #expect(didDelete)
    #expect(appState.pendingConfirmation(in: .mainWindow) == nil)
    #expect(!appState.conversations.contains(where: { $0.id == deleteTarget.id }))
  }

  @Test("Alert dismissal has no failed-confirmation retention loop")
  func alertDismissalDoesNotRetainFailedRequest() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(
        "Sources/QwenPrime/Models/AppConfirmation.swift"
      )
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(source.contains("set: { isPresented in"))
    #expect(source.contains("appState.setConfirmationPresented("))
    #expect(!source.contains("requestIDRetainedAfterFailedConfirmation"))
    #expect(!source.contains("Task.yield()"))
  }
}
