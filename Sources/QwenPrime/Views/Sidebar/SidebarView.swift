import SwiftUI
import AppKit

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
            // 1. Search Bar at Top
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                TextField("Search chats...", text: $appState.searchText)
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
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // 2. New Chat Action
            Button {
                appState.createNewConversation()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                    Text("New Chat")
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer()
                    Text("⌘N")
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
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
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            // 3. Project Scope Selector Chip Bar
            HStack(spacing: 6) {
                Button {
                    appState.selectedProjectScope = "all"
                } label: {
                    Text("All")
                        .font(.system(size: 10.5, weight: appState.selectedProjectScope == "all" ? .bold : .medium))
                        .foregroundStyle(appState.selectedProjectScope == "all" ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3.5)
                        .background(
                            appState.selectedProjectScope == "all" ? Color.white.opacity(0.12) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)

                Button {
                    appState.selectedProjectScope = appState.sandboxDirectory.lastPathComponent
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.cyan)
                        Text(appState.sandboxDirectory.lastPathComponent)
                            .font(.system(size: 10.5, weight: appState.selectedProjectScope != "all" ? .bold : .medium, design: .monospaced))
                            .foregroundStyle(appState.selectedProjectScope != "all" ? .primary : .secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3.5)
                    .background(
                        appState.selectedProjectScope != "all" ? Color.white.opacity(0.12) : Color.clear,
                        in: Capsule()
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            Divider()
                .opacity(0.25)

            // 4. Conversation Threads List
            List {
                ForEach(groupedConversations, id: \.0) { groupName, convs in
                    Section(header: Text(groupName).font(.system(size: 9.5, weight: .bold)).foregroundStyle(.secondary)) {
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
                                },
                                onDuplicate: {
                                    appState.duplicateConversation(id: conversation.id)
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 1.5, leading: 2, bottom: 1.5, trailing: 2))
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    appState.deleteConversation(id: conversation.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }

                                Button {
                                    appState.duplicateConversation(id: conversation.id)
                                } label: {
                                    Label("Duplicate", systemImage: "plus.square.on.square")
                                }
                                .tint(.blue)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider()
                .opacity(0.25)

            // 5. Footer: Settings, Theme & Status
            HStack(spacing: 8) {
                Button {
                    appState.isSettingsPresented = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 11))
                        Text("Settings")
                            .font(.system(size: 11))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                // Health Beacon
                HStack(spacing: 4) {
                    Circle()
                        .fill(appState.serverStatus.isConnected ? Color.green : Color.orange)
                        .frame(width: 5.5, height: 5.5)

                    Text(appState.serverStatus.isConnected ? "Engine Active" : "Engine Idle")
                        .font(.system(size: 9.5))
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
