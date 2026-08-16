import SwiftUI

public struct ConversationRow: View {
    public let conversation: Conversation
    public let isSelected: Bool
    public let onSelect: () -> Void
    public let onDelete: () -> Void
    public let onRename: (String) -> Void
    public let onDuplicate: () -> Void

    @State private var isRenaming: Bool = false
    @State private var renameText: String = ""
    @State private var isHovered: Bool = false

    public init(
        conversation: Conversation,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onRename: @escaping (String) -> Void,
        onDuplicate: @escaping () -> Void
    ) {
        self.conversation = conversation
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onRename = onRename
        self.onDuplicate = onDuplicate
    }

    private var subtitle: String {
        if let lastMsg = conversation.messages.last {
            let txt = lastMsg.content.isEmpty ? (lastMsg.thinkingContent ?? "Thinking...") : lastMsg.content
            return txt.replacingOccurrences(of: "\n", with: " ")
        }
        return "No messages yet"
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(isSelected ? Color.cyan : Color.secondary.opacity(0.8))

                if isRenaming {
                    TextField("Title", text: $renameText, onCommit: {
                        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            onRename(trimmed)
                        }
                        isRenaming = false
                    })
                    .font(.system(size: 12, weight: .medium))
                    .textFieldStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.title)
                            .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 2)

                // Row action menu (visible on hover or when selected)
                if isHovered || isSelected {
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

                        Divider()

                        Button(role: .destructive) {
                            onDelete()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.white.opacity(0.09) : (isHovered ? Color.white.opacity(0.04) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
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

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
