import Foundation
import SwiftUI
import Observation

/// Factory closure creating a NativeAgentRuntime for a captured workspace URL.
public typealias AgentRuntimeFactory = @Sendable (URL) throws -> NativeAgentRuntime

@Observable
@MainActor
public final class ChatViewModel {
    private static let agentToolGuidance = """
    Use the most specific available workspace tool for the task. When locating files or text, prefer workspace_find_files and workspace_search_text over manual directory traversal. Avoid repeated workspace_list_directory calls; use it only for shallow inspection of a known directory. Use workspace_read_file after search identifies the relevant file and line range. Use workspace_apply_changes for coherent edits across multiple existing files so the user receives one combined review. Call workspace_list_tasks before choosing a build or test working directory, then use workspace_run_task with one of the returned fixed task IDs. Do not probe for build systems through directory-by-directory traversal. After an approved edit, rerun the relevant task and use its actual result before claiming success.
    """

    public var inputText: String = ""
    public var errorMessage: String?

    private struct GenerationRun {
        let id: UUID
        let task: Task<Void, Never>
    }

    private var streamTasks: [UUID: GenerationRun] = [:]
    private let client: QwenClient
    private let agentRuntimeFactory: AgentRuntimeFactory?
    public let approvalCoordinator: WorkspaceApprovalCoordinator

    public init(
        client: QwenClient = .shared,
        agentRuntimeFactory: AgentRuntimeFactory? = nil,
        approvalCoordinator: WorkspaceApprovalCoordinator? = nil
    ) {
        self.client = client
        self.agentRuntimeFactory = agentRuntimeFactory
        self.approvalCoordinator = approvalCoordinator ?? WorkspaceApprovalCoordinator()
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
        let capturedTaskCacheURL = QwenPrimeHarnessClient.defaultTaskCacheURL()
        let agentRunConfiguration = AgentRunConfiguration(
            systemPrompt: Self.agentSystemPrompt(appendingTo: capturedSystemPrompt),
            maxTurns: AgentRunConfiguration.defaultMaxTurns,
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
                    self.approvalCoordinator.cancelAll(for: conversationID)
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

                    let runtime: NativeAgentRuntime
                    if let agentRuntimeFactory = self.agentRuntimeFactory {
                        runtime = try agentRuntimeFactory(projectURL)
                    } else {
                        await appState.refreshWorkspaceHarnessStatus()
                        let harnessReady = appState.workspaceHarnessReady == true
                        let service = try ReadOnlyWorkspaceService(rootURL: projectURL)
                        let broker = WorkspaceToolBroker(
                            readService: service,
                            mutationService: WorkspaceMutationService(readService: service),
                            approvalRequester: ConversationWorkspaceApprovalRequester(
                                coordinator: self.approvalCoordinator,
                                conversationID: conversationID,
                                messageID: assistantMsgId
                            ),
                            commandExecutor: WorkspaceExecutionRouter(
                                commandExecutor: XPCWorkspaceCommandExecutor(
                                    workspaceURL: projectURL
                                ),
                                taskExecutor: harnessReady
                                    ? HarnessWorkspaceTaskExecutor(
                                        workspaceURL: projectURL,
                                        taskCacheURL: capturedTaskCacheURL
                                    )
                                    : nil
                            ),
                            taskExecutionEnabled: harnessReady
                        )
                        let toolRegistry = try AgentToolRegistry(
                            providers: [broker.providerRegistration]
                        )
                        runtime = NativeAgentRuntime(
                            inference: QwenAgentInferenceAdapter(client: self.client),
                            toolExecutor: toolRegistry
                        )
                    }
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

    private static func agentSystemPrompt(appendingTo userPrompt: String?) -> String {
        guard let userPrompt,
              !userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return agentToolGuidance
        }
        return userPrompt + "\n\n" + agentToolGuidance
    }

    public func stopGeneration(conversationID: UUID, appState: AppState) {
        streamTasks[conversationID]?.task.cancel()
        approvalCoordinator.cancelAll(for: conversationID)
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

    public func resolveWorkspaceApproval(
        _ request: WorkspaceApprovalRequest,
        decision: ToolApprovalDecision
    ) {
        _ = approvalCoordinator.resolve(request.id, decision: decision)
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
