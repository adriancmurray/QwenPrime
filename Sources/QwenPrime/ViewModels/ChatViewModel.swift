import Foundation
import SwiftUI
import Observation

@Observable
@MainActor
public final class ChatViewModel {
    public var inputText: String = ""
    public var errorMessage: String?

    private struct GenerationRun {
        let id: UUID
        let task: Task<Void, Never>
    }

    private var streamTasks: [UUID: GenerationRun] = [:]
    private let client = QwenClient.shared

    public init() {}

    public func sendMessage(appState: AppState) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var conversation = appState.selectedConversation else { return }
        guard !text.isEmpty, streamTasks[conversation.id] == nil else { return }
        let conversationID = conversation.id

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
        appState.setConversation(conversationID, isGenerating: true)
        self.errorMessage = nil

        let messagesForAPI = conversation.messages.dropLast() // Exclude the empty assistant placeholder
        let requestThinkingEnabled = conversation.isThinkingEnabled

        let runID = UUID()
        let task = Task {
            await Task.yield()
            defer {
                if self.streamTasks[conversationID]?.id == runID {
                    self.streamTasks[conversationID] = nil
                    appState.setConversation(conversationID, isGenerating: false)
                }
            }

            var fullThinking = ""
            var fullContent = ""
            var finalStats: GenerationStats?

            if !appState.serverStatus.isConnected {
                appState.startEngine()
                for _ in 0..<25 {
                    if Task.isCancelled { break }
                    try? await Task.sleep(for: .seconds(1))
                    await appState.checkServerHealth()
                    if appState.serverStatus.isConnected { break }
                }
            }

            guard !Task.isCancelled else { return }

            do {
                let stream = await client.streamChat(
                    messages: Array(messagesForAPI),
                    baseURL: appState.baseURL,
                    model: conversation.modelId,
                    temperature: conversation.temperature,
                    systemPrompt: conversation.systemPrompt,
                    isThinkingEnabled: requestThinkingEnabled
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
                            stats: finalStats,
                            conversationID: conversationID,
                            appState: appState
                        )

                    case .contentDelta(let delta):
                        fullContent += delta
                        updateAssistantMessage(
                            id: assistantMsgId,
                            content: fullContent,
                            thinking: fullThinking,
                            isStreaming: true,
                            stats: finalStats,
                            conversationID: conversationID,
                            appState: appState
                        )

                    case .usage(let stats):
                        finalStats = stats
                        updateAssistantMessage(
                            id: assistantMsgId,
                            content: fullContent,
                            thinking: fullThinking.isEmpty ? nil : fullThinking,
                            isStreaming: true,
                            stats: stats,
                            conversationID: conversationID,
                            appState: appState
                        )

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
                    conversationID: conversationID,
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
                        conversationID: conversationID,
                        appState: appState
                    )
                }
            }

        }
        streamTasks[conversationID] = GenerationRun(id: runID, task: task)
    }

    public func stopGeneration(conversationID: UUID, appState: AppState) {
        streamTasks[conversationID]?.task.cancel()
        appState.updateConversation(id: conversationID) { conversation in
            if let index = conversation.messages.lastIndex(where: { $0.isStreaming }) {
                conversation.messages[index].isStreaming = false
                conversation.touch()
            }
        }
        if let conversation = appState.conversations.first(where: { $0.id == conversationID }) {
            appState.saveConversation(conversation)
        }
    }

    private func updateAssistantMessage(
        id: UUID,
        content: String,
        thinking: String?,
        isStreaming: Bool,
        stats: GenerationStats?,
        conversationID: UUID,
        appState: AppState
    ) {
        appState.updateConversation(id: conversationID) { conversation in
            if let index = conversation.messages.firstIndex(where: { $0.id == id }) {
                conversation.messages[index].content = content
                conversation.messages[index].thinkingContent = thinking
                conversation.messages[index].isStreaming = isStreaming
                if let stats {
                    conversation.messages[index].stats = stats
                }
                conversation.touch()
            }
        }
        if !isStreaming,
           let conversation = appState.conversations.first(where: { $0.id == conversationID }) {
            appState.saveConversation(conversation)
        }
    }
}
