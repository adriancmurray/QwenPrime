import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
public final class ChatViewModel {
    public var inputText: String = ""
    public var isStreaming: Bool = false
    public var liveStats: GenerationStats?
    public var errorMessage: String?

    private var streamTask: Task<Void, Never>?
    private let client = QwenClient.shared

    public init() {}

    public func sendMessage(appState: AppState) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        guard var conversation = appState.selectedConversation else { return }

        // Auto-generate a title from the first message
        if conversation.messages.isEmpty || conversation.title == "New Chat" {
            let autoTitle = String(text.prefix(40))
            appState.renameConversation(id: conversation.id, newTitle: autoTitle)
            conversation.title = autoTitle
        }

        let userMsg = ChatMessage(
            role: .user,
            content: text
        )

        let assistantMsgId = UUID()
        let assistantMsg = ChatMessage(
            id: assistantMsgId,
            role: .assistant,
            content: "",
            thinkingContent: "",
            isThinkingExpanded: true,
            isStreaming: true
        )

        conversation.messages.append(userMsg)
        conversation.messages.append(assistantMsg)
        conversation.touch()
        appState.selectedConversation = conversation
        appState.saveConversation(conversation)

        self.inputText = ""
        self.isStreaming = true
        self.errorMessage = nil
        self.liveStats = nil

        let messagesForAPI = conversation.messages.dropLast() // Exclude the empty assistant placeholder

        streamTask = Task {
            var fullThinking = ""
            var fullContent = ""
            var finalStats: GenerationStats?

            do {
                let stream = await client.streamChat(
                    messages: Array(messagesForAPI),
                    baseURL: appState.baseURL,
                    model: conversation.modelId,
                    temperature: conversation.temperature,
                    systemPrompt: conversation.systemPrompt
                )

                for try await event in stream {
                    if Task.isCancelled { break }

                    switch event {
                    case .reasoningDelta(let delta):
                        fullThinking += delta
                        updateAssistantMessage(
                            id: assistantMsgId,
                            content: fullContent,
                            thinking: fullThinking,
                            isStreaming: true,
                            stats: nil,
                            appState: appState
                        )

                    case .contentDelta(let delta):
                        fullContent += delta
                        updateAssistantMessage(
                            id: assistantMsgId,
                            content: fullContent,
                            thinking: fullThinking,
                            isStreaming: true,
                            stats: nil,
                            appState: appState
                        )

                    case .usage(let stats):
                        finalStats = stats
                        self.liveStats = stats

                    case .finished:
                        break
                    }
                }

                // Final message stabilization
                updateAssistantMessage(
                    id: assistantMsgId,
                    content: fullContent,
                    thinking: fullThinking.isEmpty ? nil : fullThinking,
                    isStreaming: false,
                    stats: finalStats,
                    appState: appState
                )

            } catch {
                if !Task.isCancelled {
                    self.errorMessage = error.localizedDescription
                    updateAssistantMessage(
                        id: assistantMsgId,
                        content: fullContent.isEmpty ? "⚠️ Error: \(error.localizedDescription)" : fullContent,
                        thinking: fullThinking.isEmpty ? nil : fullThinking,
                        isStreaming: false,
                        stats: finalStats,
                        appState: appState
                    )
                }
            }

            self.isStreaming = false
        }
    }

    public func stopGeneration() {
        streamTask?.cancel()
        streamTask = nil
        self.isStreaming = false
    }

    private func updateAssistantMessage(
        id: UUID,
        content: String,
        thinking: String?,
        isStreaming: Bool,
        stats: GenerationStats?,
        appState: AppState
    ) {
        guard var conversation = appState.selectedConversation else { return }
        if let idx = conversation.messages.firstIndex(where: { $0.id == id }) {
            conversation.messages[idx].content = content
            conversation.messages[idx].thinkingContent = thinking
            conversation.messages[idx].isStreaming = isStreaming
            if let stats = stats {
                conversation.messages[idx].stats = stats
            }
            conversation.touch()
            appState.selectedConversation = conversation
            appState.saveConversation(conversation)
        }
    }
}
