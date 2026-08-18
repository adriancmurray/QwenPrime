import Testing
import Foundation
@testable import QwenPrime

@Suite("Agent Preview UI & State Contract Tests")
struct AgentPreviewUIAndStateContractTests {

    private func sourceFile(_ path: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(path)
    }

    private func readSource(_ relativePath: String) throws -> String {
        try String(contentsOf: sourceFile(relativePath), encoding: .utf8)
    }

    // MARK: - Contract (1): AppState setConversationWorkspace(id:url:)

    @Test("AppState source defines setConversationWorkspace(id:url:) updating projectPath, saving, and updating global sandbox")
    func testAppStateSetConversationWorkspaceContract() throws {
        let appStateSource = try readSource("Sources/QwenPrime/ViewModels/AppState.swift")

        // 1. AppState must declare setConversationWorkspace(id:url:)
        #expect(
            appStateSource.contains("func setConversationWorkspace(id: UUID, url: URL)") ||
            appStateSource.contains("func setConversationWorkspace(id:")
        )

        // 2. Implementation must update the conversation's projectPath
        #expect(appStateSource.contains(".projectPath = workspaceURL.path"))

        // 3. Implementation must persist the conversation via saveConversation
        #expect(appStateSource.contains("saveConversation("))

        // 4. Implementation must update global sandbox directory and recent projects
        #expect(appStateSource.contains("applySandboxDirectory(workspaceURL)"))
    }

    @Test("AppState setConversationWorkspace updates target conversation projectPath, global sandboxDirectory, and recentProjects while leaving other conversations unchanged and persisting to storage")
    @MainActor
    func testSetConversationWorkspaceBehavioral() async throws {
        let (defaults, suiteName) = try ChatIntegrationTestHelpers.makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let storageFixture = try TemporaryStorageFixture()
        defer { storageFixture.tearDown() }

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

        let initialURL1 = URL(fileURLWithPath: "/tmp/project-alpha")
        let initialURL2 = URL(fileURLWithPath: "/tmp/project-beta")
        let conv1 = Conversation(
            title: "Chat 1",
            messages: [],
            modelId: "qwen-test",
            projectPath: initialURL1.path
        )
        let conv2 = Conversation(
            title: "Chat 2",
            messages: [],
            modelId: "qwen-test",
            projectPath: initialURL2.path
        )

        appState.conversations = [conv1, conv2]
        appState.selectedConversationId = conv1.id

        try await storageFixture.storage.saveConversation(conv1)
        try await storageFixture.storage.saveConversation(conv2)

        let targetURL = URL(fileURLWithPath: "/tmp/project-gamma")
        appState.setConversationWorkspace(id: conv1.id, url: targetURL)

        // 1. Verify global sandboxDirectory and recentProjects update
        #expect(appState.sandboxDirectory.path == targetURL.path)
        #expect(appState.recentProjects.contains(where: { $0.path == targetURL.path }))

        // 2. Verify target conversation projectPath changes
        let updatedConv1 = try #require(appState.conversations.first(where: { $0.id == conv1.id }))
        #expect(updatedConv1.projectPath == targetURL.path)

        // 3. Verify other conversation projectPath remains unchanged
        let updatedConv2 = try #require(appState.conversations.first(where: { $0.id == conv2.id }))
        #expect(updatedConv2.projectPath == initialURL2.path)

        // 4. Conditionally wait for async storage save and verify persisted target
        try await AsyncCondition.wait(description: "StorageService conversation save for setConversationWorkspace") {
            let loaded = (try? await storageFixture.storage.loadAllConversations()) ?? []
            guard let savedConv = loaded.first(where: { $0.id == conv1.id }) else {
                return false
            }
            return savedConv.projectPath == targetURL.path
        }

        let persistedConversations = try await storageFixture.storage.loadAllConversations()
        let persistedConv1 = try #require(persistedConversations.first(where: { $0.id == conv1.id }))
        #expect(persistedConv1.projectPath == targetURL.path)

        let persistedConv2 = try #require(persistedConversations.first(where: { $0.id == conv2.id }))
        #expect(persistedConv2.projectPath == initialURL2.path)
    }

    // MARK: - Contract (2): ChatView Composer Workspace Binding & Selection

    @Test("ChatView composer displays the conversation's own projectPath, not a stale global sandbox path")
    func testChatViewComposerWorkspaceBinding() throws {
        let chatViewSource = try readSource("Sources/QwenPrime/Views/Chat/ChatView.swift")

        // 1. ChatView composer must compute or pass the conversation's own workspace URL
        #expect(chatViewSource.contains("conversation.projectPath"))
        #expect(chatViewSource.contains("URL(fileURLWithPath:"))

        // 2. ChatView composer must not unconditionally pass raw global sandboxDirectory alone
        #expect(!chatViewSource.contains("sandboxURL: appState.sandboxDirectory,\n            recentProjects:"))
    }

    @Test("ChatView workspace selection calls setConversationWorkspace for the specific conversation")
    func testChatViewWorkspaceSelectionDelegation() throws {
        let chatViewSource = try readSource("Sources/QwenPrime/Views/Chat/ChatView.swift")

        // ChatView composer onSelectProject must invoke setConversationWorkspace with the conversation's ID
        #expect(
            chatViewSource.contains("appState.setConversationWorkspace(id: conversation.id, url:") ||
            chatViewSource.contains("appState.setConversationWorkspace(id:")
        )

        // Must not merely call setSandboxDirectory directly
        #expect(!chatViewSource.contains("onSelectProject: appState.setSandboxDirectory"))

        // Finder and Terminal actions must target the same conversation-specific
        // workspace displayed by the composer, not stale global workspace state.
        #expect(chatViewSource.contains("appState.openWorkspaceInFinder(workspaceURL)"))
        #expect(chatViewSource.contains("appState.openWorkspaceInTerminal(workspaceURL)"))
    }

    @Test("ChatView forwards agent preview visibility, availability, enabled state, and toggle to PromptInputBar")
    func testChatViewForwardsAgentPreviewState() throws {
        let chatViewSource = try readSource("Sources/QwenPrime/Views/Chat/ChatView.swift")

        #expect(chatViewSource.contains("isAgentPreviewVisible: appState.isAgentPreviewEnabled") || chatViewSource.contains("isAgentPreviewVisible:"))
        #expect(chatViewSource.contains("isAgentPreviewAvailable: appState.canEnableAgentMode(for: conversation.id)") || chatViewSource.contains("isAgentPreviewAvailable:"))
        #expect(chatViewSource.contains("isAgentPreviewEnabled: appState.isAgentModeEnabled(for: conversation.id)") || chatViewSource.contains("isAgentPreviewEnabled:"))
        #expect(chatViewSource.contains("onToggleAgentPreview:") || chatViewSource.contains("appState.setAgentMode("))
    }

    // MARK: - Contract (3): PromptInputBar Agent Preview State, Layout, & Behavior

    @Test("PromptInputBar accepts explicit agent preview visibility, availability, enabled state, and toggle action")
    func testPromptInputBarDeclaresAgentPreviewParameters() throws {
        let promptBarSource = try readSource("Sources/QwenPrime/Views/Chat/PromptInputBar.swift")

        #expect(promptBarSource.contains("isAgentPreviewVisible: Bool"))
        #expect(promptBarSource.contains("isAgentPreviewAvailable: Bool"))
        #expect(promptBarSource.contains("isAgentPreviewEnabled: Bool"))
        #expect(promptBarSource.contains("onToggleAgentPreview: () -> Void") || promptBarSource.contains("onToggleAgentPreview: (() -> Void)?"))
    }

    @Test("PromptInputBar hides agent preview control when preview feature flag is disabled")
    func testPromptInputBarHidesControlWhenFeatureDisabled() throws {
        let promptBarSource = try readSource("Sources/QwenPrime/Views/Chat/PromptInputBar.swift")

        #expect(
            promptBarSource.contains("if isAgentPreviewVisible") ||
            promptBarSource.contains("if isAgentPreviewVisible {")
        )
    }

    @Test("PromptInputBar disables agent preview control with helpful tooltip when capability or workspace is unavailable")
    func testPromptInputBarDisabledWithHelpWhenUnavailable() throws {
        let promptBarSource = try readSource("Sources/QwenPrime/Views/Chat/PromptInputBar.swift")

        // Must disable when capability/workspace unavailable or streaming
        #expect(
            promptBarSource.contains(".disabled(!isAgentPreviewAvailable || isStreaming)") ||
            promptBarSource.contains(".disabled(!isAgentPreviewAvailable") ||
            promptBarSource.contains("!isAgentPreviewAvailable")
        )

        // Must provide informative help explaining requirements or active mode
        #expect(
            promptBarSource.contains("Agent Mode Preview") ||
            promptBarSource.contains("Agent preview") ||
            promptBarSource.contains("structured tool") ||
            promptBarSource.contains("workspace required")
        )
    }

    @Test("PromptInputBar renders agent preview as an accessible compact capsule with icon, word Agent, and fixed stable sizing")
    func testPromptInputBarAgentCapsuleLayoutAndAccessibility() throws {
        let promptBarSource = try readSource("Sources/QwenPrime/Views/Chat/PromptInputBar.swift")

        // 1. Capsule container styling
        #expect(promptBarSource.contains("Capsule()"))

        // 2. Word "Agent" displayed in label
        #expect(promptBarSource.contains("Text(\"Agent\")"))

        // 3. Fixed stable sizing matching toolbar height
        #expect(promptBarSource.contains("DesignTokens.Layout.toolbarControlHeight"))

        // 4. Accessibility identifier and label
        #expect(
            promptBarSource.contains("chat_agent_preview_toggle") ||
            promptBarSource.contains("chat_agent_toggle")
        )
        #expect(
            promptBarSource.contains(".accessibilityLabel(") &&
            (promptBarSource.contains("Agent mode") || promptBarSource.contains("Agent preview"))
        )

        // 5. Reasoning toggle remains independent
        #expect(promptBarSource.contains("chat_reasoning_toggle"))
        #expect(promptBarSource.contains("isThinkingEnabled.toggle()"))
    }

    // MARK: - Contract (4): General Settings Workspace Agent Preview Toggle & Capability Communication

    @Test("General settings includes Workspace Agent Preview toggle bound to appState.isAgentPreviewEnabled")
    func testGeneralSettingsAgentPreviewToggleBinding() throws {
        let settingsSource = try readSource("Sources/QwenPrime/Views/Settings/SettingsView.swift")

        #expect(
            settingsSource.contains("Toggle(\"Workspace Agent Preview\", isOn: $appState.isAgentPreviewEnabled)") ||
            settingsSource.contains("Toggle(\"Enable Workspace Agent Preview\", isOn: $appState.isAgentPreviewEnabled)") ||
            settingsSource.contains("isOn: $appState.isAgentPreviewEnabled")
        )
    }

    @Test("Settings exposes Agent and Direct defaults for new conversations")
    func testNewConversationDefaultModeToggles() throws {
        let settingsSource = try readSource("Sources/QwenPrime/Views/Settings/SettingsView.swift")

        #expect(settingsSource.contains("Use Agent mode for new conversations"))
        #expect(settingsSource.contains("$appState.defaultAgentModeEnabled"))
        #expect(settingsSource.contains("Use direct mode for new conversations"))
        #expect(settingsSource.contains("$appState.defaultDirectModeEnabled"))
    }


    @Test("General settings explains reviewed file proposals and absence of shell execution")
    func testGeneralSettingsExplainsReviewedChangesAndNoShell() throws {
        let settingsSource = try readSource("Sources/QwenPrime/Views/Settings/SettingsView.swift")

        let lower = settingsSource.lowercased()
        #expect(lower.contains("shell") && lower.contains("unavailable"))
        #expect(lower.contains("diff") && lower.contains("apply") && lower.contains("reject"))
        #expect(lower.contains("pauses") && lower.contains("resumes"))
    }

    @Test("General settings communicates runtime structured tool capability state without blocking ordinary chat")
    func testGeneralSettingsCommunicatesRuntimeCapabilityAndChatStability() throws {
        let settingsSource = try readSource("Sources/QwenPrime/Views/Settings/SettingsView.swift")

        // Must reference runtime capability state
        #expect(
            settingsSource.contains("runtimeSupportsStructuredToolCalls") ||
            settingsSource.contains("Structured tool") ||
            settingsSource.contains("Tool capability") ||
            settingsSource.contains("Runtime tool support")
        )

        // Must clarify that ordinary chat remains unaffected
        let lower = settingsSource.lowercased()
        #expect(
            lower.contains("ordinary chat") ||
            lower.contains("standard chat") ||
            lower.contains("chat remains") ||
            lower.contains("chat is unaffected")
        )
    }

    @Test("General settings reports the independent Swift harness readiness")
    func testGeneralSettingsCommunicatesHarnessReadiness() throws {
        let settingsSource = try readSource("Sources/QwenPrime/Views/Settings/SettingsView.swift")

        #expect(settingsSource.contains("appState.workspaceHarnessReady"))
        #expect(settingsSource.contains("Swift build and test harness passed its sandbox self-test."))
        #expect(settingsSource.contains("file tools remain enabled"))
    }

    @Test("General settings exposes guarded local MCP configuration")
    func testGeneralSettingsExposesLocalMCPConfiguration() throws {
        let settingsSource = try readSource("Sources/QwenPrime/Views/Settings/SettingsView.swift")

        #expect(settingsSource.contains("Local MCP Server"))
        #expect(settingsSource.contains("$appState.isMCPServerEnabled"))
        #expect(settingsSource.contains("$appState.mcpServerDisplayName"))
        #expect(settingsSource.contains("$appState.mcpServerEndpoint"))
        #expect(settingsSource.contains("localhost only"))
        #expect(settingsSource.contains("Allow Once"))
        #expect(settingsSource.contains("does not receive the workspace path"))
    }

    // MARK: - Contract (5): ToolExecutionCard Semantic Presentation for Workspace Read

    @Test("ToolExecutionCard removes hardcoded terminal icon and Sandbox Action label")
    func testToolExecutionCardRemovesTerminalIconAndSandboxActionLabel() throws {
        let cardSource = try readSource("Sources/QwenPrime/Views/Chat/ToolExecutionCard.swift")

        // Must not contain terminal icon
        #expect(!cardSource.contains("terminal.fill"))
        #expect(!cardSource.contains("\"terminal\""))

        // Must not contain "Sandbox Action"
        #expect(!cardSource.contains("Sandbox Action"))
    }

    @Test("ToolExecutionCard presents workspace read semantically while retaining tool name, status, and output")
    func testToolExecutionCardPresentsWorkspaceReadSemantically() throws {
        let cardSource = try readSource("Sources/QwenPrime/Views/Chat/ToolExecutionCard.swift")

        // 1. Must present semantically as Workspace Read
        #expect(cardSource.contains("Workspace Read"))

        // 2. Retains tool name
        #expect(cardSource.contains("execution.toolName"))

        // 3. Retains status indicator (running progress, success, failure)
        #expect(cardSource.contains("execution.isRunning"))
        #expect(cardSource.contains("execution.isSuccess"))

        // 4. Retains input and output
        #expect(cardSource.contains("execution.input"))
        #expect(cardSource.contains("execution.output"))
    }

    @Test("Tool approval floats above the composer instead of living inside transcript cards")
    func testToolApprovalOverlayContract() throws {
        let cardSource = try readSource("Sources/QwenPrime/Views/Chat/ToolExecutionCard.swift")
        let messageSource = try readSource("Sources/QwenPrime/Views/Chat/MessageBubble.swift")
        let chatSource = try readSource("Sources/QwenPrime/Views/Chat/ChatView.swift")
        let reviewSource = try readSource("Sources/QwenPrime/Views/Chat/FloatingMutationReview.swift")

        #expect(!cardSource.contains("mutationProposal.preview"))
        #expect(!cardSource.contains("Button(\"Apply\""))
        #expect(!messageSource.contains("onApproveMutation"))
        #expect(reviewSource.contains("case .mutation(let proposal): proposal.preview"))
        #expect(reviewSource.contains("case .command(let proposal): proposal.preview"))
        #expect(reviewSource.contains("Button(approveTitle"))
        #expect(reviewSource.contains("Button(\"Reject\""))
        #expect(chatSource.contains("FloatingToolApprovalReview"))
        #expect(chatSource.contains("approvalCoordinator.pendingRequests"))
        #expect(chatSource.contains("resolveWorkspaceApproval"))
        #expect(reviewSource.contains("Agent paused"))
    }

    @Test("Command approvals and transcript cards use command-specific language")
    func testCommandApprovalPresentation() throws {
        let reviewSource = try readSource("Sources/QwenPrime/Views/Chat/FloatingMutationReview.swift")
        let cardSource = try readSource("Sources/QwenPrime/Views/Chat/ToolExecutionCard.swift")

        #expect(reviewSource.contains("Review command"))
        #expect(reviewSource.contains("isWorkspaceTask ? \"Run Task\" : \"Run\""))
        #expect(reviewSource.contains("sandboxed helper"))
        #expect(cardSource.contains("Workspace Command"))
        #expect(cardSource.contains("isWorkspaceCommand"))
    }

    @Test("Structured task approvals and transcript cards use task-specific language")
    func testTaskApprovalPresentation() throws {
        let reviewSource = try readSource("Sources/QwenPrime/Views/Chat/FloatingMutationReview.swift")
        let cardSource = try readSource("Sources/QwenPrime/Views/Chat/ToolExecutionCard.swift")

        #expect(reviewSource.contains("Review task"))
        #expect(reviewSource.contains("network-isolated build environment"))
        #expect(reviewSource.contains("Run Task"))
        #expect(cardSource.contains("Workspace Task"))
        #expect(cardSource.contains("isWorkspaceTask"))
    }

    // MARK: - Contract (6): Sandbox Settings Accurate Claims & Guardrail Explanations

    @Test("Sandbox settings removes false IPython sandbox execution claim")
    func testSandboxSettingsRemovesIPythonSandboxClaim() throws {
        let settingsSource = try readSource("Sources/QwenPrime/Views/Settings/SettingsView.swift")

        #expect(!settingsSource.contains("IPython sandbox execution"))
        #expect(!settingsSource.contains("IPython sandbox execution with stdout/stderr capture"))
    }

    @Test("Sandbox settings accurately explains ordinary chat file isolation and workspace scoping")
    func testSandboxSettingsExplainsFileIsolationAndWorkspaceScoping() throws {
        let settingsSource = try readSource("Sources/QwenPrime/Views/Settings/SettingsView.swift")

        let lower = settingsSource.lowercased()
        // Ordinary chat does not read files
        #expect(
            lower.contains("ordinary chat") && (lower.contains("not read") || lower.contains("does not read") || lower.contains("does not access"))
        )

        // Preview reads only the selected workspace
        #expect(
            lower.contains("selected workspace") || lower.contains("workspace folder") || lower.contains("only the active workspace")
        )
    }

    @Test("Sandbox settings explains blocked secret paths, reviewed changes, and no shell")
    func testSandboxSettingsExplainsSecretBlockingAndReviewedChanges() throws {
        let settingsSource = try readSource("Sources/QwenPrime/Views/Settings/SettingsView.swift")

        let lower = settingsSource.lowercased()
        // Secret/key paths blocked
        #expect(
            (lower.contains("secret") || lower.contains(".git") || lower.contains(".env") || lower.contains("key")) &&
            (lower.contains("blocked") || lower.contains("denied") || lower.contains("protected") || lower.contains("restricted"))
        )

        #expect(lower.contains("diff") && lower.contains("apply") && lower.contains("reject"))
        #expect(lower.contains("shell") && lower.contains("unavailable"))
    }

    // MARK: - Contract (7): Accessibility & Reduced Motion Preservation

    @Test("Compact and icon-only controls provide accessibility labels and help text")
    func testCompactControlsAccessibilityAndHelp() throws {
        let promptBarSource = try readSource("Sources/QwenPrime/Views/Chat/PromptInputBar.swift")

        // Prompt input accessibility
        #expect(promptBarSource.contains(".accessibilityIdentifier(\"chat_input\")"))

        // Reasoning toggle accessibility & help
        #expect(promptBarSource.contains(".accessibilityIdentifier(\"chat_reasoning_toggle\")"))
        #expect(promptBarSource.contains(".accessibilityLabel("))
        #expect(promptBarSource.contains(".help("))

        // Send & Stop buttons accessibility & help
        #expect(promptBarSource.contains(".accessibilityIdentifier(\"chat_send_button\")"))
        #expect(promptBarSource.contains(".accessibilityIdentifier(\"chat_stop_button\")"))
    }

    @Test("Interactive views respect accessibility reduce motion")
    func testAccessibilityReduceMotionPreservation() throws {
        let chatViewSource = try readSource("Sources/QwenPrime/Views/Chat/ChatView.swift")
        let promptBarSource = try readSource("Sources/QwenPrime/Views/Chat/PromptInputBar.swift")
        let toolCardSource = try readSource("Sources/QwenPrime/Views/Chat/ToolExecutionCard.swift")

        // ChatView declares and respects reduceMotion
        #expect(chatViewSource.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        #expect(chatViewSource.contains("reduceMotion ? nil :"))

        // PromptInputBar declares and respects reduceMotion
        #expect(promptBarSource.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        #expect(promptBarSource.contains("reduceMotion ? nil :"))

        // Tool card expansion also respects Reduce Motion.
        #expect(toolCardSource.contains("@Environment(\\.accessibilityReduceMotion) private var reduceMotion"))
        #expect(toolCardSource.contains("reduceMotion ? nil :"))
    }

    // MARK: - Contract (8): Settings About Dynamic Version

    @Test("Settings About version comes dynamically from Bundle CFBundleShortVersionString and contains no hardcoded 1.0.0")
    func testSettingsAboutVersionContract() throws {
        let settingsSource = try readSource("Sources/QwenPrime/Views/Settings/SettingsView.swift")

        // 1. SettingsView must NOT contain hardcoded "1.0.0"
        #expect(!settingsSource.contains("Text(\"1.0.0"))
        #expect(!settingsSource.contains("\"1.0.0 (Apple Silicon Native)\""))

        // 2. SettingsView must reference CFBundleShortVersionString from Bundle
        #expect(settingsSource.contains("CFBundleShortVersionString"))
    }
}
