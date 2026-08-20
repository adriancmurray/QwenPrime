import SwiftUI

public struct ConversationRow: View {
  public let conversation: Conversation
  public let isSelected: Bool
  public let isGenerating: Bool
  public let themeTint: Color
  public let onRequestDelete: () -> Void
  public let onRename: (String) -> Void
  public let onDuplicate: () -> Void
  public let onSelect: () -> Void

  @State private var isRenaming: Bool = false
  @State private var renameText: String = ""
  @State private var isHovered: Bool = false
  @State private var isCancelingRename: Bool = false
  @State private var isActionPopoverPresented: Bool = false
  @FocusState private var isRenameFocused: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(
    conversation: Conversation,
    isSelected: Bool,
    isGenerating: Bool,
    themeTint: Color,
    onRequestDelete: @escaping () -> Void,
    onRename: @escaping (String) -> Void,
    onDuplicate: @escaping () -> Void,
    onSelect: @escaping () -> Void
  ) {
    self.conversation = conversation
    self.isSelected = isSelected
    self.isGenerating = isGenerating
    self.themeTint = themeTint
    self.onRequestDelete = onRequestDelete
    self.onRename = onRename
    self.onDuplicate = onDuplicate
    self.onSelect = onSelect
  }

  private var presentation: ConversationRowPresentation {
    ConversationRowPresentation(conversation: conversation)
  }

  private var conversationIcon: some View {
    Image(systemName: isSelected ? "bubble.left.fill" : "bubble.left")
      .font(DesignTokens.TextStyle.footnote)
      .foregroundStyle(isSelected ? themeTint : Color.secondary)
      .frame(width: 15)
      .accessibilityHidden(true)
  }

  public var body: some View {
    HStack(spacing: DesignTokens.Spacing.md) {
      if isRenaming {
        HStack(spacing: DesignTokens.Spacing.sm) {
          conversationIcon

          TextField("Conversation title", text: $renameText)
            .font(DesignTokens.TextStyle.callout.weight(.medium))
            .textFieldStyle(.plain)
            .focused($isRenameFocused)
            .onSubmit(commitRename)
            .onExitCommand(perform: cancelRename)
            .accessibilityLabel("Rename conversation")
        }
      } else {
        Button(action: onSelect) {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            HStack(spacing: DesignTokens.Spacing.sm) {
              conversationIcon

              Text(conversation.title)
                .font(
                  DesignTokens.TextStyle.callout.weight(
                    isSelected ? .semibold : .medium
                  )
                )
                .foregroundStyle(.primary)
                .lineLimit(1)

              Spacer(minLength: DesignTokens.Spacing.xs)

              Text(presentation.timestamp)
                .font(DesignTokens.TextStyle.caption2Monospaced)
                .foregroundStyle(.quaternary)
            }

            Text(presentation.preview)
              .font(DesignTokens.TextStyle.caption)
              .foregroundStyle(.tertiary)
              .lineLimit(1)
              .padding(
                .leading,
                15 + DesignTokens.Spacing.sm
              )
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(conversation.title)
        .accessibilityValue(
          isGenerating ? "Generating response" : presentation.preview
        )
      }

      if isGenerating {
        ConversationActivityIndicator(color: DesignTokens.Status.reasoning)
          .transition(.opacity.combined(with: .scale(scale: 0.84)))
      }

      conversationActionButton
    }
    .padding(.horizontal, DesignTokens.Spacing.md)
    .padding(.vertical, DesignTokens.Spacing.sm)
    .frame(maxWidth: .infinity, alignment: .leading)
    .frame(minHeight: DesignTokens.Layout.sidebarRowMinHeight)
    .background(
      RoundedRectangle(
        cornerRadius: DesignTokens.Radius.md,
        style: .continuous
      )
      .fill(isSelected ? themeTint.opacity(0.24) : Color.clear)
    )
    .contentShape(Rectangle())
    .onHover { hovering in
      withAnimation(reduceMotion ? nil : DesignTokens.AnimationCurve.hover) {
        isHovered = hovering
      }
    }
    .animation(reduceMotion ? nil : DesignTokens.AnimationCurve.standard, value: isSelected)
    .animation(reduceMotion ? nil : DesignTokens.AnimationCurve.standard, value: isGenerating)
    .onChange(of: isRenameFocused) { wasFocused, isFocused in
      if wasFocused && !isFocused && isRenaming && !isCancelingRename {
        commitRename()
      }
      isCancelingRename = false
    }
  }

  private var conversationActionButton: some View {
    Button {
      isActionPopoverPresented = true
    } label: {
      Image(systemName: "ellipsis")
        .font(DesignTokens.TextStyle.caption.weight(.bold))
        .foregroundStyle(.secondary)
        .frame(
          width: DesignTokens.Layout.toolbarControlHeight,
          height: DesignTokens.Layout.toolbarControlHeight
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .popover(
      isPresented: $isActionPopoverPresented,
      arrowEdge: .trailing
    ) {
      ConversationActionPopover(
        themeTint: themeTint,
        isGenerating: isGenerating,
        onRename: renameFromActionPopover,
        onDuplicate: duplicateFromActionPopover,
        onRequestDelete: deleteFromActionPopover
      )
    }
    .opacity(isHovered || isSelected ? 1 : 0.62)
    .help("Conversation actions")
    .accessibilityLabel("Actions for \(conversation.title)")
  }

  private func beginRenaming() {
    renameText = conversation.title
    isCancelingRename = false
    isRenaming = true
    Task { @MainActor in
      await Task.yield()
      isRenameFocused = true
    }
  }

  private func renameFromActionPopover() {
    isActionPopoverPresented = false
    beginRenaming()
  }

  private func duplicateFromActionPopover() {
    isActionPopoverPresented = false
    onDuplicate()
  }

  private func deleteFromActionPopover() {
    isActionPopoverPresented = false
    onRequestDelete()
  }

  private func commitRename() {
    let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      onRename(trimmed)
    }
    isRenaming = false
    isRenameFocused = false
  }

  private func cancelRename() {
    isCancelingRename = true
    renameText = conversation.title
    isRenaming = false
    isRenameFocused = false
  }
}
