import Foundation
import Testing

@testable import QwenPrime

@Suite("App Preferences and Command Integration")
struct AppPreferencesAndCommandsTests {
  private func makeTestDefaults() throws -> (UserDefaults, String) {
    let suiteName = "QwenPrimeTests-Preferences-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    return (defaults, suiteName)
  }

  @Test("Displayed preferences persist together in the injected defaults suite")
  @MainActor
  func displayedPreferencesPersistTogether() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let appState = AppState(startServices: false, userDefaults: defaults)
    appState.currentThemeType = .nord
    appState.selectedModel = "qwen-custom"
    appState.baseURL = "http://localhost:9400/v1"
    appState.isAutoScrollEnabled = false
    appState.isThinkingExpandedByDefault = true
    appState.defaultThinkingEnabled = true
    appState.defaultAgentModeEnabled = false
    appState.defaultSystemPrompt = "Custom default prompt"
    appState.isAgentPreviewEnabled = false
    appState.isWorkspaceInstructionsEnabled = false

    let reloaded = AppState(startServices: false, userDefaults: defaults)
    #expect(reloaded.currentThemeType == .nord)
    #expect(reloaded.selectedModel == "qwen-custom")
    #expect(reloaded.baseURL == "http://localhost:9400/v1")
    #expect(reloaded.isAutoScrollEnabled == false)
    #expect(reloaded.isThinkingExpandedByDefault == true)
    #expect(reloaded.defaultThinkingEnabled)
    #expect(!reloaded.defaultAgentModeEnabled)
    #expect(reloaded.defaultSystemPrompt == "Custom default prompt")
    #expect(!reloaded.isAgentPreviewEnabled)
    #expect(!reloaded.isWorkspaceInstructionsEnabled)
  }

  @Test("Base URL assignment normalizes without invalidating equivalent health")
  @MainActor
  func baseURLAssignmentNormalizesEndpoint() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    appState.baseURL = "http://localhost:9400/v1"
    appState.runtimeSupportsStructuredToolCalls = true

    appState.baseURL = "  HTTP://user:pass@LOCALHOST:9400/v1///?token=secret#fragment  "

    #expect(appState.baseURL == "http://localhost:9400/v1")
    #expect(appState.runtimeSupportsStructuredToolCalls)
    #expect(appState.verifiedBaseURL == "http://localhost:9400/v1")

    appState.baseURL = " http://localhost:9500/v1/ "

    #expect(appState.baseURL == "http://localhost:9500/v1")
    #expect(!appState.runtimeSupportsStructuredToolCalls)
    #expect(appState.verifiedBaseURL == nil)
    let reloaded = AppState(startServices: false, userDefaults: defaults)
    #expect(reloaded.baseURL == "http://localhost:9500/v1")
  }

  @Test("Initializer endpoint override uses secure canonical normalization")
  @MainActor
  func initializerNormalizesEndpointOverride() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let rawEndpoint = """
       \n HTTPS://user:pass@EXAMPLE.COM:9443/CaseSensitive/V1///?token=secret#fragment \t
      """
    let appState = AppState(
      baseURL: rawEndpoint,
      startServices: false,
      userDefaults: defaults
    )

    #expect(
      appState.baseURL == "https://example.com:9443/CaseSensitive/V1"
    )
    #expect(appState.baseURL == AppState.normalizeEndpoint(rawEndpoint))
    #expect(!appState.baseURL.contains("user"))
    #expect(!appState.baseURL.contains("pass"))
    #expect(!appState.baseURL.contains("token"))
    #expect(!appState.baseURL.contains("fragment"))
  }

  @Test("Endpoint normalization supports IPv6 and preserves path case")
  @MainActor
  func endpointNormalizationSupportsIPv6() {
    #expect(AppState.normalizeEndpoint("") == "")
    #expect(AppState.normalizeEndpoint("  \n\t  ") == "")
    #expect(
      AppState.normalizeEndpoint("  HTTP://[::1]:8080/Models/Qwen///  ")
        == "http://[::1]:8080/Models/Qwen"
    )
    #expect(
      AppState.normalizeEndpoint("HTTPS://EXAMPLE.COM/CaseSensitive/V1/")
        == "https://example.com/CaseSensitive/V1"
    )
  }

  @Test("Settings routing selects explicit tabs and preserves the current default")
  @MainActor
  func settingsRoutingContract() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)

    appState.settingsSelection = .appearance
    appState.openSettings()
    #expect(appState.settingsSelection == .appearance)

    appState.openSettings(tab: .systemPrompts)
    #expect(appState.settingsSelection == .systemPrompts)

    appState.openSettings(tab: .engine)
    #expect(appState.settingsSelection == .engine)
  }

  @Test("Legacy chat toggles migrate into the centralized preference model")
  @MainActor
  func legacyChatTogglesMigrate() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(false, forKey: "autoScroll")
    defaults.set(true, forKey: "expandThinkingByDefault")
    defaults.set(true, forKey: "defaultThinkingEnabled")
    defaults.set(false, forKey: "defaultAgentModeEnabled")
    defaults.set("Legacy prompt", forKey: "defaultSystemPrompt")
    defaults.set(false, forKey: "isAgentPreviewEnabled")
    defaults.set(false, forKey: "isWorkspaceInstructionsEnabled")

    let appState = AppState(startServices: false, userDefaults: defaults)

    #expect(appState.isAutoScrollEnabled == false)
    #expect(appState.isThinkingExpandedByDefault == true)
    #expect(appState.defaultThinkingEnabled)
    #expect(!appState.defaultAgentModeEnabled)
    #expect(appState.defaultSystemPrompt == "Legacy prompt")
    #expect(!appState.isAgentPreviewEnabled)
    #expect(!appState.isWorkspaceInstructionsEnabled)
  }

  @Test("Earlier preference payloads merge legacy settings once")
  @MainActor
  func earlierPreferencePayloadMergesLegacySettings() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let earlierPayload: [String: Any] = [
      "theme": ThemeType.nord.rawValue,
      "selectedModel": "earlier-model",
      "baseURL": "http://localhost:9100/v1",
      "isAutoScrollEnabled": true,
      "isThinkingExpandedByDefault": false,
    ]
    defaults.set(
      try JSONSerialization.data(withJSONObject: earlierPayload),
      forKey: "appPreferences.v1"
    )
    defaults.set(true, forKey: "defaultThinkingEnabled")
    defaults.set(false, forKey: "defaultAgentModeEnabled")
    defaults.set("Migrated prompt", forKey: "defaultSystemPrompt")

    let preferences = AppPreferencesPersistence.load(from: defaults)

    #expect(preferences.theme == .nord)
    #expect(preferences.selectedModel == "earlier-model")
    #expect(preferences.defaultThinkingEnabled)
    #expect(!preferences.defaultAgentModeEnabled)
    #expect(preferences.defaultSystemPrompt == "Migrated prompt")
    let savedData = try #require(defaults.data(forKey: "appPreferences.v1"))
    let saved = try JSONDecoder().decode(AppPreferences.self, from: savedData)
    #expect(saved == preferences)
  }

  @Test("Encoded preference schema is derived from Codable keys")
  func encodedPreferenceSchemaMatchesCodingKeys() throws {
    let data = try JSONEncoder().encode(AppPreferences())
    let object = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let codingKeys = Set(
      AppPreferences.CodingKeys.allCases.map(\.rawValue)
    )

    #expect(Set(object.keys) == codingKeys)
  }

  @Test("Corrupted preference data falls back to safe defaults")
  @MainActor
  func corruptedPreferencesFallBackToDefaults() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set(Data([0xFF, 0x00, 0xAA]), forKey: "appPreferences.v1")

    let preferences = AppPreferencesPersistence.load(from: defaults)

    #expect(preferences == AppPreferences())
    let repairedData = try #require(
      defaults.data(forKey: "appPreferences.v1")
    )
    let repaired = try JSONDecoder().decode(
      AppPreferences.self,
      from: repairedData
    )
    #expect(repaired == preferences)
    #expect(AppPreferencesPersistence.load(from: defaults) == repaired)
  }

  @Test("Unknown saved theme preserves every other preference")
  func unknownThemeFallsBackIndependently() throws {
    let original = AppPreferences(
      theme: .nord,
      selectedModel: "preserved-model",
      baseURL: "http://localhost:9410/v1",
      isAutoScrollEnabled: false,
      isThinkingExpandedByDefault: true,
      defaultThinkingEnabled: true,
      defaultAgentModeEnabled: false,
      defaultSystemPrompt: "Preserved prompt",
      isAgentPreviewEnabled: false,
      isWorkspaceInstructionsEnabled: false
    )
    let encoded = try JSONEncoder().encode(original)
    var payload = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    payload["theme"] = "Deprecated Theme"

    let decoded = try JSONDecoder().decode(
      AppPreferences.self,
      from: JSONSerialization.data(withJSONObject: payload)
    )
    var expected = original
    expected.theme = .primeDark

    #expect(decoded == expected)
  }

  @Test("Preference failure diagnostics omit invalid values")
  @MainActor
  func preferenceFailureDiagnosticsAreSafe() {
    let context = DecodingError.Context(
      codingPath: [],
      debugDescription: "Rejected value: [REDACTED_SECRET]"
    )
    let decodingError = DecodingError.dataCorrupted(context)
    let diagnostic = AppPreferencesPersistence.failureDescription(
      for: decodingError
    )

    #expect(diagnostic == "dataCorrupted at <root>")
    #expect(!diagnostic.contains("[REDACTED_SECRET]"))

    let encodingError = EncodingError.invalidValue(
      "[REDACTED_SECRET]",
      EncodingError.Context(
        codingPath: [],
        debugDescription: "Rejected value: [REDACTED_SECRET]"
      )
    )
    let encodingDiagnostic = AppPreferencesPersistence.failureDescription(
      for: encodingError
    )
    #expect(encodingDiagnostic == "invalidValue at <root>")
    #expect(!encodingDiagnostic.contains("[REDACTED_SECRET]"))
  }

  @Test("Prime built-in prompt uses the preference default as its SSOT")
  func primePromptUsesPreferenceDefault() throws {
    let primePreset = try #require(SystemPromptPreset.builtInPresets.first)

    #expect(primePreset.promptText == AppPreferences.defaultSystemPromptText)
  }

  @Test("Built-in prompt identifiers remain persistence-compatible")
  func builtInPromptIdentifiersRemainStable() {
    let identifiers = SystemPromptPreset.builtInPresets.map(\.id.uuidString)

    #expect(identifiers == [
      "11111111-1111-1111-1111-111111111111",
      "22222222-2222-2222-2222-222222222222",
      "33333333-3333-3333-3333-333333333333",
      "44444444-4444-4444-4444-444444444444",
      "55555555-5555-5555-5555-555555555555",
    ])
  }

  @Test("Editing the default prompt keeps every mutation synchronized")
  @MainActor
  func defaultPromptEditsStaySynchronized() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let preset = SystemPromptPreset(
      name: "Editable Default",
      promptText: "Initial prompt"
    )
    appState.savePromptPreset(preset)
    appState.setDefaultPromptPreset(id: preset.id)

    appState.updatePromptPresetText(
      id: preset.id,
      promptText: "First keystroke"
    )
    appState.updatePromptPresetText(
      id: preset.id,
      promptText: "Second keystroke"
    )

    #expect(appState.defaultSystemPrompt == "Second keystroke")
    #expect(appState.defaultSystemPromptPresetId == preset.id)
    #expect(
      appState.promptPresets.first(where: { $0.id == preset.id })?.promptText
        == "Second keystroke"
    )

    let reloaded = AppState(startServices: false, userDefaults: defaults)
    #expect(reloaded.defaultSystemPrompt == "Second keystroke")
    #expect(reloaded.defaultSystemPromptPresetId == preset.id)
    #expect(
      reloaded.promptPresets.first(where: { $0.id == preset.id })?.promptText
        == "Second keystroke"
    )
  }

  @Test("Editing an unknown prompt preset is a full no-op")
  @MainActor
  func unknownPromptPresetEditIsNoOp() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let originalPresets = appState.promptPresets
    let originalPreferences = appState.preferences
    let originalDefaults = NSDictionary(
      dictionary: defaults.persistentDomain(forName: suiteName) ?? [:]
    )

    appState.updatePromptPresetText(
      id: UUID(),
      promptText: "Must not be stored"
    )

    #expect(appState.promptPresets == originalPresets)
    #expect(appState.preferences == originalPreferences)
    #expect(
      originalDefaults.isEqual(
        to: defaults.persistentDomain(forName: suiteName) ?? [:]
      )
    )
  }

  @Test("Deleting the custom default restores the factory prompt")
  @MainActor
  func deletingCustomDefaultRestoresFactoryPrompt() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let preset = SystemPromptPreset(
      name: "Temporary Default",
      promptText: "Temporary instructions"
    )
    appState.savePromptPreset(preset)
    appState.setDefaultPromptPreset(id: preset.id)

    appState.requestDeletePromptPreset(id: preset.id)
    appState.confirmPendingAction()

    #expect(!appState.promptPresets.contains(where: { $0.id == preset.id }))
    #expect(
      appState.defaultSystemPrompt == AppPreferences.defaultSystemPromptText
    )

    let reloaded = AppState(startServices: false, userDefaults: defaults)
    #expect(
      reloaded.defaultSystemPrompt == AppPreferences.defaultSystemPromptText
    )
  }

  @Test("Duplicate prompt text does not couple non-default preset mutations")
  @MainActor
  func duplicatePromptTextDoesNotCoupleMutations() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let factoryPreset = try #require(
      appState.promptPresets.first(where: {
        $0.promptText == AppPreferences.defaultSystemPromptText
      })
    )
    let duplicate = SystemPromptPreset(
      name: "Duplicate Factory Text",
      promptText: AppPreferences.defaultSystemPromptText
    )
    appState.savePromptPreset(duplicate)

    #expect(appState.isDefaultPromptPreset(id: factoryPreset.id))
    #expect(!appState.isDefaultPromptPreset(id: duplicate.id))

    appState.updatePromptPresetText(
      id: duplicate.id,
      promptText: "Edited duplicate"
    )
    #expect(
      appState.defaultSystemPrompt == AppPreferences.defaultSystemPromptText
    )
    #expect(appState.defaultSystemPromptPresetId == factoryPreset.id)

    appState.deletePromptPreset(id: duplicate.id)
    #expect(
      appState.defaultSystemPrompt == AppPreferences.defaultSystemPromptText
    )
    #expect(appState.defaultSystemPromptPresetId == factoryPreset.id)
  }

  @Test("Duplicate-text default identity persists across restart")
  @MainActor
  func duplicatePromptDefaultIdentityPersists() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let factoryPreset = try #require(
      appState.promptPresets.first(where: {
        $0.promptText == AppPreferences.defaultSystemPromptText
      })
    )
    let duplicate = SystemPromptPreset(
      name: "Explicit Duplicate Default",
      promptText: AppPreferences.defaultSystemPromptText
    )
    appState.savePromptPreset(duplicate)
    appState.setDefaultPromptPreset(id: duplicate.id)

    let reloaded = AppState(startServices: false, userDefaults: defaults)

    #expect(reloaded.defaultSystemPromptPresetId == duplicate.id)
    #expect(reloaded.isDefaultPromptPreset(id: duplicate.id))
    #expect(!reloaded.isDefaultPromptPreset(id: factoryPreset.id))

    reloaded.updatePromptPresetText(
      id: duplicate.id,
      promptText: "Restarted duplicate edit"
    )
    #expect(reloaded.defaultSystemPrompt == "Restarted duplicate edit")
    #expect(reloaded.defaultSystemPromptPresetId == duplicate.id)
  }

  @Test("Legacy prompt default migrates to a persisted preset identity")
  @MainActor
  func legacyPromptDefaultMigratesToIdentity() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preset = SystemPromptPreset(
      name: "Legacy Default",
      promptText: "Legacy preset prompt"
    )
    var preferencePayload = try #require(
      JSONSerialization.jsonObject(
        with: JSONEncoder().encode(
          AppPreferences(defaultSystemPrompt: preset.promptText)
        )
      ) as? [String: Any]
    )
    preferencePayload[
      AppPreferences.CodingKeys.defaultSystemPromptPresetId.rawValue
    ] = nil
    defaults.set(
      try JSONSerialization.data(withJSONObject: preferencePayload),
      forKey: "appPreferences.v1"
    )
    defaults.set(
      try JSONEncoder().encode(SystemPromptPreset.builtInPresets + [preset]),
      forKey: AppState.UserDefaultsKey.customPromptPresets.rawValue
    )

    let appState = AppState(startServices: false, userDefaults: defaults)
    #expect(appState.defaultSystemPrompt == preset.promptText)
    #expect(appState.defaultSystemPromptPresetId == preset.id)

    let reloaded = AppState(startServices: false, userDefaults: defaults)
    #expect(reloaded.defaultSystemPromptPresetId == preset.id)
  }

  @Test("Invalid prompt preset identity preserves the saved prompt")
  @MainActor
  func invalidPromptPresetIdentityPreservesPrompt() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let prompt = "Keep this unmatched saved prompt"
    defaults.set(
      try JSONEncoder().encode(
        AppPreferences(
          defaultSystemPrompt: prompt,
          defaultSystemPromptPresetId: UUID()
        )
      ),
      forKey: "appPreferences.v1"
    )

    let appState = AppState(startServices: false, userDefaults: defaults)

    #expect(appState.defaultSystemPrompt == prompt)
    #expect(appState.defaultSystemPromptPresetId == nil)
    let reloaded = AppState(startServices: false, userDefaults: defaults)
    #expect(reloaded.defaultSystemPrompt == prompt)
    #expect(reloaded.defaultSystemPromptPresetId == nil)
  }

  @Test("Selected conversation rejects mismatched replacement identity")
  @MainActor
  func selectedConversationRejectsMismatchedIdentity() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let selected = Conversation(title: "Selected")
    var different = Conversation(title: "Different")
    appState.conversations = [selected, different]
    appState.selectedConversationId = selected.id
    let originalConversations = appState.conversations
    different.title = "Must not overwrite selected"

    appState.selectedConversation = different

    #expect(appState.conversations == originalConversations)
    #expect(appState.selectedConversationId == selected.id)
    #expect(appState.selectedConversation == selected)
  }

  @Test("Empty prompt length reports zero estimated tokens")
  func emptyPromptLengthReportsZeroTokens() {
    let summary = SystemPromptPresentation.lengthSummary(
      "",
      locale: Locale(identifier: "en_US")
    )

    #expect(summary == "0 characters • ~0 tokens")
  }

  @Test("Shortcut metadata is unique and contains every advertised action")
  func shortcutMetadataIsComplete() {
    let commands = AppCommands.shortcuts

    #expect(Set(commands.map(\.id)).count == commands.count)
    #expect(commands.contains(AppCommands.newConversation))
    #expect(commands.contains(AppCommands.clearActiveChat))
    #expect(commands.contains(AppCommands.openSettings))
    #expect(commands.contains(AppCommands.reconnectToEngine))
    #expect(commands.contains(AppCommands.sendMessage))
    #expect(commands.contains(AppCommands.insertNewline))
    #expect(commands.contains(AppCommands.stopGeneration))
    #expect(AppCommands.stopGeneration.shortcut.displayName == "Esc")
    #expect(AppCommands.reconnectToEngine.shortcut.displayName == "⌘ ⇧ R")
    #expect(commands.allSatisfy { !$0.help.isEmpty })

    let idle = AppCommandContext(
      hasConversation: true,
      hasMessageText: true,
      hasInputFocus: true
    )
    let generating = AppCommandContext(
      hasConversation: true,
      isGenerating: true,
      hasMessageText: true,
      hasInputFocus: true
    )
    #expect(AppCommands.clearActiveChat.isEnabled(in: idle))
    #expect(!AppCommands.clearActiveChat.isEnabled(in: generating))
    #expect(AppCommands.sendMessage.isEnabled(in: idle))
    #expect(!AppCommands.sendMessage.isEnabled(in: generating))
    #expect(AppCommands.stopGeneration.isEnabled(in: generating))
    #expect(!AppCommands.stopGeneration.isEnabled(in: idle))
  }

  @Test("Stop command targets only the selected generating conversation")
  @MainActor
  func stopCommandTargetsSelectedGeneration() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let conversation = appState.createNewConversation()

    appState.requestStopGeneration()
    #expect(appState.pendingCommandRequest == nil)

    appState.setConversation(conversation.id, isGenerating: true)
    appState.requestStopGeneration()
    let request = try #require(appState.pendingCommandRequest)
    #expect(request.command == .stopGeneration)
    #expect(request.conversationID == conversation.id)

    appState.acknowledgeCommandRequest(id: request.id)
    #expect(appState.pendingCommandRequest == nil)
  }

  @Test("Repeated stop requests for one conversation are deduplicated")
  @MainActor
  func repeatedStopRequestsAreDeduplicated() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let conversation = appState.createNewConversation()
    appState.setConversation(conversation.id, isGenerating: true)

    appState.requestStopGeneration()
    let originalRequest = try #require(appState.pendingCommandRequest)
    appState.requestStopGeneration()

    #expect(appState.pendingCommandRequests == [originalRequest])
  }

  @Test("Commands remain ordered until each request is acknowledged")
  @MainActor
  func commandRequestsAreQueued() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let first = Conversation(title: "First")
    let second = Conversation(title: "Second")
    appState.conversations = [first, second]
    appState.setConversation(first.id, isGenerating: true)
    appState.setConversation(second.id, isGenerating: true)

    appState.selectedConversationId = first.id
    appState.requestStopGeneration()
    let firstRequest = try #require(appState.pendingCommandRequest)

    appState.selectedConversationId = second.id
    appState.requestStopGeneration()
    #expect(appState.pendingCommandRequest?.id == firstRequest.id)

    appState.acknowledgeCommandRequest(id: firstRequest.id)
    let secondRequest = try #require(appState.pendingCommandRequest)
    #expect(secondRequest.conversationID == second.id)
    appState.acknowledgeCommandRequest(id: secondRequest.id)
    #expect(appState.pendingCommandRequest == nil)
  }

  @Test("Clear messages waits for explicit destructive confirmation")
  @MainActor
  func clearMessagesRequiresConfirmation() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let conversation = Conversation(
      messages: [ChatMessage(role: .user, content: "Keep until confirmed")]
    )
    appState.conversations = [conversation]
    appState.selectedConversationId = conversation.id

    appState.requestClearConversationMessages(id: conversation.id)
    #expect(appState.selectedConversation?.messages.count == 1)
    #expect(
      appState.pendingConfirmation?.action
        == .clearConversation(conversation.id)
    )

    appState.confirmPendingAction()
    #expect(appState.selectedConversation?.messages.isEmpty == true)
    #expect(appState.pendingConfirmation == nil)
  }

  @Test("Deleting a conversation waits for confirmation and supports cancel")
  @MainActor
  func deleteConversationRequiresConfirmation() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let first = Conversation(title: "First")
    let second = Conversation(title: "Second")
    appState.conversations = [first, second]
    appState.selectedConversationId = first.id

    appState.requestDeleteConversation(id: first.id)
    #expect(appState.conversations.map(\.id) == [first.id, second.id])
    #expect(appState.pendingConfirmation?.action == .deleteConversation(first.id))

    appState.dismissPendingConfirmation()
    #expect(appState.conversations.map(\.id) == [first.id, second.id])
    #expect(appState.pendingConfirmation == nil)

    appState.requestDeleteConversation(id: first.id)
    appState.confirmPendingAction()
    #expect(appState.conversations.map(\.id) == [second.id])
    #expect(appState.pendingConfirmation == nil)
  }

  @Test("A visible confirmation cannot be replaced by another request")
  @MainActor
  func pendingConfirmationIsStable() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let first = Conversation(
      title: "First",
      messages: [ChatMessage(role: .user, content: "Keep until confirmed")]
    )
    let second = Conversation(title: "Second")
    appState.conversations = [first, second]

    appState.requestClearConversationMessages(id: first.id)
    appState.requestDeleteConversation(id: second.id)

    #expect(
      appState.pendingConfirmation?.action == .clearConversation(first.id)
    )
    appState.confirmPendingAction()
    #expect(appState.conversations.map(\.id) == [first.id, second.id])
    #expect(appState.conversations.first?.messages.isEmpty == true)
  }

  @Test("Destructive requests reject protected and missing targets")
  @MainActor
  func destructiveRequestsValidateTargets() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let conversation = Conversation(title: "Generating")
    appState.conversations = [conversation]

    appState.requestClearConversationMessages(id: UUID())
    appState.requestDeleteConversation(id: UUID())
    #expect(appState.pendingConfirmation == nil)

    appState.setConversation(conversation.id, isGenerating: true)
    appState.requestClearConversationMessages(id: conversation.id)
    appState.requestDeleteConversation(id: conversation.id)
    #expect(appState.pendingConfirmation == nil)

    let active = RuntimeModelProfile(name: "Active")
    let alternate = RuntimeModelProfile(name: "Alternate")
    appState.runtimeConfiguration = RuntimeConfiguration(
      activeProfileId: active.id,
      profiles: [active]
    )

    appState.requestDeleteModelProfile(id: active.id)
    #expect(appState.pendingConfirmation == nil)

    appState.runtimeConfiguration = RuntimeConfiguration(
      activeProfileId: active.id,
      profiles: [active, alternate]
    )

    appState.requestDeleteModelProfile(id: active.id)
    #expect(appState.pendingConfirmation == nil)
    appState.requestDeleteModelProfile(id: UUID())
    #expect(appState.pendingConfirmation == nil)

    appState.requestDeleteModelProfile(id: alternate.id)
    #expect(appState.pendingConfirmation?.action == .deleteModelProfile(alternate.id))
    appState.dismissPendingConfirmation()

    let builtIn = try #require(
      appState.promptPresets.first(where: { $0.isBuiltIn })
    )
    appState.requestDeletePromptPreset(id: builtIn.id)
    #expect(appState.pendingConfirmation == nil)
    appState.requestDeletePromptPreset(id: UUID())
    #expect(appState.pendingConfirmation == nil)

    let custom = SystemPromptPreset(
      name: "Custom",
      promptText: "Keep until confirmed"
    )
    appState.savePromptPreset(custom)
    appState.requestDeletePromptPreset(id: custom.id)
    #expect(appState.promptPresets.contains(where: { $0.id == custom.id }))
    #expect(appState.pendingConfirmation?.action == .deletePromptPreset(custom.id))
  }

  @Test("Resetting prompts waits for explicit confirmation")
  @MainActor
  func resetPromptsRequiresConfirmation() throws {
    let (defaults, suiteName) = try makeTestDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let custom = SystemPromptPreset(name: "Custom", promptText: "Custom text")
    appState.savePromptPreset(custom)

    appState.requestResetPromptPresets()
    #expect(appState.promptPresets.contains(where: { $0.id == custom.id }))
    #expect(appState.pendingConfirmation?.action == .resetPromptPresets)

    appState.dismissPendingConfirmation()
    #expect(appState.promptPresets.contains(where: { $0.id == custom.id }))

    appState.requestResetPromptPresets()
    appState.confirmPendingAction()
    #expect(!appState.promptPresets.contains(where: { $0.id == custom.id }))
    #expect(appState.promptPresets.allSatisfy { $0.isBuiltIn })
  }

  @Test("Prompt selection resolves missing and empty preset collections")
  func promptSelectionHandlesEmptyCollections() {
    let first = UUID()
    let second = UUID()

    #expect(
      SystemPromptSelection.resolved(
        current: first,
        available: [first, second]
      ) == first
    )
    #expect(
      SystemPromptSelection.resolved(
        current: UUID(),
        available: [first, second]
      ) == first
    )
    #expect(
      SystemPromptSelection.resolved(
        current: first,
        available: []
      ) == nil
    )
  }
}
