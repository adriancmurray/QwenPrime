import SwiftUI

public struct ConversationRow: View {
    public let conversation: Conversation
    public let isSelected: Bool
    public let onSelect: () -> Void
    public let onDelete: () -> Void
    public let onRename: (String) -> Void

    @State private var isRenaming: Bool = false
    @State private var renameText: String = ""

    public init(
        conversation: Conversation,
        isSelected: Bool,
        onSelect: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onRename: @escaping (String) -> Void
    ) {
        self.conversation = conversation
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onDelete = onDelete
        self.onRename = onRename
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
            HStack(spacing: 9) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.cyan : Color.secondary)

                if isRenaming {
                    TextField("Title", text: $renameText, onCommit: {
                        let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            onRename(trimmed)
                        }
                        isRenaming = false
                    })
                    .font(.system(size: 12.5, weight: .medium))
                    .textFieldStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.title)
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.primary : Color.primary.opacity(0.85))
                            .lineLimit(1)

                        Text(subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                renameText = conversation.title
                isRenaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
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
