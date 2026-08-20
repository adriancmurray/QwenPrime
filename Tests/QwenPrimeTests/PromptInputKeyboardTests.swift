import SwiftUI
import Testing

@testable import QwenPrime

@Suite("Prompt input keyboard behavior")
struct PromptInputKeyboardTests {
  private let enabledContext = AppCommandContext(
    hasConversation: true,
    hasMessageText: true,
    hasInputFocus: true
  )

  @Test("Shift Return inserts a newline without sending")
  func shiftReturnInsertsNewline() {
    var text = "First line"
    var sendCount = 0

    let isHandled = PromptInputKeyboardPolicy.handleReturn(
      modifiers: AppCommands.insertNewline.shortcut.modifiers.eventModifiers,
      context: enabledContext,
      insertNewline: { text.append("\n") },
      onSend: { sendCount += 1 }
    )

    #expect(isHandled)
    #expect(text == "First line\n")
    #expect(sendCount == 0)
  }

  @Test("Return sends without inserting a newline")
  func returnSendsMessage() {
    var text = "Send this"
    var sendCount = 0

    let isHandled = PromptInputKeyboardPolicy.handleReturn(
      modifiers: AppCommands.sendMessage.shortcut.modifiers.eventModifiers,
      context: enabledContext,
      insertNewline: { text.append("\n") },
      onSend: { sendCount += 1 }
    )

    #expect(isHandled)
    #expect(text == "Send this")
    #expect(sendCount == 1)
  }

  @Test("Return shortcuts use canonical command descriptors and availability")
  func shortcutsConsumeCanonicalDescriptors() {
    let noFocus = AppCommandContext(
      hasConversation: true,
      hasMessageText: true
    )
    let generating = AppCommandContext(
      hasConversation: true,
      isGenerating: true,
      hasMessageText: true,
      hasInputFocus: true
    )

    #expect(
      PromptInputKeyboardPolicy.action(
        for: AppCommands.insertNewline.shortcut.modifiers.eventModifiers,
        context: enabledContext
      ) == .insertNewline
    )
    #expect(
      PromptInputKeyboardPolicy.action(
        for: AppCommands.sendMessage.shortcut.modifiers.eventModifiers,
        context: enabledContext
      ) == .sendMessage
    )
    #expect(
      PromptInputKeyboardPolicy.action(
        for: AppCommands.insertNewline.shortcut.modifiers.eventModifiers,
        context: noFocus
      ) == .ignored
    )
    #expect(
      PromptInputKeyboardPolicy.action(
        for: AppCommands.sendMessage.shortcut.modifiers.eventModifiers,
        context: generating
      ) == .ignored
    )
  }

  @Test("Prompt input handles Return once through the keyboard policy")
  func promptInputWiresCanonicalShortcutWithoutSubmitDuplication() throws {
    let source = try sourceFile(
      "Sources/QwenPrime/Views/Chat/PromptInputBar.swift"
    )

    #expect(
      source.contains(
        "AppCommands.sendMessage.shortcut.key.keyEquivalent"
      )
    )
    #expect(source.contains("handleReturnKey(keyPress)"))
    #expect(source.contains("AppCommands.insertNewline"))
    #expect(!source.contains(".onSubmit"))
  }

  private func sourceFile(_ path: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(
      contentsOf: repositoryRoot.appendingPathComponent(path),
      encoding: .utf8
    )
  }
}
