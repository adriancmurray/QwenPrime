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
                    // Message Stream Area (Centered with Max-Width)
                    ScrollViewReader { proxy in
                        ScrollView {
                            HStack {
                                Spacer(minLength: 0)

                                LazyVStack(spacing: 12) {
                                    ForEach(conversation.messages) { message in
                                        MessageBubble(
                                            message: message,
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
        "Write a Swift 6 actor for concurrency safety",
        "Build a high-performance Python script",
        "Architect a fast Rust microservice"
    ]

    public var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.2), Color.indigo.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Image(systemName: "cpu.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }

                Text("Qwen Prime")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.primary)

                Text("Local Speculative Engine • Qwen 3.8 27B")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
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
                                .foregroundStyle(.primary.opacity(0.9))
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: 380)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.white.opacity(0.07), lineWidth: 1)
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
