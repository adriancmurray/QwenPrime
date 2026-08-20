import SwiftUI

struct ConversationActionDescriptor: Sendable {
  let title: String
  let systemImage: String
  let accessibilityLabel: String
  let isDisabledWhileGenerating: Bool

  func isDisabled(isGenerating: Bool) -> Bool {
    isGenerating && isDisabledWhileGenerating
  }
}

enum ConversationActions {
  static let rename = ConversationActionDescriptor(
    title: "Rename",
    systemImage: "pencil",
    accessibilityLabel: "Rename conversation",
    isDisabledWhileGenerating: false
  )
  static let duplicate = ConversationActionDescriptor(
    title: "Duplicate",
    systemImage: "plus.square.on.square",
    accessibilityLabel: "Duplicate conversation",
    isDisabledWhileGenerating: true
  )
  static let delete = ConversationActionDescriptor(
    title: "Delete",
    systemImage: "trash",
    accessibilityLabel: "Delete conversation",
    isDisabledWhileGenerating: true
  )
}

struct ConversationActionPopover: View {
  let themeTint: Color
  let isGenerating: Bool
  let onRename: () -> Void
  let onDuplicate: () -> Void
  let onRequestDelete: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      ThemedPopoverActionRow(
        title: ConversationActions.rename.title,
        systemImage: ConversationActions.rename.systemImage,
        selectionTint: themeTint,
        accessibilityLabel: ConversationActions.rename.accessibilityLabel,
        action: onRename
      )

      ThemedPopoverActionRow(
        title: ConversationActions.duplicate.title,
        systemImage: ConversationActions.duplicate.systemImage,
        selectionTint: themeTint,
        isEnabled: !ConversationActions.duplicate.isDisabled(
          isGenerating: isGenerating
        ),
        accessibilityLabel: ConversationActions.duplicate.accessibilityLabel,
        action: onDuplicate
      )

      Divider()

      ThemedPopoverActionRow(
        title: ConversationActions.delete.title,
        systemImage: ConversationActions.delete.systemImage,
        selectionTint: DesignTokens.Status.danger,
        foregroundColor: DesignTokens.Status.danger,
        isEnabled: !ConversationActions.delete.isDisabled(
          isGenerating: isGenerating
        ),
        accessibilityLabel: ConversationActions.delete.accessibilityLabel,
        action: onRequestDelete
      )
    }
    .padding(DesignTokens.Spacing.xxs)
    .frame(width: DesignTokens.Layout.conversationActionPopoverWidth)
    .tint(themeTint)
  }
}

struct ConversationSwipeActions: View {
  let isGenerating: Bool
  let onDuplicate: () -> Void
  let onRequestDelete: () -> Void

  var body: some View {
    Group {
      Button(role: .destructive, action: onRequestDelete) {
        Image(systemName: ConversationActions.delete.systemImage)
      }
      .accessibilityLabel(ConversationActions.delete.accessibilityLabel)
      .disabled(
        ConversationActions.delete.isDisabled(
          isGenerating: isGenerating
        )
      )

      Button(action: onDuplicate) {
        Image(systemName: ConversationActions.duplicate.systemImage)
      }
      .accessibilityLabel(ConversationActions.duplicate.accessibilityLabel)
      .disabled(
        ConversationActions.duplicate.isDisabled(
          isGenerating: isGenerating
        )
      )
      .tint(DesignTokens.Status.information)
    }
  }
}
