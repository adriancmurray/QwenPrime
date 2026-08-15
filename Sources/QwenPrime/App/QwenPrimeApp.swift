import SwiftUI

@main
struct QwenPrimeApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainSplitView(appState: appState)
                .frame(minWidth: 800, minHeight: 550)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            SidebarCommands()

            CommandGroup(replacing: .newItem) {
                Button("New Conversation") {
                    appState.createNewConversation()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Chat") {
                Button("Clear Messages") {
                    if var conv = appState.selectedConversation {
                        conv.messages.removeAll()
                        conv.touch()
                        appState.selectedConversation = conv
                        appState.saveConversation(conv)
                    }
                }
                .keyboardShortcut("k", modifiers: .command)

                Divider()

                Button("Reconnect to Engine") {
                    Task {
                        await appState.checkServerHealth()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
        }

        #if os(macOS)
        Settings {
            SettingsView(appState: appState)
                .preferredColorScheme(.dark)
        }
        #endif
    }
}
