import Foundation
import Testing

@testable import QwenPrime

@Suite("Runtime profile persistence and conversation export")
struct RuntimeProfilePersistenceAndExportTests {
  @MainActor
  private final class SuggestedFilenameRecorder {
    var values: [String] = []
  }

  private struct SensitiveFailure: LocalizedError, Sendable {
    let detail: String

    var errorDescription: String? { detail }
  }

  @Test("Operation error kinds have one window scope mapping")
  func operationErrorScopeMapping() {
    #expect(
      AppOperationErrorPresentation.workspaceAuthorization(message: "Denied")
        .presentationScope == .mainWindow
    )
    #expect(
      AppOperationErrorPresentation.conversationExport.presentationScope
        == .mainWindow
    )
    #expect(
      AppOperationErrorPresentation.runtimeProfilePersistence.presentationScope
        == .settingsWindow
    )
  }

  @Test("Failed profile persistence leaves every in-memory mutation uncommitted")
  @MainActor
  func failedProfilePersistenceIsTransactional() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "RuntimeProfileFailure-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let blocker = root.appendingPathComponent("not-a-directory")
    try Data("blocked".utf8).write(to: blocker)
    let configurationURL = blocker.appendingPathComponent("runtime.json")
    let suiteName = "RuntimeProfileFailure.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(
      startServices: false,
      runtimeConfigurationService: RuntimeConfigurationService(
        configurationURL: configurationURL
      ),
      userDefaults: defaults,
      storage: StorageService(
        directoryURL: root.appendingPathComponent("storage")
      )
    )

    let initialConfiguration = appState.runtimeConfiguration
    let initialSelection = appState.selectedEditingProfileId
    let added = appState.addModelProfile(name: "Unsaved")

    #expect(added == nil)
    #expect(appState.runtimeConfiguration == initialConfiguration)
    #expect(appState.selectedEditingProfileId == initialSelection)
    #expect(appState.presentedOperationError(in: .mainWindow) == nil)
    #expect(
      appState.presentedOperationError(in: .settingsWindow)
        == .runtimeProfilePersistence
    )
    #expect(!FileManager.default.fileExists(atPath: configurationURL.path))

    appState.setOperationErrorPresented(false, in: .mainWindow)
    #expect(
      appState.presentedOperationError(in: .settingsWindow)
        == .runtimeProfilePersistence
    )
    appState.setOperationErrorPresented(false, in: .settingsWindow)
    #expect(appState.presentedOperationError == nil)

    let active = RuntimeModelProfile(name: "Active")
    let alternate = RuntimeModelProfile(name: "Alternate")
    let twoProfileConfiguration = RuntimeConfiguration(
      activeProfileId: active.id,
      profiles: [active, alternate]
    )
    appState.runtimeConfiguration = twoProfileConfiguration
    appState.selectedEditingProfileId = alternate.id
    var updatedAlternate = alternate
    updatedAlternate.name = "Unsaved Rename"

    #expect(!appState.saveModelProfile(updatedAlternate))
    #expect(appState.runtimeConfiguration == twoProfileConfiguration)
    #expect(appState.selectedEditingProfileId == alternate.id)
    #expect(!appState.deleteModelProfile(id: alternate.id))
    #expect(appState.runtimeConfiguration == twoProfileConfiguration)
    #expect(appState.selectedEditingProfileId == alternate.id)

    let presentation = try #require(
      appState.presentedOperationError(in: .settingsWindow)
    )
    #expect(presentation.title == "Model Profile Could Not Be Saved")
    #expect(presentation.message.contains("not-a-directory") == false)
    #expect(presentation.message.contains(root.path) == false)
  }

  @Test("Successful profile mutations keep memory and disk identical")
  @MainActor
  func successfulProfilePersistenceMatchesDisk() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "RuntimeProfileSuccess-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: root) }
    let suiteName = "RuntimeProfileSuccess.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let service = RuntimeConfigurationService(
      configurationURL: root.appendingPathComponent("runtime.json")
    )
    let appState = AppState(
      startServices: false,
      runtimeConfigurationService: service,
      userDefaults: defaults,
      storage: StorageService(
        directoryURL: root.appendingPathComponent("storage")
      )
    )

    var added = try #require(appState.addModelProfile(name: "Saved"))
    #expect(try service.load() == appState.runtimeConfiguration)

    added.name = "Saved Rename"
    #expect(appState.saveModelProfile(added))
    #expect(try service.load() == appState.runtimeConfiguration)

    #expect(appState.deleteModelProfile(id: added.id))
    #expect(try service.load() == appState.runtimeConfiguration)
    #expect(appState.presentedOperationError == nil)
  }

  @Test("Export write failures present generic feedback without sensitive details")
  @MainActor
  func exportFailurePresentsSanitizedFeedback() async throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "ConversationExportFailure-\(UUID().uuidString)",
        isDirectory: true
      )
    defer { try? FileManager.default.removeItem(at: root) }
    let suiteName = "ConversationExportFailure.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let destination = root.appendingPathComponent("private-export.md")
    let sensitiveDetail = "Write denied at \(destination.path) [REDACTED_SECRET]"
    let appState = AppState(
      startServices: false,
      userDefaults: defaults,
      storage: StorageService(
        directoryURL: root.appendingPathComponent("storage")
      ),
      conversationExportDestinationPicker: { _ in destination },
      conversationExportWriter: { _, _ in
        throw SensitiveFailure(detail: sensitiveDetail)
      }
    )
    let conversation = Conversation(
      title: "Private/Conversation",
      messages: [ChatMessage(role: .user, content: "Private content")]
    )
    appState.conversations = [conversation]
    appState.selectedConversationId = conversation.id

    appState.exportConversationAsMarkdown()
    try await AsyncCondition.wait(
      description: "conversation export failure feedback"
    ) {
      appState.presentedOperationError == .conversationExport
    }

    #expect(appState.presentedOperationError(in: .settingsWindow) == nil)
    let presentation = try #require(
      appState.presentedOperationError(in: .mainWindow)
    )
    #expect(presentation.title == "Export Failed")
    #expect(presentation.message.contains(destination.path) == false)
    #expect(presentation.message.contains("[REDACTED_SECRET]") == false)
    #expect(!FileManager.default.fileExists(atPath: destination.path))

    appState.setOperationErrorPresented(false, in: .settingsWindow)
    #expect(appState.presentedOperationError(in: .mainWindow) == presentation)
    appState.setOperationErrorPresented(false, in: .mainWindow)
    #expect(appState.presentedOperationError == nil)
  }

  @Test("Export suggestions are safe and have one untitled fallback")
  @MainActor
  func exportSuggestedFilenamesAreSanitized() async throws {
    let suiteName = "ConversationExportNames.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let recorder = SuggestedFilenameRecorder()
    let appState = AppState(
      startServices: false,
      userDefaults: defaults,
      conversationExportDestinationPicker: { suggestedFilename in
        recorder.values.append(suggestedFilename)
        return nil
      }
    )
    let cases = [
      ("", "Untitled Conversation.md"),
      ("  \n\t", "Untitled Conversation.md"),
      ("///", "Untitled Conversation.md"),
      ("Plan: Draft", "Plan- Draft.md"),
      (".private", "-private.md"),
      ("Project Notes", "Project Notes.md"),
    ]

    for (index, testCase) in cases.enumerated() {
      let (title, expectedFilename) = testCase
      let conversation = Conversation(title: title)
      appState.conversations = [conversation]
      appState.selectedConversationId = conversation.id
      appState.exportConversationAsMarkdown()
      try await AsyncCondition.wait(
        description: "export suggestion \(expectedFilename)"
      ) {
        recorder.values.count == index + 1
      }
    }

    #expect(recorder.values == cases.map { $0.1 })
  }

  @Test("Operation error alerts are reusable and attached at both scene roots")
  func operationErrorAlertSceneRoutingContract() throws {
    let appSource = try source(
      "Sources/QwenPrime/App/QwenPrimeApp.swift"
    )
    let chatSource = try source(
      "Sources/QwenPrime/Views/Chat/ChatView.swift"
    )
    let alertSource = try source(
      "Sources/QwenPrime/Views/Shared/AppOperationErrorAlert.swift"
    )
    let sceneAttachments = appSource.components(
      separatedBy: ".appOperationErrorAlert("
    )

    #expect(sceneAttachments.count == 3)
    #expect(sceneAttachments[1].prefix(160).contains("scope: .mainWindow"))
    #expect(sceneAttachments[2].prefix(160).contains("scope: .settingsWindow"))
    #expect(alertSource.contains("appState.presentedOperationError(in: scope)"))
    #expect(alertSource.contains("appState.setOperationErrorPresented("))
    #expect(!chatSource.contains("presentedOperationError"))
  }

  private func source(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(
      contentsOf: repositoryRoot.appendingPathComponent(relativePath),
      encoding: .utf8
    )
  }
}
