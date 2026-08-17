import Foundation
import SwiftUI
import Observation

/// Factory closure creating a NativeAgentRuntime for a captured workspace URL.
public typealias AgentRuntimeFactory = @Sendable (URL) throws -> NativeAgentRuntime

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
    private let client: QwenClient
    private let agentRuntimeFactory: AgentRuntimeFactory

    public init(
        client: QwenClient = .shared,
        agentRuntimeFactory: AgentRuntimeFactory? = nil
    ) {
        self.client = client
        if let agentRuntimeFactory {
            self.agentRuntimeFactory = agentRuntimeFactory
        } else {
            self.agentRuntimeFactory = { [client] rootURL in
                let service = try ReadOnlyWorkspaceService(rootURL: rootURL)
                let broker = ReadOnlyWorkspaceToolBroker(service: service)
                let adapter = QwenAgentInferenceAdapter(client: client)
                return NativeAgentRuntime(
                    inference: adapter,
                    toolExecutor: broker
                )
            }
        }
    }

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
        appState.updateConversation(id: conversationID) { $0 = conversation }
        appState.saveConversation(conversation)

        self.inputText = ""
        appState.setConversation(conversationID, isGenerating: true)
        self.errorMessage = nil

        let messagesForAPI = conversation.messages.dropLast() // Exclude the empty assistant placeholder
        let isAgentMode = appState.isAgentModeEnabled(for: conversationID)
        let capturedBaseURL = appState.baseURL
        let capturedModel = conversation.modelId
        let capturedTemperature = conversation.temperature
        let capturedSystemPrompt = conversation.systemPrompt
        let requestThinkingEnabled = conversation.isThinkingEnabled
        let capturedProjectPath = conversation.projectPath
        let capturedProjectURL = appState.authorizedWorkspaceURL(for: conversationID)
        let agentRunConfiguration = AgentRunConfiguration(
            systemPrompt: capturedSystemPrompt,
            maxTurns: 5,
            baseURL: capturedBaseURL,
            temperature: capturedTemperature,
            model: capturedModel,
            isThinkingEnabled: requestThinkingEnabled,
            maxCompletionTokens: 1024,
            maxReasoningTokens: 96
        )

        let runID = UUID()
        let task = Task {
            await Task.yield()
            defer {
                if self.streamTasks[conversationID]?.id == runID {
                    self.streamTasks[conversationID] = nil
                    appState.setConversation(conversationID, isGenerating: false)
                }
            }

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

            if isAgentMode {
                var projection = AgentMessageProjection(message: assistantMsg)
                do {
                    guard let projectURL = capturedProjectURL else {
                        throw WorkspaceAccessError.invalidPath(path: capturedProjectPath ?? "")
                    }

                    let runtime = try self.agentRuntimeFactory(projectURL)
                    let stream = runtime.run(
                        history: Array(messagesForAPI),
                        configuration: agentRunConfiguration
                    )

                    for try await event in stream {
                        if Task.isCancelled { break }

                        projection.apply(event)
                        appState.updateConversation(id: conversationID) { conversation in
                            if let index = conversation.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                                conversation.messages[index] = projection.message
                                conversation.touch()
                            }
                        }
                    }

                    if !Task.isCancelled {
                        projection.message.isStreaming = false
                        for idx in projection.message.toolExecutions.indices {
                            projection.message.toolExecutions[idx].isRunning = false
                        }
                        appState.updateConversation(id: conversationID) { conversation in
                            if let index = conversation.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                                conversation.messages[index] = projection.message
                                conversation.touch()
                            }
                        }
                        if let conversation = appState.conversations.first(where: { $0.id == conversationID }) {
                            appState.saveConversation(conversation)
                        }
                    }
                } catch {
                    if !Task.isCancelled && !(error is CancellationError) {
                        self.errorMessage = error.localizedDescription
                        let errorDescription = error.localizedDescription
                        let errorPrefix = "⚠️ Error: \(errorDescription)"
                        let finalContent = projection.message.content.isEmpty
                            ? errorPrefix
                            : "\(projection.message.content)\n\n\(errorPrefix)"
                        projection.message.content = finalContent
                        projection.message.isStreaming = false
                        for idx in projection.message.toolExecutions.indices {
                            projection.message.toolExecutions[idx].isRunning = false
                        }
                        appState.updateConversation(id: conversationID) { conversation in
                            if let index = conversation.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                                conversation.messages[index] = projection.message
                                conversation.touch()
                            }
                        }
                        if let conversation = appState.conversations.first(where: { $0.id == conversationID }) {
                            appState.saveConversation(conversation)
                        }
                    }
                }
            } else {
                var fullThinking = ""
                var fullContent = ""
                var finalStats: GenerationStats?

                do {
                    let stream = await client.streamChat(
                        messages: Array(messagesForAPI),
                        baseURL: capturedBaseURL,
                        model: capturedModel,
                        temperature: capturedTemperature,
                        systemPrompt: capturedSystemPrompt,
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

                        case .toolCall:
                            break

                        case .finished:
                            break
                        }
                    }

                    // Final message stabilization
                    if !Task.isCancelled {
                        updateAssistantMessage(
                            id: assistantMsgId,
                            content: fullContent,
                            thinking: fullThinking.isEmpty ? nil : fullThinking,
                            isStreaming: false,
                            stats: finalStats,
                            conversationID: conversationID,
                            appState: appState
                        )
                    }

                } catch {
                    if !Task.isCancelled && !(error is CancellationError) {
                        self.errorMessage = error.localizedDescription
                        updateAssistantMessage(
                            id: assistantMsgId,
                            content: fullContent.isEmpty ? "⚠️ Error: \(error.localizedDescription)" : "\(fullContent)\n\n⚠️ Error: \(error.localizedDescription)",
                            thinking: fullThinking.isEmpty ? nil : fullThinking,
                            isStreaming: false,
                            stats: finalStats,
                            conversationID: conversationID,
                            appState: appState
                        )
                    }
                }
            }
        }
        streamTasks[conversationID] = GenerationRun(id: runID, task: task)
    }

    public func stopGeneration(conversationID: UUID, appState: AppState) {
        streamTasks[conversationID]?.task.cancel()
        appState.updateConversation(id: conversationID) { conversation in
            if let index = conversation.messages.lastIndex(where: { $0.role == .assistant }) {
                conversation.messages[index].isStreaming = false
                for toolIndex in conversation.messages[index].toolExecutions.indices {
                    conversation.messages[index].toolExecutions[toolIndex].isRunning = false
                }
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
