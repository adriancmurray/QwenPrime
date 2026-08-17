import Testing
import Foundation
@testable import QwenPrime

@Suite("AppState Agent Preview State Integration Tests")
struct AppStateAgentPreviewTests {

    private func makeTestDefaults() throws -> (UserDefaults, String) {
        let suiteName = "QwenPrimeTests-AppStatePreview-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        return (defaults, suiteName)
    }

    // MARK: - Feature Flag & UserDefaults Persistence

    @Test("Agent preview feature flag defaults to false and persists in injected UserDefaults suite")
    @MainActor
    func testAgentPreviewFeatureFlagPersistence() throws {
        let (defaults, suiteName) = try makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        // 1. Fresh instance with empty defaults -> defaults to false
        let appState = AppState(startServices: false, userDefaults: defaults)
        #expect(appState.isAgentPreviewEnabled == false)

        // 2. Enabling feature flag updates the in-memory state and persists to injected defaults
        appState.isAgentPreviewEnabled = true
        #expect(appState.isAgentPreviewEnabled == true)

        // 3. Re-instantiating AppState with same defaults reads persisted true state
        let reloadedAppState = AppState(startServices: false, userDefaults: defaults)
        #expect(reloadedAppState.isAgentPreviewEnabled == true)

        // 4. Disabling persists false back to defaults
        reloadedAppState.isAgentPreviewEnabled = false
        #expect(reloadedAppState.isAgentPreviewEnabled == false)

        let thirdAppState = AppState(startServices: false, userDefaults: defaults)
        #expect(thirdAppState.isAgentPreviewEnabled == false)
    }

    // MARK: - Runtime Structured Tool Calls Capability

    @Test("Runtime structured tool calls capability defaults to false and tracks capability updates")
    @MainActor
    func testRuntimeStructuredToolCallsCapabilityState() throws {
        let (defaults, suiteName) = try makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(startServices: false, userDefaults: defaults)
        #expect(appState.runtimeSupportsStructuredToolCalls == false)

        appState.runtimeSupportsStructuredToolCalls = true
        #expect(appState.runtimeSupportsStructuredToolCalls == true)

        appState.runtimeSupportsStructuredToolCalls = false
        #expect(appState.runtimeSupportsStructuredToolCalls == false)
    }

    // MARK: - Transient Agent Mode & Non-Persistence

    @Test("Agent mode is a transient in-memory per-conversation ID set and never persists")
    @MainActor
    func testAgentModeIsTransientPerConversationAndNeverPersists() throws {
        let (defaults, suiteName) = try makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(startServices: false, userDefaults: defaults)
        appState.isAgentPreviewEnabled = true
        appState.runtimeSupportsStructuredToolCalls = true

        let conv1 = Conversation(
            title: "Project Alpha",
            projectPath: appState.sandboxDirectory.path
        )
        let conv2 = Conversation(
            title: "Project Beta",
            projectPath: appState.sandboxDirectory.path
        )
        appState.conversations = [conv1, conv2]

        // Initially no conversation has agent mode enabled
        #expect(appState.isAgentModeEnabled(for: conv1.id) == false)
        #expect(appState.isAgentModeEnabled(for: conv2.id) == false)

        // Enable agent mode for conv1 only
        appState.setAgentMode(true, for: conv1.id)
        #expect(appState.isAgentModeEnabled(for: conv1.id) == true)
        #expect(appState.isAgentModeEnabled(for: conv2.id) == false)

        // Verify agent mode is NOT stored in UserDefaults
        let allKeys = defaults.dictionaryRepresentation().keys
        for key in allKeys {
            #expect(!key.contains(conv1.id.uuidString))
        }

        // A new AppState instance with the same defaults has no transient agent mode selected
        let freshAppState = AppState(startServices: false, userDefaults: defaults)
        freshAppState.conversations = [conv1, conv2]
        #expect(freshAppState.isAgentModeEnabled(for: conv1.id) == false)
        #expect(freshAppState.isAgentModeEnabled(for: conv2.id) == false)
    }

    // MARK: - Preconditions for Enabling Agent Mode

