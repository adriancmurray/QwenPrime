import SwiftUI

public struct QuickSettingsPopover: View {
    @Bindable public var appState: AppState
    public let onOpenFullSettings: () -> Void
    public let onOpenSystemPrompt: () -> Void

    @State private var isClearConfirmationPresented = false

    public init(
        appState: AppState,
        onOpenFullSettings: @escaping () -> Void,
        onOpenSystemPrompt: @escaping () -> Void
    ) {
        self.appState = appState
        self.onOpenFullSettings = onOpenFullSettings
        self.onOpenSystemPrompt = onOpenSystemPrompt
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xl) {
            header
            Divider().opacity(DesignTokens.Opacity.divider)
            appearanceSection
            Divider().opacity(DesignTokens.Opacity.divider)
            conversationSection
            Divider().opacity(DesignTokens.Opacity.divider)
            runtimeSection
        }
        .padding(DesignTokens.Spacing.gutter)
        .frame(width: DesignTokens.Layout.quickSettingsPopoverWidth)
        .primeGlassSurface(cornerRadius: DesignTokens.Radius.xl)
        .alert("Clear this conversation?", isPresented: $isClearConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive, action: clearMessages)
        } message: {
            Text("This removes every message in the selected conversation.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Quick Settings")
                    .font(.system(size: DesignTokens.Typography.headline, weight: .semibold))
                Text("Tune this workspace without leaving the chat.")
                    .font(.system(size: DesignTokens.Typography.caption))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("All Settings…", action: onOpenFullSettings)
                .font(.system(size: DesignTokens.Typography.caption, weight: .medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundStyle(.primary)
                .help("Open all Qwen Prime settings")
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Appearance")
                .quickSettingsSectionLabel()

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: DesignTokens.Spacing.sm
            ) {
                ForEach(ThemeType.allCases) { theme in
                    ThemeOptionButton(
                        theme: theme,
                        isSelected: appState.currentThemeType == theme
                    ) {
                        appState.currentThemeType = theme
                    }
                }
            }
        }
    }

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Conversation")
                .quickSettingsSectionLabel()

            QuickSettingsActionRow(
                icon: "text.bubble",
                title: "System prompts",
                detail: "Defaults and reusable presets",
                action: onOpenSystemPrompt
            )

            QuickSettingsActionRow(
                icon: "square.and.arrow.up",
                title: "Export Markdown",
                detail: "Save the current conversation",
                action: appState.exportConversationAsMarkdown
            )

            QuickSettingsActionRow(
                icon: "trash",
                title: "Clear messages",
                detail: "Keep the conversation settings",
                tint: .red,
                isEnabled: !selectedConversationIsGenerating
            ) {
                isClearConfirmationPresented = true
            }
        }
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Runtime")
                .quickSettingsSectionLabel()

            HStack(spacing: DesignTokens.Spacing.md) {
                HStack(spacing: DesignTokens.Spacing.md) {
                    ZStack(alignment: .bottomTrailing) {
                        Image(systemName: "cpu")
                            .font(.system(size: DesignTokens.Typography.subheadline, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(DesignTokens.Surface.subtle, in: Circle())

                        Circle()
                            .fill(appState.serverStatus.isConnected ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                            .overlay(Circle().stroke(DesignTokens.Surface.opaqueFallback, lineWidth: 1.5))
                    }

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(appState.activeModelProfile?.name ?? "Qwen 3.8 27B")
                            .font(.system(size: DesignTokens.Typography.callout, weight: .semibold))
                            .lineLimit(1)
                        Text(runtimeQuantizationSummary)
                            .font(.system(size: DesignTokens.Typography.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    appState.serverStatus.isConnected
                        ? "\(appState.activeModelProfile?.name ?? "Qwen 3.8 27B"), \(runtimeQuantizationSummary), connected"
                        : "\(appState.activeModelProfile?.name ?? "Qwen 3.8 27B") runtime offline"
                )

                Spacer(minLength: DesignTokens.Spacing.sm)

                Button(action: toggleRuntime) {
                    Label(
                        appState.serverStatus.isConnected
                            ? (appState.isRuntimeManaged ? "Stop Runtime" : "External Runtime")
                            : "Start Runtime",
                        systemImage: appState.serverStatus.isConnected
                            ? (appState.isRuntimeManaged ? "power" : "link")
                            : "play.fill"
                    )
                    .font(.system(size: DesignTokens.Typography.caption, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(
                    appState.isGenerating
                        || (appState.serverStatus.isConnected && !appState.isRuntimeManaged)
                )
                .help(
                    appState.isGenerating
                        ? "Stop the active response before changing the runtime"
                        : (appState.serverStatus.isConnected
                            ? (appState.isRuntimeManaged
                                ? "Stop the local model server"
                                : "This runtime is managed outside Qwen Prime")
                            : "Start the local model server")
                )
            }

            Menu {
                ForEach(appState.runtimeConfiguration.profiles) { profile in
                    Button {
                        appState.activateProfile(id: profile.id)
                    } label: {
                        HStack {
                            Text(profile.name)
                            if profile.id == appState.runtimeConfiguration.activeProfileId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button("Manage Profiles…") {
                    onOpenFullSettings()
                    appState.settingsSelection = .engine
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: DesignTokens.Typography.caption))
                    Text(appState.activeModelProfile?.name ?? "Select Profile")
                        .font(.system(size: DesignTokens.Typography.caption, weight: .medium))
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: DesignTokens.Typography.micro))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(height: 30)
                .background(
                    DesignTokens.Surface.subtle,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
                )
            }
            .menuStyle(.borderlessButton)
            .disabled(appState.isGenerating)
            .help(appState.isGenerating ? "Cannot switch profile while generating" : "Switch active model profile")

            Button {
                UpdaterService.shared.checkForUpdates()
            } label: {
                HStack(spacing: DesignTokens.Spacing.md) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Check for Updates")
                        .fontWeight(.medium)
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development")
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: DesignTokens.Typography.caption))
                .padding(.horizontal, DesignTokens.Spacing.md)
                .frame(height: 32)
                .background(
                    DesignTokens.Surface.subtle,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
                )
            }
            .buttonStyle(.plain)
            .disabled(!UpdaterService.shared.canCheckForUpdates)
            .help(
                UpdaterService.shared.isConfigured
                    ? "Check GitHub Releases for a signed Qwen Prime update"
                    : "Updates become available in signed public builds"
            )
            .accessibilityLabel("Check for Qwen Prime updates")
        }
    }

    private var runtimeQuantizationSummary: String {
        if appState.serverStatus.isConnected {
            guard let identity = appState.verifiedRuntimeIdentity else { return "Active" }
            return "\(identity.quantizationSummary) · \(identity.featureSummary)"
        }
        return appState.activeModelProfile?.isConfigured == true ? "Configured · Offline" : "Setup Required"
    }

    private var selectedConversationIsGenerating: Bool {
        appState.selectedConversationId.map(appState.isConversationGenerating) ?? false
    }

    private func toggleRuntime() {
        if appState.serverStatus.isConnected {
            if appState.isRuntimeManaged {
                appState.stopEngine()
            }
        } else {
            appState.startEngine()
        }
    }

    private func clearMessages() {
        guard let conversationID = appState.selectedConversationId else { return }
        appState.clearConversationMessages(id: conversationID)
    }
}

private struct ThemeOptionButton: View {
    let theme: ThemeType
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var themeModel: MarkdownTheme {
        MarkdownTheme.theme(for: theme)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Circle()
                    .fill(themeModel.codeBlockBackground)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().fill(themeModel.h1).frame(width: 8, height: 8))

                Text(theme.rawValue)
                    .font(.system(size: DesignTokens.Typography.caption, weight: .medium))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: DesignTokens.Typography.micro, weight: .bold))
                        .foregroundStyle(themeModel.h1)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(height: 32)
            .background(
                isSelected ? DesignTokens.Surface.selected : DesignTokens.Surface.subtle,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
                    .stroke(isSelected ? themeModel.h1.opacity(0.45) : DesignTokens.Stroke.separator)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use \(theme.rawValue) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(reduceMotion ? nil : DesignTokens.AnimationCurve.standard, value: isSelected)
    }
}

private struct QuickSettingsActionRow: View {
    let icon: String
    let title: String
    let detail: String
    var tint: Color = .primary
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: DesignTokens.Typography.subheadline, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(title)
                        .font(.system(size: DesignTokens.Typography.callout, weight: .medium))
                        .foregroundStyle(tint)
                    Text(detail)
                        .font(.system(size: DesignTokens.Typography.caption))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: DesignTokens.Typography.micro, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(minHeight: 42)
            .background(
                isHovered ? DesignTokens.Surface.selected : Color.clear,
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : DesignTokens.AnimationCurve.hover) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}

private extension View {
    func quickSettingsSectionLabel() -> some View {
        font(.system(size: DesignTokens.Typography.caption, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.5)
    }
}
