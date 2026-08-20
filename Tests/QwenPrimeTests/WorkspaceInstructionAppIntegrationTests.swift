import Foundation
import Testing
@testable import QwenPrime

@Suite("Workspace instruction app integration")
struct WorkspaceInstructionAppIntegrationTests {
    @Test("Workspace instructions default on and can be disabled persistently")
    @MainActor
    func enablementPersists() throws {
        let fixture = try WorkspaceInstructionAppFixture()
        defer { fixture.tearDown() }

        let appState = fixture.makeAppState()
        #expect(appState.isWorkspaceInstructionsEnabled)
        appState.isWorkspaceInstructionsEnabled = false

        let restored = fixture.makeAppState()
        #expect(restored.isWorkspaceInstructionsEnabled == false)
    }

    @Test("Root AGENTS.md is injected automatically and shown as loaded context")
    @MainActor
    func instructionsReachAgentRun() async throws {
        let fixture = try WorkspaceInstructionAppFixture()
        defer { fixture.tearDown() }
        let appState = fixture.makeAppState()
        appState.setSandboxDirectory(fixture.workspaceURL)
        await appState.refreshWorkspaceInstructions()
        #expect(appState.workspaceInstructions?.content == "ROOT-AGENT-RULE")

        appState.serverStatus = .connected(model: "qwen-test", latencyMs: 1)
        appState.runtimeSupportsStructuredToolCalls = true
        let conversation = Conversation(
            title: "Workspace Instructions Test",
            messages: [],
            modelId: "qwen-test",
            projectPath: fixture.workspaceURL.path
        )
        appState.conversations = [conversation]
        appState.selectedConversationId = conversation.id
        appState.setConversationWorkspace(id: conversation.id, url: fixture.workspaceURL)
        appState.setAgentMode(true, for: conversation.id)

        let inference = ScriptedAgentInference(turns: [[
            .contentDelta("Workspace instructions received."),
            .finished
        ]])
        let viewModel = ChatViewModel(agentInference: inference)
        viewModel.inputText = "Inspect the workspace"
        viewModel.sendMessage(appState: appState)

        try await AsyncCondition.wait(description: "workspace instruction run") {
            !appState.isConversationGenerating(conversation.id)
        }

        let configuration = try #require(await inference.getCapturedConfigurations().first)
        #expect(configuration.systemPrompt?.contains("ROOT-AGENT-RULE") == true)
        let assistant = try #require(appState.conversations.first?.messages.last)
        let card = try #require(assistant.toolExecutions.first)
        #expect(card.toolName == ToolName.workspaceInstructions)
        #expect(card.isSuccess == true)
    }

    @Test("Disabled workspace instructions stay out of the run")
    @MainActor
    func disabledInstructionsStayOut() throws {
        let fixture = try WorkspaceInstructionAppFixture()
        defer { fixture.tearDown() }
        let appState = fixture.makeAppState()
        appState.isWorkspaceInstructionsEnabled = false

        #expect(appState.workspaceInstructionDocument(at: fixture.workspaceURL) == nil)
    }
}

private struct WorkspaceInstructionAppFixture {
    let rootURL: URL
    let workspaceURL: URL
    let defaults: UserDefaults
    let suiteName: String
    let storage: StorageService

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwenprime-instruction-app-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try Data("ROOT-AGENT-RULE".utf8).write(to: workspaceURL.appendingPathComponent("AGENTS.md"))
        suiteName = "QwenPrimeTests-WorkspaceInstructions-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        storage = StorageService(directoryURL: rootURL.appendingPathComponent("storage", isDirectory: true))
    }

    @MainActor
    func makeAppState() -> AppState {
        AppState(
            startServices: false,
            workspaceAuthorizationService: WorkspaceAuthorizationService(
                userDefaults: defaults,
                bookmarker: TestWorkspaceBookmarker(),
                scopeAccessor: TestWorkspaceSecurityScopeAccessor()
            ),
            userDefaults: defaults,
            storage: storage,
            workspaceInstructionService: WorkspaceInstructionService()
        )
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: rootURL)
    }
}