    @Test("External workspace requires a durable bookmark before Agent mode can run")
    @MainActor
    func testExternalWorkspaceRequiresDurableAuthorization() async throws {
        let (defaults, suiteName) = try makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let storageFixture = try TemporaryStorageFixture()
        defer { storageFixture.tearDown() }
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("agent-workspace-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let authorization = WorkspaceAuthorizationService(
            userDefaults: defaults,
            bookmarker: TestWorkspaceBookmarker(),
        scopeAccessor: TestWorkspaceSecurityScopeAccessor()
        )
        let appState = AppState(
            startServices: false,
            workspaceAuthorizationService: authorization,
            userDefaults: defaults,
            storage: storageFixture.storage
        )
        appState.isAgentPreviewEnabled = true
        appState.runtimeSupportsStructuredToolCalls = true
        let conversation = Conversation(title: "Authorized", projectPath: workspace.path)
        appState.conversations = [conversation]

        #expect(appState.canEnableAgentMode(for: conversation.id) == false)

        appState.setConversationWorkspace(id: conversation.id, url: workspace)
        #expect(appState.canEnableAgentMode(for: conversation.id) == true)
        #expect(appState.authorizedWorkspaceURL(for: conversation.id)?.path == workspace.path)

        let restored = AppState(
            startServices: false,
            workspaceAuthorizationService: WorkspaceAuthorizationService(
                userDefaults: defaults,
                bookmarker: TestWorkspaceBookmarker(),
            scopeAccessor: TestWorkspaceSecurityScopeAccessor()
            ),
            userDefaults: defaults,
            storage: storageFixture.storage
        )
        restored.isAgentPreviewEnabled = true
        restored.runtimeSupportsStructuredToolCalls = true
        restored.conversations = [conversation]
        #expect(restored.canEnableAgentMode(for: conversation.id) == true)
    }

    @Test("canEnableAgentMode requires preview enabled, runtime capability, existing conversation, and nonempty projectPath")
    @MainActor
    func testCanEnableAgentModePreconditions() throws {
        let (defaults, suiteName) = try makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(startServices: false, userDefaults: defaults)

        let validConv = Conversation(
            title: "Valid Workspace Chat",
            projectPath: appState.sandboxDirectory.path
        )
        let nilPathConv = Conversation(
            title: "No Workspace Chat",
            projectPath: nil
        )
        let emptyPathConv = Conversation(
            title: "Empty Path Chat",
            projectPath: ""
        )
        let whitespacePathConv = Conversation(
            title: "Whitespace Path Chat",
            projectPath: "   \t\n  "
        )
        appState.conversations = [validConv, nilPathConv, emptyPathConv, whitespacePathConv]

        // 1. Both flags false -> all false
        appState.isAgentPreviewEnabled = false
        appState.runtimeSupportsStructuredToolCalls = false
        #expect(appState.canEnableAgentMode(for: validConv.id) == false)
        #expect(appState.canEnableAgentMode(for: nilPathConv.id) == false)
        #expect(appState.canEnableAgentMode(for: emptyPathConv.id) == false)
        #expect(appState.canEnableAgentMode(for: whitespacePathConv.id) == false)

        // 2. Feature enabled, but runtime capability false -> false
        appState.isAgentPreviewEnabled = true
        appState.runtimeSupportsStructuredToolCalls = false
        #expect(appState.canEnableAgentMode(for: validConv.id) == false)

        // 3. Runtime capability true, but feature disabled -> false
        appState.isAgentPreviewEnabled = false
        appState.runtimeSupportsStructuredToolCalls = true
        #expect(appState.canEnableAgentMode(for: validConv.id) == false)

        // 4. Both feature and capability true:
        appState.isAgentPreviewEnabled = true
        appState.runtimeSupportsStructuredToolCalls = true

        // 4a. Valid conversation with nonempty projectPath -> TRUE
        #expect(appState.canEnableAgentMode(for: validConv.id) == true)

        // 4b. Nonexistent conversation ID -> FALSE
        #expect(appState.canEnableAgentMode(for: UUID()) == false)

        // 4c. Conversation with nil projectPath -> FALSE
        #expect(appState.canEnableAgentMode(for: nilPathConv.id) == false)

        // 4d. Conversation with empty projectPath -> FALSE
        #expect(appState.canEnableAgentMode(for: emptyPathConv.id) == false)

        // 4e. Conversation with whitespace-only projectPath -> FALSE
        #expect(appState.canEnableAgentMode(for: whitespacePathConv.id) == false)
    }

    // MARK: - Activation Refusal When Preconditions Fail

