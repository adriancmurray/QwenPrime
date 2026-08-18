import Foundation
import SwiftUI
import AppKit
import Observation

public enum SettingsSection: Int, Hashable, Sendable {
    case systemPrompts
    case appearance
    case engine
    case sandbox
    case general
    case shortcuts
}

@Observable
@MainActor
public final class AppState {
    public var conversations: [Conversation] = []
    public var selectedConversationId: UUID?
    public var serverStatus: ServerStatus = .connecting
    public var baseURL: String = "http://127.0.0.1:8000/v1" {
        didSet {
            let oldNorm = Self.normalizeEndpoint(oldValue)
            let newNorm = Self.normalizeEndpoint(baseURL)
            if oldNorm != newNorm {
                healthCheckGeneration &+= 1
                verifiedBaseURL = nil
                runtimeSupportsStructuredToolCalls = false
            }
        }
    }
    public private(set) var verifiedBaseURL: String?
    public var selectedModel: String = "qwen3.8-27b"
    public var isSettingsPresented: Bool = false
    public var settingsSelection: SettingsSection = .systemPrompts
    public var searchText: String = ""
    public var currentThemeType: ThemeType = .primeDark
    public var sandboxDirectory: URL
    public var recentProjects: [URL] = []
    public var selectedProjectScope: String = "all" // "all" or specific folder name
    public var runtimeConfiguration: RuntimeConfiguration
    public var selectedEditingProfileId: UUID?
    public var runtimeSetupStatus: RuntimeSetupStatus
    public private(set) var workspaceAuthorizationError: String?
    public private(set) var verifiedRuntimeIdentity: QwenRuntimeIdentity?
    public private(set) var isRuntimeManaged: Bool = false
    public private(set) var workspaceHarnessReady: Bool?

    public var activeModelProfile: RuntimeModelProfile? {
        runtimeConfiguration.activeProfile
    }

    public var editingModelProfile: RuntimeModelProfile? {
        runtimeConfiguration.profiles.first(where: { $0.id == selectedEditingProfileId }) ?? activeModelProfile
    }

    public private(set) var generatingConversationIDs: Set<UUID> = []
    public var isGenerating: Bool { !generatingConversationIDs.isEmpty }
    public var defaultThinkingEnabled: Bool {
        didSet {
            userDefaults.set(defaultThinkingEnabled, forKey: "defaultThinkingEnabled")
        }
    }
    public var defaultDirectModeEnabled: Bool {
        get { !defaultThinkingEnabled }
        set { defaultThinkingEnabled = !newValue }
    }
    public var defaultAgentModeEnabled: Bool {
        didSet {
            userDefaults.set(defaultAgentModeEnabled, forKey: "defaultAgentModeEnabled")
        }
    }
    public var defaultSystemPrompt: String {
        didSet {
            userDefaults.set(defaultSystemPrompt, forKey: "defaultSystemPrompt")
        }
    }
    public var isAgentPreviewEnabled: Bool {
        didSet {
            userDefaults.set(isAgentPreviewEnabled, forKey: "isAgentPreviewEnabled")
            if !isAgentPreviewEnabled {
                activeAgentModeConversationIds.removeAll()
            }
        }
    }
    public var isMCPServerEnabled: Bool {
        didSet {
            userDefaults.set(isMCPServerEnabled, forKey: "isMCPServerEnabled")
            if !isMCPServerEnabled {
                mcpConnectionError = nil
            }
        }
    }
    public var mcpServerDisplayName: String {
        didSet {
            userDefaults.set(mcpServerDisplayName, forKey: "mcpServerDisplayName")
            mcpConnectionError = nil
        }
    }
    public var mcpServerEndpoint: String {
        didSet {
            userDefaults.set(mcpServerEndpoint, forKey: "mcpServerEndpoint")
            mcpConnectionError = nil
        }
    }
    public private(set) var mcpConnectionError: String?

    public var mcpServerConfiguration: MCPServerConfiguration? {
        guard isMCPServerEnabled else { return nil }
        return try? MCPServerConfiguration(
            id: "local",
            displayName: mcpServerDisplayName,
            endpoint: mcpServerEndpoint
        )
    }

