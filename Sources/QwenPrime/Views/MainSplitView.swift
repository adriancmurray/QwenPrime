import SwiftUI

public struct MainSplitView: View {
    @Bindable public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            ChatView(appState: appState)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help("Toggle Sidebar")
            }

            ToolbarItem(placement: .principal) {
                if let conv = appState.selectedConversation {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(appState.serverStatus.isConnected ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)

                        Text(conv.title)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 12) {
                    // Clear messages in chat
                    Button {
                        if var conv = appState.selectedConversation {
                            conv.messages.removeAll()
                            conv.touch()
                            appState.selectedConversation = conv
                            appState.saveConversation(conv)
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Clear Chat (⌘K)")
                    .keyboardShortcut("k", modifiers: .command)

                    // Settings trigger
                    Button {
                        appState.isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("Settings")
                }
            }
        }
        .sheet(isPresented: $appState.isSettingsPresented) {
            SettingsView(appState: appState)
        }
    }
}
