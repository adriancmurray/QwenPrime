import SwiftUI
import AppKit

public struct ChatHeaderView: View {
    @Bindable public var appState: AppState

    @State private var isEditingTitle: Bool = false
    @State private var editTitleText: String = ""

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        HStack(spacing: 12) {
            // 1. Editable Title
            if let conv = appState.selectedConversation {
                if isEditingTitle {
                    TextField("Title", text: $editTitleText, onCommit: {
                        let trimmed = editTitleText.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            appState.renameConversation(id: conv.id, newTitle: trimmed)
                        }
                        isEditingTitle = false
                    })
                    .font(.system(size: 13, weight: .bold))
                    .textFieldStyle(.plain)
                    .frame(maxWidth: 240)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Button {
                        editTitleText = conv.title
                        isEditingTitle = true
                    } label: {
                        HStack(spacing: 5) {
                            Text(conv.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            Image(systemName: "pencil")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Click to Rename Chat")
                }
            }

            Spacer()

            // 2. Sandbox Folder Action Menu
            Menu {
                Button {
                    appState.openSandboxInFinder()
                } label: {
                    Label("Reveal Sandbox in Finder", systemImage: "folder")
                }

                Button {
                    appState.openSandboxInTerminal()
                } label: {
                    Label("Open Sandbox in Terminal", systemImage: "terminal")
                }

                Divider()

                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Select Sandbox Directory"
                    if panel.runModal() == .OK, let url = panel.url {
                        appState.sandboxDirectory = url
                    }
                } label: {
                    Label("Change Sandbox Folder...", systemImage: "folder.badge.gearshape")
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color.cyan)

                    Text(appState.sandboxDirectory.lastPathComponent)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Sandbox Workspace: \(appState.sandboxDirectory.path)")

            // 3. Theme Picker Menu
            Menu {
                ForEach(ThemeType.allCases) { theme in
                    Button {
                        appState.currentThemeType = theme
                    } label: {
                        HStack {
                            Text(theme.rawValue)
                            if appState.currentThemeType == theme {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 10.5))
                        .foregroundStyle(appState.activeTheme.h1)

                    Text(appState.currentThemeType.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .help("Switch Markdown & UI Theme")

            // 4. More Options Menu (Export, Clear)
            Menu {
                Button {
                    appState.exportConversationAsMarkdown()
                } label: {
                    Label("Export as Markdown (.md)...", systemImage: "square.and.arrow.up")
                }

                Button {
                    if let conv = appState.selectedConversation {
                        let full = conv.messages.map { "\($0.role == .user ? "User:" : "Assistant:")\n\($0.content)" }.joined(separator: "\n\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(full, forType: .string)
                    }
                } label: {
                    Label("Copy All Messages", systemImage: "doc.on.doc")
                }

                Divider()

                Button(role: .destructive) {
                    if var conv = appState.selectedConversation {
                        conv.messages.removeAll()
                        conv.touch()
                        appState.selectedConversation = conv
                        appState.saveConversation(conv)
                    }
                } label: {
                    Label("Clear Chat (⌘K)", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help("Chat Actions")

            // 5. Engine Status Indicator
            HStack(spacing: 5) {
                Circle()
                    .fill(appState.serverStatus.isConnected ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)

                Text(appState.serverStatus.isConnected ? "27B MLX" : "Offline")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.04), in: Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        .overlay(
            Divider().opacity(0.2), alignment: .bottom
        )
    }
}
