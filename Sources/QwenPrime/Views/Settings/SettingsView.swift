import SwiftUI
import AppKit

public struct SettingsView: View {
    @Bindable public var appState: AppState

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        TabView(selection: $appState.settingsSelection) {
            SystemPromptSettingsTab(appState: appState)
                .tabItem {
                    Label("System Prompts", systemImage: "text.bubble.fill")
                }
                .tag(SettingsSection.systemPrompts)

            AppearanceSettingsTab(appState: appState)
                .tabItem {
                    Label("Appearance", systemImage: "paintpalette.fill")
                }
                .tag(SettingsSection.appearance)

            EngineSettingsTab(appState: appState)
                .tabItem {
                    Label("Engine & MLX", systemImage: "bolt.horizontal.fill")
                }
                .tag(SettingsSection.engine)

            SandboxSettingsTab(appState: appState)
                .tabItem {
                    Label("Workspace", systemImage: "shippingbox.fill")
                }
                .tag(SettingsSection.sandbox)

            GeneralSettingsTab(appState: appState)
                .tabItem {
                    Label("General", systemImage: "gearshape.fill")
                }
                .tag(SettingsSection.general)

            ShortcutsSettingsTab()
                .tabItem {
                    Label("Shortcuts", systemImage: "command")
                }
                .tag(SettingsSection.shortcuts)
        }
        .frame(width: DesignTokens.Layout.settingsWindowWidth, height: DesignTokens.Layout.settingsWindowHeight)
    }
}

// MARK: - 1. System Prompts Tab (Modern Master-Detail Architecture)
struct SystemPromptSettingsTab: View {
    @Bindable var appState: AppState
    @State private var selectedPresetId: UUID = SystemPromptPreset.builtInPresets[0].id
    @State private var isAppliedFeedback: Bool = false

    private var selectedPreset: SystemPromptPreset? {
        appState.promptPresets.first(where: { $0.id == selectedPresetId }) ?? appState.promptPresets.first
    }