    @Test("setAgentMode(true, for:) refuses activation unless canEnableAgentMode is currently true")
    @MainActor
    func testSetAgentModeRefusesActivationUnlessCanEnable() throws {
        let (defaults, suiteName) = try makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(startServices: false, userDefaults: defaults)

        let validConv = Conversation(
            title: "Valid Workspace Chat",
            projectPath: appState.sandboxDirectory.path
        )
        let nilPathConv = Conversation(
            title: "No Workspace Chat",
            projectPath: nil
        )
        let emptyPathConv = Conversation(
            title: "Empty Path Chat",
            projectPath: ""
        )
        let whitespacePathConv = Conversation(
            title: "Whitespace Path Chat",
            projectPath: "   \t\n  "
        )
        appState.conversations = [validConv, nilPathConv, emptyPathConv, whitespacePathConv]

        // 1. Refuses activation when preview feature flag is disabled
        appState.isAgentPreviewEnabled = false
        appState.runtimeSupportsStructuredToolCalls = true
        #expect(appState.canEnableAgentMode(for: validConv.id) == false)
        appState.setAgentMode(true, for: validConv.id)
        #expect(appState.isAgentModeEnabled(for: validConv.id) == false)

        // 2. Refuses activation when runtime capability is disabled
        appState.isAgentPreviewEnabled = true
        appState.runtimeSupportsStructuredToolCalls = false
        #expect(appState.canEnableAgentMode(for: validConv.id) == false)
        appState.setAgentMode(true, for: validConv.id)
        #expect(appState.isAgentModeEnabled(for: validConv.id) == false)

        // 3. Refuses activation for invalid projectPath variants even when flags are enabled
        appState.isAgentPreviewEnabled = true
        appState.runtimeSupportsStructuredToolCalls = true

        #expect(appState.canEnableAgentMode(for: nilPathConv.id) == false)
        appState.setAgentMode(true, for: nilPathConv.id)
        #expect(appState.isAgentModeEnabled(for: nilPathConv.id) == false)

        #expect(appState.canEnableAgentMode(for: emptyPathConv.id) == false)
        appState.setAgentMode(true, for: emptyPathConv.id)
        #expect(appState.isAgentModeEnabled(for: emptyPathConv.id) == false)

        #expect(appState.canEnableAgentMode(for: whitespacePathConv.id) == false)
        appState.setAgentMode(true, for: whitespacePathConv.id)
        #expect(appState.isAgentModeEnabled(for: whitespacePathConv.id) == false)

        // 4. Refuses activation for nonexistent conversation ID
        let unknownId = UUID()
        #expect(appState.canEnableAgentMode(for: unknownId) == false)
        appState.setAgentMode(true, for: unknownId)
        #expect(appState.isAgentModeEnabled(for: unknownId) == false)

        // 5. Successfully activates when all preconditions hold
        #expect(appState.canEnableAgentMode(for: validConv.id) == true)
        appState.setAgentMode(true, for: validConv.id)
        #expect(appState.isAgentModeEnabled(for: validConv.id) == true)

        // 6. Explicit deactivation always succeeds
        appState.setAgentMode(false, for: validConv.id)
        #expect(appState.isAgentModeEnabled(for: validConv.id) == false)
    }

    // MARK: - Dynamic Invalidation on Runtime Capability Loss

    @Test("isAgentModeEnabled dynamically returns false and clears mode when runtime capability becomes false")
    @MainActor
    func testRuntimeCapabilityDropClearsAgentMode() throws {
        let (defaults, suiteName) = try makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(startServices: false, userDefaults: defaults)
        appState.isAgentPreviewEnabled = true
        appState.runtimeSupportsStructuredToolCalls = true

        let conv1 = Conversation(title: "Project Alpha", projectPath: appState.sandboxDirectory.path)
        let conv2 = Conversation(title: "Project Beta", projectPath: appState.sandboxDirectory.path)
        appState.conversations = [conv1, conv2]

        // Enable agent mode for both conversations
        appState.setAgentMode(true, for: conv1.id)
        appState.setAgentMode(true, for: conv2.id)
        #expect(appState.isAgentModeEnabled(for: conv1.id) == true)
        #expect(appState.isAgentModeEnabled(for: conv2.id) == true)

        // Runtime structured tool calls capability becomes false (e.g. backend disconnect or model switch)
        appState.runtimeSupportsStructuredToolCalls = false

        // isAgentModeEnabled dynamically returns false
        #expect(appState.canEnableAgentMode(for: conv1.id) == false)
        #expect(appState.canEnableAgentMode(for: conv2.id) == false)
        #expect(appState.isAgentModeEnabled(for: conv1.id) == false)
        #expect(appState.isAgentModeEnabled(for: conv2.id) == false)

        // Mode is cleared: restoring runtime capability does NOT resurrect previously active mode without explicit activation
        appState.runtimeSupportsStructuredToolCalls = true
        #expect(appState.canEnableAgentMode(for: conv1.id) == true)
        #expect(appState.canEnableAgentMode(for: conv2.id) == true)
        #expect(appState.isAgentModeEnabled(for: conv1.id) == false)
        #expect(appState.isAgentModeEnabled(for: conv2.id) == false)

        // Can be explicitly re-enabled now that capability is restored
        appState.setAgentMode(true, for: conv1.id)
        #expect(appState.isAgentModeEnabled(for: conv1.id) == true)
    }

