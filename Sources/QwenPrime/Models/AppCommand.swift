import SwiftUI

public enum AppCommandIdentifier: String, Equatable, Sendable {
  case newConversation
  case clearActiveChat
  case openSettings
  case reconnectToEngine
  case sendMessage
  case insertNewline
  case stopGeneration
}

public struct AppCommandContext: Equatable, Sendable {
  public let hasConversation: Bool
  public let isGenerating: Bool
  public let hasMessageText: Bool
  public let hasInputFocus: Bool

  public init(
    hasConversation: Bool = false,
    isGenerating: Bool = false,
    hasMessageText: Bool = false,
    hasInputFocus: Bool = false
  ) {
    self.hasConversation = hasConversation
    self.isGenerating = isGenerating
    self.hasMessageText = hasMessageText
    self.hasInputFocus = hasInputFocus
  }
}

public enum AppCommandAvailability: Equatable, Sendable {
  case always
  case conversationIdle
  case conversationGenerating
  case messageTextWhileIdle
  case inputFocused

  func isEnabled(in context: AppCommandContext) -> Bool {
    switch self {
    case .always:
      true
    case .conversationIdle:
      context.hasConversation && !context.isGenerating
    case .conversationGenerating:
      context.hasConversation && context.isGenerating
    case .messageTextWhileIdle:
      context.hasConversation
        && !context.isGenerating
        && context.hasMessageText
    case .inputFocused:
      context.hasInputFocus
    }
  }
}

public enum AppShortcutKey: String, Equatable, Sendable {
  case escape
  case k
  case n
  case r
  case comma
  case returnKey

  public var keyEquivalent: KeyEquivalent {
    switch self {
    case .escape: .escape
    case .k: "k"
    case .n: "n"
    case .r: "r"
    case .comma: ","
    case .returnKey: .return
    }
  }

  fileprivate var displayName: String {
    switch self {
    case .escape: "Esc"
    case .returnKey: "Return"
    default: rawValue.uppercased()
    }
  }
}

public struct AppShortcutModifiers: OptionSet, Equatable, Sendable {
  public let rawValue: Int

  public static let command = AppShortcutModifiers(rawValue: 1 << 0)
  public static let shift = AppShortcutModifiers(rawValue: 1 << 1)

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public var eventModifiers: EventModifiers {
    var result: EventModifiers = []
    if contains(.command) {
      result.insert(.command)
    }
    if contains(.shift) {
      result.insert(.shift)
    }
    return result
  }

  fileprivate var displayPrefix: String {
    var result = ""
    if contains(.command) {
      result += "⌘ "
    }
    if contains(.shift) {
      result += "⇧ "
    }
    return result
  }
}

public struct AppCommandShortcut: Equatable, Sendable {
  public let key: AppShortcutKey
  public let modifiers: AppShortcutModifiers

  public init(
    key: AppShortcutKey,
    modifiers: AppShortcutModifiers = []
  ) {
    self.key = key
    self.modifiers = modifiers
  }

  public var displayName: String {
    "\(modifiers.displayPrefix)\(key.displayName)"
  }
}

public struct AppCommandDescriptor: Identifiable, Equatable, Sendable {
  public let id: AppCommandIdentifier
  public let title: String
  public let help: String
  public let shortcut: AppCommandShortcut
  public let availability: AppCommandAvailability

  public init(
    id: AppCommandIdentifier,
    title: String,
    help: String,
    shortcut: AppCommandShortcut,
    availability: AppCommandAvailability = .always
  ) {
    self.id = id
    self.title = title
    self.help = help
    self.shortcut = shortcut
    self.availability = availability
  }

  public func isEnabled(in context: AppCommandContext) -> Bool {
    availability.isEnabled(in: context)
  }

  public var helpWithShortcut: String {
    "\(help) (\(shortcut.displayName))"
  }
}

/// The single source for menu and settings shortcut presentation.
public enum AppCommands {
  public static let newConversation = AppCommandDescriptor(
    id: .newConversation,
    title: "New Conversation",
    help: "Start a new conversation",
    shortcut: AppCommandShortcut(key: .n, modifiers: .command)
  )
  public static let clearActiveChat = AppCommandDescriptor(
    id: .clearActiveChat,
    title: "Clear Active Chat",
    help: "Remove every message from the active conversation",
    shortcut: AppCommandShortcut(key: .k, modifiers: .command),
    availability: .conversationIdle
  )
  public static let openSettings = AppCommandDescriptor(
    id: .openSettings,
    title: "Open Settings Window",
    help: "Open Qwen Prime settings",
    shortcut: AppCommandShortcut(key: .comma, modifiers: .command)
  )
  public static let reconnectToEngine = AppCommandDescriptor(
    id: .reconnectToEngine,
    title: "Reconnect to Engine",
    help: "Check the local inference engine connection",
    shortcut: AppCommandShortcut(
      key: .r,
      modifiers: [.command, .shift]
    )
  )
  public static let sendMessage = AppCommandDescriptor(
    id: .sendMessage,
    title: "Send Message",
    help: "Send the current message",
    shortcut: AppCommandShortcut(key: .returnKey),
    availability: .messageTextWhileIdle
  )
  public static let insertNewline = AppCommandDescriptor(
    id: .insertNewline,
    title: "Insert Newline in Input",
    help: "Insert a newline in the message field",
    shortcut: AppCommandShortcut(key: .returnKey, modifiers: .shift),
    availability: .inputFocused
  )
  public static let stopGeneration = AppCommandDescriptor(
    id: .stopGeneration,
    title: "Stop Streaming Response",
    help: "Stop the active generation",
    shortcut: AppCommandShortcut(key: .escape),
    availability: .conversationGenerating
  )

  public static let shortcuts: [AppCommandDescriptor] = [
    newConversation,
    clearActiveChat,
    openSettings,
    reconnectToEngine,
    sendMessage,
    insertNewline,
    stopGeneration,
  ]
}

public struct AppCommandRequest: Equatable, Identifiable, Sendable {
  public let id: UUID
  public let command: AppCommandIdentifier
  public let conversationID: UUID?

  public init(
    id: UUID = UUID(),
    command: AppCommandIdentifier,
    conversationID: UUID?
  ) {
    self.id = id
    self.command = command
    self.conversationID = conversationID
  }
}

extension View {
  public func appKeyboardShortcut(_ command: AppCommandDescriptor) -> some View {
    keyboardShortcut(
      command.shortcut.key.keyEquivalent,
      modifiers: command.shortcut.modifiers.eventModifiers
    )
  }
}
