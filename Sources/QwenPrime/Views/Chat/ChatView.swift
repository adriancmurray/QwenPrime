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
            if let conversation = appState.selectedConversation {
                if conversation.messages.isEmpty {
                    // Empty State with Quick Prompts
                    EmptyConversationView(
                        modelName: conversation.modelId,
                        onSelectPrompt: { prompt in
                            viewModel.inputText = prompt
                            viewModel.sendMessage(appState: appState)
                        }
                    )
                } else {
                    // Message List
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(conversation.messages) { message in
                                    MessageBubble(
                                        message: message,
                                        isThinkingExpanded: Binding(
                                            get: { thinkingExpandedStates[message.id] ?? true },
                                            set: { thinkingExpandedStates[message.id] = $0 }
                                        )
                                    )
                                    .id(message.id)
                                }

                                Color.clear
                                    .frame(height: 1)
                                    .id("bottomAnchor")
                            }
                            .padding(.vertical, 16)
                        }
                        .onChange(of: conversation.messages.last?.content) { _, _ in
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo("bottomAnchor", anchor: .bottom)
                            }
                        }
                        .onChange(of: conversation.messages.last?.thinkingContent) { _, _ in
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo("bottomAnchor", anchor: .bottom)
                            }
                        }
                    }
                }

                // Input Bar
                PromptInputBar(
                    text: $viewModel.inputText,
                    isStreaming: viewModel.isStreaming,
                    modelName: conversation.modelId,
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
    public let onSelectPrompt: (String) -> Void

    private let suggestions = [
        "Explain speculative decoding with MLX",
        "Write a Swift 6 actor for caching requests",
        "Refactor this Python script for concurrency",
        "Build a high-performance REST API in Rust"
    ]

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.2), Color.indigo.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 72, height: 72)

                    Image(systemName: "cpu.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text("Qwen Prime")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Powered by Qwen 3.8 27B on Apple Silicon")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            // Suggestion Cards
            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        onSelectPrompt(suggestion)
                    } label: {
                        HStack {
                            Text(suggestion)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.primary.opacity(0.9))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .frame(maxWidth: 420)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
