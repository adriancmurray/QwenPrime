import AppKit
import Foundation
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let terminationCoordinator = ApplicationTerminationCoordinator()
    private var terminationTask: Task<Void, Never>?

    func applicationShouldTerminate(
        _ sender: NSApplication
    ) -> NSApplication.TerminateReply {
        guard terminationTask == nil else { return .terminateLater }
        terminationTask = Task {
            await terminationCoordinator.stopThenReply(
                stop: {
                    await ServerHealthService.shared.stopEngine()
                },
                reply: {
                    sender.reply(toApplicationShouldTerminate: true)
                }
            )
        }
        return .terminateLater
    }
}

struct ApplicationTerminationCoordinator: Sendable {
    /// The runtime's own graceful and forced shutdown windows total seven
    /// seconds, leaving one second for actor scheduling before AppKit proceeds.
    static let defaultTimeout = Duration.seconds(8)

    let timeout: Duration

    init(timeout: Duration = Self.defaultTimeout) {
        self.timeout = timeout
    }

    func stopThenReply(
        stop: @escaping @Sendable () async -> Void,
        reply: @escaping @MainActor @Sendable () -> Void
    ) async {
        await waitForStopOrTimeout(stop: stop)
        await reply()
    }

    private func waitForStopOrTimeout(
        stop: @escaping @Sendable () async -> Void
    ) async {
        // Unstructured contenders are intentional: structured task groups wait
        // for a noncooperative losing child even after the timeout wins.
        await withCheckedContinuation { continuation in
            let race = OneShotContinuation(continuation)
            Task {
                await stop()
                race.resume()
            }
            Task {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return
                }
                race.resume()
            }
        }
    }
}

private final class OneShotContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume()
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
                .appConfirmationAlert(
                    appState: appState,
                    scope: .mainWindow
                )
                .appOperationErrorAlert(
                    appState: appState,
                    scope: .mainWindow
                )
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
                Button(AppCommands.newConversation.title) {
                    appState.createNewConversation()
                }
                .help(AppCommands.newConversation.help)
                .appKeyboardShortcut(AppCommands.newConversation)
            }

            CommandMenu("Chat") {
                Button(AppCommands.clearActiveChat.title) {
                    if let conversationID = appState.selectedConversationId {
                        appState.requestClearConversationMessages(id: conversationID)
                    }
                }
                .disabled(
                    !AppCommands.clearActiveChat.isEnabled(
                        in: appState.commandContext()
                    )
                )
                .help(AppCommands.clearActiveChat.help)
                .appKeyboardShortcut(AppCommands.clearActiveChat)

                Button(AppCommands.stopGeneration.title) {
                    appState.requestStopGeneration()
                }
                .disabled(
                    !AppCommands.stopGeneration.isEnabled(
                        in: appState.commandContext()
                    )
                )
                .help(AppCommands.stopGeneration.help)
                .appKeyboardShortcut(AppCommands.stopGeneration)

                Divider()

                Button(AppCommands.reconnectToEngine.title) {
                    Task {
                        await appState.checkServerHealth()
                    }
                }
                .help(AppCommands.reconnectToEngine.help)
                .appKeyboardShortcut(AppCommands.reconnectToEngine)
            }
        }

        #if os(macOS)
        Settings {
            SettingsView(appState: appState)
                .appConfirmationAlert(
                    appState: appState,
                    scope: .settingsWindow
                )
                .appOperationErrorAlert(
                    appState: appState,
                    scope: .settingsWindow
                )
        }
        #endif
    }
}
