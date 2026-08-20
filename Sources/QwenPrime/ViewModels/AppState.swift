import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

public typealias ConversationExportDestinationPicker = @MainActor @Sendable (
    _ suggestedFilename: String
) async -> URL?
public typealias ConversationExportWriter = @Sendable (
    _ data: Data,
    _ destination: URL
) throws -> Void

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
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "QwenPrime",
        category: "AppState"
    )
    public var conversations: [Conversation] = []
    public var selectedConversationId: UUID?
    public var serverStatus: ServerStatus = .connecting
    public var preferences: AppPreferences {
        didSet {
            AppPreferencesPersistence.save(preferences, to: userDefaults)
            let oldNorm = Self.normalizeEndpoint(oldValue.baseURL)
            let newNorm = Self.normalizeEndpoint(preferences.baseURL)
            if oldNorm != newNorm {
                healthCheckGeneration &+= 1
                verifiedBaseURL = nil
                runtimeSupportsStructuredToolCalls = false
            }
        }
    }
    public var baseURL: String {
        get { preferences.baseURL }
        set { preferences.baseURL = Self.normalizeEndpoint(newValue) }
    }
    public private(set) var verifiedBaseURL: String?
    public var selectedModel: String {
        get { preferences.selectedModel }
        set { preferences.selectedModel = newValue }
    }
    public var settingsSelection: SettingsSection = .systemPrompts
    public var searchText: String = ""
    public var currentThemeType: ThemeType {
        get { preferences.theme }
        set { preferences.theme = newValue }
    }
    public var isAutoScrollEnabled: Bool {
        get { preferences.isAutoScrollEnabled }
        set { preferences.isAutoScrollEnabled = newValue }
    }
    public var isThinkingExpandedByDefault: Bool {
        get { preferences.isThinkingExpandedByDefault }
        set { preferences.isThinkingExpandedByDefault = newValue }
    }
    private(set) var pendingCommandRequests: [AppCommandRequest] = []
    public var pendingCommandRequest: AppCommandRequest? {
        pendingCommandRequests.first
    }
    private var pendingConfirmations: [
        AppConfirmationPresentationScope: AppConfirmationRequest
    ] = [:]
    public var pendingConfirmation: AppConfirmationRequest? {
        pendingConfirmation(in: .mainWindow)
            ?? pendingConfirmation(in: .settingsWindow)
    }
    public var sandboxDirectory: URL
    public var recentProjects: [URL] = []
    public var selectedProjectScope: ProjectScope = .all
    public var runtimeConfiguration: RuntimeConfiguration
    public var selectedEditingProfileId: UUID?
    public var runtimeSetupStatus: RuntimeSetupStatus
    public private(set) var presentedOperationError: AppOperationErrorPresentation?
    public private(set) var verifiedRuntimeIdentity: QwenRuntimeIdentity?
    public private(set) var isRuntimeManaged: Bool = false
    public var runtimeLifecycleAction: RuntimeLifecycleAction {
        RuntimeLifecycleAction.resolve(
            isConnected: serverStatus.isConnected,
            isManaged: isRuntimeManaged
        )
    }
    public private(set) var agentSkills: [AgentSkill] = []
    public private(set) var enabledAgentSkillIDs: Set<String> = []
    public private(set) var workspaceInstructions: WorkspaceInstructionDocument?
    public var isWorkspaceInstructionsEnabled: Bool {
        get { preferences.isWorkspaceInstructionsEnabled }
        set { preferences.isWorkspaceInstructionsEnabled = newValue }
    }

    public var activeModelProfile: RuntimeModelProfile? {
        runtimeConfiguration.activeProfile
    }

    public var editingModelProfile: RuntimeModelProfile? {
        runtimeConfiguration.profiles.first(where: { $0.id == selectedEditingProfileId }) ?? activeModelProfile
    }

    public private(set) var generatingConversationIDs: Set<UUID> = []
    public var isGenerating: Bool { !generatingConversationIDs.isEmpty }

    public func commandContext(
        hasMessageText: Bool = false,
        hasInputFocus: Bool = false
    ) -> AppCommandContext {
        let hasConversation = selectedConversationId != nil
        let isGenerating = selectedConversationId.map(
            isConversationGenerating
        ) == true
        return AppCommandContext(
            hasConversation: hasConversation,
            isGenerating: isGenerating,
            hasMessageText: hasMessageText,
            hasInputFocus: hasInputFocus
        )
    }

    public var defaultThinkingEnabled: Bool {
        get { preferences.defaultThinkingEnabled }
        set { preferences.defaultThinkingEnabled = newValue }
    }
    public var defaultDirectModeEnabled: Bool {
        get { !defaultThinkingEnabled }
        set { defaultThinkingEnabled = !newValue }
    }
    public var defaultAgentModeEnabled: Bool {
        get { preferences.defaultAgentModeEnabled }
        set { preferences.defaultAgentModeEnabled = newValue }
    }
    public var defaultSystemPrompt: String {
        get { preferences.defaultSystemPrompt }
        set {
            guard newValue != preferences.defaultSystemPrompt else { return }
            setDefaultSystemPrompt(text: newValue, presetId: nil)
        }
    }
    public var defaultSystemPromptPresetId: UUID? {
        preferences.defaultSystemPromptPresetId
    }
    public var isAgentPreviewEnabled: Bool {
        get { preferences.isAgentPreviewEnabled }
        set {
            preferences.isAgentPreviewEnabled = newValue
            if !newValue {
                activeAgentModeConversationIds.removeAll()
            }
        }
    }
    public var mcpServers: [MCPServerProfile] {
        didSet {
            persistMCPServers()
            let validIDs = Set(mcpServers.map(\.id))
            mcpServerConnectionStates = mcpServerConnectionStates.filter {
                validIDs.contains($0.key)
            }
        }
    }
    public private(set) var mcpServerConnectionStates: [String: MCPServerConnectionState] = [:]

    // Compatibility accessors for the original single-server preview settings.
    public var isMCPServerEnabled: Bool {
        get { mcpServers.first?.isEnabled == true }
        set {
            updatePrimaryMCPServer { profile in
                profile.isEnabled = newValue
            }
        }
    }

    public var mcpServerDisplayName: String {
        get { mcpServers.first?.displayName ?? MCPServerProfile.defaultDisplayName }
        set {
            updatePrimaryMCPServer { profile in
                profile.displayName = newValue
            }
        }
    }

    public var mcpServerEndpoint: String {
        get { mcpServers.first?.endpoint ?? MCPServerProfile.defaultEndpoint }
        set {
            updatePrimaryMCPServer { profile in
                profile.endpoint = newValue
            }
        }
    }

    public var mcpConnectionError: String? {
        for profile in mcpServers {
            guard case .failed(let message) = mcpServerConnectionStates[profile.id] else {
                continue
            }
            return message
        }
        return nil
    }

    public var enabledMCPServerConfigurations: [MCPServerConfiguration] {
        mcpServers.compactMap { profile in
            guard profile.isEnabled else { return nil }
            return try? profile.configuration()
        }
    }

    public var mcpServerConfiguration: MCPServerConfiguration? {
        enabledMCPServerConfigurations.first
    }

    public var mcpServerConfigurationError: String? {
        for profile in mcpServers where profile.isEnabled {
            do {
                _ = try profile.configuration()
            } catch {
                return error.localizedDescription
            }
        }
        return nil
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
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased() else {
            var result = trimmed
            while result.hasSuffix("/") { result.removeLast() }
            return result
        }
        components.scheme = scheme
        components.host = host
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path
        return components.string ?? trimmed
    }

    private var activeAgentModeConversationIds: Set<UUID> = []
    private let userDefaults: UserDefaults
    let storage: StorageService
    private let healthService: ServerHealthService
    private let runtimeConfigurationService: RuntimeConfigurationService
    private let workspaceAuthorizationService: WorkspaceAuthorizationService
    private let agentSkillService: AgentSkillService
    private let workspaceInstructionService: WorkspaceInstructionService
    private let conversationExportDestinationPicker: ConversationExportDestinationPicker
    private let conversationExportWriter: ConversationExportWriter
    private let defaultSandboxDirectory: URL
    private var healthCheckTask: Task<Void, Never>?
    private var profileSwitchTask: Task<Void, Never>?
    private var healthCheckGeneration: UInt64 = 0
    private static let runtimeStartupHealthCheckDelay = Duration.seconds(2)
    private static let defaultMCPServerId = "local"

    enum UserDefaultsKey: String {
        case customPromptPresets
        case enabledAgentSkillIDs
        case isMCPServerEnabled
        case mcpServerDisplayName
        case mcpServerEndpoint
        case mcpServerProfiles
    }

    public var promptPresets: [SystemPromptPreset] = SystemPromptPreset.builtInPresets

    public init(
        baseURL: String? = nil,
        startServices: Bool = true,
        healthService: ServerHealthService = .shared,
        runtimeConfigurationService: RuntimeConfigurationService = RuntimeConfigurationService(),
        workspaceAuthorizationService: WorkspaceAuthorizationService? = nil,
        userDefaults: UserDefaults = .standard,
        storage: StorageService? = nil,
        agentSkillService: AgentSkillService = AgentSkillService(),
        workspaceInstructionService: WorkspaceInstructionService = WorkspaceInstructionService(),
        conversationExportDestinationPicker: ConversationExportDestinationPicker? = nil,
        conversationExportWriter: ConversationExportWriter? = nil
    ) {
        self.healthService = healthService
        self.userDefaults = userDefaults
        var loadedPreferences = AppPreferencesPersistence.load(from: userDefaults)
        if let baseURL {
            loadedPreferences.baseURL = Self.normalizeEndpoint(baseURL)
        }
        self.preferences = loadedPreferences
        self.storage = storage
            ?? (startServices ? StorageService.shared : StorageService(persistenceEnabled: false))
        let resolvedWorkspaceAuthorizationService = workspaceAuthorizationService
            ?? WorkspaceAuthorizationService(userDefaults: userDefaults)
        self.workspaceAuthorizationService = resolvedWorkspaceAuthorizationService
        self.agentSkillService = agentSkillService
        self.workspaceInstructionService = workspaceInstructionService
        self.conversationExportDestinationPicker =
            conversationExportDestinationPicker ?? { suggestedFilename in
                await Self.chooseConversationExportDestination(
                    suggestedFilename: suggestedFilename
                )
            }
        self.conversationExportWriter = conversationExportWriter ?? { data, destination in
            try data.write(to: destination, options: .atomic)
        }
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
        self.enabledAgentSkillIDs = Set(
            userDefaults.stringArray(
                forKey: UserDefaultsKey.enabledAgentSkillIDs.rawValue
            ) ?? []
        )
        if let data = userDefaults.data(
            forKey: UserDefaultsKey.mcpServerProfiles.rawValue
        ),
           let decoded = try? JSONDecoder().decode([MCPServerProfile].self, from: data) {
            self.mcpServers = decoded
        } else {
            self.mcpServers = [
                MCPServerProfile(
                    id: Self.defaultMCPServerId,
                    displayName: userDefaults.string(
                        forKey: UserDefaultsKey.mcpServerDisplayName.rawValue
                    )
                        ?? MCPServerProfile.defaultDisplayName,
                    endpoint: userDefaults.string(
                        forKey: UserDefaultsKey.mcpServerEndpoint.rawValue
                    )
                        ?? MCPServerProfile.defaultEndpoint,
                    isEnabled: userDefaults.object(
                        forKey: UserDefaultsKey.isMCPServerEnabled.rawValue
                    ) as? Bool ?? false
                )
            ]
        }
        self.runtimeSupportsStructuredToolCalls = false
        self.runtimeConfigurationService = runtimeConfigurationService
        let savedRuntimeConfiguration =
            (try? runtimeConfigurationService.load()) ?? RuntimeConfiguration()
        self.runtimeConfiguration = savedRuntimeConfiguration
        self.selectedEditingProfileId = savedRuntimeConfiguration.activeProfileId
        self.runtimeSetupStatus = runtimeConfigurationService.localValidation(
            savedRuntimeConfiguration
        )

        if let data = userDefaults.data(
            forKey: UserDefaultsKey.customPromptPresets.rawValue
        ),
           let decoded = try? JSONDecoder().decode([SystemPromptPreset].self, from: data), !decoded.isEmpty {
            self.promptPresets = decoded
        } else {
            self.promptPresets = SystemPromptPreset.builtInPresets
        }
        let reconciledPreferences = Self.reconciledPromptPreferences(
            preferences,
            presets: promptPresets
        )
        if reconciledPreferences != preferences {
            self.preferences = reconciledPreferences
            AppPreferencesPersistence.save(
                reconciledPreferences,
                to: userDefaults
            )
        }

        if startServices {
            Task {
                await loadConversations()
                await refreshAgentSkills()
                await refreshWorkspaceInstructions()
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

    /// Selects a settings route; the calling view remains responsible for
    /// presenting the platform settings window.
    public func openSettings(tab: SettingsSection? = nil) {
        guard let tab else { return }
        settingsSelection = tab
    }

    public func savePromptPreset(_ preset: SystemPromptPreset) {
        let isDefault = preset.id == defaultSystemPromptPresetId
        if let idx = promptPresets.firstIndex(where: { $0.id == preset.id }) {
            promptPresets[idx] = preset
        } else {
            promptPresets.append(preset)
        }
        persistPromptPresets()
        if isDefault {
            setDefaultSystemPrompt(text: preset.promptText, presetId: preset.id)
        }
    }

    public func updatePromptPresetText(id: UUID, promptText: String) {
        guard let index = promptPresets.firstIndex(where: { $0.id == id }) else {
            return
        }
        promptPresets[index].promptText = promptText
        persistPromptPresets()
        if id == defaultSystemPromptPresetId {
            setDefaultSystemPrompt(text: promptText, presetId: id)
        }
    }

    public func isDefaultPromptPreset(id: UUID) -> Bool {
        defaultSystemPromptPresetId == id
    }

    public func setDefaultPromptPreset(id: UUID) {
        guard let preset = promptPresets.first(where: { $0.id == id }) else {
            return
        }
        setDefaultSystemPrompt(text: preset.promptText, presetId: preset.id)
    }

    public func deletePromptPreset(id: UUID) {
        guard let preset = promptPresets.first(where: {
            $0.id == id && !$0.isBuiltIn
        }) else {
            return
        }
        promptPresets.removeAll(where: { $0.id == preset.id })
        persistPromptPresets()
        if preset.id == defaultSystemPromptPresetId {
            setFactoryDefaultPrompt()
        }
    }

    public func resetToFactoryPresets() {
        self.promptPresets = SystemPromptPreset.builtInPresets
        persistPromptPresets()
        setFactoryDefaultPrompt()
    }

    private func setDefaultSystemPrompt(text: String, presetId: UUID?) {
        var updatedPreferences = preferences
        updatedPreferences.defaultSystemPrompt = text
        updatedPreferences.defaultSystemPromptPresetId = presetId
        preferences = updatedPreferences
    }

    private func setFactoryDefaultPrompt() {
        let presetId = Self.preferredPreset(
            matching: AppPreferences.defaultSystemPromptText,
            in: promptPresets
        )?.id
        setDefaultSystemPrompt(
            text: AppPreferences.defaultSystemPromptText,
            presetId: presetId
        )
    }

    private static func reconciledPromptPreferences(
        _ preferences: AppPreferences,
        presets: [SystemPromptPreset]
    ) -> AppPreferences {
        var reconciled = preferences
        if let presetId = preferences.defaultSystemPromptPresetId,
           let preset = presets.first(where: { $0.id == presetId }) {
            reconciled.defaultSystemPrompt = preset.promptText
            return reconciled
        }
        reconciled.defaultSystemPromptPresetId = preferredPreset(
            matching: preferences.defaultSystemPrompt,
            in: presets
        )?.id
        return reconciled
    }

    private static func preferredPreset(
        matching promptText: String,
        in presets: [SystemPromptPreset]
    ) -> SystemPromptPreset? {
        presets.first(where: {
            $0.isBuiltIn && $0.promptText == promptText
        }) ?? presets.first(where: { $0.promptText == promptText })
    }

    private func persistPromptPresets() {
        if let data = try? JSONEncoder().encode(promptPresets) {
            userDefaults.set(
                data,
                forKey: UserDefaultsKey.customPromptPresets.rawValue
            )
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
            guard let id = selectedConversationId,
                  let newValue,
                  newValue.id == id else {
                return
            }
            if let index = conversations.firstIndex(where: { $0.id == id }) {
                conversations[index] = newValue
            }
        }
    }

    public var filteredConversations: [Conversation] {
        var result = conversations.filter {
            selectedProjectScope.includes(
                projectPath: $0.projectPath,
                currentProjectDirectory: sandboxDirectory
            )
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

    public func requestClearConversationMessages(
        id: UUID,
        presentationScope: AppConfirmationPresentationScope = .mainWindow
    ) {
        requestConfirmation(
            for: .clearConversation(id),
            presentationScope: presentationScope
        )
    }

    public func requestDeleteConversation(
        id: UUID,
        presentationScope: AppConfirmationPresentationScope = .mainWindow
    ) {
        requestConfirmation(
            for: .deleteConversation(id),
            presentationScope: presentationScope
        )
    }

    public func requestDeletePromptPreset(
        id: UUID,
        presentationScope: AppConfirmationPresentationScope = .mainWindow
    ) {
        requestConfirmation(
            for: .deletePromptPreset(id),
            presentationScope: presentationScope
        )
    }

    public func requestDeleteModelProfile(
        id: UUID,
        presentationScope: AppConfirmationPresentationScope = .mainWindow
    ) {
        requestConfirmation(
            for: .deleteModelProfile(id),
            presentationScope: presentationScope
        )
    }

    public func requestRemoveMCPServer(
        id: String,
        presentationScope: AppConfirmationPresentationScope = .mainWindow
    ) {
        requestConfirmation(
            for: .removeMCPServer(id),
            presentationScope: presentationScope
        )
    }

    public func requestResetPromptPresets(
        presentationScope: AppConfirmationPresentationScope = .mainWindow
    ) {
        requestConfirmation(
            for: .resetPromptPresets,
            presentationScope: presentationScope
        )
    }

    private func requestConfirmation(
        for action: AppConfirmationAction,
        presentationScope: AppConfirmationPresentationScope
    ) {
        guard confirmationUnavailabilityMessage(for: action) == nil else {
            return
        }
        queueConfirmation(
            confirmationRequest(
                for: action,
                presentationScope: presentationScope
            )
        )
    }

    private func confirmationRequest(
        for action: AppConfirmationAction,
        presentationScope: AppConfirmationPresentationScope
    ) -> AppConfirmationRequest {
        let content: (title: String, message: String, buttonTitle: String)
        switch action {
        case .clearConversation:
            content = (
                "Clear this conversation?",
                "This removes every message from the conversation.",
                "Clear Messages"
            )
        case .deleteConversation:
            content = (
                "Delete this conversation?",
                "The conversation and its messages will be permanently removed.",
                "Delete Conversation"
            )
        case .deleteModelProfile:
            content = (
                "Delete this model profile?",
                "The selected model profile will be permanently removed.",
                "Delete Profile"
            )
        case .deletePromptPreset:
            content = (
                "Delete this custom prompt?",
                "The custom prompt will be permanently removed.",
                "Delete Prompt"
            )
        case .removeMCPServer(let id):
            let displayName = mcpServers.first(where: { $0.id == id })?
                .displayName ?? "this server"
            content = (
                "Remove \(displayName)?",
                "The local MCP server configuration will be permanently removed.",
                "Remove Server"
            )
        case .resetPromptPresets:
            content = (
                "Reset system prompts?",
                "Custom prompts will be removed and the factory default restored.",
                "Reset Prompts"
            )
        }
        return AppConfirmationRequest(
            action: action,
            title: content.title,
            message: content.message,
            confirmButtonTitle: content.buttonTitle,
            presentationScope: presentationScope
        )
    }

    private func queueConfirmation(_ request: AppConfirmationRequest) {
        let scope = request.presentationScope
        guard pendingConfirmations[scope] == nil else { return }
        pendingConfirmations[scope] = request
    }

    @discardableResult
    public func confirmPendingAction() -> Bool {
        guard let request = pendingConfirmation else { return false }
        return confirmPendingAction(
            id: request.id,
            in: request.presentationScope
        )
    }

    @discardableResult
    public func confirmPendingAction(
        id: UUID,
        in scope: AppConfirmationPresentationScope
    ) -> Bool {
        guard let request = pendingConfirmation(in: scope),
              request.id == id else {
            return false
        }
        guard canConfirm(request) else {
            pendingConfirmations[scope] = nil
            return false
        }
        pendingConfirmations[scope] = nil
        switch request.action {
        case .clearConversation(let id):
            clearConversationMessages(id: id)
        case .deleteConversation(let id):
            deleteConversation(id: id)
        case .deleteModelProfile(let id):
            deleteModelProfile(id: id)
        case .deletePromptPreset(let id):
            deletePromptPreset(id: id)
        case .removeMCPServer(let id):
            removeMCPServer(id: id)
        case .resetPromptPresets:
            resetToFactoryPresets()
        }
        return true
    }

    public func dismissPendingConfirmation() {
        guard let request = pendingConfirmation else { return }
        dismissPendingConfirmation(
            id: request.id,
            in: request.presentationScope
        )
    }

    public func dismissPendingConfirmation(
        id: UUID,
        in scope: AppConfirmationPresentationScope
    ) {
        guard pendingConfirmation(in: scope)?.id == id else { return }
        pendingConfirmations[scope] = nil
    }

    func setConfirmationPresented(
        _ isPresented: Bool,
        id: UUID,
        in scope: AppConfirmationPresentationScope
    ) {
        guard !isPresented else { return }
        dismissPendingConfirmation(id: id, in: scope)
    }

    public func pendingConfirmation(
        in scope: AppConfirmationPresentationScope
    ) -> AppConfirmationRequest? {
        pendingConfirmations[scope]
    }

    public func canConfirm(_ request: AppConfirmationRequest) -> Bool {
        confirmationUnavailabilityMessage(for: request.action) == nil
    }

    public func confirmationMessage(
        for request: AppConfirmationRequest
    ) -> String {
        guard let unavailable = confirmationUnavailabilityMessage(
            for: request.action
        ) else {
            return request.message
        }
        return "\(request.message)\n\n\(unavailable)"
    }

    private func confirmationUnavailabilityMessage(
        for action: AppConfirmationAction
    ) -> String? {
        switch action {
        case .clearConversation(let id), .deleteConversation(let id):
            guard conversations.contains(where: { $0.id == id }) else {
                return "This conversation is no longer available."
            }
            guard !isConversationGenerating(id) else {
                return "Wait for the active response to finish before continuing."
            }
            return nil
        case .deleteModelProfile(let id):
            guard runtimeConfiguration.profiles.count > 1,
                  runtimeConfiguration.activeProfileId != id,
                  runtimeConfiguration.profiles.contains(where: { $0.id == id }) else {
                return "This model profile can no longer be deleted."
            }
            return nil
        case .deletePromptPreset(let id):
            guard promptPresets.contains(where: { $0.id == id && !$0.isBuiltIn }) else {
                return "This prompt can no longer be deleted."
            }
            return nil
        case .removeMCPServer(let id):
            guard mcpServers.contains(where: { $0.id == id }) else {
                return "This MCP server is no longer available."
            }
            return nil
        case .resetPromptPresets:
            return nil
        }
    }

    public func requestStopGeneration() {
        guard let conversationID = selectedConversationId,
              isConversationGenerating(conversationID) else {
            return
        }
        guard !pendingCommandRequests.contains(where: {
            $0.command == .stopGeneration
                && $0.conversationID == conversationID
        }) else {
            return
        }
        pendingCommandRequests.append(AppCommandRequest(
            command: .stopGeneration,
            conversationID: conversationID
        ))
    }

    public func acknowledgeCommandRequest(id: UUID) {
        guard let requestIndex = pendingCommandRequests.firstIndex(where: {
            $0.id == id
        }) else {
            return
        }
        pendingCommandRequests.remove(at: requestIndex)
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
            clearPresentedOperationError(for: .workspaceAuthorization)
        } catch {
            presentOperationError(
                .workspaceAuthorization(message: error.localizedDescription),
                error: error
            )
            return
        }
        applySandboxDirectory(workspaceURL)
        Task {
            await refreshAgentSkills()
            await refreshWorkspaceInstructions()
        }
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
            clearPresentedOperationError(for: .workspaceAuthorization)
        } catch {
            presentOperationError(
                .workspaceAuthorization(message: error.localizedDescription),
                error: error
            )
            activeAgentModeConversationIds.remove(id)
            return
        }

        applySandboxDirectory(workspaceURL)
        Task {
            await refreshAgentSkills()
            await refreshWorkspaceInstructions()
        }
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].projectPath = workspaceURL.path
            conversations[index].touch()
            saveConversation(conversations[index])
        }
    }

    public func refreshAgentSkills() async {
        let service = agentSkillService
        let workspaceURL = sandboxDirectory
        agentSkills = await Task.detached(priority: .utility) {
            service.discover(workspaceURL: workspaceURL)
        }.value
    }

    public func setAgentSkill(_ skill: AgentSkill, enabled: Bool) {
        if enabled {
            enabledAgentSkillIDs.insert(skill.id)
        } else {
            enabledAgentSkillIDs.remove(skill.id)
        }
        userDefaults.set(
            Array(enabledAgentSkillIDs).sorted(),
            forKey: UserDefaultsKey.enabledAgentSkillIDs.rawValue
        )
    }

    public func refreshWorkspaceInstructions() async {
        let service = workspaceInstructionService
        let workspaceURL = sandboxDirectory
        workspaceInstructions = await Task.detached(priority: .utility) {
            service.load(workspaceURL: workspaceURL)
        }.value
    }

    public func workspaceInstructionDocument(
        at workspaceURL: URL
    ) -> WorkspaceInstructionDocument? {
        guard isWorkspaceInstructionsEnabled else { return nil }
        return workspaceInstructionService.load(workspaceURL: workspaceURL)
    }

    public func invokedAgentSkills(
        in prompt: String,
        workspaceURL: URL? = nil
    ) -> [AgentSkill] {
        let availableSkills = workspaceURL.map(agentSkillService.discover(workspaceURL:))
            ?? agentSkills
        return AgentSkillService.selectInvokedSkills(
            in: prompt,
            from: availableSkills,
            enabledSkillIDs: enabledAgentSkillIDs
        )
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

    public func presentedOperationError(
        in scope: AppPresentationScope
    ) -> AppOperationErrorPresentation? {
        guard presentedOperationError?.presentationScope == scope else {
            return nil
        }
        return presentedOperationError
    }

    public func setOperationErrorPresented(
        _ isPresented: Bool,
        in scope: AppPresentationScope
    ) {
        guard !isPresented,
              presentedOperationError(in: scope) != nil else {
            return
        }
        presentedOperationError = nil
    }

    private func clearPresentedOperationError(
        for kind: AppOperationErrorPresentation.Kind
    ) {
        guard presentedOperationError?.kind == kind else { return }
        presentedOperationError = nil
    }

    private func presentOperationError(
        _ presentation: AppOperationErrorPresentation,
        error: Error
    ) {
        let category = presentation.kind.rawValue
        let errorType = String(reflecting: type(of: error))
        Self.logger.error(
            "Operation failed: \(category, privacy: .public); \(errorType, privacy: .public)"
        )
        presentedOperationError = presentation
    }

    @discardableResult
    public func addMCPServer() -> MCPServerProfile {
        let profile = MCPServerProfile(
            id: "server_\(UUID().uuidString.lowercased().prefix(8))",
            isEnabled: false
        )
        mcpServers.append(profile)
        return profile
    }

    public func updateMCPServer(_ profile: MCPServerProfile) {
        guard let index = mcpServers.firstIndex(where: { $0.id == profile.id }) else { return }
        mcpServers[index] = profile
        mcpServerConnectionStates[profile.id] = .idle
    }

    private func updatePrimaryMCPServer(
        _ update: (inout MCPServerProfile) -> Void
    ) {
        guard var profile = mcpServers.first else {
            var defaultProfile = MCPServerProfile(id: Self.defaultMCPServerId)
            update(&defaultProfile)
            mcpServers = [defaultProfile]
            mcpServerConnectionStates[defaultProfile.id] = .idle
            return
        }
        update(&profile)
        updateMCPServer(profile)
    }

    public func removeMCPServer(id: String) {
        mcpServers.removeAll(where: { $0.id == id })
        mcpServerConnectionStates[id] = nil
    }

    public func setMCPServerConnectionState(
        _ state: MCPServerConnectionState,
        for id: String
    ) {
        guard mcpServers.contains(where: { $0.id == id }) else { return }
        mcpServerConnectionStates[id] = state
    }

    public func testMCPServer(id: String) async {
        await testMCPServer(id: id) { configuration in
            try await MCPHTTPClient.connect(configuration: configuration)
        }
    }

    func testMCPServer(
        id: String,
        clientFactory: MCPClientFactory
    ) async {
        guard let profile = mcpServers.first(where: { $0.id == id }) else { return }
        mcpServerConnectionStates[id] = .testing
        do {
            let configuration = try profile.configuration()
            let client = try await clientFactory(configuration)
            do {
                let tools = try await client.listTools()
                await client.close()
                guard mcpServers.first(where: { $0.id == id }) == profile else { return }
                mcpServerConnectionStates[id] = .connected(
                    tools: tools.map {
                        MCPDiscoveredTool(name: $0.name, description: $0.description)
                    }
                )
            } catch {
                await client.close()
                throw error
            }
        } catch is CancellationError {
            mcpServerConnectionStates[id] = .idle
        } catch {
            guard mcpServers.first(where: { $0.id == id }) == profile else { return }
            mcpServerConnectionStates[id] = .failed(message: error.localizedDescription)
        }
    }

    private func persistMCPServers() {
        guard let data = try? JSONEncoder().encode(mcpServers) else { return }
        userDefaults.set(
            data,
            forKey: UserDefaultsKey.mcpServerProfiles.rawValue
        )
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
            openSettings(tab: .engine)
            serverStatus = .disconnected(reason: runtimeSetupStatus.message)
            return
        }
        Task {
            await healthService.startEngine()
            try? await Task.sleep(
                for: Self.runtimeStartupHealthCheckDelay
            )
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
    public func toggleEngine() -> RuntimeLifecycleAction {
        let action = runtimeLifecycleAction
        switch action {
        case .start:
            startEngine()
        case .stop:
            stopEngine()
        case .external:
            break
        }
        return action
    }

    @discardableResult
    public func addModelProfile(
        name: String = "New Profile",
        targetPath: String = "",
        draftPath: String = ""
    ) -> RuntimeModelProfile? {
        let newProfile = RuntimeModelProfile(
            name: name,
            targetModelPath: targetPath,
            draftModelPath: draftPath
        )
        var nextConfiguration = runtimeConfiguration
        nextConfiguration.profiles.append(newProfile)
        guard persistRuntimeConfiguration(nextConfiguration) else { return nil }
        runtimeConfiguration = nextConfiguration
        selectedEditingProfileId = newProfile.id
        return newProfile
    }

    @discardableResult
    public func saveModelProfile(_ profile: RuntimeModelProfile) -> Bool {
        var nextConfiguration = runtimeConfiguration
        if let index = nextConfiguration.profiles.firstIndex(where: { $0.id == profile.id }) {
            nextConfiguration.profiles[index] = profile
        } else {
            nextConfiguration.profiles.append(profile)
        }
        let nextSetupStatus: RuntimeSetupStatus?
        if nextConfiguration.activeProfileId == profile.id {
            nextConfiguration.targetModelPath = profile.targetModelPath
            nextConfiguration.draftModelPath = profile.draftModelPath
            nextSetupStatus = runtimeConfigurationService.localValidation(profile)
        } else {
            nextSetupStatus = nil
        }
        guard persistRuntimeConfiguration(nextConfiguration) else { return false }
        runtimeConfiguration = nextConfiguration
        if let nextSetupStatus {
            runtimeSetupStatus = nextSetupStatus
        }
        return true
    }

    @discardableResult
    public func deleteModelProfile(id: UUID) -> Bool {
        guard runtimeConfiguration.profiles.count > 1 else { return false }
        guard runtimeConfiguration.activeProfileId != id else { return false }
        guard runtimeConfiguration.profiles.contains(where: { $0.id == id }) else {
            return false
        }
        var nextConfiguration = runtimeConfiguration
        nextConfiguration.profiles.removeAll(where: { $0.id == id })
        guard persistRuntimeConfiguration(nextConfiguration) else { return false }
        runtimeConfiguration = nextConfiguration
        if selectedEditingProfileId == id {
            selectedEditingProfileId = nextConfiguration.activeProfileId
        }
        return true
    }

    private func persistRuntimeConfiguration(
        _ configuration: RuntimeConfiguration
    ) -> Bool {
        do {
            try runtimeConfigurationService.save(configuration)
            clearPresentedOperationError(for: .runtimeProfilePersistence)
            return true
        } catch {
            presentOperationError(
                .runtimeProfilePersistence,
                error: error
            )
            return false
        }
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
                presentOperationError(
                    .runtimeProfilePersistence,
                    error: error
                )
                runtimeSetupStatus = .invalid(
                    AppOperationErrorPresentation.runtimeProfilePersistence.message
                )
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
        guard let conversation = selectedConversation else { return }
        let data = Data(Self.markdownExport(for: conversation).utf8)
        let suggestedFilename = Self.conversationExportSuggestedFilename(
            for: conversation.title
        )
        let destinationPicker = conversationExportDestinationPicker
        let writer = conversationExportWriter

        Task {
            guard let destination = await destinationPicker(
                suggestedFilename
            ) else {
                return
            }
            do {
                try await Task.detached(priority: .utility) {
                    try writer(data, destination)
                }.value
                clearPresentedOperationError(for: .conversationExport)
            } catch {
                presentOperationError(.conversationExport, error: error)
            }
        }
    }

    private static func conversationExportSuggestedFilename(
        for title: String
    ) -> String {
        let trimmedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        var sanitizedTitle = trimmedTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        let leadingDotCount = sanitizedTitle.prefix(while: { $0 == "." }).count
        if leadingDotCount > 0 {
            let unsafePrefixEnd = sanitizedTitle.index(
                sanitizedTitle.startIndex,
                offsetBy: leadingDotCount
            )
            sanitizedTitle.replaceSubrange(
                sanitizedTitle.startIndex..<unsafePrefixEnd,
                with: String(repeating: "-", count: leadingDotCount)
            )
        }
        let meaningfulTitle = sanitizedTitle.trimmingCharacters(
            in: CharacterSet(charactersIn: "-.")
                .union(.whitespacesAndNewlines)
        )
        guard !meaningfulTitle.isEmpty else {
            return "Untitled Conversation.md"
        }
        return "\(sanitizedTitle).md"
    }

    private static func markdownExport(for conversation: Conversation) -> String {
        var markdown = "# \(conversation.title)\n\n"
        if let projectPath = conversation.projectPath {
            markdown += "_Workspace: \(projectPath)_\n\n"
        }
        let createdAt = conversation.createdAt.formatted(
            date: .abbreviated,
            time: .shortened
        )
        markdown += "_Generated on \(createdAt) via Qwen Prime_\n\n---\n\n"

        for message in conversation.messages {
            let roleHeader = message.role == .user
                ? "### 👤 User"
                : "### 🤖 Qwen Prime"
            markdown += "\(roleHeader)\n\n"
            if let thinking = message.thinkingContent, !thinking.isEmpty {
                markdown += "<details><summary>Thought Process</summary>\n\n"
                markdown += "\(thinking)\n\n</details>\n\n"
            }
            markdown += "\(message.content)\n\n---\n\n"
        }
        return markdown
    }

    private static func chooseConversationExportDestination(
        suggestedFilename: String
    ) async -> URL? {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Conversation as Markdown"
        savePanel.nameFieldStringValue = suggestedFilename
        savePanel.allowedContentTypes = [.plainText]

        let response = await withCheckedContinuation { continuation in
            savePanel.begin { response in
                continuation.resume(returning: response)
            }
        }
        guard response == .OK else { return nil }
        return savePanel.url
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
