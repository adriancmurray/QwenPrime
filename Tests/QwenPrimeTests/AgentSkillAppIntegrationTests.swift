import Foundation
import Testing
@testable import QwenPrime

@Suite("Agent skill app integration")
struct AgentSkillAppIntegrationTests {
    @Test("Skills remain disabled until enabled and the choice persists")
    @MainActor
    func skillEnablementPersists() async throws {
        let fixture = try SkillAppFixture()
        defer { fixture.tearDown() }

        let appState = fixture.makeAppState()
        appState.setSandboxDirectory(fixture.workspaceURL)
        await appState.refreshAgentSkills()
        let skill = try #require(appState.agentSkills.first)
        #expect(appState.enabledAgentSkillIDs.isEmpty)

        appState.setAgentSkill(skill, enabled: true)
        #expect(appState.enabledAgentSkillIDs == [skill.id])

        let restored = fixture.makeAppState()
        restored.setSandboxDirectory(fixture.workspaceURL)
        await restored.refreshAgentSkills()
        #expect(restored.enabledAgentSkillIDs == [skill.id])
    }

    @Test("Explicitly invoked enabled skill is injected and shown as a loaded card")
    @MainActor
    func invokedSkillReachesAgentPromptAndTranscript() async throws {
        let fixture = try SkillAppFixture()
        defer { fixture.tearDown() }
        let appState = fixture.makeAppState()
        appState.setSandboxDirectory(fixture.workspaceURL)
        await appState.refreshAgentSkills()
        let skill = try #require(appState.agentSkills.first)
        appState.setAgentSkill(skill, enabled: true)
        appState.serverStatus = .connected(model: "qwen-test", latencyMs: 1)
        appState.runtimeSupportsStructuredToolCalls = true

        let conversation = Conversation(
            title: "Skill Test",
            messages: [],
            modelId: "qwen-test",
            projectPath: fixture.workspaceURL.path
        )
        appState.conversations = [conversation]
        appState.selectedConversationId = conversation.id
        appState.setConversationWorkspace(id: conversation.id, url: fixture.workspaceURL)
        appState.setAgentMode(true, for: conversation.id)

        let inference = ScriptedAgentInference(turns: [[
            .contentDelta("Skill instructions received."),
            .finished
        ]])
        let viewModel = ChatViewModel(agentInference: inference)
        viewModel.inputText = "Use $swift-review to inspect this design"
        viewModel.sendMessage(appState: appState)

        try await AsyncCondition.wait(description: "skill-backed agent run") {
            !appState.isConversationGenerating(conversation.id)
        }

        let configuration = try #require(await inference.getCapturedConfigurations().first)
        #expect(configuration.systemPrompt?.contains("CHECK-SWIFT-CONCURRENCY") == true)
        #expect(configuration.systemPrompt?.contains("qwen-prime-skill name=\"swift-review\"") == true)

        let assistant = try #require(appState.conversations.first?.messages.last)
        let card = try #require(assistant.toolExecutions.first)
        #expect(card.toolName == "skill__swift-review")
        #expect(card.input == "$swift-review")
        #expect(card.isSuccess == true)
    }

    @Test("Unmentioned enabled skill is not injected or shown")
    @MainActor
    func unmentionedSkillStaysOutOfRun() async throws {
        let fixture = try SkillAppFixture()
        defer { fixture.tearDown() }
        let appState = fixture.makeAppState()
        appState.setSandboxDirectory(fixture.workspaceURL)
        await appState.refreshAgentSkills()
        let skill = try #require(appState.agentSkills.first)
        appState.setAgentSkill(skill, enabled: true)

        #expect(appState.invokedAgentSkills(in: "Review this normally").isEmpty)
    }
}

private struct SkillAppFixture {
    let rootURL: URL
    let workspaceURL: URL
    let userSkillsURL: URL
    let defaults: UserDefaults
    let suiteName: String
    let storage: StorageService

    init() throws {
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("qwenprime-skill-app-\(UUID().uuidString)", isDirectory: true)
        workspaceURL = rootURL.appendingPathComponent("workspace", isDirectory: true)
        userSkillsURL = rootURL.appendingPathComponent("user-skills", isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userSkillsURL, withIntermediateDirectories: true)

        let package = workspaceURL
            .appendingPathComponent(".qwenprime/skills/swift-review", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try """
        ---
        name: swift-review
        description: Review Swift concurrency boundaries.
        ---
        CHECK-SWIFT-CONCURRENCY
        """.write(to: package.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        suiteName = "QwenPrimeTests-AgentSkills-\(UUID().uuidString)"
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
            agentSkillService: AgentSkillService(userSkillsDirectory: userSkillsURL)
        )
    }

    func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: rootURL)
    }
}
