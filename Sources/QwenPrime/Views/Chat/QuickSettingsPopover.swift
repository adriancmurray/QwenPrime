import SwiftUI

public struct QuickSettingsPopover: View {
    @Bindable public var appState: AppState
    public let onOpenSettings: (SettingsSection?) -> Void
    @State private var isRuntimeProfilePickerPresented = false

    public init(
        appState: AppState,
        onOpenSettings: @escaping (SettingsSection?) -> Void
    ) {
        self.appState = appState
        self.onOpenSettings = onOpenSettings
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
        .primeGlassSurface(
            cornerRadius: DesignTokens.Radius.xl
        )
        .tint(appState.activeTheme.h1)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Quick Settings")
                    .font(DesignTokens.TextStyle.headline.weight(.semibold))
                Text("Tune this chat.")
                    .font(DesignTokens.TextStyle.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button("All Settings…") {
                onOpenSettings(nil)
            }
            .font(DesignTokens.TextStyle.caption.weight(.medium))
            .buttonStyle(.bordered)
            .controlSize(.small)
            .foregroundStyle(.primary)
            .help("Open all Qwen Prime settings")
        }
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            SettingsSectionLabel(title: "Appearance")

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
            SettingsSectionLabel(title: "Conversation")

            QuickSettingsActionRow(
                icon: "text.bubble",
                title: "System prompts",
                detail: "Defaults and reusable presets",
                action: { onOpenSettings(.systemPrompts) }
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
                tint: DesignTokens.Status.danger,
                isEnabled: !selectedConversationIsGenerating,
                action: requestClearMessages
            )
        }
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            SettingsSectionLabel(title: "Runtime")

            VStack(spacing: DesignTokens.Spacing.sm) {
                runtimeStatusRow
                    .background(
                        DesignTokens.Surface.subtle,
                        in: runtimeCardShape
                    )

                runtimeProfileSelector
                    .frame(maxWidth: .infinity)
                    .background(
                        DesignTokens.Surface.subtle,
                        in: runtimeCardShape
                    )
            }

            runtimeUpdateAction
        }
    }

    private var runtimeCardShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: DesignTokens.Radius.md,
            style: .continuous
        )
    }

    private var runtimeStatusRow: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "cpu")
                    .font(DesignTokens.TextStyle.subheadline.weight(.medium))
                    .foregroundStyle(runtimeStatusColor)
                    .frame(width: 28, height: 28)
                    .background(runtimeStatusColor.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text("Local Runtime")
                        .font(DesignTokens.TextStyle.callout.weight(.semibold))
                    Text(runtimeStatusDetail)
                        .font(DesignTokens.TextStyle.captionMonospaced)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(runtimeAccessibilityLabel)

            Spacer(minLength: DesignTokens.Spacing.sm)

            Button {
                appState.toggleEngine()
            } label: {
                Label(
                    appState.runtimeLifecycleAction.title,
                    systemImage: runtimeLifecycleSymbol
                )
                .font(DesignTokens.TextStyle.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(
                appState.isGenerating
                    || (appState.serverStatus.isConnected && !appState.isRuntimeManaged)
            )
            .help(runtimeLifecycleHelp)
        }
        .padding(DesignTokens.Spacing.md)
        .frame(minHeight: DesignTokens.Layout.quickSettingsControlHeight)
    }

    private var runtimeProfileSelector: some View {
        Button {
            isRuntimeProfilePickerPresented = true
        } label: {
            runtimeProfileCard
        }
        .buttonStyle(.plain)
        .disabled(appState.isGenerating)
        .popover(
            isPresented: $isRuntimeProfilePickerPresented,
            arrowEdge: .bottom
        ) {
            runtimeProfilePicker
        }
        .help(
            appState.isGenerating
                ? "Cannot switch profile while generating"
                : "Switch active model profile"
        )
        .accessibilityLabel("Runtime profile: \(runtimeModelSummary)")
    }

    private var runtimeProfileCard: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "slider.horizontal.3")
                .font(DesignTokens.TextStyle.subheadline.weight(.medium))
                .foregroundStyle(appState.activeTheme.h1)
                .frame(width: 28, height: 28)
                .background(appState.activeTheme.h1.opacity(0.14), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text("Profile")
                    .font(DesignTokens.TextStyle.callout.weight(.semibold))
                Text(runtimeModelSummary)
                    .font(DesignTokens.TextStyle.captionMonospaced)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: DesignTokens.Spacing.sm)

            Image(systemName: "chevron.down")
                .font(DesignTokens.TextStyle.micro)
                .foregroundStyle(appState.activeTheme.h1)
                .accessibilityHidden(true)
        }
        .padding(DesignTokens.Spacing.md)
        .frame(
            maxWidth: .infinity,
            minHeight: DesignTokens.Layout.quickSettingsControlHeight,
            alignment: .leading
        )
        .contentShape(Rectangle())
        .opacity(appState.isGenerating ? DesignTokens.Opacity.disabled : 1)
    }

    private var runtimeProfilePicker: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            ThemedPopoverSectionTitle("Runtime Profile")

            ForEach(appState.runtimeConfiguration.profiles) { profile in
                ThemedPopoverActionRow(
                    title: profile.displaySummary,
                    systemImage: "slider.horizontal.3",
                    selectionTint: appState.activeTheme.h1,
                    isSelected: profile.id
                        == appState.runtimeConfiguration.activeProfileId,
                    trailingSystemImage: profile.id
                        == appState.runtimeConfiguration.activeProfileId
                        ? "checkmark"
                        : nil
                ) {
                    appState.activateProfile(id: profile.id)
                    isRuntimeProfilePickerPresented = false
                }
            }

            Divider().padding(.vertical, DesignTokens.Spacing.xxs)

            ThemedPopoverActionRow(
                title: "Manage Profiles…",
                systemImage: "slider.horizontal.3",
                selectionTint: appState.activeTheme.h1,
                foregroundColor: appState.activeTheme.h1
            ) {
                isRuntimeProfilePickerPresented = false
                onOpenSettings(.engine)
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .bottomAttachedPopoverContent()
        .frame(width: DesignTokens.Layout.runtimeProfilePickerPopoverWidth)
        .tint(appState.activeTheme.h1)
    }

    private var runtimeUpdateAction: some View {
        Button {
            UpdaterService.shared.checkForUpdates()
        } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text("Check for Updates")
                    .fontWeight(.medium)
                Spacer()
                Text(AppVersionPresentation.shortVersion)
            }
            .font(DesignTokens.TextStyle.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, DesignTokens.Spacing.xs)
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

    private var runtimeStatusColor: Color {
        appState.serverStatus.isConnected
            ? DesignTokens.Status.success
            : DesignTokens.Status.warning
    }

    private var runtimeLifecycleSymbol: String {
        switch appState.runtimeLifecycleAction {
        case .start:
            "play.fill"
        case .stop:
            "power"
        case .external:
            "link"
        }
    }

    private var runtimeLifecycleHelp: String {
        if appState.isGenerating {
            return "Stop the active response before changing the runtime"
        }
        if appState.serverStatus.isConnected {
            return appState.isRuntimeManaged
                ? "Stop the local model server"
                : "This runtime is managed outside Qwen Prime"
        }
        return "Start the local model server"
    }

    private var runtimeStatusDetail: String {
        if appState.serverStatus.isConnected {
            guard let identity = appState.verifiedRuntimeIdentity else { return "Active" }
            return "\(identity.quantizationSummary) · \(identity.featureSummary)"
        }
        return appState.activeModelProfile?.isConfigured == true ? "Configured · Offline" : "Setup Required"
    }

    private var runtimeModelSummary: String {
        appState.activeModelProfile?.displaySummary ?? AppPreferences.defaultModel
    }

    private var runtimeAccessibilityLabel: String {
        if appState.serverStatus.isConnected {
            return "\(runtimeModelSummary), \(runtimeStatusDetail), connected"
        }
        return "\(runtimeModelSummary) runtime offline"
    }

    private var selectedConversationIsGenerating: Bool {
        appState.selectedConversationId.map(appState.isConversationGenerating) ?? false
    }

    private func requestClearMessages() {
        guard let conversationID = appState.selectedConversationId else { return }
        appState.requestClearConversationMessages(id: conversationID)
    }
}

