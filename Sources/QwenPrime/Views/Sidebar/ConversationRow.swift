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
            return lastMsg.content.isEmpty ? (lastMsg.thinkingContent ?? "Thinking...") : lastMsg.content
        }
        return "No messages yet"
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: "bubble.left.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? Color.cyan : Color.secondary)

                if isRenaming {
                    TextField("Title", text: $renameText, onCommit: {
                        if !renameText.trimmingCharacters(in: .whitespaces).isEmpty {
                            onRename(renameText)
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

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") {
                renameText = conversation.title
                isRenaming = true
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
    }
}