    // MARK: - Clearing or Changing ProjectPath Inactivates Agent Mode

    @Test("Clearing or changing conversation projectPath to empty makes selected agent mode inactive")
    @MainActor
    func testClearingOrEmptyingProjectPathMakesAgentModeInactive() throws {
        let (defaults, suiteName) = try makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(startServices: false, userDefaults: defaults)
        appState.isAgentPreviewEnabled = true
        appState.runtimeSupportsStructuredToolCalls = true

        let conv1 = Conversation(title: "Project 1", projectPath: appState.sandboxDirectory.path)
        let conv2 = Conversation(title: "Project 2", projectPath: appState.sandboxDirectory.path)
        appState.conversations = [conv1, conv2]

        appState.setAgentMode(true, for: conv1.id)
        appState.setAgentMode(true, for: conv2.id)
        #expect(appState.isAgentModeEnabled(for: conv1.id) == true)
        #expect(appState.isAgentModeEnabled(for: conv2.id) == true)

        // 1. Changing projectPath to empty string inactivates conv1 mode
        guard let idx1 = appState.conversations.firstIndex(where: { $0.id == conv1.id }) else {
            Issue.record("Conversation 1 not found")
            return
        }
        appState.conversations[idx1].projectPath = ""

        #expect(appState.canEnableAgentMode(for: conv1.id) == false)
        #expect(appState.isAgentModeEnabled(for: conv1.id) == false)
        #expect(appState.isAgentModeEnabled(for: conv2.id) == true) // conv2 remains active

        // 2. Setting projectPath to whitespace-only also remains inactive
        appState.conversations[idx1].projectPath = "   \n\t "
        #expect(appState.canEnableAgentMode(for: conv1.id) == false)
        #expect(appState.isAgentModeEnabled(for: conv1.id) == false)

        // 3. Setting projectPath to nil remains inactive
        appState.conversations[idx1].projectPath = nil
        #expect(appState.canEnableAgentMode(for: conv1.id) == false)
        #expect(appState.isAgentModeEnabled(for: conv1.id) == false)

        // 4. Attempting to activate agent mode while projectPath is nil fails
        appState.setAgentMode(true, for: conv1.id)
        #expect(appState.isAgentModeEnabled(for: conv1.id) == false)

        // 5. Restoring valid projectPath allows explicit re-activation
        appState.conversations[idx1].projectPath = appState.sandboxDirectory.path
        #expect(appState.canEnableAgentMode(for: conv1.id) == true)
        #expect(appState.isAgentModeEnabled(for: conv1.id) == false) // Does not auto-activate

        appState.setAgentMode(true, for: conv1.id)
        #expect(appState.isAgentModeEnabled(for: conv1.id) == true)
    }

    // MARK: - Disabling Feature Flag Clears All Agent Modes

    @Test("Disabling preview feature flag clears all selected agent modes across conversations")
    @MainActor
    func testDisablingFeatureClearsAllSelectedAgentModes() throws {
        let (defaults, suiteName) = try makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(startServices: false, userDefaults: defaults)
        appState.isAgentPreviewEnabled = true
        appState.runtimeSupportsStructuredToolCalls = true

        let conv1 = Conversation(title: "Chat 1", projectPath: appState.sandboxDirectory.path)
        let conv2 = Conversation(title: "Chat 2", projectPath: appState.sandboxDirectory.path)
        let conv3 = Conversation(title: "Chat 3", projectPath: appState.sandboxDirectory.path)
        appState.conversations = [conv1, conv2, conv3]

        appState.setAgentMode(true, for: conv1.id)
        appState.setAgentMode(true, for: conv2.id)

        #expect(appState.isAgentModeEnabled(for: conv1.id) == true)
        #expect(appState.isAgentModeEnabled(for: conv2.id) == true)
        #expect(appState.isAgentModeEnabled(for: conv3.id) == false)

        // Disable preview feature flag
        appState.isAgentPreviewEnabled = false

        // All selected agent modes must be cleared immediately
        #expect(appState.isAgentModeEnabled(for: conv1.id) == false)
        #expect(appState.isAgentModeEnabled(for: conv2.id) == false)
        #expect(appState.isAgentModeEnabled(for: conv3.id) == false)
    }

