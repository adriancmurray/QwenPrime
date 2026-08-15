import SwiftUI

public struct ChatView: View {
    @Bindable public var appState: AppState
    @State private var viewModel = ChatViewModel()
    @State private var thinkingExpandedStates: [UUID: Bool] = [:]

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Purposeful Toolbar Header
            ChatHeaderView(appState: appState)

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

                // Centered Input Bar
                PromptInputBar(
                    text: $viewModel.inputText,
                    isStreaming: viewModel.isStreaming,
                    modelName: conversation.modelId,
                    theme: appState.activeTheme,
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
    }
}

public struct EmptyConversationView: View {
    public let modelName: String
    public let theme: MarkdownTheme
    public let onSelectPrompt: (String) -> Void

    private let suggestions = [
        "Explain speculative decoding with MLX",
        "Write a Swift 6 actor for concurrency safety",
        "Build an autonomous Python script for file operations",
        "Architect a fast Rust service for streaming"
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
