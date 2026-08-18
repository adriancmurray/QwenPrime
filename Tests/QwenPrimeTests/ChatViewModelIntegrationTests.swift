import Foundation
import Testing
@testable import QwenPrime

@Suite("ChatViewModel Integration & Agent Execution Tests")
struct ChatViewModelIntegrationTests {

    // MARK: - Test 1: Agent Mode Enabled Execution & Projection Lifecycle

    @Test("Agent mode enabled with capability and projectPath uses factory exactly once, executes workspace_read_file round through ReadOnlyWorkspaceToolBroker, projects message lifecycle, persists completed ToolExecution, and clears generation")
    @MainActor
    func testAgentModeExecutionWithRealWorkspaceBrokerAndProjection() async throws {
        try await ChatIntegrationTestHelpers.withWorkspaceFixture { workspaceFixture in
            let storageFixture = try TemporaryStorageFixture()
            defer { storageFixture.tearDown() }

            let (defaults, suiteName) = try ChatIntegrationTestHelpers.makeTestDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let testFileContent = "alpha bravo charlie workspace secret payload"
            try workspaceFixture.createFile(at: "sample.txt", content: testFileContent)

            // Wished seam: AppState accepts injected StorageService
            let appState = AppState(
                startServices: false,
                workspaceAuthorizationService: WorkspaceAuthorizationService(
                    userDefaults: defaults,
                    bookmarker: TestWorkspaceBookmarker(),
                scopeAccessor: TestWorkspaceSecurityScopeAccessor()
                ),
                userDefaults: defaults,
                storage: storageFixture.storage
            )
            appState.serverStatus = .connected(model: "qwen-test", latencyMs: 1)
            appState.isAgentPreviewEnabled = true
            appState.runtimeSupportsStructuredToolCalls = true

            let conv = Conversation(
                title: "Agent Execution Test",
                messages: [],
                modelId: "qwen-preview-agent",
                temperature: 0.1,
                systemPrompt: "You are a test agent.",
                isThinkingEnabled: true,
                projectPath: workspaceFixture.rootURL.path
            )
            appState.conversations = [conv]
            appState.selectedConversationId = conv.id
            appState.setConversationWorkspace(id: conv.id, url: workspaceFixture.rootURL)
            appState.setAgentMode(true, for: conv.id)

            // Setup scripted inference:
            // Turn 1: Model emits reasoning and requests workspace_read_file
            // Turn 2: Model emits final reasoning, answer, usage stats, and finished
            let expectedStats = GenerationStats(
                promptTokens: 42,
                completionTokens: 28,
                tokensPerSecond: 64.0,
                latencySeconds: 0.5,
                timeToFirstTokenSeconds: 0.1,
                prefillTokensPerSecond: 120.0
            )

            let readToolCall = ToolCall(
                id: "call_read_sample_1",
                type: "function",
                function: ToolCall.FunctionCall(
                    name: "workspace_read_file",
                    arguments: "{\"path\":\"sample.txt\"}"
                )
            )

            let scriptedInference = ScriptedAgentInference(turns: [
                [
                    .reasoningDelta("I need to inspect the contents of sample.txt."),
                    .toolCall(readToolCall),
                    .finished
                ],
                [
                    .reasoningDelta(" The file content has been verified."),
                    .contentDelta("The file contains: alpha bravo charlie workspace secret payload"),
                    .usage(expectedStats),
                    .finished
                ]
            ])

            let tracker = ThreadSafeFactoryTracker()

            let factory: AgentRuntimeFactory = { capturedRoot in
                tracker.record(workspaceURL: capturedRoot)
                let broker = ReadOnlyWorkspaceToolBroker(
                    service: try ReadOnlyWorkspaceService(rootURL: capturedRoot)
                )
                return NativeAgentRuntime(
                    inference: scriptedInference,
                    toolExecutor: broker
                )
            }

            // Wished seam: ChatViewModel accepts injected QwenClient and AgentRuntimeFactory
            let client = QwenClient()
            let viewModel = ChatViewModel(
                client: client,
                agentRuntimeFactory: factory
            )

            viewModel.inputText = "Please read sample.txt"
            viewModel.sendMessage(appState: appState)

            // Bounded wait for generation to complete
            try await AsyncCondition.wait(description: "Agent execution completion") {
                !appState.isConversationGenerating(conv.id)
            }

            // 1. Factory was invoked exactly once with the captured workspace root
            #expect(tracker.callCount == 1)
            #expect(tracker.capturedWorkspaceURLs.first?.standardizedFileURL == workspaceFixture.rootURL.standardizedFileURL)

            // 2. Generation state is cleared
            #expect(appState.isConversationGenerating(conv.id) == false)
            #expect(appState.isGenerating == false)
            #expect(viewModel.errorMessage == nil)

            let configurations = await scriptedInference.getCapturedConfigurations()
            let agentSystemPrompt = try #require(configurations.first?.systemPrompt)
            #expect(agentSystemPrompt.contains("You are a test agent."))
            #expect(agentSystemPrompt.contains("prefer workspace_find_files and workspace_search_text"))
            #expect(agentSystemPrompt.contains("Avoid repeated workspace_list_directory calls"))
            #expect(agentSystemPrompt.contains("Call workspace_list_tasks before choosing a build or test working directory"))

            // 3. Conversation projection assertions in AppState memory
            let updatedConv = try #require(appState.conversations.first(where: { $0.id == conv.id }))
            #expect(updatedConv.messages.count == 2)

            let userMessage = updatedConv.messages[0]
            #expect(userMessage.role == MessageRole.user)
            #expect(userMessage.content == "Please read sample.txt")

            let assistantMessage = updatedConv.messages[1]
            #expect(assistantMessage.role == MessageRole.assistant)
            #expect(assistantMessage.isStreaming == false)
            #expect(assistantMessage.content == "The file contains: alpha bravo charlie workspace secret payload")
            #expect(assistantMessage.thinkingContent == "I need to inspect the contents of sample.txt. The file content has been verified.")
            #expect(assistantMessage.stats == expectedStats)

            #expect(assistantMessage.toolExecutions.count == 1)
            let toolExecution = try #require(assistantMessage.toolExecutions.first)
            #expect(toolExecution.id == "call_read_sample_1")
            #expect(toolExecution.toolName == "workspace_read_file")
            #expect(toolExecution.input.contains("sample.txt"))
            #expect(toolExecution.isRunning == false)
            #expect(toolExecution.isSuccess == true)
            #expect(toolExecution.output?.contains("alpha bravo charlie workspace secret payload") == true)

            // 4. Persistence assertions in StorageService: wait conditionally for the async StorageService save
            try await AsyncCondition.wait(description: "StorageService conversation save") {
                let loaded = (try? await storageFixture.storage.loadAllConversations()) ?? []
                guard let savedConv = loaded.first(where: { $0.id == conv.id }) else {
                    return false
                }
                return savedConv.messages.count == 2 &&
                       savedConv.messages[1].isStreaming == false &&
                       savedConv.messages[1].toolExecutions.first?.isRunning == false
            }

            let persistedConversations = try await storageFixture.storage.loadAllConversations()
            let persistedConv = try #require(persistedConversations.first(where: { $0.id == conv.id }))
            #expect(persistedConv.messages.count == 2)
            let persistedAssistant = persistedConv.messages[1]
            #expect(persistedAssistant.isStreaming == false)
            #expect(persistedAssistant.content == "The file contains: alpha bravo charlie workspace secret payload")
            let persistedTool = try #require(persistedAssistant.toolExecutions.first)
            #expect(persistedTool.isRunning == false)
            #expect(persistedTool.isSuccess == true)
            #expect(persistedTool.output?.contains("alpha bravo charlie workspace secret payload") == true)
        }
    }

