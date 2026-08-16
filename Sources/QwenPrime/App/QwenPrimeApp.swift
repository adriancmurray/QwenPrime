import SwiftUI
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await ServerHealthService.shared.stopEngine()
            await MainActor.run {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }
}

@main
struct QwenPrimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainSplitView(appState: appState)
                .frame(minWidth: 720, minHeight: 480)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
            .commands {
                SidebarCommands()

                CommandGroup(after: .appInfo) {
                    Button("Check for Updates…") {
                        UpdaterService.shared.checkForUpdates()
                    }
                    .disabled(!UpdaterService.shared.canCheckForUpdates)
                }

                CommandGroup(replacing: .newItem) {
                Button("New Conversation") {
                    appState.createNewConversation()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Chat") {
                Button("Clear Messages") {
                    if let conversationID = appState.selectedConversationId {
                        appState.clearConversationMessages(id: conversationID)
                    }
                }
                .disabled(
                    appState.selectedConversationId.map(appState.isConversationGenerating) ?? false
                )
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
