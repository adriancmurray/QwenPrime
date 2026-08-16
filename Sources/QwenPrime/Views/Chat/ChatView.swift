import SwiftUI
import AppKit

public struct ChatView: View {
    @Bindable public var appState: AppState
    @State private var viewModel = ChatViewModel()
    @State private var thinkingExpandedStates: [UUID: Bool] = [:]

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let conversation = appState.selectedConversation {
                if conversation.messages.isEmpty {
                    // Empty State with Quick Prompts
                    EmptyConversationView(
                        modelName: conversation.modelId,
                        theme: appState.activeTheme,
                        onSelectPrompt: { prompt in
                            viewModel.inputText = prompt
                            viewModel.sendMessage(appState: appState)
                        }
                    )
                } else {
                    // Centered Scrollable Messages
                    ScrollViewReader { proxy in
                        ScrollView {
                            HStack {
                                Spacer(minLength: 0)

                                LazyVStack(spacing: 14) {
                                    ForEach(conversation.messages) { message in
                                        MessageBubble(
                                            message: message,
                                            theme: appState.activeTheme,
                                            isThinkingExpanded: Binding(
                                                get: { thinkingExpandedStates[message.id] ?? false },
                                                set: { thinkingExpandedStates[message.id] = $0 }
                                            )
                                        )
                                        .id(message.id)
                                    }

                                    Color.clear
                                        .frame(height: 1)
                                        .id("bottomAnchor")
                                }
                                .frame(maxWidth: 780)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)

                                Spacer(minLength: 0)
                            }
                        }
                        .onChange(of: conversation.messages.last?.content) { _, _ in
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo("bottomAnchor", anchor: .bottom)
                            }
                        }
                        .onChange(of: conversation.messages.last?.thinkingContent) { _, _ in
                            withAnimation(.easeOut(duration: 0.12)) {
                                proxy.scrollTo("bottomAnchor", anchor: .bottom)
                            }
                        }
                    }
                }

                // Centered Input Bar with Unified Project Selector
                PromptInputBar(
                    text: $viewModel.inputText,
                    isStreaming: viewModel.isStreaming,
                    modelName: conversation.modelId,
                    theme: appState.activeTheme,
                    sandboxURL: appState.sandboxDirectory,
                    recentProjects: appState.recentProjects,
                    onSelectProject: { url in
                        appState.setSandboxDirectory(url)
                    },
                    onOpenFinder: {
                        appState.openSandboxInFinder()
                    },
                    onOpenTerminal: {
                        appState.openSandboxInTerminal()
                    },
                    onSend: {
                        viewModel.sendMessage(appState: appState)
                    },
                    onStop: {
                        viewModel.stopGeneration()
                    }
                )
            } else {
                ContentUnavailableView(
                    "No Conversation Selected",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Select or create a conversation from the sidebar.")
                )
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .toolbar {
            // Title in center of top macOS window toolbar
            ToolbarItem(placement: .principal) {
                if let conv = appState.selectedConversation {
                    Text(conv.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }

            // Top-right window toolbar actions (Zero Redundancy)
            ToolbarItemGroup(placement: .primaryAction) {
                // 1. Theme Picker Menu
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
                            .foregroundStyle(appState.activeTheme.h1)
                        Text(appState.currentThemeType.rawValue)
                            .font(.system(size: 11.5, weight: .medium))
                    }
                }
                .help("Switch Theme")

                // 2. Chat Options Menu
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
                }
                .help("Chat Options")

                // 3. Engine Control & Telemetry Menu
                Menu {
                    Section("Resident MLX Engine") {
                        if appState.serverStatus.isConnected {
                            Text("● Status: Active on port 8000")
                            Text("⚡ Drafter: DFlash w8 Speculative")
                            Divider()
                            Button(role: .destructive) {
                                appState.stopEngine()
                            } label: {
                                Label("Stop Engine (Free GPU Memory)", systemImage: "power")
                            }
                        } else {
                            Text("○ Status: Engine Offline")
                            Divider()
                            Button {
                                appState.startEngine()
                            } label: {
                                Label("Start Engine (Load Qwen 3.8 27B)", systemImage: "bolt.fill")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4.5) {
                        Circle()
                            .fill(appState.serverStatus.isConnected ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)

                        Text(appState.serverStatus.isConnected ? "27B MLX" : "Stopped")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(appState.serverStatus.isConnected ? Color.primary : Color.secondary)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 7.5))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Color.white.opacity(0.06), in: Capsule())
                }
                .help("MLX Speculative Engine Status & Power Control")
            }
        }
    }
}

public struct EmptyConversationView: View {
    public let modelName: String
    public let theme: MarkdownTheme
    public let onSelectPrompt: (String) -> Void

    private let suggestions = [
        "Explain speculative decoding with MLX",
        "Write a Swift 6 actor for concurrency safety",
        "Build an autonomous Python script in the sandbox",
        "Architect a fast Rust microservice"
    ]

    public var body: some View {
        VStack(spacing: 18) {
            Spacer()

            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [theme.h1.opacity(0.25), theme.link.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)

                    Image(systemName: "cpu.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [theme.h1, theme.link],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text("Qwen Prime")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(theme.text)

                Text("Local Speculative Engine • 27B MLX")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.secondaryText)
            }

            // Suggestion Grid
            VStack(spacing: 7) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onSelectPrompt(suggestion)
                    } label: {
                        HStack {
                            Text(suggestion)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(theme.text.opacity(0.9))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9.5))
                                .foregroundStyle(theme.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .frame(maxWidth: 380)
                        .background(
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.white.opacity(0.06), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding()
    }
}