private struct ThemeOptionButton: View {
    let theme: ThemeType
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @FocusState private var isFocused: Bool

    private var themeModel: MarkdownTheme {
        MarkdownTheme.theme(for: theme).resolved(for: contrast)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Circle()
                    .fill(themeModel.codeBlockBackground)
                    .frame(width: 18, height: 18)
                    .overlay(Circle().fill(themeModel.h1).frame(width: 8, height: 8))

                Text(theme.rawValue)
                    .font(DesignTokens.TextStyle.caption.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(DesignTokens.TextStyle.micro.weight(.bold))
                        .foregroundStyle(themeModel.h1)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(height: 32)
            .background(
                isSelected || isFocused
                    ? DesignTokens.Surface.adaptiveSelected(
                        tint: themeModel.h1,
                        contrast: contrast,
                        reduceTransparency: reduceTransparency
                    )
                    : DesignTokens.Surface.adaptiveSubtle(
                        contrast: contrast,
                        reduceTransparency: reduceTransparency
                    ),
                in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
                    .stroke(
                        isSelected || isFocused
                            ? DesignTokens.Stroke.adaptiveFocus(
                                tint: themeModel.h1,
                                contrast: contrast
                            )
                            : DesignTokens.Stroke.adaptiveSeparator(
                                contrast: contrast
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .focused($isFocused)
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
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: icon)
                    .font(DesignTokens.TextStyle.subheadline.weight(.medium))
                    .foregroundStyle(tint)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                    Text(title)
                        .font(DesignTokens.TextStyle.callout.weight(.medium))
                        .foregroundStyle(tint)
                    Text(detail)
                        .font(DesignTokens.TextStyle.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(DesignTokens.TextStyle.micro.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .frame(minHeight: DesignTokens.Layout.quickSettingsActionRowHeight)
            .primeCardSurface(
                cornerRadius: DesignTokens.Radius.base,
                tint: isHovered || isFocused ? tint : nil
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(QuickSettingsActionButtonStyle())
        .focused($isFocused)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : DesignTokens.Opacity.disabled)
        .onHover { hovering in
            withAnimation(
                DesignTokens.Motion.animation(
                    DesignTokens.AnimationCurve.hover,
                    reduceMotion: reduceMotion
                )
            ) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }
}

private struct QuickSettingsActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(
                configuration.isPressed ? DesignTokens.Opacity.high : 1
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(
                reduceMotion ? nil : DesignTokens.AnimationCurve.fast,
                value: configuration.isPressed
            )
    }
}