    var body: some View {
        HSplitView {
            // Left Master Sidebar: Prompt Preset List
            VStack(spacing: 0) {
                // Header & Add Button
                HStack {
                    Text("PROMPTS")
                        .font(.system(size: DesignTokens.Typography.footnote, weight: .bold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        let newPreset = SystemPromptPreset(
                            name: "New Prompt",
                            category: "Custom",
                            description: "Custom system instructions.",
                            icon: "pencil.line",
                            promptText: "You are a custom AI assistant.",
                            isBuiltIn: false
                        )
                        appState.savePromptPreset(newPreset)
                        selectedPresetId = newPreset.id
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: DesignTokens.Typography.subheadline, weight: .semibold))
                            .foregroundStyle(.cyan)
                            .padding(DesignTokens.Spacing.xs)
                            .background(Color.white.opacity(DesignTokens.Opacity.subtle), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .help("Add Custom Prompt")
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.base)
                .background(Color(nsColor: .controlBackgroundColor).opacity(DesignTokens.Opacity.strong))

                Divider().opacity(DesignTokens.Opacity.divider)

                // List of presets
                ScrollView {
                    LazyVStack(spacing: DesignTokens.Spacing.xs) {
                        ForEach(appState.promptPresets) { preset in
                            let isSelected = preset.id == selectedPresetId
                            let isDefault = preset.promptText == appState.defaultSystemPrompt

                            Button {
                                selectedPresetId = preset.id
                            } label: {
                                HStack(spacing: DesignTokens.Spacing.md) {
                                    Image(systemName: preset.icon)
                                        .font(.system(size: DesignTokens.Typography.subheadline))
                                        .foregroundStyle(isSelected ? .cyan : .secondary)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: DesignTokens.Spacing.xs) {
                                            Text(preset.name)
                                                .font(.system(size: DesignTokens.Typography.callout, weight: isSelected ? .semibold : .regular))
                                                .foregroundStyle(.primary)
                                                .lineLimit(1)

                                            if isDefault {
                                                Circle()
                                                    .fill(Color.cyan)
                                                    .frame(width: 5, height: 5)
                                                    .help("Active Default")
                                            }
                                        }

                                        Text(preset.category)
                                            .font(.system(size: DesignTokens.Typography.caption))
                                            .foregroundStyle(.tertiary)
                                    }

                                    Spacer()
                                }
                                .padding(.horizontal, DesignTokens.Spacing.base)
                                .padding(.vertical, DesignTokens.Spacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
                                        .fill(isSelected ? Color.white.opacity(DesignTokens.Opacity.hover) : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(DesignTokens.Spacing.sm)
                }

                Divider().opacity(DesignTokens.Opacity.divider)

                // Footer Actions
                HStack {
                    Button("Reset Defaults") {
                        appState.resetToFactoryPresets()
                        if let first = appState.promptPresets.first {
                            selectedPresetId = first.id
                        }
                    }
                    .font(.system(size: DesignTokens.Typography.footnote))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.vertical, DesignTokens.Spacing.sm)
            }
            .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))

            // Right Detail Editor
            if let preset = selectedPreset {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    // Header Bar (Name, Category, Actions)
                    HStack(spacing: DesignTokens.Spacing.md) {
                        Image(systemName: preset.icon)
                            .font(.system(size: DesignTokens.Typography.title3))
                            .foregroundStyle(.cyan)

                        VStack(alignment: .leading, spacing: 2) {
                            if preset.isBuiltIn {
                                Text(preset.name)
                                    .font(.system(size: DesignTokens.Typography.headline, weight: .bold))
                            } else {
                                TextField("Prompt Name", text: Binding(
                                    get: { preset.name },
                                    set: { var p = preset; p.name = $0; appState.savePromptPreset(p) }
                                ))
                                .font(.system(size: DesignTokens.Typography.headline, weight: .bold))
                                .textFieldStyle(.plain)
                            }

                            Text(preset.description)
                                .font(.system(size: DesignTokens.Typography.subheadline))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        if !preset.isBuiltIn {
                            Button(role: .destructive) {
                                appState.deletePromptPreset(id: preset.id)
                                if let next = appState.promptPresets.first {
                                    selectedPresetId = next.id
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: DesignTokens.Typography.subheadline))
                                    .foregroundStyle(.red.opacity(0.8))
                                    .padding(DesignTokens.Spacing.xs)
                            }
                            .buttonStyle(.plain)
                            .help("Delete Custom Prompt")
                        }
                    }
                    .padding(.bottom, DesignTokens.Spacing.xs)

                    // Text Editor Container
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        HStack {
                            Text("INSTRUCTIONS")
                                .font(.system(size: DesignTokens.Typography.footnote, weight: .bold))
                                .foregroundStyle(.secondary)

                            Spacer()

                            Text("\(preset.promptText.count) chars • ~\(max(1, preset.promptText.count / 4)) tokens")
                                .font(.system(size: DesignTokens.Typography.footnote, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }

                        TextEditor(text: Binding(
                            get: { preset.promptText },
                            set: {
                                var p = preset
                                p.promptText = $0
                                appState.savePromptPreset(p)
                                if preset.promptText == appState.defaultSystemPrompt {
                                    appState.defaultSystemPrompt = $0
                                }
                            }
                        ))
                        .font(.system(size: DesignTokens.Typography.callout, design: .monospaced))
                        .lineSpacing(DesignTokens.Typography.lineSpacingCode)
                        .padding(DesignTokens.Spacing.sm)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
                                .stroke(Color.white.opacity(DesignTokens.Opacity.subtle), lineWidth: 1)
                        )
                    }

                    // Action Toolbar
                    HStack(spacing: DesignTokens.Spacing.md) {
                        let isDefault = preset.promptText == appState.defaultSystemPrompt

                        Button {
                            appState.defaultSystemPrompt = preset.promptText
                        } label: {
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(isDefault ? .green : .secondary)
                                Text(isDefault ? "Default for New Chats" : "Set as Global Default")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        if isAppliedFeedback {
                            Text("Applied to Active Chat!")
                                .font(.system(size: DesignTokens.Typography.subheadline, weight: .semibold))
                                .foregroundStyle(.green)
                        }

                        Button("Apply to Active Chat") {
                            if var conv = appState.selectedConversation {
                                conv.systemPrompt = preset.promptText
                                conv.touch()
                                appState.selectedConversation = conv
                                appState.saveConversation(conv)
                                withAnimation { isAppliedFeedback = true }
                                Task {
                                    try? await Task.sleep(for: .seconds(2))
                                    withAnimation { isAppliedFeedback = false }
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(DesignTokens.Spacing.gutter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Select a Prompt", systemImage: "text.bubble")
            }
        }
    }
}

// MARK: - 2. Appearance Tab (Visual Interactive Theme Cards)
struct AppearanceSettingsTab: View {
    @Bindable var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
                // Section 1: Visual Theme Cards
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    Text("THEME PALETTES")
                        .font(.system(size: DesignTokens.Typography.footnote, weight: .bold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: DesignTokens.Spacing.lg) {
                        ForEach(ThemeType.allCases) { theme in
                            ThemePaletteCard(
                                theme: theme,
                                isSelected: appState.currentThemeType == theme,
                                onSelect: { appState.currentThemeType = theme }
                            )
                        }
                    }
                }

                // Section 2: Design Token System Overview
                GroupBox("Design Token Architecture") {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        HStack(spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.cyan)
                            Text("Apple Silicon Native Design System Active")
                                .font(.system(size: DesignTokens.Typography.callout, weight: .semibold))
                        }

                        Text("Centralized typographic scale, 12-point spacing intervals, adaptive opacity layers, and zero hardcoded magic numbers.")
                            .font(.system(size: DesignTokens.Typography.subheadline))
                            .foregroundStyle(.secondary)
                    }
                    .padding(DesignTokens.Spacing.sm)
                }
            }
            .padding(DesignTokens.Spacing.gutter)
        }
    }
}

// MARK: - 3. Engine & MLX Tab
struct EngineSettingsTab: View {
    @Bindable var appState: AppState

    private var currentProfile: RuntimeModelProfile {
        appState.editingModelProfile ?? appState.activeModelProfile ?? RuntimeModelProfile()
    }

    private var isActiveProfile: Bool {
        currentProfile.id == appState.runtimeConfiguration.activeProfileId
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                GroupBox("Local Runtime") {
                    HStack(spacing: DesignTokens.Spacing.base) {
                        Image(systemName: runtimeStatusIcon)
                            .foregroundStyle(runtimeStatusColor)
                            .font(.system(size: DesignTokens.Typography.title3))

                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            Text(runtimeStatusTitle)
                                .font(.system(size: DesignTokens.Typography.callout, weight: .semibold))
                            Text(appState.runtimeSetupStatus.message)
                                .font(.system(size: DesignTokens.Typography.caption))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        Spacer()

                        Button(
                            appState.serverStatus.isConnected
                                ? (appState.isRuntimeManaged ? "Stop Server" : "External Server")
                                : "Start Server"
                        ) {
                            if appState.serverStatus.isConnected {
                                if appState.isRuntimeManaged {
                                    appState.stopEngine()
                                }
                            } else {
                                appState.startEngine()
                            }
                        }
                        .disabled(
                            appState.serverStatus.isConnected
                                ? !appState.isRuntimeManaged
                                : appState.runtimeSetupStatus != .ready
                        )
                    }
                    .padding(DesignTokens.Spacing.md)
                }

                GroupBox("Model Profiles") {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
                        Text("Model weights stay outside the app and are never replaced by an update. Select your Qwen3.8 target and matching native-MTP draft (Hybrid Q8/Q4 or 6-bit recommended).")
                            .font(.system(size: DesignTokens.Typography.subheadline))
                            .foregroundStyle(.secondary)

                        HStack(spacing: DesignTokens.Spacing.md) {
                            Picker("Profile:", selection: Binding(
                                get: { appState.selectedEditingProfileId ?? appState.runtimeConfiguration.activeProfileId ?? currentProfile.id },
                                set: { newId in
                                    appState.selectedEditingProfileId = newId
                                }
                            )) {
                                ForEach(appState.runtimeConfiguration.profiles) { profile in
                                    HStack {
                                        Text(profile.name)
                                        if profile.id == appState.runtimeConfiguration.activeProfileId {
                                            Text("(Active)")
                                        }
                                    }
                                    .tag(profile.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: 240)

                            Button {
                                let newProfile = appState.addModelProfile(
                                    name: "New Profile",
                                    targetPath: "",
                                    draftPath: ""
                                )
                                appState.selectedEditingProfileId = newProfile.id
                            } label: {
                                Image(systemName: "plus")
                                Text("New Profile")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if appState.runtimeConfiguration.profiles.count > 1 && !isActiveProfile {
                                Button(role: .destructive) {
                                    appState.deleteModelProfile(id: currentProfile.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.red.opacity(0.8))
                                .help("Delete this profile")
                            }

                            Spacer()

                            if isActiveProfile {
                                HStack(spacing: DesignTokens.Spacing.xs) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                    Text("Active Profile")
                                        .font(.system(size: DesignTokens.Typography.caption, weight: .semibold))
                                        .foregroundStyle(.green)
                                }
                                .padding(.horizontal, DesignTokens.Spacing.sm)
                                .padding(.vertical, DesignTokens.Spacing.xxs)
                                .background(Color.green.opacity(DesignTokens.Opacity.faint), in: Capsule())
                            }
                        }

                        Divider().opacity(DesignTokens.Opacity.divider)

                        HStack {
                            Text("Profile Name")
                                .font(.system(size: DesignTokens.Typography.callout, weight: .medium))
                            Spacer()
                            TextField("Profile Name", text: Binding(
                                get: { currentProfile.name },
                                set: { newName in
                                    var updated = currentProfile
                                    updated.name = newName
                                    appState.saveModelProfile(updated)
                                }
                            ))
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 260)
                        }

                        modelPathRow(
                            title: "Target Model Folder",
                            path: currentProfile.targetModelPath,
                            buttonTitle: "Choose Target…"
                        ) {
                            if let url = chooseModelDirectory(prompt: "Choose Qwen3.8 27B target model folder") {
                                var updated = currentProfile
                                updated.targetModelPath = url.path
                                appState.saveModelProfile(updated)
                                appState.setRuntimeTargetModel(url)
                            }
                        }

                        Divider().opacity(DesignTokens.Opacity.divider)

                        modelPathRow(
                            title: "Native-MTP Draft Folder",
                            path: currentProfile.draftModelPath,
                            buttonTitle: "Choose Draft…"
                        ) {
                            if let url = chooseModelDirectory(prompt: "Choose matching Qwen3.8 native-MTP draft folder") {
                                var updated = currentProfile
                                updated.draftModelPath = url.path
                                appState.saveModelProfile(updated)
                                appState.setRuntimeDraftModel(url)
                            }
                        }

                        if let identity = appState.verifiedRuntimeIdentity, isActiveProfile && appState.serverStatus.isConnected {
                            HStack(spacing: DesignTokens.Spacing.xs) {
                                Image(systemName: "cpu")
                                    .foregroundStyle(.cyan)
                                Text("Verified Runtime Quantization: \(identity.quantizationSummary)")
                                    .font(.system(size: DesignTokens.Typography.caption))
                                    .foregroundStyle(.secondary)
                                Text(identity.featureSummary)
                                    .font(.system(size: DesignTokens.Typography.caption, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        HStack {
                            Text("Validation checks directories locally, then asks the bundled runtime to verify model identity, quantization, and the draft checksum.")
                                .font(.system(size: DesignTokens.Typography.caption))
                                .foregroundStyle(.tertiary)
                            Spacer()

                            if !isActiveProfile {
                                Button("Activate Profile") {
                                    appState.activateProfile(id: currentProfile.id)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(
                                    appState.isGenerating
                                        || !currentProfile.isConfigured
                                        || appState.runtimeSetupStatus == .validating
                                )
                                .help(appState.isGenerating ? "Cannot switch profile while generating" : "Activate this model profile")
                            } else {
                                Button("Save & Validate") {
                                    appState.saveAndValidateRuntimeConfiguration()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(
                                    appState.isGenerating
                                        || !currentProfile.isConfigured
                                        || appState.runtimeSetupStatus == .validating
                                )
                                .help(appState.isGenerating ? "Cannot switch profile while generating" : "Save and validate active profile")
                            }
                        }
                    }
                    .padding(DesignTokens.Spacing.md)
                }

                GroupBox("Connection & Response Mode") {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
                        HStack {
                            Text("Endpoint")
                                .font(.system(size: DesignTokens.Typography.callout))
                            Spacer()
                            TextField("http://127.0.0.1:8000/v1", text: $appState.baseURL)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 260)
                                .font(.system(size: DesignTokens.Typography.subheadline, design: .monospaced))
                        }

                        Toggle("Use reasoning mode for new conversations", isOn: $appState.defaultThinkingEnabled)
                            .font(.system(size: DesignTokens.Typography.callout))

                        Text("Direct mode suppresses deliberate reasoning. Actual throughput varies with context, thermals, and native-MTP acceptance.")
                            .font(.system(size: DesignTokens.Typography.caption))
                            .foregroundStyle(.secondary)
                    }
                    .padding(DesignTokens.Spacing.md)
                }
            }
            .padding(DesignTokens.Spacing.gutter)
        }
    }

    private var runtimeStatusTitle: String {
        switch appState.runtimeSetupStatus {
        case .notConfigured: "Setup required"
        case .validating: "Checking runtime"
        case .ready: appState.serverStatus.isConnected ? "Runtime active" : "Ready to start"
        case .invalid: "Setup needs attention"
        }
    }

    private var runtimeStatusIcon: String {
        switch appState.runtimeSetupStatus {
        case .notConfigured: "folder.badge.questionmark"
        case .validating: "hourglass"
        case .ready: appState.serverStatus.isConnected ? "checkmark.circle.fill" : "checkmark.circle"
        case .invalid: "exclamationmark.triangle.fill"
        }
    }

    private var runtimeStatusColor: Color {
        switch appState.runtimeSetupStatus {
        case .notConfigured: .secondary
        case .validating: .cyan
        case .ready: .green
        case .invalid: .orange
        }
    }

    private func modelPathRow(
        title: String,
        path: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: DesignTokens.Spacing.base) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                Text(title)
                    .font(.system(size: DesignTokens.Typography.callout, weight: .semibold))
                Text(path.isEmpty ? "No folder selected" : path)
                    .font(.system(size: DesignTokens.Typography.caption, design: .monospaced))
                    .foregroundStyle(path.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(path)
            }
            Spacer(minLength: DesignTokens.Spacing.md)
            Button(buttonTitle, action: action)
        }
    }

    private func chooseModelDirectory(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.message = prompt
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - 4. Sandbox Tab
struct SandboxSettingsTab: View {
    @Bindable var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                GroupBox("Active Project Workspace") {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
                        Text(appState.sandboxDirectory.path)
                            .font(.system(size: DesignTokens.Typography.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(DesignTokens.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(DesignTokens.Opacity.prominent), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base))

                        HStack(spacing: DesignTokens.Spacing.base) {
                            Button("Choose Folder...") {
                                let panel = NSOpenPanel()
                                panel.canChooseDirectories = true
                                panel.canChooseFiles = false
                                panel.allowsMultipleSelection = false
                                if panel.runModal() == .OK, let url = panel.url {
                                    appState.setSandboxDirectory(url)
                                }
                            }

                            Button("Reveal in Finder") {
                                appState.openSandboxInFinder()
                            }

                            Button("Open Terminal") {
                                appState.openSandboxInTerminal()
                            }
                        }
                    }
                    .padding(DesignTokens.Spacing.md)
                }

                GroupBox("Workspace Isolation & Guardrails") {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(Color.green)
                            Text("Ordinary chat does not read files or access the filesystem.")
                                .font(.system(size: DesignTokens.Typography.subheadline))
                        }

                        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundStyle(Color.green)
                            Text("Agent preview inspection is strictly scoped to the selected workspace folder.")
                                .font(.system(size: DesignTokens.Typography.subheadline))
                        }

                        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: "lock.shield.fill")
                                .foregroundStyle(Color.orange)
                            Text("Secret and sensitive paths (.git, .env, private keys) are blocked and denied access.")
                                .font(.system(size: DesignTokens.Typography.subheadline))
                        }

                        HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
                            Image(systemName: "hand.raised.shield.fill")
                                .foregroundStyle(Color.cyan)
                            Text("Read-only inspection only: no shell commands, terminal execution, or file changes are available.")
                                .font(.system(size: DesignTokens.Typography.subheadline))
                        }
                    }
                    .foregroundStyle(.secondary)
                    .padding(DesignTokens.Spacing.md)
                }

