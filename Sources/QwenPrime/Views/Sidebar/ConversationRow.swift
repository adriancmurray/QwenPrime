import SwiftUI

public struct ConversationRow: View {
    public let conversation: Conversation
    public let isSelected: Bool
    public let isGenerating: Bool
    public let onSelect: () -> Void
    public let onDelete: () -> Void
    public let onRename: (String) -> Void
    public let onDuplicate: () -> Void

    @State private var isRenaming: Bool = false
    @State private var renameText: String = ""
    @State private var isHovered: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        conversation: Conversation,
        isSelected: Bool,
        isGenerating: Bool,
        onSelect: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        onDuplicate: @escaping () -> Void
    ) {
        self.conversation = conversation
        self.isSelected = isSelected
        self.isGenerating = isGenerating
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onRename = onRename
        self.onDuplicate = onDuplicate
    }

    private var presentation: ConversationRowPresentation {
        ConversationRowPresentation(conversation: conversation)
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: isSelected ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: DesignTokens.Typography.footnote))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 15)

                if isRenaming {
                    TextField("Title", text: $renameText, onCommit: {
                        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            onRename(trimmed)
                        }
                        isRenaming = false
                    })
                    .font(.system(size: DesignTokens.Typography.callout, weight: .medium))
                    .textFieldStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Text(conversation.title)
                                .font(.system(size: DesignTokens.Typography.callout, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Spacer(minLength: DesignTokens.Spacing.xs)

                            Text(presentation.timestamp)
                                .font(.system(size: DesignTokens.Typography.caption2, design: .monospaced))
                                .foregroundStyle(.quaternary)
                                .opacity(isHovered ? 0 : 1)
                        }

                        Text(presentation.preview)
                            .font(.system(size: DesignTokens.Typography.caption))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                ZStack {
                    if isGenerating && !isSelected {
                        ConversationActivityIndicator(color: .cyan)
                            .transition(.opacity.combined(with: .scale(scale: 0.84)))
                    }

                    Menu {
                        Button {
                            renameText = conversation.title
                            isRenaming = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        Button {
                            onDuplicate()
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .disabled(isGenerating)

                        Divider()

                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(isGenerating)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: DesignTokens.Typography.caption, weight: .bold))
                            .foregroundStyle(.secondary)
                            .frame(
                                width: DesignTokens.Layout.sidebarRowActionWidth,
                                height: DesignTokens.Layout.sidebarRowActionWidth
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .opacity((isHovered || isSelected) && !isGenerating ? 1 : 0)
                    .allowsHitTesting((isHovered || isSelected) && !isGenerating)
                }
                .frame(width: DesignTokens.Layout.sidebarRowActionWidth)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .frame(minHeight: DesignTokens.Layout.sidebarRowMinHeight)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
                    .fill(
                        isSelected
                            ? DesignTokens.Surface.selected
                            : (isHovered ? DesignTokens.Surface.subtle : Color.clear)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : DesignTokens.AnimationCurve.hover) {
                isHovered = hovering
            }
        }
        .animation(reduceMotion ? nil : DesignTokens.AnimationCurve.standard, value: isSelected)
        .animation(reduceMotion ? nil : DesignTokens.AnimationCurve.standard, value: isGenerating)
        .accessibilityLabel(conversation.title)
        .accessibilityValue(isGenerating ? "Generating response" : presentation.preview)
        .contextMenu {
            Button {
                renameText = conversation.title
                isRenaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }

            Button {
                onDuplicate()
            } label: {
                Label("Duplicate", systemImage: "plus.square.on.square")
            }
            .disabled(isGenerating)

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(isGenerating)
        }
    }
}
