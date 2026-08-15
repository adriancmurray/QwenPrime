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
            VStack(spacing: 8) {
                Button {
                    appState.createNewConversation()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("New Chat")
                            .font(.system(size: 12.5, weight: .semibold))
                        Spacer()
                        Text("⌘N")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        LinearGradient(
                            colors: [Color.blue.opacity(0.85), Color.indigo.opacity(0.85)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)

                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField("Search chats...", text: $appState.searchText)
                        .font(.system(size: 11.5))
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
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Divider()
                .opacity(0.3)

            // Swipeable Conversation List
            List {
                ForEach(groupedConversations, id: \.0) { groupName, convs in
                    Section(header: Text(groupName).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)) {
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
                            .listRowInsets(EdgeInsets(top: 2, leading: 2, bottom: 2, trailing: 2))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    appState.deleteConversation(id: conversation.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    // Trigger rename via context
                                } label: {
                                    Label("Options", systemImage: "ellipsis")
                                }
                                .tint(.gray)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
                .opacity(0.3)

            // Footer: Settings & Server status
            HStack(spacing: 8) {
                Button {
                    appState.isSettingsPresented = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11.5))
                        Text("Settings")
                            .font(.system(size: 11.5))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                // Health beacon
                HStack(spacing: 5) {
                    Circle()
                        .fill(appState.serverStatus.isConnected ? Color.green : Color.orange)
                        .frame(width: 6, height: 6)

                    Text(appState.serverStatus.isConnected ? "Engine Ready" : "Connecting...")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        }
        .frame(minWidth: 210, idealWidth: 250, maxWidth: 300)
    }
}