                Spacer()
            }
            .padding(DesignTokens.Spacing.gutter)
        }
    }
}

// MARK: - 5. General Tab
struct GeneralSettingsTab: View {
    @Bindable var appState: AppState
    @AppStorage("autoScroll") private var autoScroll: Bool = true
    @AppStorage("expandThinkingByDefault") private var expandThinkingByDefault: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                GroupBox("Chat Behavior") {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                        HStack {
                            Text("Default Model:")
                                .font(.system(size: DesignTokens.Typography.callout))
                            Spacer()
                            TextField("Model ID", text: $appState.selectedModel)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)
                                .font(.system(size: DesignTokens.Typography.subheadline, design: .monospaced))
                        }

                        Toggle("Auto-scroll to latest token while streaming", isOn: $autoScroll)
                            .font(.system(size: DesignTokens.Typography.callout))

                        Toggle("Expand Chain-of-Thought (<think>) by default", isOn: $expandThinkingByDefault)
                            .font(.system(size: DesignTokens.Typography.callout))
                    }
                    .padding(DesignTokens.Spacing.md)
                }

                GroupBox("Workspace Agent Preview") {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                        Toggle("Workspace Agent Preview", isOn: $appState.isAgentPreviewEnabled)
                            .font(.system(size: DesignTokens.Typography.callout))

                        Text("Read-only Agent mode lists folders and reads text files in the selected workspace. It cannot run shell commands or change files.")
                            .font(.system(size: DesignTokens.Typography.caption))
                            .foregroundStyle(.secondary)

                        HStack(spacing: DesignTokens.Spacing.xs) {
                            Image(systemName: appState.runtimeSupportsStructuredToolCalls ? "checkmark.circle.fill" : "info.circle")
                                .foregroundStyle(appState.runtimeSupportsStructuredToolCalls ? Color.green : Color.orange)
                            Text(appState.runtimeSupportsStructuredToolCalls
                                ? "Runtime structured tool calls supported."
                                : "Runtime structured tool support unavailable (active model or endpoint does not advertise tool calling).")
                                .font(.system(size: DesignTokens.Typography.caption))
                                .foregroundStyle(.secondary)
                        }

                        Text("Ordinary chat remains available and unaffected regardless of this preview setting.")
                            .font(.system(size: DesignTokens.Typography.caption))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(DesignTokens.Spacing.md)
                }

                GroupBox("About Qwen Prime") {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        HStack {
                            Text("Version:")
                                .font(.system(size: DesignTokens.Typography.callout))
                            Spacer()
                            Text("\((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "Development") (Apple Silicon Native)")
                                .font(.system(size: DesignTokens.Typography.callout))
                                .foregroundStyle(.secondary)
                        }

                        HStack {
                            Text("Engine Support:")
                                .font(.system(size: DesignTokens.Typography.callout))
                            Spacer()
                            Text("Apple Metal MLX & DFlash")
                                .font(.system(size: DesignTokens.Typography.callout))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(DesignTokens.Spacing.md)
                }

                Spacer()
            }
            .padding(DesignTokens.Spacing.gutter)
        }
    }
}

