import SwiftUI
import AppKit

public struct SettingsView: View {
    @Bindable public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        TabView {
            GeneralSettingsTab(appState: appState)
                .tabItem {
                    Label("General", systemImage: "gearshape.fill")
                }
                .tag(0)

            EngineSettingsTab(appState: appState)
                .tabItem {
                    Label("Engine & MLX", systemImage: "bolt.horizontal.fill")
                }
                .tag(1)

            SandboxSettingsTab(appState: appState)
                .tabItem {
                    Label("Sandbox", systemImage: "shippingbox.fill")
                }
                .tag(2)

            AppearanceSettingsTab(appState: appState)
                .tabItem {
                    Label("Appearance", systemImage: "paintpalette.fill")
                }
                .tag(3)

            ShortcutsSettingsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
                .tag(4)
        }
        .frame(width: 540, height: 420)
    }
}

// MARK: - 1. General Tab
struct GeneralSettingsTab: View {
    @Bindable var appState: AppState
    @AppStorage("autoScroll") private var autoScroll: Bool = true
    @AppStorage("expandThinkingByDefault") private var expandThinkingByDefault: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Chat Behavior") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Default Model:")
                            .font(.system(size: 12))
                        Spacer()
                        TextField("Model ID", text: $appState.selectedModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .font(.system(size: 11.5, design: .monospaced))
                    }

                    Toggle("Auto-scroll to latest token while streaming", isOn: $autoScroll)
                        .font(.system(size: 12))

                    Toggle("Expand Chain-of-Thought (<think>) by default", isOn: $expandThinkingByDefault)
                        .font(.system(size: 12))
                }
                .padding(8)
            }

            GroupBox("About Qwen Prime") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Version:")
                            .font(.system(size: 12))
                        Spacer()
                        Text("1.0.0 (Apple Silicon Native)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Engine Support:")
                            .font(.system(size: 12))
                        Spacer()
                        Text("Apple Metal MLX & DFlash")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(18)
    }
}

// MARK: - 2. Engine & MLX Tab
struct EngineSettingsTab: View {
    @Bindable var appState: AppState
    @State private var isTesting: Bool = false
    @State private var temperature: Double = 0.1
    @State private var topP: Double = 0.95

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Inference Server Endpoint") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Base URL:")
                            .font(.system(size: 12))
                        Spacer()
                        TextField("http://127.0.0.1:8000/v1", text: $appState.baseURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                            .font(.system(size: 11.5, design: .monospaced))
                    }

                    HStack {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(appState.serverStatus.isConnected ? Color.green : Color.orange)
                                .frame(width: 7, height: 7)

                            Text(appState.serverStatus.displayText)
                                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                                .foregroundStyle(appState.serverStatus.isConnected ? .primary : .secondary)
                        }

                        Spacer()

                        Button {
                            isTesting = true
                            Task {
                                await appState.checkServerHealth()
                                isTesting = false
                            }
                        } label: {
                            if isTesting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("Test Connection")
                            }
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("Sampling Hyperparameters") {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Temperature:")
                                .font(.system(size: 12))
                            Spacer()
                            Text(String(format: "%.2f", temperature))
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.cyan)
                        }
                        Slider(value: $temperature, in: 0.0...1.0, step: 0.05)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Top-P:")
                                .font(.system(size: 12))
                            Spacer()
                            Text(String(format: "%.2f", topP))
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(Color.cyan)
                        }
                        Slider(value: $topP, in: 0.1...1.0, step: 0.05)
                    }
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(18)
    }
}

// MARK: - 3. Sandbox & Tools Tab
struct SandboxSettingsTab: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Active Project Workspace") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(appState.sandboxDirectory.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))

                    HStack(spacing: 10) {
                        Button("Choose Folder...") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                appState.setSandboxDirectory(url)
                            }
                        }

                        Button("Reveal in Finder") {
                            appState.openSandboxInFinder()
                        }

                        Button("Open Terminal") {
                            appState.openSandboxInTerminal()
                        }
                    }
                }
                .padding(8)
            }

            GroupBox("Agent Sandbox Capabilities") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                        Text("IPython sandbox execution with stdout/stderr capture")
                            .font(.system(size: 11.5))
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                        Text("Auto-detection of per-project rules (.prime/, PRIME.md)")
                            .font(.system(size: 11.5))
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                        Text("CLI integration configured at ~/.prime/agent/models.json")
                            .font(.system(size: 11.5))
                    }
                }
                .foregroundStyle(.secondary)
                .padding(8)
            }

            Spacer()
        }
        .padding(18)
    }
}

// MARK: - 4. Appearance Tab
struct AppearanceSettingsTab: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Chat & Markdown Theme") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Theme Style:", selection: $appState.currentThemeType) {
                        ForEach(ThemeType.allCases) { theme in
                            Text(theme.rawValue).tag(theme)
                        }
                    }
                    .pickerStyle(.menu)

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Heading 1 Preview")
                                .font(.system(size: 13.5, weight: .bold))
                                .foregroundStyle(appState.activeTheme.h1)

                            Text("Paragraph text with accent styling.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(appState.activeTheme.text)

                            Text("inline_code_block()")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(appState.activeTheme.inlineCodeText)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(appState.activeTheme.inlineCodeBackground, in: RoundedRectangle(cornerRadius: 4))
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(18)
    }
}

// MARK: - 5. Shortcuts Tab
struct ShortcutsSettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox("Keyboard Shortcuts") {
                VStack(spacing: 8) {
                    shortcutRow(action: "New Conversation", key: "⌘ N")
                    shortcutRow(action: "Clear Active Chat", key: "⌘ K")
                    shortcutRow(action: "Open Settings Window", key: "⌘ ,")
                    shortcutRow(action: "Reconnect to Engine", key: "⌘ ⇧ R")
                    shortcutRow(action: "Send Message", key: "Return")
                    shortcutRow(action: "Insert Newline in Input", key: "⇧ Return")
                    shortcutRow(action: "Stop Streaming Response", key: "Esc")
                }
                .padding(8)
            }

            Spacer()
        }
        .padding(18)
    }

    private func shortcutRow(action: String, key: String) -> some View {
        HStack {
            Text(action)
                .font(.system(size: 12))
            Spacer()
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
        }
    }
}