    public var mcpServerConfigurationError: String? {
        guard isMCPServerEnabled else { return nil }
        do {
            _ = try MCPServerConfiguration(
                id: "local",
                displayName: mcpServerDisplayName,
                endpoint: mcpServerEndpoint
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }
    public var runtimeSupportsStructuredToolCalls: Bool = false {
        didSet {
            if runtimeSupportsStructuredToolCalls {
                verifiedBaseURL = Self.normalizeEndpoint(baseURL)
            } else {
                verifiedBaseURL = nil
            }
        }
    }

    public static func normalizeEndpoint(_ endpoint: String) -> String {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host?.lowercased() else {
            var result = trimmed
            while result.hasSuffix("/") { result.removeLast() }
            return result
        }
        let portString = url.port.map { ":\($0)" } ?? ""
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return "\(scheme)://\(host)\(portString)\(path)"
    }

    private var activeAgentModeConversationIds: Set<UUID> = []
    private let userDefaults: UserDefaults
    let storage: StorageService
    private let healthService: ServerHealthService
    private let runtimeConfigurationService: RuntimeConfigurationService
    private let workspaceAuthorizationService: WorkspaceAuthorizationService
    private let defaultSandboxDirectory: URL
    private var healthCheckTask: Task<Void, Never>?
    private var profileSwitchTask: Task<Void, Never>?
    private var healthCheckGeneration: UInt64 = 0

    public static let factorySystemPrompt = """
You are Qwen Prime, an elite AI systems and software engineering assistant running natively on Apple Silicon with MLX and DFlash speculative acceleration.

Guidelines:
1. Provide precise, production-grade implementations with clean explanations.
2. In Swift code, strictly enforce Swift 6 concurrency safety, actor isolation, and Sendable conformance. Avoid force-unwrapping.
3. In Rust and Python, follow zero-cost abstractions, idiomatic design, and proper error handling.
4. When reasoning, use your <think> chain-of-thought to explore edge cases and architectural trade-offs thoroughly before answering.
"""

    public var promptPresets: [SystemPromptPreset] = SystemPromptPreset.builtInPresets

    public init(
        baseURL: String = "http://127.0.0.1:8000/v1",
        startServices: Bool = true,
        healthService: ServerHealthService = .shared,
        runtimeConfigurationService: RuntimeConfigurationService = RuntimeConfigurationService(),
        workspaceAuthorizationService: WorkspaceAuthorizationService? = nil,
        userDefaults: UserDefaults = .standard,
        storage: StorageService? = nil
    ) {
        self.baseURL = baseURL
        self.healthService = healthService
        self.userDefaults = userDefaults
        self.storage = storage
            ?? (startServices ? StorageService.shared : StorageService(persistenceEnabled: false))
        let resolvedWorkspaceAuthorizationService = workspaceAuthorizationService
            ?? WorkspaceAuthorizationService(userDefaults: userDefaults)
        self.workspaceAuthorizationService = resolvedWorkspaceAuthorizationService
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultSandbox = home.appendingPathComponent("prime-sandbox", isDirectory: true)
        if !FileManager.default.fileExists(atPath: defaultSandbox.path) {
            try? FileManager.default.createDirectory(at: defaultSandbox, withIntermediateDirectories: true)
        }
        self.defaultSandboxDirectory = defaultSandbox
        self.sandboxDirectory = defaultSandbox
        var initialRecentProjects = [defaultSandbox]
        for authorizedURL in resolvedWorkspaceAuthorizationService.authorizedURLs
            where authorizedURL.standardizedFileURL != defaultSandbox.standardizedFileURL {
            initialRecentProjects.append(authorizedURL)
        }
        self.recentProjects = initialRecentProjects
        self.workspaceAuthorizationError = nil
        self.defaultThinkingEnabled = userDefaults.object(forKey: "defaultThinkingEnabled") as? Bool ?? false
        self.defaultAgentModeEnabled = userDefaults.object(forKey: "defaultAgentModeEnabled") as? Bool ?? true
        self.defaultSystemPrompt = userDefaults.string(forKey: "defaultSystemPrompt") ?? AppState.factorySystemPrompt
        self.isAgentPreviewEnabled = userDefaults.object(forKey: "isAgentPreviewEnabled") as? Bool ?? true
        self.isMCPServerEnabled = userDefaults.object(forKey: "isMCPServerEnabled") as? Bool ?? false
        self.mcpServerDisplayName = userDefaults.string(forKey: "mcpServerDisplayName") ?? "Local MCP"
        self.mcpServerEndpoint = userDefaults.string(forKey: "mcpServerEndpoint") ?? "http://127.0.0.1:3001/mcp"
        self.mcpConnectionError = nil
        self.runtimeSupportsStructuredToolCalls = false
        self.runtimeConfigurationService = runtimeConfigurationService
        let savedRuntimeConfiguration =
            (try? runtimeConfigurationService.load()) ?? RuntimeConfiguration()
        self.runtimeConfiguration = savedRuntimeConfiguration
        self.selectedEditingProfileId = savedRuntimeConfiguration.activeProfileId
        self.runtimeSetupStatus = runtimeConfigurationService.localValidation(
            savedRuntimeConfiguration
        )

        if let data = userDefaults.data(forKey: "customPromptPresets"),
           let decoded = try? JSONDecoder().decode([SystemPromptPreset].self, from: data), !decoded.isEmpty {
            self.promptPresets = decoded
        } else {
            self.promptPresets = SystemPromptPreset.builtInPresets
        }

        if startServices {
            Task {
                await loadConversations()
                await refreshWorkspaceHarnessStatus()
                await checkServerHealth()
                if !serverStatus.isConnected {
                    if runtimeSetupStatus == .ready {
                        let validation = await healthService.doctorRuntime()
                        runtimeSetupStatus = validation.isReady
                            ? .ready
                            : .invalid(validation.message)
                        if validation.isReady {
                            await healthService.startEngine()
                        }
                    } else {
                        self.serverStatus = .disconnected(
                            reason: "Choose model folders in Engine settings"
                        )
                    }
                }
                startHealthCheckLoop()
            }
        }
    }

    public func refreshWorkspaceHarnessStatus() async {
        workspaceHarnessReady = await QwenPrimeHarnessClient.shared.isReady()
    }

    public func savePromptPreset(_ preset: SystemPromptPreset) {
        if let idx = promptPresets.firstIndex(where: { $0.id == preset.id }) {
            promptPresets[idx] = preset
        } else {
            promptPresets.append(preset)
        }
        persistPromptPresets()
    }

    public func deletePromptPreset(id: UUID) {
        promptPresets.removeAll(where: { $0.id == id && !$0.isBuiltIn })
        persistPromptPresets()
    }

    public func resetToFactoryPresets() {
        self.promptPresets = SystemPromptPreset.builtInPresets
        self.defaultSystemPrompt = AppState.factorySystemPrompt
        persistPromptPresets()
    }

    private func persistPromptPresets() {
        if let data = try? JSONEncoder().encode(promptPresets) {
            userDefaults.set(data, forKey: "customPromptPresets")
        }
    }

    public var activeTheme: MarkdownTheme {
        MarkdownTheme.theme(for: currentThemeType)
    }

    public var selectedConversation: Conversation? {
        get {
            guard let id = selectedConversationId else { return nil }
            return conversations.first(where: { $0.id == id })
        }
        set {
            guard let id = selectedConversationId, let newValue = newValue else { return }
            if let index = conversations.firstIndex(where: { $0.id == id }) {
                conversations[index] = newValue
            }
        }
    }

    public var filteredConversations: [Conversation] {
        var result = conversations

        if selectedProjectScope != "all" {
            result = result.filter { ($0.projectPath ?? "").contains(selectedProjectScope) }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.messages.contains { $0.content.localizedCaseInsensitiveContains(query) }
            }
        }

        return result
    }

    public func loadConversations() async {
        do {
            let loaded = try await storage.loadAllConversations()
            self.conversations = loaded
            if selectedConversationId == nil {
                if let first = loaded.first {
                    self.selectedConversationId = first.id
                } else {
                    createNewConversation()
                }
            }
        } catch {
            print("[AppState] Error loading conversations: \(error)")
            if conversations.isEmpty {
                createNewConversation()
            }
        }
    }

    @discardableResult
    public func createNewConversation() -> Conversation {
        let newConv = Conversation(
            title: "New Chat",
            modelId: selectedModel,
            systemPrompt: defaultSystemPrompt,
            isThinkingEnabled: defaultThinkingEnabled,
            projectPath: sandboxDirectory.path
        )
        conversations.insert(newConv, at: 0)
        if defaultAgentModeEnabled {
            activeAgentModeConversationIds.insert(newConv.id)
        }
        selectedConversationId = newConv.id
        saveConversation(newConv)
        return newConv
    }


    public func duplicateConversation(id: UUID) {
        guard let source = conversations.first(where: { $0.id == id }) else { return }
        var copiedMessages = source.messages
        for index in copiedMessages.indices {
            copiedMessages[index].isStreaming = false
        }
        let duplicate = Conversation(
            title: "\(source.title) (Copy)",
            messages: copiedMessages,
            modelId: source.modelId,
            temperature: source.temperature,
            systemPrompt: source.systemPrompt,
            isThinkingEnabled: source.isThinkingEnabled,
            projectPath: source.projectPath
        )
        conversations.insert(duplicate, at: 0)
        selectedConversationId = duplicate.id
        saveConversation(duplicate)
    }

    public func deleteConversation(id: UUID) {
        guard !isConversationGenerating(id) else { return }
        activeAgentModeConversationIds.remove(id)
        conversations.removeAll(where: { $0.id == id })
        if selectedConversationId == id {
            selectedConversationId = conversations.first?.id
            if selectedConversationId == nil {
                createNewConversation()
            }
        }
        Task {
            try? await storage.deleteConversation(id: id)
        }
    }

    public func clearConversationMessages(id: UUID) {
        guard !isConversationGenerating(id) else { return }
        updateConversation(id: id) { conversation in
            conversation.messages.removeAll()
            conversation.touch()
        }
        if let conversation = conversations.first(where: { $0.id == id }) {
            saveConversation(conversation)
        }
    }

    public func renameConversation(id: UUID, newTitle: String) {
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].title = newTitle
            conversations[index].touch()
            saveConversation(conversations[index])
        }
    }

    public func updateConversation(
        id: UUID,
        mutation: (inout Conversation) -> Void
    ) {
        guard let index = conversations.firstIndex(where: { $0.id == id }) else {
            return
        }
        mutation(&conversations[index])
    }

    public func updateConversationThinking(id: UUID, isEnabled: Bool) {
        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].isThinkingEnabled = isEnabled
            saveConversation(conversations[idx])
        }
    }

    public func setConversation(_ id: UUID, isGenerating: Bool) {
        if isGenerating {
            generatingConversationIDs.insert(id)
        } else {
            generatingConversationIDs.remove(id)
        }
    }

    public func isConversationGenerating(_ id: UUID) -> Bool {
        generatingConversationIDs.contains(id)
    }

    public func setSandboxDirectory(_ url: URL) {
        let workspaceURL: URL
        do {
            workspaceURL = isImplicitlyAuthorizedWorkspace(url)
                ? url.standardizedFileURL
                : try workspaceAuthorizationService.authorize(url)
            workspaceAuthorizationError = nil
        } catch {
            workspaceAuthorizationError = error.localizedDescription
            return
        }
        applySandboxDirectory(workspaceURL)
    }

    private func applySandboxDirectory(_ url: URL) {
        sandboxDirectory = url
        if !recentProjects.contains(where: { $0.path == url.path }) {
            recentProjects.insert(url, at: 0)
            if recentProjects.count > 5 {
                recentProjects = Array(recentProjects.prefix(5))
            }
        }
    }

    public func setConversationWorkspace(id: UUID, url: URL) {
        let workspaceURL: URL
        do {
            workspaceURL = isImplicitlyAuthorizedWorkspace(url)
                ? url.standardizedFileURL
                : try workspaceAuthorizationService.authorize(url)
            workspaceAuthorizationError = nil
        } catch {
            workspaceAuthorizationError = error.localizedDescription
            activeAgentModeConversationIds.remove(id)
            return
        }

        applySandboxDirectory(workspaceURL)
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].projectPath = workspaceURL.path
            conversations[index].touch()
            saveConversation(conversations[index])
        }
    }

    public func authorizedWorkspaceURL(for conversationId: UUID) -> URL? {
        guard let conversation = conversations.first(where: { $0.id == conversationId }) else {
            return nil
        }
        let storedPath = conversation.projectPath?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let path: String
        if let storedPath, !storedPath.isEmpty {
            path = storedPath
        } else {
            guard selectedConversationId == conversationId else { return nil }
            path = sandboxDirectory.path
        }
        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        if isImplicitlyAuthorizedWorkspace(url) {
            return url
        }
        return workspaceAuthorizationService.resolveAuthorizedURL(path: path)
    }

    public func clearWorkspaceAuthorizationError() {
        workspaceAuthorizationError = nil
    }

    public func setMCPConnectionError(_ message: String?) {
        mcpConnectionError = message
    }

    private func isImplicitlyAuthorizedWorkspace(_ url: URL) -> Bool {
        let rootPath = defaultSandboxDirectory.standardizedFileURL.path
        let candidatePath = url.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    public func saveConversation(_ conversation: Conversation) {
        Task {
            try? await storage.saveConversation(conversation)
        }
    }

    public func checkServerHealth() async {
        healthCheckGeneration &+= 1
        let generation = healthCheckGeneration
        let requestedURL = baseURL
        let normalizedRequestedURL = Self.normalizeEndpoint(requestedURL)
        let status = await healthService.checkHealth(baseURL: requestedURL)
        guard generation == healthCheckGeneration,
              Self.normalizeEndpoint(self.baseURL) == normalizedRequestedURL else {
            return
        }
        self.serverStatus = status
        self.isRuntimeManaged = await healthService.isManagedServerRunning()
        let identity = await healthService.currentIdentity(for: requestedURL)
        guard generation == healthCheckGeneration,
              Self.normalizeEndpoint(self.baseURL) == normalizedRequestedURL else {
            return
        }
        let profileMatches = activeModelProfile.map { profile in
            !profile.isConfigured || identity?.matches(profile) == true
        } ?? true
        if status.isConnected, identity != nil, !profileMatches {
            self.serverStatus = .disconnected(
                reason: "The active endpoint is running a different model profile"
            )
        }
        let isCapable = (
            self.serverStatus.isConnected
                && profileMatches
                && identity?.supportsStructuredToolCalls == true
        )
        if isCapable {
            self.verifiedRuntimeIdentity = identity
            self.verifiedBaseURL = normalizedRequestedURL
            self.runtimeSupportsStructuredToolCalls = true
        } else {
            self.verifiedRuntimeIdentity = status.isConnected ? identity : nil
            self.verifiedBaseURL = nil
            self.runtimeSupportsStructuredToolCalls = false
        }
    }

    public func startEngine() {
        guard runtimeSetupStatus == .ready else {
            settingsSelection = .engine
            serverStatus = .disconnected(reason: runtimeSetupStatus.message)
            return
        }
        Task {
            await healthService.startEngine()
            try? await Task.sleep(for: .seconds(2))
            await checkServerHealth()
        }
    }

    public func stopEngine() {
        Task {
            await healthService.stopEngine()
            await checkServerHealth()
        }
    }

    @discardableResult
    public func addModelProfile(
        name: String = "New Profile",
        targetPath: String = "",
        draftPath: String = ""
    ) -> RuntimeModelProfile {
        let newProfile = RuntimeModelProfile(
            name: name,
            targetModelPath: targetPath,
            draftModelPath: draftPath
        )
        runtimeConfiguration.profiles.append(newProfile)
        selectedEditingProfileId = newProfile.id
        try? runtimeConfigurationService.save(runtimeConfiguration)
        return newProfile
    }

    public func saveModelProfile(_ profile: RuntimeModelProfile) {
        if let index = runtimeConfiguration.profiles.firstIndex(where: { $0.id == profile.id }) {
            runtimeConfiguration.profiles[index] = profile
        } else {
            runtimeConfiguration.profiles.append(profile)
        }
        if runtimeConfiguration.activeProfileId == profile.id {
            runtimeConfiguration.targetModelPath = profile.targetModelPath
            runtimeConfiguration.draftModelPath = profile.draftModelPath
            runtimeSetupStatus = runtimeConfigurationService.localValidation(profile)
        }
        try? runtimeConfigurationService.save(runtimeConfiguration)
    }

    public func deleteModelProfile(id: UUID) {
        guard runtimeConfiguration.profiles.count > 1 else { return }
        guard runtimeConfiguration.activeProfileId != id else { return }
        runtimeConfiguration.profiles.removeAll(where: { $0.id == id })
        if selectedEditingProfileId == id {
            selectedEditingProfileId = runtimeConfiguration.activeProfileId
        }
        try? runtimeConfigurationService.save(runtimeConfiguration)
    }

    public func activateProfile(id: UUID) {
        guard !isGenerating else { return }
        guard let profile = runtimeConfiguration.profiles.first(where: { $0.id == id }) else { return }

        let localStatus = runtimeConfigurationService.localValidation(profile)
        guard localStatus == .ready else {
            runtimeSetupStatus = localStatus
            return
        }

        runtimeSetupStatus = .validating
        profileSwitchTask?.cancel()
        profileSwitchTask = Task {
            let managed = await healthService.isManagedServerRunning()
            let occupied = await healthService.endpointIsOccupied()
            let alreadyRunningSelectedProfile = serverStatus.isConnected
                && verifiedRuntimeIdentity?.matches(profile) == true

            if occupied && !managed && !alreadyRunningSelectedProfile {
                runtimeSetupStatus = .invalid(
                    "Another runtime owns the endpoint. Stop it before switching model profiles."
                )
                return
            }

            var nextConfiguration = runtimeConfiguration
            nextConfiguration.activeProfileId = id
            nextConfiguration.targetModelPath = profile.targetModelPath
            nextConfiguration.draftModelPath = profile.draftModelPath
            do {
                try runtimeConfigurationService.save(nextConfiguration)
            } catch {
                runtimeSetupStatus = .invalid(error.localizedDescription)
                return
            }
            runtimeConfiguration = nextConfiguration
            selectedEditingProfileId = id

            if alreadyRunningSelectedProfile {
                runtimeSetupStatus = .ready
                return
            }

            if managed {
                await healthService.stopEngine()
            }

            let result = await healthService.doctorRuntime()
            guard !Task.isCancelled else { return }
            guard result.isReady else {
                runtimeSetupStatus = .invalid(result.message)
                return
            }

            await healthService.startEngine()
            guard !Task.isCancelled else { return }

            for _ in 0..<180 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                await checkServerHealth()
                if serverStatus.isConnected,
                   verifiedRuntimeIdentity?.matches(profile) == true {
                    runtimeSetupStatus = .ready
                    return
                }
                if case .disconnected(let reason) = serverStatus,
                   reason.contains("different model profile")
                    || reason.contains("occupied") {
                    runtimeSetupStatus = .invalid(reason)
                    return
                }
            }
            runtimeSetupStatus = .invalid("Timed out waiting for the selected model profile to start.")
        }
    }

    public func setRuntimeTargetModel(_ url: URL) {
        if let editingId = selectedEditingProfileId,
           let idx = runtimeConfiguration.profiles.firstIndex(where: { $0.id == editingId }) {
            runtimeConfiguration.profiles[idx].targetModelPath = url.path
            if runtimeConfiguration.activeProfileId == editingId {
                runtimeConfiguration.targetModelPath = url.path
            }
        } else {
            runtimeConfiguration.targetModelPath = url.path
        }
        updateRuntimeSelectionStatus()
    }

    public func setRuntimeDraftModel(_ url: URL) {
        if let editingId = selectedEditingProfileId,
           let idx = runtimeConfiguration.profiles.firstIndex(where: { $0.id == editingId }) {
            runtimeConfiguration.profiles[idx].draftModelPath = url.path
            if runtimeConfiguration.activeProfileId == editingId {
                runtimeConfiguration.draftModelPath = url.path
            }
        } else {
            runtimeConfiguration.draftModelPath = url.path
        }
        updateRuntimeSelectionStatus()
    }

    public func saveAndValidateRuntimeConfiguration() {
        guard let active = runtimeConfiguration.activeProfile else { return }
        activateProfile(id: active.id)
    }

    private func updateRuntimeSelectionStatus() {
        let profileToValidate = editingModelProfile ?? runtimeConfiguration.activeProfile ?? RuntimeModelProfile()
        let localStatus = runtimeConfigurationService.localValidation(profileToValidate)
        runtimeSetupStatus = localStatus == .ready
            ? .invalid("Save and validate the selected model pair before starting.")
            : localStatus
    }

    public func openSandboxInFinder() {
        openWorkspaceInFinder(sandboxDirectory)
    }

    public func openSandboxInTerminal() {
        openWorkspaceInTerminal(sandboxDirectory)
    }

    public func openWorkspaceInFinder(_ url: URL) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
    }

    public func openWorkspaceInTerminal(_ url: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", url.path]
        try? process.run()
    }

    public func exportConversationAsMarkdown() {
        guard let conv = selectedConversation else { return }
        var md = "# \(conv.title)\n\n"
        if let proj = conv.projectPath {
            md += "_Workspace: \(proj)_\n\n"
        }
        md += "_Generated on \(conv.createdAt.formatted(date: .abbreviated, time: .shortened)) via Qwen Prime_\n\n---\n\n"

        for msg in conv.messages {
            let roleHeader = msg.role == .user ? "### 👤 User" : "### 🤖 Qwen Prime"
            md += "\(roleHeader)\n\n"
            if let thinking = msg.thinkingContent, !thinking.isEmpty {
                md += "<details><summary>Thought Process</summary>\n\n\(thinking)\n\n</details>\n\n"
            }
            md += "\(msg.content)\n\n---\n\n"
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Export Conversation as Markdown"
        savePanel.nameFieldStringValue = "\(conv.title.replacingOccurrences(of: "/", with: "-")).md"
        savePanel.allowedContentTypes = [.plainText]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? md.data(using: .utf8)?.write(to: url)
        }
    }

    // MARK: - Agent Mode Preview Controls

    public func canAttemptAgentMode(for conversationId: UUID) -> Bool {
        guard isAgentPreviewEnabled,
              conversations.contains(where: { $0.id == conversationId }) else {
            return false
        }
        return authorizedWorkspaceURL(for: conversationId) != nil
    }

    public func canEnableAgentMode(for conversationId: UUID) -> Bool {
        guard canAttemptAgentMode(for: conversationId),
              runtimeSupportsStructuredToolCalls else {
            return false
        }
        guard let verified = verifiedBaseURL,
              verified == Self.normalizeEndpoint(baseURL) else {
            return false
        }
        return true
    }

    public func setAgentModeAfterRefreshing(
        _ enabled: Bool,
        for conversationId: UUID
    ) async {
        guard enabled else {
            setAgentMode(false, for: conversationId)
            return
        }
        guard canAttemptAgentMode(for: conversationId) else { return }
        await checkServerHealth()
        setAgentMode(true, for: conversationId)
    }

    public func setAgentMode(_ enabled: Bool, for conversationId: UUID) {
        if enabled {
            if selectedConversationId == conversationId,
               conversations.first(where: { $0.id == conversationId })?.projectPath?
                   .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                setConversationWorkspace(id: conversationId, url: sandboxDirectory)
            }
            guard canEnableAgentMode(for: conversationId) else { return }
            activeAgentModeConversationIds.insert(conversationId)
        } else {
            activeAgentModeConversationIds.remove(conversationId)
        }
    }

    public func isAgentModeEnabled(for conversationId: UUID) -> Bool {
        guard activeAgentModeConversationIds.contains(conversationId) else {
            return false
        }
        return canEnableAgentMode(for: conversationId)
    }

    private func startHealthCheckLoop() {
        healthCheckTask?.cancel()
        healthCheckTask = Task {
            while !Task.isCancelled {
                await checkServerHealth()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}
