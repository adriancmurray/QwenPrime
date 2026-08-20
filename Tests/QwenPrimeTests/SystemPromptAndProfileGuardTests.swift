import Foundation
import Testing

@testable import QwenPrime

@Suite("System prompt styling and profile activation guards")
struct SystemPromptAndProfileGuardTests {
  private func settingsSource(named fileName: String) throws -> String {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(
        "Sources/QwenPrime/Views/Settings/\(fileName)"
      )
    return try String(contentsOf: sourceURL, encoding: .utf8)
  }

  @Test("Selected prompt icons use the semantic reasoning status color")
  func selectedPromptIconColor() throws {
    let source = try settingsSource(named: "SystemPromptSettingsTab.swift")

    #expect(source.contains("? DesignTokens.Status.reasoning"))
    #expect(!source.contains(".cyan"))
  }

  @Test("Applied feedback owns one cancellation-safe lifecycle task")
  func appliedFeedbackTaskLifecycle() throws {
    let source = try settingsSource(named: "SystemPromptSettingsTab.swift")

    #expect(
      source.contains(
        "@State private var appliedFeedbackTask: Task<Void, Never>?"
      )
    )
    #expect(source.contains("appliedFeedbackTask?.cancel()"))
    #expect(source.contains("try await Task.sleep("))
    #expect(!source.contains("try? await Task.sleep("))
    #expect(source.contains("guard !Task.isCancelled else { return }"))
    #expect(source.contains(".onDisappear(perform: cancelAppliedFeedback)"))
  }

  @Test("Model folder panels are asynchronous and return on the main actor")
  func asynchronousModelFolderPanel() throws {
    let source = try settingsSource(named: "EngineSettingsTab.swift")

    #expect(source.contains("panel.begin { response in"))
    #expect(source.contains("Task { @MainActor in"))
    #expect(!source.contains("runModal()"))
    #expect(
      source.components(
        separatedBy: "let profileID = currentProfile.id"
      ).count == 3
    )
    #expect(source.contains("to: profileID"))
    #expect(source.contains("return appState.saveModelProfile(profile)"))
    #expect(!source.contains("appState.setRuntimeTargetModel(url)"))
    #expect(!source.contains("appState.setRuntimeDraftModel(url)"))
  }

  @Test(
    "Folder completion updates its captured profile and mirrors only active paths"
  )
  @MainActor
  func folderSelectionUsesCapturedProfileIdentity() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      "ProfileFolderSelection-\(UUID().uuidString)",
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    let suiteName = "ProfileFolderSelection-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(
      startServices: false,
      runtimeConfigurationService: RuntimeConfigurationService(
        configurationURL: root.appendingPathComponent("runtime.json")
      ),
      userDefaults: defaults
    )
    let active = RuntimeModelProfile(
      name: "Active",
      targetModelPath: "/active/target",
      draftModelPath: "/active/draft"
    )
    let alternate = RuntimeModelProfile(
      name: "Alternate",
      targetModelPath: "/alternate/target",
      draftModelPath: "/alternate/draft"
    )
    appState.runtimeConfiguration = RuntimeConfiguration(
      targetModelPath: active.targetModelPath,
      draftModelPath: active.draftModelPath,
      activeProfileId: active.id,
      profiles: [active, alternate]
    )
    appState.selectedEditingProfileId = alternate.id
    let capturedAlternateID = alternate.id
    appState.selectedEditingProfileId = active.id
    let alternateTarget = URL(fileURLWithPath: "/new/alternate-target")
    #expect(
      RuntimeModelFolderSelection.apply(
        alternateTarget,
        to: capturedAlternateID,
        kind: .target,
        appState: appState
      ))
    #expect(
      appState.runtimeConfiguration.profiles.first(where: {
        $0.id == alternate.id
      })?.targetModelPath == alternateTarget.path
    )
    #expect(
      appState.runtimeConfiguration.targetModelPath == active.targetModelPath
    )
    #expect(appState.selectedEditingProfileId == active.id)

    let capturedActiveID = active.id
    appState.selectedEditingProfileId = alternate.id
    let activeDraft = URL(fileURLWithPath: "/new/active-draft")
    #expect(
      RuntimeModelFolderSelection.apply(
        activeDraft,
        to: capturedActiveID,
        kind: .draft,
        appState: appState
      ))
    #expect(
      appState.runtimeConfiguration.profiles.first(where: {
        $0.id == active.id
      })?.draftModelPath == activeDraft.path
    )
    #expect(appState.runtimeConfiguration.draftModelPath == activeDraft.path)
    #expect(appState.selectedEditingProfileId == alternate.id)
  }

  @Test("A background generation prevents switching model profiles")
  @MainActor
  func generationPreventsProfileActivation() throws {
    let suiteName = "ProfileActivationGuard-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(
      startServices: false,
      userDefaults: defaults
    )
    let activeProfile = RuntimeModelProfile(
      name: "Active",
      targetModelPath: "/models/active-target",
      draftModelPath: "/models/active-draft"
    )
    let candidateProfile = RuntimeModelProfile(
      name: "Candidate",
      targetModelPath: "/models/candidate-target",
      draftModelPath: "/models/candidate-draft"
    )
    appState.runtimeConfiguration = RuntimeConfiguration(
      targetModelPath: activeProfile.targetModelPath,
      draftModelPath: activeProfile.draftModelPath,
      activeProfileId: activeProfile.id,
      profiles: [activeProfile, candidateProfile]
    )
    appState.runtimeSetupStatus = .ready

    let visibleConversation = Conversation(title: "Visible")
    let backgroundConversation = Conversation(title: "Generating")
    appState.conversations = [visibleConversation, backgroundConversation]
    appState.selectedConversationId = visibleConversation.id
    appState.setConversation(backgroundConversation.id, isGenerating: true)

    appState.activateProfile(id: candidateProfile.id)

    #expect(appState.isGenerating)
    #expect(
      appState.runtimeConfiguration.activeProfileId == activeProfile.id
    )
    #expect(
      appState.runtimeConfiguration.targetModelPath
        == activeProfile.targetModelPath
    )
    #expect(appState.runtimeSetupStatus == .ready)
  }
}
