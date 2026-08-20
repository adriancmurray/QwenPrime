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

    @Test("AppState without services uses non-persisting storage unless explicitly injected")
    @MainActor
    func testServiceDisabledAppStateDoesNotUseProductionStorage() async throws {
        let appState = AppState(startServices: false)
        #expect(await appState.storage.isPersistenceEnabled == false)

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ExplicitStorage-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let explicitStorage = StorageService(directoryURL: root)
        let explicitAppState = AppState(startServices: false, storage: explicitStorage)
        #expect(await explicitAppState.storage.isPersistenceEnabled == true)
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
        #expect(chatView.contains("NoConversationSelectedView("))
        #expect(!chatView.contains("ContentUnavailableView("))
        #expect(chatView.contains("onCreateConversation"))
        #expect(chatView.contains("AppCommands.newConversation.helpWithShortcut"))
        #expect(chatView.contains("isNewConversationHighlighted"))
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

    @Test("Completed generation cleanup allows another run in the same conversation")
    @MainActor
    func testGenerationRunCleanupAllowsNextRun() async throws {
        let suiteName = "GenerationRunCleanup.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let scope = MockSSEScope { request in
            let responseURL = request.url ?? URL(fileURLWithPath: "/")
            let response = try #require(
                MockHTTPResponseFactory.makeEventStreamResponse(
                    url: responseURL
                )
            )
            return (
                response,
                MockSSEFormatting.formatSSEPayload(
                    contentChunks: ["Completed response"]
                )
            )
        }
        defer { scope.tearDown() }
        let conversation = Conversation(title: "Sequential runs")
        let appState = AppState(
            baseURL: scope.baseURL,
            startServices: false,
            userDefaults: defaults
        )
        appState.serverStatus = .connected(model: "test", latencyMs: 1)
        appState.conversations = [conversation]
        appState.selectedConversationId = conversation.id
        let viewModel = ChatViewModel(
            client: QwenClient(session: scope.session)
        )

        for prompt in ["First run", "Second run"] {
            viewModel.inputText = prompt
            viewModel.sendMessage(appState: appState)
            try await AsyncCondition.wait(
                description: "\(prompt) cleanup"
            ) {
                !appState.isConversationGenerating(conversation.id)
            }
        }

        let messages = try #require(appState.selectedConversation?.messages)
        #expect(messages.map(\.role) == [.user, .assistant, .user, .assistant])
        #expect(messages[0].content == "First run")
        #expect(messages[2].content == "Second run")
        #expect(messages[1].content == "Completed response")
        #expect(messages[3].content == "Completed response")
        #expect(!appState.isGenerating)
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

    @Test("Composer uses measured safe-area layout without fixed clearance")
    func testMeasuredComposerLayout() throws {
        let chatView = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Chat/ChatView.swift"),
            encoding: .utf8
        )

        #expect(chatView.contains(".safeAreaInset(edge: .bottom, spacing: 0)"))
        #expect(chatView.contains("conversationControls(for: conversation)"))
        #expect(!chatView.contains("DesignTokens.Layout.composerScrollClearance"))
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
        #expect(
            quickSettings.contains("SettingsSectionLabel(title: \"Appearance\")")
        )
        #expect(
            quickSettings.contains("SettingsSectionLabel(title: \"Conversation\")")
        )
        #expect(
            quickSettings.contains("SettingsSectionLabel(title: \"Runtime\")")
        )
        #expect(quickSettings.contains("Text(runtimeModelSummary)"))
        let modelFallback =
            "appState.activeModelProfile?.displaySummary"
            + " ?? AppPreferences.defaultModel"
        #expect(
            quickSettings.contains(modelFallback)
        )
        #expect(
            quickSettings.contains(
                ".accessibilityLabel(runtimeAccessibilityLabel)"
            )
        )
        #expect(!quickSettings.contains("Qwen 3.8 27B"))
    }

    @Test("Split-view background remains continuous through the sidebar divider")
    func testSplitViewOwnsSharedBackground() throws {
        let splitView = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/MainSplitView.swift"),
            encoding: .utf8
        )

        #expect(
            splitView.contains(
                ".toolbarBackgroundVisibility(.hidden, for: .windowToolbar)"
            )
        )
        #expect(
            splitView.contains("if #available(macOS 15.0, *)")
        )
        #expect(!splitView.contains("IconActionButton("))
        #expect(!splitView.contains(".toolbar(removing: .sidebarToggle)"))
    }

    @Test("Sidebar selection and actions use the active theme tint")
    func testSidebarUsesActiveThemeTint() throws {
        let sidebar = try String(
            contentsOf: sourceFile(
                "Sources/QwenPrime/Views/Sidebar/SidebarView.swift"
            ),
            encoding: .utf8
        )
        let conversationRow = try String(
            contentsOf: sourceFile(
                "Sources/QwenPrime/Views/Sidebar/ConversationRow.swift"
            ),
            encoding: .utf8
        )

        #expect(sidebar.contains("appState.activeTheme.h1"))
        #expect(sidebar.contains("private func projectScopeChip"))
        #expect(sidebar.contains("ProjectScope.displayName(for: appState.sandboxDirectory)"))
        #expect(sidebar.contains("themeTint.opacity(DesignTokens.Opacity.hover)"))
        #expect(!sidebar.contains(".pickerStyle(.segmented)"))
        #expect(!sidebar.contains("List(selection:"))
        #expect(!sidebar.contains(".listRowBackground("))
        #expect(sidebar.contains("DesignTokens.Layout.sidebarContentInset"))
        #expect(sidebar.contains("ScrollView"))
        #expect(sidebar.contains("LazyVStack(alignment: .leading"))
        #expect(sidebar.contains(".accessibilityIdentifier(\"conversation_list\")"))
        #expect(!sidebar.contains(".listRowInsets("))
        #expect(sidebar.contains("HStack(spacing: DesignTokens.Spacing.sm)"))
        #expect(!sidebar.contains("Color.accentColor"))
        #expect(conversationRow.contains("public let themeTint: Color"))
        #expect(conversationRow.contains("isSelected ? themeTint : Color.secondary"))
        #expect(conversationRow.contains("public let onSelect: () -> Void"))
        #expect(conversationRow.contains("Button(action: onSelect)"))
        #expect(conversationRow.contains(".frame(maxWidth: .infinity, alignment: .leading)"))
        #expect(conversationRow.contains(".fill(isSelected ? themeTint.opacity(0.24)"))
        #expect(!conversationRow.contains("Color.accentColor"))
        #expect(!conversationRow.contains("Menu {"))
        #expect(!conversationRow.contains(".contextMenu"))
        #expect(conversationRow.contains("ConversationActionPopover("))
        #expect(conversationRow.contains("Text(presentation.timestamp)"))
        #expect(conversationRow.contains("conversationActionButton"))
        #expect(conversationRow.contains("Spacer(minLength: DesignTokens.Spacing.xs)"))
        let actionPopover = try String(
            contentsOf: sourceFile(
                "Sources/QwenPrime/Views/Sidebar/ConversationRowActions.swift"
            ),
            encoding: .utf8
        )
        let themedPopoverRow = try String(
            contentsOf: sourceFile(
                "Sources/QwenPrime/Views/Shared/ThemedPopoverActionRow.swift"
            ),
            encoding: .utf8
        )
        #expect(actionPopover.contains("VStack(spacing: 0)"))
        #expect(actionPopover.contains(".padding(DesignTokens.Spacing.xxs)"))
        #expect(actionPopover.contains("ThemedPopoverActionRow("))
        #expect(
            themedPopoverRow.contains(
                ".frame(width: DesignTokens.Layout.popoverActionIconWidth)"
            )
        )
        #expect(themedPopoverRow.contains("isSelected || isHovered || isFocused"))
    }

    @Test("Composer uses shared human-readable workspace names")
    func testComposerUsesSharedWorkspaceDisplayName() throws {
        let promptInput = try String(
            contentsOf: sourceFile(
                "Sources/QwenPrime/Views/Chat/PromptInputBar.swift"
            ),
            encoding: .utf8
        )

        #expect(promptInput.contains("ProjectScope.displayName(for: sandboxURL)"))
        #expect(promptInput.contains("ProjectScope.displayName(for: project)"))
        #expect(promptInput.contains("Text(workspaceDisplayName)"))
        #expect(promptInput.contains(".accessibilityValue(workspaceDisplayName)"))
        #expect(!promptInput.contains("sandboxURL.lastPathComponent"))
        #expect(!promptInput.contains("project.lastPathComponent"))
        #expect(!promptInput.contains("Menu {"))
        #expect(promptInput.contains("workspacePickerPopover"))
        #expect(!promptInput.contains(".frame(maxWidth: 220)"))
        #expect(promptInput.contains("ViewThatFits(in: .horizontal)"))
    }

    @Test("Sidebar settings control is text-only")
    func testSidebarSettingsControlHasNoContainer() throws {
        let sidebar = try String(
            contentsOf: sourceFile(
                "Sources/QwenPrime/Views/Sidebar/SidebarView.swift"
            ),
            encoding: .utf8
        )
        let footerStart = try #require(sidebar.range(of: "// 5. Footer"))
        let footer = String(sidebar[footerStart.lowerBound...])

        #expect(footer.contains("Label(\"Settings\", systemImage: \"gearshape\")"))
        #expect(!footer.contains("DesignTokens.Surface.subtle"))
        #expect(!footer.contains("toolbarControlHeight"))
        #expect(footer.contains(".accessibilityLabel(\"Settings and themes\")"))
    }

    @Test("Two-line row icons stay on their title lines")
    func testTwoLineRowIconsStayOnTitleLines() throws {
        let promptSettings = try String(
            contentsOf: sourceFile(
                "Sources/QwenPrime/Views/Settings/SystemPromptSettingsTab.swift"
            ),
            encoding: .utf8
        )
        let conversationRow = try String(
            contentsOf: sourceFile(
                "Sources/QwenPrime/Views/Sidebar/ConversationRow.swift"
            ),
            encoding: .utf8
        )

        #expect(promptSettings.contains("Image(systemName: preset.icon)"))
        #expect(
            promptSettings.contains(
                "18 + DesignTokens.Spacing.xs"
            )
        )
        #expect(
            promptSettings.contains(
                "24 + DesignTokens.Spacing.md"
            )
        )
        #expect(conversationRow.contains("private var conversationIcon"))
        #expect(
            conversationRow.contains(
                "15 + DesignTokens.Spacing.sm"
            )
        )
    }

    @Test("Quick runtime settings separate state, profile, and updates")
    func testQuickRuntimeHierarchy() throws {
        let quickSettings = try String(
            contentsOf: sourceFile(
                "Sources/QwenPrime/Views/Chat/QuickSettingsPopover.swift"
            ),
            encoding: .utf8
        )

        #expect(quickSettings.contains("runtimeStatusRow"))
        #expect(quickSettings.contains("runtimeProfileSelector"))
        #expect(quickSettings.contains("runtimeUpdateAction"))
        #expect(quickSettings.contains("Text(\"Local Runtime\")"))
        #expect(quickSettings.contains("Text(runtimeModelSummary)"))
        #expect(quickSettings.contains("private var runtimeStatusDetail"))
        #expect(quickSettings.contains(".primeGlassSurface("))
        #expect(quickSettings.contains("Text(\"Tune this chat.\")"))
        #expect(quickSettings.contains(".lineLimit(1)"))
        #expect(!quickSettings.contains("Tune this workspace without leaving the chat."))
        #expect(!quickSettings.contains("tint: appState.activeTheme.h1"))
        #expect(quickSettings.contains("private var runtimeCardShape"))
        #expect(
            quickSettings.contains(
                "minHeight: DesignTokens.Layout.quickSettingsControlHeight"
            )
        )
        #expect(quickSettings.contains("private var runtimeProfilePicker: some View"))
        #expect(quickSettings.contains(".popover("))
        #expect(quickSettings.contains("isRuntimeProfilePickerPresented = true"))
        #expect(!quickSettings.contains("Menu {"))
        #expect(!quickSettings.contains("chevron.up.chevron.down"))
        #expect(quickSettings.contains("title: profile.displaySummary"))
        #expect(!quickSettings.contains("profile.name"))
        #expect(quickSettings.contains("ThemedPopoverActionRow("))
        #expect(quickSettings.contains("ThemedPopoverSectionTitle(\"Runtime Profile\")"))
        #expect(quickSettings.contains("Text(runtimeModelSummary)"))
        #expect(quickSettings.contains(".background(appState.activeTheme.h1.opacity(0.14), in: Circle())"))
        #expect(
            quickSettings.components(
                separatedBy: ".frame(minHeight: DesignTokens.Layout.quickSettingsControlHeight)"
            ).count == 2
        )
        #expect(
            quickSettings.components(separatedBy: "in: runtimeCardShape").count == 3
        )
        #expect(!quickSettings.contains("ZStack(alignment: .bottomTrailing)"))
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
        let chat = try String(
            contentsOf: sourceFile("Sources/QwenPrime/Views/Chat/ChatView.swift"),
            encoding: .utf8
        )

        #expect(sidebar.contains("appState.openSettings(tab: tab)"))
        #expect(quickSettings.contains("onOpenSettings(.systemPrompts)"))
        #expect(quickSettings.contains("onOpenSettings(.engine)"))
        #expect(!quickSettings.contains("appState.settingsSelection ="))
        #expect(chat.contains("appState.openSettings(tab: .engine)"))
        #expect(!chat.contains("appState.settingsSelection ="))
        #expect(settings.contains("SettingsTabBar("))
        #expect(settings.contains("selection: $appState.settingsSelection"))
        #expect(quickSettings.contains("appState.toggleEngine()"))
        #expect(quickSettings.contains("appState.runtimeLifecycleAction.title"))
        #expect(!quickSettings.contains("appState.stopEngine()"))
        #expect(!quickSettings.contains("appState.startEngine()"))
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
        let actions = try String(
            contentsOf: sourceFile(
                "Sources/QwenPrime/Views/Sidebar/ConversationRowActions.swift"
            ),
            encoding: .utf8
        )

        #expect(ConversationActions.delete.accessibilityLabel == "Delete conversation")
        #expect(ConversationActions.duplicate.accessibilityLabel == "Duplicate conversation")
        #expect(actions.contains("Image(systemName: ConversationActions.delete.systemImage)"))
        #expect(actions.contains("Image(systemName: ConversationActions.duplicate.systemImage)"))
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
        let releaseApp = try String(
            contentsOf: sourceFile("release_app.command"),
            encoding: .utf8
        )

        #expect(publisher.contains("SPARKLE_ACCOUNT"))
        #expect(publisher.contains("generate_keys"))
        #expect(!publisher.contains("SPARKLE_PRIVATE_KEY"))
        #expect(publisher.contains("generate_appcast"))
        #expect(publisher.contains("--account \"$SPARKLE_ACCOUNT\""))
        #expect(publisher.contains("-o \"$RELEASE_DIR/appcast.xml\""))
        #expect(publisher.contains("gh release create"))
        #expect(publisher.contains("release_preflight.command"))
        #expect(preflight.contains("status --porcelain"))
        #expect(preflight.contains("--publish"))
        #expect(preflight.contains("generate_keys"))
        #expect(!preflight.contains("SPARKLE_PRIVATE_KEY"))
        #expect(preflight.contains("APPLE_ID"))
        #expect(preflight.contains("APPLE_TEAM_ID"))
        #expect(preflight.contains("NOTARY_APP_PASSWORD"))
        #expect(releaseApp.contains("--apple-id \"$APPLE_ID\""))
        #expect(releaseApp.contains("--team-id \"$APPLE_TEAM_ID\""))
        #expect(releaseApp.contains("--password \"$NOTARY_APP_PASSWORD\""))
        #expect(releaseApp.contains("shasum -a 256 \"$ARCHIVE_NAME\""))
        #expect(!releaseApp.contains("shasum -a 256 \"$ARCHIVE\""))
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
        let engineSettingsSource = try String(
            contentsOf: sourceFile(
                "Sources/QwenPrime/Views/Settings/EngineSettingsTab.swift"
            ),
            encoding: .utf8
        )

        #expect(appStateSource.contains("runtimeSetupStatus == .ready"))
        #expect(settingsSource.contains("EngineSettingsTab(appState: appState)"))
        #expect(engineSettingsSource.contains("Choose Target…"))
        #expect(engineSettingsSource.contains("Choose Draft…"))
        #expect(engineSettingsSource.contains("Save & Validate"))
        #expect(!engineSettingsSource.contains("DFlash 4K-Trained Q8"))
        #expect(!engineSettingsSource.contains("35–42 tok/s"))
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

        #expect(accordion.contains("isStreaming: isStreaming"))
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
        #expect(quickSettings.contains("appState.toggleEngine()"))
        #expect(quickSettings.contains("appState.runtimeLifecycleAction.title"))
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