    // MARK: - Deleting Conversation Clears its Agent Mode

    @Test("Deleting a conversation clears its mode while leaving other conversations intact")
    @MainActor
    func testDeletingConversationClearsItsMode() throws {
        let (defaults, suiteName) = try makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(startServices: false, userDefaults: defaults)
        appState.isAgentPreviewEnabled = true
        appState.runtimeSupportsStructuredToolCalls = true

        let conv1 = Conversation(title: "Chat 1", projectPath: appState.sandboxDirectory.path)
        let conv2 = Conversation(title: "Chat 2", projectPath: appState.sandboxDirectory.path)
        appState.conversations = [conv1, conv2]

        appState.setAgentMode(true, for: conv1.id)
        appState.setAgentMode(true, for: conv2.id)

        #expect(appState.isAgentModeEnabled(for: conv1.id) == true)
        #expect(appState.isAgentModeEnabled(for: conv2.id) == true)

        // Delete conv1
        appState.deleteConversation(id: conv1.id)

        #expect(appState.isAgentModeEnabled(for: conv1.id) == false)
        #expect(appState.isAgentModeEnabled(for: conv2.id) == true)
    }

    // MARK: - Ordinary Chat State Stability

    @Test("Ordinary chat operations remain unaffected by agent preview state")
    @MainActor
    func testOrdinaryChatStateUnchanged() throws {
        let (defaults, suiteName) = try makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(startServices: false, userDefaults: defaults)

        // Default thinking and system prompt behavior
        #expect(appState.defaultThinkingEnabled == true)
        #expect(!appState.defaultSystemPrompt.isEmpty)

        // Creating conversations
        let newConv = appState.createNewConversation()
        #expect(appState.conversations.first?.id == newConv.id)
        #expect(appState.selectedConversationId == newConv.id)
        #expect(appState.isAgentModeEnabled(for: newConv.id) == false)

        // Renaming conversation
        appState.renameConversation(id: newConv.id, newTitle: "Renamed Title")
        #expect(appState.conversations.first?.title == "Renamed Title")

        // Duplicating conversation
        appState.duplicateConversation(id: newConv.id)
        #expect(appState.conversations.count == 2)
        let duplicate = appState.conversations[0]
        #expect(duplicate.title == "Renamed Title (Copy)")
        #expect(appState.isAgentModeEnabled(for: duplicate.id) == false)

        // Generation tracking
        appState.setConversation(newConv.id, isGenerating: true)
        #expect(appState.isConversationGenerating(newConv.id) == true)
        #expect(appState.isGenerating == true)

        appState.setConversation(newConv.id, isGenerating: false)
        #expect(appState.isConversationGenerating(newConv.id) == false)
        #expect(appState.isGenerating == false)
    }

    // MARK: - Endpoint-Bound Authorization & BaseURL Mutation

    @Test("Assigning AppState.baseURL synchronously clears runtimeSupportsStructuredToolCalls and all active agent modes across conversations")
    @MainActor
    func testBaseURLChangeClearsCapabilityAndActiveAgentModesSynchronously() throws {
        let (defaults, suiteName) = try makeTestDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let appState = AppState(
            baseURL: "http://endpoint-a.local:8000/v1",
            startServices: false,
            userDefaults: defaults
        )
        appState.isAgentPreviewEnabled = true
        appState.runtimeSupportsStructuredToolCalls = true

        let conv1 = Conversation(title: "Project Alpha", projectPath: appState.sandboxDirectory.path)
        let conv2 = Conversation(title: "Project Beta", projectPath: appState.sandboxDirectory.path)
        appState.conversations = [conv1, conv2]

        appState.setAgentMode(true, for: conv1.id)
        appState.setAgentMode(true, for: conv2.id)

        #expect(appState.isAgentModeEnabled(for: conv1.id) == true)
        #expect(appState.isAgentModeEnabled(for: conv2.id) == true)

        // Assign baseURL to endpoint B
        appState.baseURL = "http://endpoint-b.local:8000/v1"

        // Synchronously verify capability is cleared
        #expect(appState.runtimeSupportsStructuredToolCalls == false)

        // Synchronously verify active agent modes are cleared
        #expect(appState.isAgentModeEnabled(for: conv1.id) == false)
        #expect(appState.isAgentModeEnabled(for: conv2.id) == false)
        #expect(appState.canEnableAgentMode(for: conv1.id) == false)
        #expect(appState.canEnableAgentMode(for: conv2.id) == false)
    }
}