// MARK: - 6. Shortcuts Tab
struct ShortcutsSettingsTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
            GroupBox("Keyboard Shortcuts") {
                VStack(spacing: DesignTokens.Spacing.md) {
                    shortcutRow(action: "New Conversation", key: "⌘ N")
                    shortcutRow(action: "Clear Active Chat", key: "⌘ K")
                    shortcutRow(action: "Open Settings Window", key: "⌘ ,")
                    shortcutRow(action: "Reconnect to Engine", key: "⌘ ⇧ R")
                    shortcutRow(action: "Send Message", key: "Return")
                    shortcutRow(action: "Insert Newline in Input", key: "⇧ Return")
                    shortcutRow(action: "Stop Streaming Response", key: "Esc")
                }
                .padding(DesignTokens.Spacing.md)
            }

            Spacer()
        }
        .padding(DesignTokens.Spacing.gutter)
    }

    private func shortcutRow(action: String, key: String) -> some View {
        HStack {
            Text(action)
                .font(.system(size: DesignTokens.Typography.callout))
            Spacer()
            Text(key)
                .font(.system(size: DesignTokens.Typography.subheadline, weight: .semibold, design: .monospaced))
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, DesignTokens.Spacing.xs)
                .background(Color.white.opacity(DesignTokens.Opacity.subtle), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        }
    }
}