    // MARK: - Test 2: Selected Conversation Switch During Active Gated Run

    @Test("Switch selectedConversationId while gated agent run is active: only originating conversation updates and visible conversation remains unchanged")
    @MainActor
    func testSwitchSelectedConversationWhileAgentRunActive() async throws {
        try await ChatIntegrationTestHelpers.withWorkspaceFixture { workspaceFixture in
            let storageFixture = try TemporaryStorageFixture()
            defer { storageFixture.tearDown() }

            let (defaults, suiteName) = try ChatIntegrationTestHelpers.makeTestDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let appState = AppState(
                startServices: false,
                workspaceAuthorizationService: WorkspaceAuthorizationService(
                    userDefaults: defaults,
                    bookmarker: TestWorkspaceBookmarker(),
                scopeAccessor: TestWorkspaceSecurityScopeAccessor()
                ),
                userDefaults: defaults,
                storage: storageFixture.storage
            )
            appState.serverStatus = .connected(model: "qwen-test", latencyMs: 1)
            appState.isAgentPreviewEnabled = true
            appState.runtimeSupportsStructuredToolCalls = true

            let conv1 = Conversation(
                title: "Originating Agent Conv",
                messages: [],
                modelId: "qwen-agent-model",
                projectPath: workspaceFixture.rootURL.path
            )

            let existingConv2Messages = [
                ChatMessage(role: .user, content: "Existing prompt in conv2"),
                ChatMessage(role: .assistant, content: "Existing response in conv2", isStreaming: false)
            ]
            let conv2 = Conversation(
                title: "Separate Visible Conv",
                messages: existingConv2Messages,
                projectPath: nil
            )

            appState.conversations = [conv1, conv2]
            appState.selectedConversationId = conv1.id
            appState.setConversationWorkspace(id: conv1.id, url: workspaceFixture.rootURL)
            appState.setAgentMode(true, for: conv1.id)

            let gate = TestExecutionGate()

            let scriptedInference = ScriptedAgentInference { messages, tools, config in
                // Wait on gate during inference turn
                await gate.wait()
                return [
                    .reasoningDelta("Executing background task for conv1."),
                    .contentDelta("Agent finished work for conv1."),
                    .finished
                ]
            }

            let factory: AgentRuntimeFactory = { capturedRoot in
                NativeAgentRuntime(
                    inference: scriptedInference,
                    toolExecutor: ReadOnlyWorkspaceToolBroker(service: try ReadOnlyWorkspaceService(rootURL: capturedRoot))
                )
            }

            let client = QwenClient()
            let viewModel = ChatViewModel(
                client: client,
                agentRuntimeFactory: factory
            )

            viewModel.inputText = "Start background agent run"
            viewModel.sendMessage(appState: appState)

            // Wait until conv1 is actively generating
            try await AsyncCondition.wait(description: "conv1 started generating") {
                appState.isConversationGenerating(conv1.id)
            }

            // User switches selected conversation to conv2 while conv1 is actively in flight
            appState.selectedConversationId = conv2.id
            #expect(appState.selectedConversation?.id == conv2.id)

            // Snapshot conv2 visible messages before releasing gate
            let conv2SnapshotBefore = appState.selectedConversation?.messages

            // Unblock the execution gate to allow conv1 to complete
            await gate.unblock()

            // Wait until conv1 finishes generating
            try await AsyncCondition.wait(description: "conv1 finished generating") {
                !appState.isConversationGenerating(conv1.id)
            }

            // 1. Visible conversation (conv2) was NOT polluted or modified
            #expect(appState.selectedConversationId == conv2.id)
            let currentVisible = try #require(appState.selectedConversation)
            #expect(currentVisible.id == conv2.id)
            #expect(currentVisible.messages == conv2SnapshotBefore)

            // 2. Originating conversation (conv1) was correctly updated with the assistant response
            let originating = try #require(appState.conversations.first(where: { $0.id == conv1.id }))
            #expect(originating.messages.count == 2)
            let assistant = originating.messages[1]
            #expect(assistant.role == MessageRole.assistant)
            #expect(assistant.isStreaming == false)
            #expect(assistant.content == "Agent finished work for conv1.")
            #expect(assistant.thinkingContent == "Executing background task for conv1.")
        }
    }

