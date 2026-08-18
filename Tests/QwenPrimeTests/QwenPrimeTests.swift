import Testing
import Foundation
@testable import QwenPrime

@Suite("QwenPrime Model & Storage Tests")
struct QwenPrimeTests {

    private func sourceFile(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }

    @Test("Empty conversations do not show canned prompt cards")
    func testEmptyConversationHasNoPromptSuggestions() throws {
        let chatView = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Chat/ChatView.swift"),
            encoding: .utf8
        )

        #expect(!chatView.contains("Explain speculative decoding with MLX"))
        #expect(!chatView.contains("Write a lock-free ring buffer in Rust"))
        #expect(!chatView.contains("Design an actor-isolated Cache in Swift 6"))
        #expect(!chatView.contains("Implement dynamic programming Fibonacci in Python"))
    }

    @Test("Conversation serialization and roundtrip")
    func testConversationSerialization() throws {
        let msg1 = ChatMessage(
            role: .user,
            content: "Hello Qwen!"
        )
        let msg2 = ChatMessage(
            role: .assistant,
            content: "Hello! How can I assist you with code today?",
            thinkingContent: "User greeted. Provide a friendly coding assistant greeting.",
            stats: GenerationStats(promptTokens: 12, completionTokens: 25, tokensPerSecond: 45.2, latencySeconds: 0.55)
        )

        var conv = Conversation(
            title: "Test Greeting",
            messages: [msg1, msg2],
            modelId: "qwen3.8-27b"
        )
        conv.touch()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(conv)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Conversation.self, from: data)

        #expect(decoded.id == conv.id)
        #expect(decoded.title == "Test Greeting")
        #expect(decoded.messages.count == 2)
        #expect(decoded.messages[1].thinkingContent == "User greeted. Provide a friendly coding assistant greeting.")
        #expect(decoded.messages[1].stats?.tokensPerSecond == 45.2)
    }

    @Test("Background generation updates its originating conversation")
    @MainActor
    func testConversationIdentityScopedMutation() {
        let appState = AppState(startServices: false)
        let originating = Conversation(title: "Originating")
        let visible = Conversation(title: "Visible")
        appState.conversations = [originating, visible]
        appState.selectedConversationId = visible.id

        appState.updateConversation(id: originating.id) { conversation in
            conversation.title = "Updated in background"
        }

        #expect(appState.selectedConversation?.title == "Visible")
        #expect(
            appState.conversations.first(where: { $0.id == originating.id })?.title
                == "Updated in background"
        )
    }

    @Test("Generation activity is tracked per conversation")
    @MainActor
    func testConversationScopedGenerationActivity() {
        let appState = AppState(startServices: false)
        let first = UUID()
        let second = UUID()

        appState.setConversation(first, isGenerating: true)

        #expect(appState.isGenerating)
        #expect(appState.isConversationGenerating(first))
        #expect(!appState.isConversationGenerating(second))

        appState.setConversation(first, isGenerating: false)

        #expect(!appState.isGenerating)
    }

    @Test("Active generation mutations remain lifecycle safe")
    @MainActor
    func testGenerationMutationSafety() {
        let appState = AppState(startServices: false)
        let source = Conversation(
            title: "Streaming",
            messages: [ChatMessage(role: .assistant, content: "Partial", isStreaming: true)],
            isThinkingEnabled: false
        )
        appState.conversations = [source]
        appState.selectedConversationId = source.id
        appState.setConversation(source.id, isGenerating: true)

        appState.deleteConversation(id: source.id)
        #expect(appState.conversations.contains(where: { $0.id == source.id }))

        appState.clearConversationMessages(id: source.id)
        #expect(
            appState.conversations.first(where: { $0.id == source.id })?.messages.count == 1
        )

        appState.duplicateConversation(id: source.id)
        let duplicate = appState.conversations.first(where: { $0.id != source.id })
        #expect(duplicate?.messages.allSatisfy { !$0.isStreaming } == true)
        #expect(duplicate?.isThinkingEnabled == false)
    }

    @Test("Generation runs use identity-checked cleanup")
    func testGenerationRunIdentityCleanup() throws {
        let source = try String(
            contentsOf: sourceFile("Sources/QwenPrime/ViewModels/ChatViewModel.swift"),
            encoding: .utf8
        )

        #expect(source.contains("runID"))
        #expect(source.contains("streamTasks[conversationID]?.id == runID"))
        #expect(source.contains("guard !Task.isCancelled else { return }"))
    }

    @Test("Sidebar previews collapse Markdown into one quiet line")
    func testConversationRowPreviewNormalization() {
        let conversation = Conversation(
            title: "Implementation",
            messages: [
                ChatMessage(
                    role: .assistant,
                    content: "## Result\n\n**Use** a stable layout.\n```swift\nZStack {}\n```"
                )
            ]
        )

        let presentation = ConversationRowPresentation(conversation: conversation)

        #expect(presentation.preview == "Result Use a stable layout. ZStack {}")
    }

    @Test("Composer floats over the timeline without consuming stack layout")
    func testFloatingComposerLayout() throws {
        let chatView = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Chat/ChatView.swift"),
            encoding: .utf8
        )

        #expect(chatView.contains("ZStack(alignment: .bottom)"))
        #expect(chatView.contains("DesignTokens.Layout.composerScrollClearance"))
        #expect(!chatView.contains("VStack(spacing: 0) {\n            // Chat Content"))

        let promptBar = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Chat/PromptInputBar.swift"),
            encoding: .utf8
        )
        #expect(promptBar.contains(".lineLimit(1...4)"))
        #expect(promptBar.contains(".accessibilityLabel(\"Send message\")"))
        #expect(promptBar.contains(".accessibilityLabel(\"Stop generation\")"))
    }

    @Test("Runtime identity and navigation chrome have one clear home")
    func testRuntimeIdentityAndToolbarHierarchy() throws {
        let chatView = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Chat/ChatView.swift"),
            encoding: .utf8
        )
        let promptBar = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Chat/PromptInputBar.swift"),
            encoding: .utf8
        )
        let sidebar = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Sidebar/SidebarView.swift"),
            encoding: .utf8
        )
        let quickSettings = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Chat/QuickSettingsPopover.swift"),
            encoding: .utf8
        )

        #expect(chatView.contains("conversation.projectPath"))
        #expect(chatView.contains("Text(\"/\")"))
        #expect(chatView.contains("sharedBackgroundVisibility(.hidden)"))
        #expect(!chatView.contains("ToolbarItemGroup(placement: .primaryAction)"))
        #expect(!promptBar.contains(".fill(Color.green)"))
        #expect(!sidebar.contains("Image(systemName: \"cpu\")"))
        #expect(quickSettings.contains("Text(\"Appearance\")"))
        #expect(quickSettings.contains("Text(\"Conversation\")"))
        #expect(quickSettings.contains("Text(\"Runtime\")"))
        #expect(quickSettings.contains("Qwen 3.8 27B"))
    }

    @Test("Quick settings route directly and control the runtime")
    func testQuickSettingsRoutingAndRuntimeControl() throws {
        let sidebar = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Sidebar/SidebarView.swift"),
            encoding: .utf8
        )
        let settings = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Settings/SettingsView.swift"),
            encoding: .utf8
        )
        let quickSettings = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Chat/QuickSettingsPopover.swift"),
            encoding: .utf8
        )

        #expect(sidebar.contains("appState.settingsSelection = .systemPrompts"))
        #expect(settings.contains("TabView(selection: $appState.settingsSelection)"))
        #expect(quickSettings.contains("appState.stopEngine()"))
        #expect(quickSettings.contains("appState.startEngine()"))
        #expect(quickSettings.contains("Stop Runtime"))
        #expect(quickSettings.contains("Start Runtime"))
        #expect(!quickSettings.contains(".foregroundStyle(Color.accentColor)"))
    }

    @Test("Updates are manual, GitHub-hosted, and include an embedded runtime seam")
    func testUpdateAndEmbeddedRuntimeArchitecture() throws {
        let package = try String(contentsOf: sourceFile("Package.swift"), encoding: .utf8)
        let app = try String(
            contentsOf: sourceFile("Sources/QwenPrime/App/QwenPrimeApp.swift"),
            encoding: .utf8
        )
        let quickSettings = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Chat/QuickSettingsPopover.swift"),
            encoding: .utf8
        )
        let server = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Services/ServerHealthService.swift"),
            encoding: .utf8
        )
        let packager = try String(contentsOf: sourceFile("package_app.sh"), encoding: .utf8)

        #expect(package.contains("sparkle-project/Sparkle"))
        #expect(app.contains("Check for Updates…"))
        #expect(quickSettings.contains("Check for Updates"))
        #expect(server.contains("QwenPrimeRuntime/bin/qwen-prime-runtime"))
        #expect(packager.contains("QWEN_PRIME_EMBEDDED_RUNTIME"))
        #expect(packager.contains("<string>app.dech.qwenprime</string>"))
        #expect(!packager.contains("com.adrian.qwenprime"))
        #expect(packager.contains("@executable_path/../Frameworks"))
        #expect(packager.contains("SUEnableAutomaticChecks"))
        #expect(packager.contains("false"))
        #expect(packager.contains("--preserve-metadata=entitlements"))
        #expect(!packager.contains("codesign --force --deep"))
    }

    @Test("Sidebar swipe actions use compact icons")
    func testCompactSidebarSwipeActions() throws {
        let sidebar = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Sidebar/SidebarView.swift"),
            encoding: .utf8
        )

        #expect(sidebar.contains(".accessibilityLabel(\"Delete conversation\")"))
        #expect(sidebar.contains(".accessibilityLabel(\"Duplicate conversation\")"))
        #expect(!sidebar.contains("Label(\"Delete\", systemImage: \"trash\")"))
        #expect(!sidebar.contains("Label(\"Duplicate\", systemImage: \"plus.square.on.square\")"))
    }

    @Test("App icon has an editable vector master")
    func testVectorAppIcon() throws {
        let svg = try String(
            contentsOf: sourceFile("Resources/AppIcon.svg"),
            encoding: .utf8
        )
        let icon = sourceFile("Resources/AppIcon.icns")

        #expect(svg.contains("Qwen Prime app icon"))
        #expect(svg.contains("speculative token nodes"))
        #expect(!svg.contains("<text"))
        #expect(FileManager.default.fileExists(atPath: icon.path))
    }

    @Test("Release publishing is one guarded local command")
    func testReleasePublisher() throws {
        let publisher = try String(
            contentsOf: sourceFile("publish_release.command"),
            encoding: .utf8
        )
        let preflight = try String(
            contentsOf: sourceFile("release_preflight.command"),
            encoding: .utf8
        )

        #expect(publisher.contains("SPARKLE_PRIVATE_KEY"))
        #expect(publisher.contains("generate_appcast"))
        #expect(publisher.contains("gh release create"))
        #expect(publisher.contains("release_preflight.command"))
        #expect(preflight.contains("status --porcelain"))
        #expect(preflight.contains("--publish"))
    }

    @Test("Runtime model configuration persists atomically and validates directories")
    func testRuntimeConfigurationPersistence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QwenPrimeRuntimeConfig-\(UUID().uuidString)")
        let target = root.appendingPathComponent("target", isDirectory: true)
        let draft = root.appendingPathComponent("draft", isDirectory: true)
        let configURL = root.appendingPathComponent("runtime.json")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: draft, withIntermediateDirectories: true)

        let service = RuntimeConfigurationService(configurationURL: configURL)
        let configuration = RuntimeConfiguration(
            targetModelPath: target.path,
            draftModelPath: draft.path
        )

        try service.save(configuration)

        #expect(try service.load() == configuration)
        #expect(service.localValidation(configuration) == .ready)
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: configURL)
        ) as? [String: Any]
        #expect(json?["target_model"] as? String == target.path)
        #expect(json?["draft_model"] as? String == draft.path)
    }

    @Test("Runtime configuration names the missing model directory")
    func testRuntimeConfigurationMissingDirectory() {
        let service = RuntimeConfigurationService(
            configurationURL: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
        )
        let configuration = RuntimeConfiguration(
            targetModelPath: "/missing/qwen-target",
            draftModelPath: "/missing/qwen-draft"
        )

        #expect(
            service.localValidation(configuration)
                == .invalid("Target model folder does not exist.")
        )
    }

    @Test("Unconfigured startup does not launch the inference server")
    func testRuntimeOnboardingGuardsAutomaticStart() throws {
        let appStateSource = try String(
            contentsOf: sourceFile("Sources/QwenPrime/ViewModels/AppState.swift"),
            encoding: .utf8
        )
        let settingsSource = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Settings/SettingsView.swift"),
            encoding: .utf8
        )

        #expect(appStateSource.contains("runtimeSetupStatus == .ready"))
        #expect(settingsSource.contains("Choose Target…"))
        #expect(settingsSource.contains("Choose Draft…"))
        #expect(settingsSource.contains("Save & Validate"))
        #expect(!settingsSource.contains("DFlash 4K-Trained Q8"))
        #expect(!settingsSource.contains("35–42 tok/s"))
    }

    @Test("Generation stats decode speculative telemetry and remain backward compatible")
    func testGenerationStatsSpeculativeTelemetry() throws {
        let current = Data(#"{"promptTokens":10,"completionTokens":20,"tokensPerSecond":14.2,"latencySeconds":2.5,"timeToFirstTokenSeconds":0.4,"speculativeAcceptanceRate":0.25,"acceptedDraftTokens":5,"speculativeCycles":10,"prefillSeconds":0.5,"prefillTokensPerSecond":200.0,"prefillTokensComputed":100,"prefillTokensRestored":50,"prefixCacheHitTokens":50,"reasoningTokens":8,"reasoningSeconds":0.75,"isThroughputEstimated":false}"#.utf8)
        let decoded = try JSONDecoder().decode(GenerationStats.self, from: current)

        #expect(decoded.speculativeAcceptanceRate == 0.25)
        #expect(decoded.acceptedDraftTokens == 5)
        #expect(decoded.speculativeCycles == 10)
        #expect(decoded.prefillSeconds == 0.5)
        #expect(decoded.prefillTokensPerSecond == 200.0)
        #expect(decoded.prefillTokensComputed == 100)
        #expect(decoded.prefillTokensRestored == 50)
        #expect(decoded.prefixCacheHitTokens == 50)
        #expect(decoded.reasoningTokens == 8)
        #expect(decoded.reasoningSeconds == 0.75)
        #expect(decoded.isThroughputEstimated == false)

        let legacy = Data(#"{"promptTokens":10,"completionTokens":20,"tokensPerSecond":14.2,"latencySeconds":2.5,"timeToFirstTokenSeconds":0.4}"#.utf8)
        let legacyDecoded = try JSONDecoder().decode(GenerationStats.self, from: legacy)

        #expect(legacyDecoded.speculativeAcceptanceRate == nil)
        #expect(legacyDecoded.acceptedDraftTokens == nil)
        #expect(legacyDecoded.speculativeCycles == nil)
        #expect(legacyDecoded.prefillSeconds == nil)
        #expect(legacyDecoded.prefixCacheHitTokens == nil)
        #expect(legacyDecoded.reasoningTokens == nil)
        #expect(legacyDecoded.reasoningSeconds == nil)
        #expect(legacyDecoded.isThroughputEstimated == nil)
    }

    @Test("Thinking accordion renders Markdown without a nested vertical scroller")
    func testThinkingAccordionPresentation() throws {
        let sourceRoot = sourceFile("Sources/QwenPrime/Views/Chat")
        let accordion = try String(
            contentsOf: sourceRoot.appendingPathComponent("ThinkingAccordion.swift"),
            encoding: .utf8
        )
        let bubble = try String(
            contentsOf: sourceRoot.appendingPathComponent("MessageBubble.swift"),
            encoding: .utf8
        )

        #expect(accordion.contains("MarkdownView(content: thinking, theme: theme)"))
        #expect(!accordion.contains("ScrollView(.vertical"))
        #expect(bubble.contains("message.stats?.reasoningTokens"))
        #expect(bubble.contains("message.stats?.reasoningSeconds"))
        #expect(bubble.contains("presentation.usesPolishedRecap ? nil"))
        #expect(!bubble.contains("duration: message.stats?.timeToFirstTokenSeconds"))
    }

    @Test("Polished final reasoning is consolidated into the thinking accordion")
    func testReasoningPresentationConsolidatesLeadingReasoningSection() {
        let presentation = ReasoningPresentation.resolve(
            hiddenThinking: "truncated private thought",
            content: """
            ## Design Reasoning

            **Ownership.** Resume each continuation exactly once.

            ---

            ## Implementation

            ```swift
            actor Channel {}
            ```
            """
        )

        #expect(presentation.thinking == "**Ownership.** Resume each continuation exactly once.")
        #expect(presentation.answer.hasPrefix("## Implementation"))
        #expect(!presentation.answer.contains("Design Reasoning"))
        #expect(presentation.usesPolishedRecap)
    }

    @Test("Streaming reasoning recap remains in one bundle before answer starts")
    func testReasoningPresentationHandlesIncompleteReasoningSection() {
        let presentation = ReasoningPresentation.resolve(
            hiddenThinking: "private thought",
            content: "## Design Reasoning\n\n**Ownership.** Still streaming"
        )

        #expect(presentation.thinking == "**Ownership.** Still streaming")
        #expect(presentation.answer.isEmpty)
    }

    @Test("Ordinary answers remain unchanged")
    func testReasoningPresentationLeavesOrdinaryAnswerAlone() {
        let presentation = ReasoningPresentation.resolve(
            hiddenThinking: "private thought",
            content: "## Implementation\n\nComplete answer"
        )

        #expect(presentation.thinking == "private thought")
        #expect(presentation.answer == "## Implementation\n\nComplete answer")
        #expect(!presentation.usesPolishedRecap)
    }

    @Test("Runtime identity accepts only the warmed Qwen3.8 native MTP configuration")
    func testRuntimeIdentityValidation() throws {
        let valid = Data(#"{"runtime_id":"qwen38-native-mtp-v2","target_model_id":"Qwen/Qwen3.8-27B","draft_model_id":"Qwen/Qwen3.8-27B#native-mtp","target_quantization":{"scheme":"mixed","bits":[4,8],"default_bits":4,"group_size":64,"mode":"affine"},"draft_quantization":{"scheme":"uniform","bits":[6],"default_bits":6,"group_size":64,"mode":"affine"},"block_tokens":4,"prefix_cache_enabled":true,"warmup_complete":true}"#.utf8)
        let identity = try JSONDecoder().decode(QwenRuntimeIdentity.self, from: valid)
        #expect(identity.isExpectedRuntime)

        let stale = Data(#"{"runtime_id":"qwen38-native-mtp-v2","target_model_id":"Qwen/Qwen3.8-27B","draft_model_id":"Qwen/Qwen3.8-27B#native-mtp","target_quantization":{"scheme":"mixed","bits":[4,8],"default_bits":4,"group_size":64,"mode":"affine"},"draft_quantization":{"scheme":"uniform","bits":[6],"default_bits":6,"group_size":64,"mode":"affine"},"block_tokens":4,"prefix_cache_enabled":false,"warmup_complete":true}"#.utf8)
        let staleIdentity = try JSONDecoder().decode(QwenRuntimeIdentity.self, from: stale)
        #expect(!staleIdentity.isExpectedRuntime)
    }

    @Test("Server lifecycle launches only the installed runtime executable")
    func testServerLifecycleUsesInstalledRuntime() throws {
        let sourceURL = sourceFile(
            "Sources/QwenPrime/Services/ServerHealthService.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("QWEN_PRIME_RUNTIME_EXECUTABLE"))
        #expect(source.contains("proc.arguments = [\"serve\"]"))
        #expect(!source.contains("pkill"))
        #expect(!source.contains("/bin/zsh"))
        #expect(source.contains("/engine"))
    }

    @Test("Application termination waits for the managed runtime to stop")
    func testApplicationTerminationStopsRuntime() throws {
        let source = try String(
            contentsOf: sourceFile("Sources/QwenPrime/App/QwenPrimeApp.swift"),
            encoding: .utf8
        )

        #expect(source.contains("applicationShouldTerminate"))
        #expect(source.contains(".terminateLater"))
        #expect(source.contains("reply(toApplicationShouldTerminate: true)"))
        #expect(!source.contains("applicationWillTerminate"))
    }

    @Test("Managed runtime termination is bounded and external runtime controls are truthful")
    func testBoundedManagedRuntimeTermination() throws {
        let health = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Services/ServerHealthService.swift"),
            encoding: .utf8
        )
        let quickSettings = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Chat/QuickSettingsPopover.swift"),
            encoding: .utf8
        )

        #expect(health.contains("gracefulTimeout"))
        #expect(health.contains("SIGKILL"))
        #expect(health.contains("terminateManagedProcess(process)"))
        #expect(quickSettings.contains("External Runtime"))
        #expect(quickSettings.contains("appState.isRuntimeManaged"))
    }

    @Test("Client preserves assistant reasoning in subsequent API turns")
    func testClientPreservesReasoningForPrefixCache() throws {
        let sourceURL = sourceFile("Sources/QwenPrime/Services/QwenClient.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("reasoning_content"))
        #expect(source.contains("msg.thinkingContent"))
    }

    @Test("Client sends bounded completion and reasoning budgets")
    func testClientSendsBoundedGenerationBudgets() throws {
        let sourceURL = sourceFile("Sources/QwenPrime/Services/QwenClient.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("maxCompletionTokens: Int = 1024"))
        #expect(source.contains("maxReasoningTokens: Int = 96"))
        #expect(source.contains(#""max_completion_tokens": maxCompletionTokens"#))
        #expect(source.contains(#""max_reasoning_tokens": maxReasoningTokens"#))
    }

    @Test("Chat captures reasoning mode before starting asynchronous work")
    func testChatCapturesReasoningModeAtSendTime() throws {
        let sourceURL = sourceFile("Sources/QwenPrime/ViewModels/ChatViewModel.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("let requestThinkingEnabled = conversation.isThinkingEnabled"))
        #expect(source.contains("isThinkingEnabled: requestThinkingEnabled"))
    }

    @Test("StorageService save and delete lifecycle")
    func testStorageService() async throws {
        let testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QwenPrimeTests-\(UUID().uuidString)")
        let storage = StorageService(directoryURL: testDirectory)
        defer { try? FileManager.default.removeItem(at: testDirectory) }
        let testId = UUID()
        let conv = Conversation(
            id: testId,
            title: "Unit Test Temp Conversation",
            messages: [ChatMessage(role: .user, content: "Ping")]
        )

        try await storage.saveConversation(conv)
        let all = try await storage.loadAllConversations()
        #expect(all.contains(where: { $0.id == testId }))

        try await storage.deleteConversation(id: testId)
        let afterDelete = try await storage.loadAllConversations()
        #expect(!afterDelete.contains(where: { $0.id == testId }))
    }

    @Test("MarkdownParser tokenization tests")
    func testMarkdownParser() {
        let sample = """
        # Title Header
        This is a paragraph with **bold** text.
        
        ```swift
        let x = 42
        ```
        
        - First bullet
        - Second bullet
        
        > A wise quote
        """
        let blocks = MarkdownParser.parse(markdown: sample)
        #expect(blocks.count >= 4)
    }

    @Test("Theme catalog verification")
    func testThemes() {
        for themeType in ThemeType.allCases {
            let t = MarkdownTheme.theme(for: themeType)
            #expect(!t.name.isEmpty)
        }
    }
}