// MARK: - Theme Palette Card Component
struct ThemePaletteCard: View {
    let theme: ThemeType
    let isSelected: Bool
    let onSelect: () -> Void

    private var themeModel: MarkdownTheme {
        MarkdownTheme.theme(for: theme)
    }

    var body: some View {
        Button {
            onSelect()
        } label: {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
                // Header
                HStack {
                    Text(theme.rawValue)
                        .font(.system(size: DesignTokens.Typography.body, weight: .bold))
                        .foregroundStyle(themeModel.text)

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(themeModel.h1)
                            .font(.system(size: DesignTokens.Typography.headline))
                    }
                }

                // Swatches
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Circle().fill(themeModel.h1).frame(width: 14, height: 14)
                    Circle().fill(themeModel.userTextColor).frame(width: 14, height: 14)
                    Circle().fill(themeModel.quoteBorder).frame(width: 14, height: 14)
                    Circle().fill(themeModel.codeBlockBackground).frame(width: 14, height: 14)
                }

                // Mini Preview
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                    Text("Heading 1 Title")
                        .font(.system(size: DesignTokens.Typography.footnote, weight: .bold))
                        .foregroundStyle(themeModel.h1)

                    Text("Theme response preview.")
                        .font(.system(size: DesignTokens.Typography.caption))
                        .foregroundStyle(themeModel.secondaryText)
                }
                .padding(DesignTokens.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(themeModel.codeBlockBackground, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base))
            }
            .padding(DesignTokens.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .fill(Color.white.opacity(DesignTokens.Opacity.faint))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                    .stroke(isSelected ? themeModel.h1 : Color.white.opacity(DesignTokens.Opacity.subtle), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