    // MARK: - Test 3: Stopping an Active Agent Run

    @Test("Stopping an agent run cancels it, clears generation, marks assistant and tool states non-running, and does not execute a later turn")
    @MainActor
    func testStoppingActiveAgentRunCancelsCleanlyAndHaltsNextTurn() async throws {
        try await ChatIntegrationTestHelpers.withWorkspaceFixture { workspaceFixture in
            let storageFixture = try TemporaryStorageFixture()
            defer { storageFixture.tearDown() }

            let (defaults, suiteName) = try ChatIntegrationTestHelpers.makeTestDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }

            let appState = AppState(
                startServices: false,
                workspaceAuthorizationService: WorkspaceAuthorizationService(
                    userDefaults: defaults,
                    bookmarker: TestWorkspaceBookmarker(),
                scopeAccessor: TestWorkspaceSecurityScopeAccessor()
                ),
                userDefaults: defaults,
                storage: storageFixture.storage
            )
            appState.serverStatus = .connected(model: "qwen-test", latencyMs: 1)
            appState.isAgentPreviewEnabled = true
            appState.runtimeSupportsStructuredToolCalls = true

            let conv = Conversation(
                title: "Cancellable Agent Run",
                messages: [],
                projectPath: workspaceFixture.rootURL.path
            )
            appState.conversations = [conv]
            appState.selectedConversationId = conv.id
            appState.setConversationWorkspace(id: conv.id, url: workspaceFixture.rootURL)
            appState.setAgentMode(true, for: conv.id)

            let toolStartGate = TestExecutionGate()
            let toolSuspendGate = TestExecutionGate()
            let turnTracker = ThreadSafeTurnCounter()

            let toolCall = ToolCall(
                id: "call_cancel_1",
                type: "function",
                function: ToolCall.FunctionCall(
                    name: "workspace_list_directory",
                    arguments: "{}"
                )
            )

            // Turn 1 emits tool requested immediately; Turn 2 should never be reached
            let scriptedInference = ScriptedAgentInference { messages, tools, config in
                let currentTurn = turnTracker.increment()
                if currentTurn == 1 {
                    return [
                        .reasoningDelta("Searching workspace directory."),
                        .toolCall(toolCall),
                        .finished
                    ]
                } else {
                    return [
                        .contentDelta("Turn 2 MUST NOT execute."),
                        .finished
                    ]
                }
            }

            let scriptedToolExecutor = ScriptedAgentToolExecutor(tools: [
                AgentLoopTestHelpers.sampleWorkspaceListTool()
            ])
            await scriptedToolExecutor.setCustomHandler { call in
                await toolStartGate.unblock()
                await toolSuspendGate.wait()
                try Task.checkCancellation()
                return AgentToolResult(
                    callId: call.id,
                    toolName: call.function.name,
                    content: "[\"sample.txt\"]",
                    isSuccess: true
                )
            }

            let factory: AgentRuntimeFactory = { _ in
                NativeAgentRuntime(
                    inference: scriptedInference,
                    toolExecutor: scriptedToolExecutor
                )
            }

            let client = QwenClient()
            let viewModel = ChatViewModel(
                client: client,
                agentRuntimeFactory: factory
            )

            viewModel.inputText = "Execute run to cancel"
            viewModel.sendMessage(appState: appState)

            // Wait until tool executor signals start gate
            await toolStartGate.wait()

            // Wait until a running ToolExecution is projected in AppState
            try await AsyncCondition.wait(description: "running ToolExecution is projected") {
                guard let currentConv = appState.conversations.first(where: { $0.id == conv.id }),
                      let assistant = currentConv.messages.last(where: { $0.role == MessageRole.assistant }) else {
                    return false
                }
                return assistant.toolExecutions.contains(where: { $0.id == toolCall.id && $0.isRunning })
            }

            // Stop generation while tool is actively executing
            viewModel.stopGeneration(conversationID: conv.id, appState: appState)

            // Unblock suspend gate so suspended tool task can unwind upon cancellation
            await toolSuspendGate.unblock()

            // Wait for generation to clear
            try await AsyncCondition.wait(description: "Generation cleared after cancellation") {
                !appState.isConversationGenerating(conv.id)
            }

            // 1. Generation state is cleared
            #expect(appState.isConversationGenerating(conv.id) == false)
            #expect(appState.isGenerating == false)

            // 2. Assistant message and tool execution are non-streaming and non-running
            let updatedConv = try #require(appState.conversations.first(where: { $0.id == conv.id }))
            let assistantMessage = try #require(updatedConv.messages.last(where: { $0.role == MessageRole.assistant }))
            #expect(assistantMessage.isStreaming == false)
            for toolExec in assistantMessage.toolExecutions {
                #expect(toolExec.isRunning == false)
            }
            #expect(!assistantMessage.content.contains("Turn 2 MUST NOT execute."))

            // 3. Turn 2 was never reached
            #expect(turnTracker.turnCount == 1)
        }
    }

    // MARK: - Test 4: Agent Factory / Runtime Error Handling

    @Test("Agent factory or runtime error becomes a stable assistant error and cleans up generation")
    @MainActor
    func testAgentFactoryErrorYieldsStableAssistantErrorAndCleansUp() async throws {
        let storageFixture = try TemporaryStorageFixture()
        defer { storageFixture.tearDown() }

        let (defaults, suiteName) = try ChatIntegrationTestHelpers.makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(
            startServices: false,
            workspaceAuthorizationService: WorkspaceAuthorizationService(
                userDefaults: defaults,
                bookmarker: TestWorkspaceBookmarker(),
            scopeAccessor: TestWorkspaceSecurityScopeAccessor()
            ),
            userDefaults: defaults,
            storage: storageFixture.storage
        )
        appState.serverStatus = .connected(model: "qwen-test", latencyMs: 1)
        appState.isAgentPreviewEnabled = true
        appState.runtimeSupportsStructuredToolCalls = true

        let conv = Conversation(
            title: "Failing Agent Conv",
            messages: [],
            projectPath: "/tmp/nonexistent-workspace-path"
        )
        appState.conversations = [conv]
        appState.selectedConversationId = conv.id
        appState.setConversationWorkspace(
            id: conv.id,
            url: URL(fileURLWithPath: "/tmp/nonexistent-workspace-path", isDirectory: true)
        )
        appState.setAgentMode(true, for: conv.id)

        struct FactoryInitError: Error, LocalizedError {
            var errorDescription: String? { "Workspace root directory is invalid or inaccessible." }
        }

        let factory: AgentRuntimeFactory = { _ in
            throw FactoryInitError()
        }

        let client = QwenClient()
        let viewModel = ChatViewModel(
            client: client,
            agentRuntimeFactory: factory
        )

        viewModel.inputText = "Trigger factory failure"
        viewModel.sendMessage(appState: appState)

        // Wait until generation completes/aborts
        try await AsyncCondition.wait(description: "Generation completed after factory error") {
            !appState.isConversationGenerating(conv.id)
        }

        // 1. Generation flags are fully cleared
        #expect(appState.isConversationGenerating(conv.id) == false)
        #expect(appState.isGenerating == false)

        // 2. ViewModel exposes the error description
        #expect(viewModel.errorMessage?.contains("Workspace root directory is invalid or inaccessible.") == true)

        // 3. Assistant message is marked non-streaming and contains error info
        let updatedConv = try #require(appState.conversations.first(where: { $0.id == conv.id }))
        let assistantMessage = try #require(updatedConv.messages.last(where: { $0.role == MessageRole.assistant }))
        #expect(assistantMessage.isStreaming == false)
        #expect(
            assistantMessage.content.contains("Workspace root directory is invalid or inaccessible.") ||
            assistantMessage.content.hasPrefix("⚠️ Error:")
        )
    }

    // MARK: - Test 5: Ordinary Mode with Feature Off Uses Injected QwenClient Mocked SSE

    @Test("Ordinary mode with feature off uses injected QwenClient mocked SSE, never calls agent factory, sends no tools, and preserves direct reasoning behavior")
    @MainActor
    func testOrdinaryModeUsesInjectedClientWithoutCallingAgentFactory() async throws {
        let storageFixture = try TemporaryStorageFixture()
        defer { storageFixture.tearDown() }

        let (defaults, suiteName) = try ChatIntegrationTestHelpers.makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let expectedStats = GenerationStats(
            promptTokens: 12,
            completionTokens: 18,
            tokensPerSecond: 45.0,
            latencySeconds: 0.4,
            timeToFirstTokenSeconds: 0.08
        )

        let capture = ThreadSafeRequestCapture()

        // Setup dedicated race-safe mock SSE scope
        let sseScope = MockSSEScope { request in
            capture.record(
                request: request,
                body: request.httpBody ?? TransportTestHelpers.extractRequestBodyData(from: request)
            )
            let sseData = MockSSEFormatting.formatSSEPayload(
                reasoningChunks: ["Direct thought without agent loop."],
                contentChunks: ["Standard Qwen response without tools."],
                stats: expectedStats
            )
            let responseURL = request.url ?? URL(fileURLWithPath: "/")
            guard let response = MockHTTPResponseFactory.makeEventStreamResponse(url: responseURL) else {
                throw URLError(.badServerResponse)
            }
            return (response, sseData)
        }
        defer { sseScope.tearDown() }

        let appState = AppState(
            startServices: false,
            workspaceAuthorizationService: WorkspaceAuthorizationService(
                userDefaults: defaults,
                bookmarker: TestWorkspaceBookmarker(),
            scopeAccessor: TestWorkspaceSecurityScopeAccessor()
            ),
            userDefaults: defaults,
            storage: storageFixture.storage
        )
        appState.baseURL = sseScope.baseURL
        appState.serverStatus = ServerStatus.connected(model: "qwen-test", latencyMs: 5.0)
        appState.isAgentPreviewEnabled = false

        let conv = Conversation(
            title: "Ordinary Mode Conv",
            messages: [],
            projectPath: nil
        )
        appState.conversations = [conv]
        appState.selectedConversationId = conv.id

        let factoryTracker = ThreadSafeTurnCounter()

        let factory: AgentRuntimeFactory = { _ in
            _ = factoryTracker.increment()
            throw NSError(domain: "ShouldNotBeCalled", code: -1)
        }

        let injectedClient = QwenClient(session: sseScope.session)
        let viewModel = ChatViewModel(
            client: injectedClient,
            agentRuntimeFactory: factory
        )

        viewModel.inputText = "Hello in direct chat mode"
        viewModel.sendMessage(appState: appState)

        // Wait until generation finishes
        try await AsyncCondition.wait(description: "Direct generation finished") {
            !appState.isConversationGenerating(conv.id)
        }

        // 1. Agent factory was never called
        #expect(factoryTracker.turnCount == 0)

        // 2. Request body contained no tools key
        #expect(!capture.receivedBodies.isEmpty)
        if let bodyData = capture.receivedBodies.first,
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            #expect(json["tools"] == nil)
        }

        // 3. Generation completed and cleared
        #expect(appState.isConversationGenerating(conv.id) == false)
        #expect(appState.isGenerating == false)

        // 4. Message projected reasoning, content, stats and has no tool executions
        let updatedConv = try #require(appState.conversations.first(where: { $0.id == conv.id }))
        #expect(updatedConv.messages.count == 2)
        let assistant = updatedConv.messages[1]
        #expect(assistant.role == MessageRole.assistant)
        #expect(assistant.isStreaming == false)
        #expect(assistant.thinkingContent == "Direct thought without agent loop.")
        #expect(assistant.content == "Standard Qwen response without tools.")
        let assistantStats = try #require(assistant.stats)
        #expect(assistantStats.promptTokens == expectedStats.promptTokens)
        #expect(assistantStats.completionTokens == expectedStats.completionTokens)
        #expect(assistantStats.tokensPerSecond == expectedStats.tokensPerSecond)
        #expect(assistantStats.isThroughputEstimated == false)
        #expect(assistantStats.latencySeconds >= 0.0)
        #expect(assistantStats.timeToFirstTokenSeconds >= 0.0)
        #expect(assistant.toolExecutions.isEmpty == true)
    }

    // MARK: - Test 6: Snapshot Parameters Before Asynchronous Work

    @Test("Agent mode decision, thinking flag, workspace URL, model, temperature, and system prompt are captured before asynchronous work so later UI changes cannot redirect a run")
    @MainActor
    func testParametersAreSnapshottedBeforeAsynchronousExecution() async throws {
        try await ChatIntegrationTestHelpers.withWorkspaceFixture { fixtureA in
            try await ChatIntegrationTestHelpers.withWorkspaceFixture { fixtureB in
                let storageFixture = try TemporaryStorageFixture()
                defer { storageFixture.tearDown() }

                let (defaults, suiteName) = try ChatIntegrationTestHelpers.makeTestDefaults()
                defer { defaults.removePersistentDomain(forName: suiteName) }

                let appState = AppState(
                    startServices: false,
                    workspaceAuthorizationService: WorkspaceAuthorizationService(
                        userDefaults: defaults,
                        bookmarker: TestWorkspaceBookmarker(),
                    scopeAccessor: TestWorkspaceSecurityScopeAccessor()
                    ),
                    userDefaults: defaults,
                    storage: storageFixture.storage
                )
                appState.serverStatus = .connected(model: "qwen-test", latencyMs: 1)
                appState.isAgentPreviewEnabled = true
                appState.runtimeSupportsStructuredToolCalls = true

                let conv = Conversation(
                    title: "Snapshot Parameter Conv",
                    messages: [],
                    modelId: "initial-model-snapshotted",
                    temperature: 0.35,
                    systemPrompt: "Initial system prompt snapshot",
                    isThinkingEnabled: true,
                    projectPath: fixtureA.rootURL.path
                )
                appState.conversations = [conv]
                appState.selectedConversationId = conv.id
                appState.setConversationWorkspace(id: conv.id, url: fixtureA.rootURL)
                appState.setAgentMode(true, for: conv.id)

                let gate = TestExecutionGate()
                let tracker = ThreadSafeRunSnapshotTracker()

                let scriptedInference = ScriptedAgentInference { messages, tools, config in
                    tracker.record(config: config)
                    // Wait at gate so caller can mutate AppState before streaming completes
                    await gate.wait()
                    return [
                        .reasoningDelta("Reasoning under initial snapshot."),
                        .contentDelta("Answer under initial snapshot."),
                        .finished
                    ]
                }

                let factory: AgentRuntimeFactory = { capturedRoot in
                    tracker.record(workspaceRoot: capturedRoot)
                    return NativeAgentRuntime(
                        inference: scriptedInference,
                        toolExecutor: ReadOnlyWorkspaceToolBroker(service: try ReadOnlyWorkspaceService(rootURL: capturedRoot))
                    )
                }

                let client = QwenClient()
                let viewModel = ChatViewModel(
                    client: client,
                    agentRuntimeFactory: factory
                )

                viewModel.inputText = "Run with snapshot check"
                viewModel.sendMessage(appState: appState)

                // Wait until generation starts
                try await AsyncCondition.wait(description: "Generation active") {
                    appState.isConversationGenerating(conv.id)
                }

                // Mutate all conversation and AppState properties while run is in-flight
                appState.selectedModel = "mutated-model-other"
                appState.updateConversation(id: conv.id) { c in
                    c.modelId = "mutated-model-other"
                    c.temperature = 0.99
                    c.systemPrompt = "Mutated system prompt"
                    c.isThinkingEnabled = false
                    c.projectPath = fixtureB.rootURL.path
                }
                appState.setAgentMode(false, for: conv.id)
                appState.isAgentPreviewEnabled = false

                // Unblock gate to finish execution
                await gate.unblock()

                // Wait until generation finishes
                try await AsyncCondition.wait(description: "Generation finished") {
                    !appState.isConversationGenerating(conv.id)
                }

                // 1. Captured workspace URL was fixtureA (initial), not fixtureB
                #expect(tracker.capturedWorkspaceRoot?.standardizedFileURL == fixtureA.rootURL.standardizedFileURL)

                // 2. Captured configuration had all initial values snapshotted before async dispatch
                let config = try #require(tracker.capturedRunConfig)
                #expect(config.model == "initial-model-snapshotted")
                #expect(config.temperature == 0.35)
                #expect(config.systemPrompt?.hasPrefix("Initial system prompt snapshot") == true)
                #expect(config.systemPrompt?.contains("prefer workspace_find_files and workspace_search_text") == true)
                #expect(config.isThinkingEnabled == true)

                // 3. The run completed and projected successfully
                let updatedConv = try #require(appState.conversations.first(where: { $0.id == conv.id }))
                let assistant = try #require(updatedConv.messages.last(where: { $0.role == MessageRole.assistant }))
                #expect(assistant.isStreaming == false)
                #expect(assistant.content == "Answer under initial snapshot.")
                #expect(assistant.thinkingContent == "Reasoning under initial snapshot.")
            }
        }
    }

    // MARK: - Test 7: Immediate Send After BaseURL Change to Unverified Endpoint

    @Test("ChatViewModel immediate send after baseURL changed to unverified endpoint does not invoke agentRuntimeFactory or include tools")
    @MainActor
    func testImmediateSendAfterBaseURLChangeToUnverifiedEndpointDoesNotInvokeFactoryOrSendTools() async throws {
        try await ChatIntegrationTestHelpers.withWorkspaceFixture { workspaceFixture in
            let storageFixture = try TemporaryStorageFixture()
            defer { storageFixture.tearDown() }

            let (defaults, suiteName) = try ChatIntegrationTestHelpers.makeTestDefaults()
            defer { defaults.removePersistentDomain(forName: suiteName) }

            // Endpoint B (unverified destination)
            let capture = ThreadSafeRequestCapture()
            let expectedStats = GenerationStats(
                promptTokens: 10,
                completionTokens: 10,
                tokensPerSecond: 20.0
            )
            let sseScopeB = MockSSEScope { request in
                capture.record(
                    request: request,
                    body: request.httpBody ?? TransportTestHelpers.extractRequestBodyData(from: request)
                )
                let sseData = MockSSEFormatting.formatSSEPayload(
                    contentChunks: ["Direct response from unverified endpoint B."],
                    stats: expectedStats
                )
                let responseURL = request.url ?? URL(fileURLWithPath: "/")
                guard let response = MockHTTPResponseFactory.makeEventStreamResponse(url: responseURL) else {
                    throw URLError(.badServerResponse)
                }
                return (response, sseData)
            }
            defer { sseScopeB.tearDown() }

            let appState = AppState(
                baseURL: "http://endpoint-a-verified.local:8000/v1",
                startServices: false,
                workspaceAuthorizationService: WorkspaceAuthorizationService(
                    userDefaults: defaults,
                    bookmarker: TestWorkspaceBookmarker(),
                scopeAccessor: TestWorkspaceSecurityScopeAccessor()
                ),
                userDefaults: defaults,
                storage: storageFixture.storage
            )
            appState.serverStatus = .connected(model: "qwen-a", latencyMs: 1)
            appState.isAgentPreviewEnabled = true
            appState.runtimeSupportsStructuredToolCalls = true

            let conv = Conversation(
                title: "Gated Conv",
                messages: [],
                modelId: "qwen-test",
                projectPath: workspaceFixture.rootURL.path
            )
            appState.conversations = [conv]
            appState.selectedConversationId = conv.id
            appState.setConversationWorkspace(id: conv.id, url: workspaceFixture.rootURL)
            appState.setAgentMode(true, for: conv.id)
            #expect(appState.isAgentModeEnabled(for: conv.id) == true)

            // Switch baseURL to endpoint B
            appState.baseURL = sseScopeB.baseURL

            let factoryTracker = ThreadSafeTurnCounter()
            let factory: AgentRuntimeFactory = { _ in
                _ = factoryTracker.increment()
                throw NSError(domain: "FactoryShouldNotBeInvoked", code: -1)
            }

            let injectedClient = QwenClient(session: sseScopeB.session)
            let viewModel = ChatViewModel(
                client: injectedClient,
                agentRuntimeFactory: factory
            )

            viewModel.inputText = "Immediate message after endpoint switch"
            viewModel.sendMessage(appState: appState)

            try await AsyncCondition.wait(description: "Generation finished after endpoint switch") {
                !appState.isConversationGenerating(conv.id)
            }

            // 1. Factory must NOT be invoked
            #expect(factoryTracker.turnCount == 0)

            // 2. Request sent to B must NOT contain tools
            #expect(!capture.receivedBodies.isEmpty)
            if let bodyData = capture.receivedBodies.first,
               let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                #expect(json["tools"] == nil)
            }

            // 3. Assistant message has no tool executions
            let updatedConv = try #require(appState.conversations.first(where: { $0.id == conv.id }))
            let assistant = try #require(updatedConv.messages.last(where: { $0.role == MessageRole.assistant }))
            #expect(assistant.toolExecutions.isEmpty == true)
            #expect(assistant.content.contains("Direct response from unverified endpoint B."))
        }
    }
}
