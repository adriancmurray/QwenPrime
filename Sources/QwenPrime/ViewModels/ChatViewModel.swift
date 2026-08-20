import Foundation
import Observation
import OSLog
import SwiftUI

/// Factory closure creating a NativeAgentRuntime for a captured workspace URL.
public typealias AgentRuntimeFactory = @Sendable (URL) throws -> NativeAgentRuntime
public typealias MCPToolProviderFactory = @Sendable (
    MCPServerConfiguration,
    any WorkspaceApprovalRequesting
) async throws -> AgentToolProviderRegistration

@Observable
@MainActor
public final class ChatViewModel {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QwenPrime",
        category: "ChatViewModel"
    )
    private static let genericGenerationFailureMessage =
        "Unable to generate a response. Please try again."
    private static let workspaceContextBudget = 16 * 1024
    private static let skillContextBudget = 16 * 1024
    private static let agentToolGuidance = """
    Use the most specific available workspace tool for the task. When locating files or text, prefer \(ToolName.workspaceFindFiles) and \(ToolName.workspaceSearchText) over manual directory traversal. Avoid repeated \(ToolName.workspaceListDirectory) calls; use it only for shallow inspection of a known directory. Use \(ToolName.workspaceReadFile) after search identifies the relevant file and line range. Use \(ToolName.workspaceApplyChanges) for coherent edits across multiple existing files so the user receives one combined review. Use \(ToolName.workspaceProcessRun) for bounded foreground work and \(ToolName.workspaceProcessStart), \(ToolName.workspaceProcessStatus), and \(ToolName.workspaceProcessStop) for supervised long-running work. Pass an executable and argv directly; do not construct shell command strings. After an approved edit, rerun the relevant process and use its actual result before claiming success.
    """

    /// Compatibility input used by programmatic callers and existing tests.
    /// The app UI uses conversation-scoped drafts through `draftBinding(for:)`.
    public var inputText: String = ""
    public var errorMessage: String?

    private var conversationDrafts: [UUID: String] = [:]

    private struct GenerationRun {
        let id: UUID
        let task: Task<Void, Never>
    }

    private enum AssistantMessageTarget {
        case identified(UUID)
        case latest
    }

    private var streamTasks: [UUID: GenerationRun] = [:]
    private let client: QwenClient
    private let agentRuntimeFactory: AgentRuntimeFactory?
    private let agentInference: (any AgentInferenceStreaming)?
    private let mcpToolProviderFactory: MCPToolProviderFactory
    public let approvalCoordinator: WorkspaceApprovalCoordinator

    public init(
        client: QwenClient = .shared,
        agentRuntimeFactory: AgentRuntimeFactory? = nil,
        agentInference: (any AgentInferenceStreaming)? = nil,
        mcpToolProviderFactory: MCPToolProviderFactory? = nil,
        approvalCoordinator: WorkspaceApprovalCoordinator? = nil
    ) {
        self.client = client
        self.agentRuntimeFactory = agentRuntimeFactory
        self.agentInference = agentInference
        self.mcpToolProviderFactory = mcpToolProviderFactory ?? { configuration, requester in
            let client = try await MCPHTTPClient.connect(configuration: configuration)
            return try await MCPToolProvider.connect(
                configuration: configuration,
                client: client,
                approvalRequester: requester
            )
        }
        self.approvalCoordinator = approvalCoordinator ?? WorkspaceApprovalCoordinator()
    }

    public func draftBinding(for conversationID: UUID) -> Binding<String> {
        Binding(
            get: { [weak self] in
                self?.conversationDrafts[conversationID] ?? ""
            },
            set: { [weak self] draft in
                self?.setDraft(draft, for: conversationID)
            }
        )
    }

    public func draft(for conversationID: UUID) -> String {
        conversationDrafts[conversationID] ?? ""
    }

    public func setDraft(_ draft: String, for conversationID: UUID) {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            conversationDrafts.removeValue(forKey: conversationID)
        } else {
            conversationDrafts[conversationID] = draft
        }
    }

    func retainDrafts(for conversationIDs: Set<UUID>) {
        conversationDrafts = ConversationDraftRetentionPolicy.retainedDrafts(
            conversationDrafts,
            conversationIDs: conversationIDs
        )
    }

    private func messageSourceText(
        explicitDraft: String?,
        conversationID: UUID
    ) -> String {
        if let explicitDraft {
            guard !explicitDraft.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty else {
                return inputText
            }
            return explicitDraft
        }
        guard inputText.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            return inputText
        }
        return draft(for: conversationID)
    }

    public func sendMessage(appState: AppState, draftText: String? = nil) {
        guard var conversation = appState.selectedConversation else { return }
        let sourceText = messageSourceText(
            explicitDraft: draftText,
            conversationID: conversation.id
        )
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              !appState.isConversationGenerating(conversation.id),
              streamTasks[conversation.id] == nil else {
            return
        }
        let conversationID = conversation.id
        let isAgentMode = appState.isAgentModeEnabled(for: conversationID)
        let capturedProjectURL = appState.authorizedWorkspaceURL(for: conversationID)
        let workspaceInstructions = isAgentMode
            ? capturedProjectURL.flatMap(appState.workspaceInstructionDocument(at:))
            : nil
        let workspaceInstructionContext = workspaceInstructions.map {
            WorkspaceInstructionService.renderPromptContext(
                $0,
                maximumBytes: Self.workspaceContextBudget
            )
        } ?? ""
        let invokedSkills = isAgentMode
            ? appState.invokedAgentSkills(in: text, workspaceURL: capturedProjectURL)
            : []
        let skillContext = AgentSkillService.renderPromptContext(
            for: invokedSkills,
            maximumBytes: Self.skillContextBudget
        )

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
        let instructionExecutions = workspaceInstructions.map { document in
            [
                ToolExecution(
                    id: "instructions-\(assistantMsgId.uuidString)",
                    toolName: ToolName.workspaceInstructions,
                    input: document.fileURL.lastPathComponent,
                    output: "Loaded root workspace instructions.",
                    isRunning: false,
                    isSuccess: true
                )
            ]
        } ?? []
        let skillExecutions = invokedSkills.map { skill in
            ToolExecution(
                id: "skill-\(assistantMsgId.uuidString)-\(skill.id)",
                toolName: ToolName.skill(skill.name),
                input: "$\(skill.name)",
                output: skill.description.isEmpty
                    ? "Loaded \(skill.source.rawValue) skill instructions."
                    : skill.description,
                isRunning: false,
                isSuccess: true
            )
        }
        let assistantMsg = ChatMessage(
            id: assistantMsgId,
            role: .assistant,
            content: "",
            thinkingContent: "",
            isThinkingExpanded: appState.isThinkingExpandedByDefault,
            toolExecutions: instructionExecutions + skillExecutions,
            isStreaming: true
        )

        conversation.messages.append(userMsg)
        conversation.messages.append(assistantMsg)
        conversation.touch()
        appState.updateConversation(id: conversationID) { $0 = conversation }
        appState.saveConversation(conversation)

        inputText = ""
        setDraft("", for: conversationID)
        appState.setConversation(conversationID, isGenerating: true)
        self.errorMessage = nil

        let messagesForAPI = conversation.messages.dropLast() // Exclude the empty assistant placeholder
        let capturedBaseURL = appState.baseURL
        let capturedModel = conversation.modelId
        let capturedTemperature = conversation.temperature
        let capturedSystemPrompt = conversation.systemPrompt
        let requestThinkingEnabled = conversation.isThinkingEnabled
        let capturedProjectPath = conversation.projectPath
        let capturedMCPProfiles = appState.mcpServers.filter(\.isEnabled)
        let agentRunConfiguration = AgentRunConfiguration(
            systemPrompt: Self.agentSystemPrompt(
                appendingTo: capturedSystemPrompt,
                workspaceInstructionContext: workspaceInstructionContext,
                skillContext: skillContext
            ),
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
                        let service = try ReadOnlyWorkspaceService(rootURL: projectURL)
                        let approvalRequester = ConversationWorkspaceApprovalRequester(
                            coordinator: self.approvalCoordinator,
                            conversationID: conversationID,
                            messageID: assistantMsgId
                        )
                        let broker = WorkspaceToolBroker(
                            readService: service,
                            mutationService: WorkspaceMutationService(readService: service),
                            approvalRequester: approvalRequester,
                            commandExecutor: XPCWorkspaceCommandExecutor(
                                workspaceURL: projectURL
                            )
                        )
                        var providers = [broker.providerRegistration]
                        for profile in capturedMCPProfiles {
                            do {
                                let configuration = try profile.configuration()
                                let provider = try await self.mcpToolProviderFactory(
                                    configuration,
                                    approvalRequester
                                )
                                providers.append(provider)
                                appState.setMCPServerConnectionState(
                                    .connected(
                                        tools: provider.tools.map {
                                            MCPDiscoveredTool(
                                                name: $0.definition.function.name,
                                                description: $0.definition.function.description
                                            )
                                        }
                                    ),
                                    for: profile.id
                                )
                            } catch {
                                Self.logger.error(
                                    "MCP provider connection failed: \(String(describing: error), privacy: .private)"
                                )
                                appState.setMCPServerConnectionState(
                                    .failed(
                                        message: "Could not connect to \(profile.displayName)."
                                    ),
                                    for: profile.id
                                )
                            }
                        }
                        let completeToolRegistry = try AgentToolRegistry(providers: providers)
                        let routingMode = AgentToolRoutingMode(
                            environmentValue: ProcessInfo.processInfo.environment["QWEN_PRIME_TOOL_ROUTING"]
                        )
                        let toolRegistry = completeToolRegistry.selectingRelevantTools(
                            for: text,
                            mode: routingMode
                        )
                        runtime = NativeAgentRuntime(
                            inference: self.agentInference ?? QwenAgentInferenceAdapter(client: self.client),
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
                        finalizeAssistantMessage(
                            target: .identified(assistantMsgId),
                            conversationID: conversationID,
                            appState: appState
                        ) { message in
                            message = projection.message
                        }
                    }
                } catch {
                    if !Task.isCancelled && !(error is CancellationError) {
                        self.reportGenerationFailure(error)
                        projection.message.content = Self.failureContent(
                            appendingTo: projection.message.content
                        )
                        finalizeAssistantMessage(
                            target: .identified(assistantMsgId),
                            conversationID: conversationID,
                            appState: appState
                        ) { message in
                            message = projection.message
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
                            updateStreamingAssistantMessage(
                                id: assistantMsgId,
                                content: fullContent,
                                thinking: fullThinking,
                                stats: finalStats,
                                conversationID: conversationID,
                                appState: appState
                            )

                        case .contentDelta(let delta):
                            fullContent += delta
                            updateStreamingAssistantMessage(
                                id: assistantMsgId,
                                content: fullContent,
                                thinking: fullThinking,
                                stats: finalStats,
                                conversationID: conversationID,
                                appState: appState
                            )

                        case .usage(let stats):
                            finalStats = stats
                            updateStreamingAssistantMessage(
                                id: assistantMsgId,
                                content: fullContent,
                                thinking: fullThinking.isEmpty ? nil : fullThinking,
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
                        finalizeAssistantMessage(
                            target: .identified(assistantMsgId),
                            conversationID: conversationID,
                            appState: appState
                        ) { message in
                            message.content = fullContent
                            message.thinkingContent = fullThinking.isEmpty
                                ? nil
                                : fullThinking
                            if let finalStats {
                                message.stats = finalStats
                            }
                        }
                    }

                } catch {
                    if !Task.isCancelled && !(error is CancellationError) {
                        self.reportGenerationFailure(error)
                        finalizeAssistantMessage(
                            target: .identified(assistantMsgId),
                            conversationID: conversationID,
                            appState: appState
                        ) { message in
                            message.content = Self.failureContent(
                                appendingTo: fullContent
                            )
                            message.thinkingContent = fullThinking.isEmpty
                                ? nil
                                : fullThinking
                            if let finalStats {
                                message.stats = finalStats
                            }
                        }
                    }
                }
            }
        }
        streamTasks[conversationID] = GenerationRun(id: runID, task: task)
    }

    private static func agentSystemPrompt(
        appendingTo userPrompt: String?,
        workspaceInstructionContext: String,
        skillContext: String
    ) -> String {
        var sections: [String] = []
        if let userPrompt,
           !userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(userPrompt)
        }
        sections.append(agentToolGuidance)
        if !workspaceInstructionContext.isEmpty {
            sections.append(workspaceInstructionContext)
        }
        if !skillContext.isEmpty {
            sections.append(skillContext)
        }
        return sections.joined(separator: "\n\n")
    }

    private static func failureContent(appendingTo content: String) -> String {
        let failure = "⚠️ Error: \(genericGenerationFailureMessage)"
        guard !content.isEmpty else { return failure }
        return "\(content)\n\n\(failure)"
    }

    private func reportGenerationFailure(_ error: Error) {
        Self.logger.error(
            "Generation failed: \(String(describing: error), privacy: .private)"
        )
        errorMessage = Self.genericGenerationFailureMessage
    }

    public func stopGeneration(conversationID: UUID, appState: AppState) {
        streamTasks[conversationID]?.task.cancel()
        approvalCoordinator.cancelAll(for: conversationID)
        finalizeAssistantMessage(
            target: .latest,
            conversationID: conversationID,
            appState: appState
        )
    }

    public func resolveWorkspaceApproval(
        _ request: WorkspaceApprovalRequest,
        decision: ToolApprovalDecision
    ) {
        _ = approvalCoordinator.resolve(request.id, decision: decision)
    }

    private func updateStreamingAssistantMessage(
        id: UUID,
        content: String,
        thinking: String?,
        stats: GenerationStats?,
        conversationID: UUID,
        appState: AppState
    ) {
        appState.updateConversation(id: conversationID) { conversation in
            if let index = conversation.messages.firstIndex(where: { $0.id == id }) {
                conversation.messages[index].content = content
                conversation.messages[index].thinkingContent = thinking
                conversation.messages[index].isStreaming = true
                if let stats {
                    conversation.messages[index].stats = stats
                }
                conversation.touch()
            }
        }
    }

    private func finalizeAssistantMessage(
        target: AssistantMessageTarget,
        conversationID: UUID,
        appState: AppState,
        mutation: (inout ChatMessage) -> Void = { _ in }
    ) {
        appState.updateConversation(id: conversationID) { conversation in
            let messageIndex: Int?
            switch target {
            case .identified(let id):
                messageIndex = conversation.messages.firstIndex(where: {
                    $0.id == id
                })
            case .latest:
                messageIndex = conversation.messages.lastIndex(where: {
                    $0.role == .assistant
                })
            }
            guard let messageIndex else { return }

            mutation(&conversation.messages[messageIndex])
            conversation.messages[messageIndex].isStreaming = false
            for toolIndex in conversation.messages[messageIndex]
                .toolExecutions.indices {
                conversation.messages[messageIndex]
                    .toolExecutions[toolIndex].isRunning = false
            }
            conversation.touch()
        }
        if let conversation = appState.conversations.first(where: {
            $0.id == conversationID
        }) {
            appState.saveConversation(conversation)
        }
    }
}

enum ConversationDraftRetentionPolicy {
    static func retainedDrafts(
        _ drafts: [UUID: String],
        conversationIDs: Set<UUID>
    ) -> [UUID: String] {
        drafts.filter { conversationIDs.contains($0.key) }
    }
}
