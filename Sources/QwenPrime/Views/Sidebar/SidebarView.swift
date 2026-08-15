import SwiftUI

public struct SidebarView: View {
    @Bindable public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    private var groupedConversations: [(String, [Conversation])] {
        let calendar = Calendar.current
        let now = Date()

        var today: [Conversation] = []
        var yesterday: [Conversation] = []
        var past7Days: [Conversation] = []
        var older: [Conversation] = []

        for conv in appState.filteredConversations {
            if calendar.isDateInToday(conv.updatedAt) {
                today.append(conv)
            } else if calendar.isDateInYesterday(conv.updatedAt) {
                yesterday.append(conv)
            } else if let days = calendar.dateComponents([.day], from: conv.updatedAt, to: now).day, days <= 7 {
                past7Days.append(conv)
            } else {
                older.append(conv)
            }
        }

        var result: [(String, [Conversation])] = []
        if !today.isEmpty { result.append(("Today", today)) }
        if !yesterday.isEmpty { result.append(("Yesterday", yesterday)) }
        if !past7Days.isEmpty { result.append(("Previous 7 Days", past7Days)) }
        if !older.isEmpty { result.append(("Older", older)) }
        return result
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header: New Chat Button & Search Bar
            VStack(spacing: 10) {
                Button {
                    appState.createNewConversation()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 13, weight: .semibold))
                        Text("New Chat")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("⌘N")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.85), Color.indigo.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)

                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField("Search conversations...", text: $appState.searchText)
                        .font(.system(size: 12))
                        .textFieldStyle(.plain)

                    if !appState.searchText.isEmpty {
                        Button {
                            appState.searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()
                .opacity(0.3)

            // Conversation Groups
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(groupedConversations, id: \.0) { groupName, convs in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(groupName)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 4)

                            ForEach(convs) { conversation in
                                ConversationRow(
                                    conversation: conversation,
                                    isSelected: appState.selectedConversationId == conversation.id,
                                    onSelect: {
                                        appState.selectedConversationId = conversation.id
                                    },
                                    onDelete: {
                                        appState.deleteConversation(id: conversation.id)
                                    },
                                    onRename: { newTitle in
                                        appState.renameConversation(id: conversation.id, newTitle: newTitle)
                                    }
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }

            Divider()
                .opacity(0.3)

            // Footer: Settings & Server status
            HStack {
                Button {
                    appState.isSettingsPresented = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 12))
                        Text("Settings")
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                // Health beacon
                HStack(spacing: 5) {
                    Circle()
                        .fill(appState.serverStatus.isConnected ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)

                    Text(appState.serverStatus.isConnected ? "Local Engine Ready" : "Connecting...")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
    }
}
