import Foundation
import Testing

@testable import QwenPrime

@Suite("System prompt active-chat application")
struct SystemPromptApplicationTests {
  @Test("A missing active conversation cannot receive a prompt")
  func missingConversation() {
    #expect(
      !AppCommandAvailability.conversationIdle.isEnabled(
        in: AppCommandContext(
          hasConversation: false,
          isGenerating: false
        )
      )
    )
  }

  @Test("An idle active conversation can receive a prompt")
  func idleConversation() {
    #expect(
      AppCommandAvailability.conversationIdle.isEnabled(
        in: AppCommandContext(
          hasConversation: true,
          isGenerating: false
        )
      )
    )
  }

  @Test("A generating active conversation cannot receive a prompt")
  func generatingConversation() {
    #expect(
      !AppCommandAvailability.conversationIdle.isEnabled(
        in: AppCommandContext(
          hasConversation: true,
          isGenerating: true
        )
      )
    )
  }

  @Test("Prompt application consumes the canonical idle-conversation policy")
  func canonicalAvailabilityContract() throws {
    let sourceURL = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent(
        "Sources/QwenPrime/Views/Settings/SystemPromptSettingsTab.swift"
      )
    let source = try String(contentsOf: sourceURL, encoding: .utf8)

    #expect(
      source.contains(
        "AppCommandAvailability.conversationIdle.isEnabled("
      )
    )
    #expect(source.contains("in: appState.commandContext()"))
    #expect(!source.contains("AppCommands.clearActiveChat"))
    #expect(!source.contains("SystemPromptApplication"))
  }
}
