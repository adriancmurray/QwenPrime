import AppKit
import SwiftUI

public struct PromptInputBar: View {
    @Binding public var text: String
    @Binding public var isThinkingEnabled: Bool
    public let isStreaming: Bool
    public let modelName: String
    public let theme: MarkdownTheme
    public let sandboxURL: URL
    public let recentProjects: [URL]
    public let onSelectProject: (URL) -> Void
    public let onOpenFinder: () -> Void
    public let onOpenTerminal: () -> Void
    public let isAgentPreviewVisible: Bool
    public let isAgentPreviewAvailable: Bool
    public let isAgentPreviewEnabled: Bool
    public let onToggleAgentPreview: () -> Void
    public let onSend: () -> Void
    public let onStop: () -> Void

    @FocusState private var isFocused: Bool
    @State private var isWorkspacePickerPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        text: Binding<String>,
        isThinkingEnabled: Binding<Bool> = .constant(true),
        isStreaming: Bool,
        modelName: String,
        theme: MarkdownTheme = MarkdownTheme.theme(for: .primeDark),
        sandboxURL: URL,
        recentProjects: [URL] = [],
        onSelectProject: @escaping (URL) -> Void,
        onOpenFinder: @escaping () -> Void,
        onOpenTerminal: @escaping () -> Void,
        isAgentPreviewVisible: Bool = false,
        isAgentPreviewAvailable: Bool = false,
        isAgentPreviewEnabled: Bool = false,
        onToggleAgentPreview: @escaping () -> Void = {},
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        self._text = text
        self._isThinkingEnabled = isThinkingEnabled
        self.isStreaming = isStreaming
        self.modelName = modelName
        self.theme = theme
        self.sandboxURL = sandboxURL
        self.recentProjects = recentProjects
        self.onSelectProject = onSelectProject
        self.onOpenFinder = onOpenFinder
        self.onOpenTerminal = onOpenTerminal
        self.isAgentPreviewVisible = isAgentPreviewVisible
        self.isAgentPreviewAvailable = isAgentPreviewAvailable
        self.isAgentPreviewEnabled = isAgentPreviewEnabled
        self.onToggleAgentPreview = onToggleAgentPreview
        self.onSend = onSend
        self.onStop = onStop
    }

    private var agentHelpText: String {
        if isStreaming {
            return "Agent Mode Preview (Stop active generation to change mode)"
        }
        if !isAgentPreviewAvailable {
            return "Agent Mode Preview (Requires runtime structured tool capability and workspace folder)"
        }
        return isAgentPreviewEnabled
            ? "Agent Mode Preview (Active — read-only workspace inspection)"
            : "Agent Mode Preview (Click to enable read-only workspace inspection)"
    }

    private var commandContext: AppCommandContext {
        AppCommandContext(
            hasConversation: true,
            isGenerating: isStreaming,
            hasMessageText: !text.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty,
            hasInputFocus: isFocused
        )
    }

    private var workspaceDisplayName: String {
        ProjectScope.displayName(for: sandboxURL)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Text Entry Area
            TextField("Message Qwen Prime", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(DesignTokens.TextStyle.body)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityIdentifier("chat_input")
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .onKeyPress(
                    keys: [
                        AppCommands.sendMessage.shortcut.key.keyEquivalent
                    ],
                    phases: .down
                ) { keyPress in
                    handleReturnKey(keyPress)
                }

            // 2. Action Footer Bar (Codex / Antigravity Style)
            HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                workspacePicker

                // Reasoning / Direct Fast Toggle Pill
                Button {
                    withAnimation(reduceMotion ? nil : DesignTokens.AnimationCurve.standard) {
                        isThinkingEnabled.toggle()
                    }
                } label: {
                    Image(systemName: isThinkingEnabled ? "brain.head.profile" : "bolt.fill")
                        .font(DesignTokens.TextStyle.subheadline.weight(.semibold))
                        .foregroundStyle(
                            isThinkingEnabled
                                ? DesignTokens.Status.reasoning
                                : DesignTokens.Status.warning
                        )
                        .frame(width: DesignTokens.Layout.toolbarControlHeight, height: DesignTokens.Layout.toolbarControlHeight)
                        .background(
                            (
                                isThinkingEnabled
                                    ? DesignTokens.Status.reasoning
                                    : DesignTokens.Status.warning
                            ).opacity(0.12),
                            in: Circle()
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat_reasoning_toggle")
                .help(isThinkingEnabled ? "Reasoning Mode (<think> enabled)" : "Direct Fast Mode (skips the reasoning phase)")
                .accessibilityLabel(isThinkingEnabled ? "Reasoning mode" : "Direct mode")
                .accessibilityValue(isThinkingEnabled ? "On" : "Off")
                .accessibilityAddTraits(isThinkingEnabled ? .isSelected : [])

                // Workspace Agent Preview Toggle Pill
                if isAgentPreviewVisible {
                    Button {
                        withAnimation(reduceMotion ? nil : DesignTokens.AnimationCurve.standard) {
                            onToggleAgentPreview()
                        }
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(DesignTokens.TextStyle.subheadline)
                                .foregroundStyle(
                                    !isAgentPreviewAvailable
                                        ? Color.secondary.opacity(0.4)
                                        : (
                                            isAgentPreviewEnabled
                                                ? DesignTokens.Status.reasoning
                                                : Color.secondary
                                        )
                                )

                            Text("Agent")
                                .font(
                                    DesignTokens.TextStyle.caption.weight(
                                        isAgentPreviewEnabled ? .semibold : .medium
                                    )
                                )
                                .foregroundStyle(
                                    !isAgentPreviewAvailable
                                        ? Color.secondary.opacity(0.4)
                                        : (isAgentPreviewEnabled ? Color.primary : Color.secondary)
                                )
                        }
                        .padding(.horizontal, DesignTokens.Spacing.base)
                        .frame(height: DesignTokens.Layout.toolbarControlHeight)
                        .background(
                            isAgentPreviewEnabled
                                ? DesignTokens.Status.reasoning.opacity(0.14)
                                : DesignTokens.Surface.subtle,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    isAgentPreviewEnabled
                                        ? DesignTokens.Status.reasoning.opacity(0.4)
                                        : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isAgentPreviewAvailable || isStreaming)
                    .accessibilityIdentifier("chat_agent_preview_toggle")
                    .accessibilityLabel(isAgentPreviewEnabled ? "Agent mode enabled" : "Agent mode disabled")
                    .accessibilityValue(isAgentPreviewEnabled ? "On" : "Off")
                    .accessibilityAddTraits(isAgentPreviewEnabled ? .isSelected : [])
                    .help(agentHelpText)
                }

                Spacer()

                // Send / Stop Action Button (Bottom Right)
                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(DesignTokens.TextStyle.caption.weight(.bold))
                            .foregroundStyle(
                                theme.selectedControlText
                            )
                            .frame(width: 30, height: 30)
                            .background(
                                DesignTokens.Status.danger.opacity(0.86),
                                in: Circle()
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat_stop_button")
                    .accessibilityLabel("Stop generation")
                    .help(AppCommands.stopGeneration.helpWithShortcut)
                } else {
                    Button(action: onSend) {
                        ZStack {
                            Circle()
                                .fill(
                                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.secondary.opacity(0.12)
                                    : theme.h1.opacity(0.95)
                                )
                                .frame(width: 30, height: 30)

                            Image(systemName: "arrow.up")
                                .font(DesignTokens.TextStyle.callout.weight(.bold))
                                .foregroundStyle(
                                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.secondary.opacity(0.4)
                                    : theme.selectedControlText
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!AppCommands.sendMessage.isEnabled(in: commandContext))
                    .accessibilityIdentifier("chat_send_button")
                    .accessibilityLabel("Send message")
                    .help(AppCommands.sendMessage.helpWithShortcut)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.xxl, style: .continuous)
                .stroke(isFocused ? theme.h1.opacity(0.45) : Color.clear, lineWidth: 1)
        )
        .onAppear {
            isFocused = true
        }
        .onExitCommand {
            guard AppCommands.stopGeneration.isEnabled(in: commandContext) else {
                return
            }
            onStop()
        }
    }

    private func chooseWorkspaceDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Workspace"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                onSelectProject(url)
            }
        }
    }

    private var workspacePicker: some View {
        Button {
            isWorkspacePickerPresented = true
        } label: {
            workspacePickerLabel
        }
        .buttonStyle(.plain)
        .popover(
            isPresented: $isWorkspacePickerPresented,
            arrowEdge: .bottom
        ) {
            workspacePickerPopover
        }
        .help("Workspace: \(sandboxURL.path)")
        .accessibilityLabel("Workspace")
        .accessibilityValue(workspaceDisplayName)
    }

    private var workspacePickerLabel: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "shippingbox.fill")
                    .font(DesignTokens.TextStyle.caption)
                    .foregroundStyle(theme.h1)

                Text(workspaceDisplayName)
                    .font(
                        DesignTokens.TextStyle.captionMonospaced
                            .weight(.medium)
                    )
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Image(systemName: "chevron.down")
                    .font(DesignTokens.TextStyle.caption2)
                    .foregroundStyle(theme.h1)
            }

            Image(systemName: "shippingbox.fill")
                .font(DesignTokens.TextStyle.caption)
                .foregroundStyle(theme.h1)
                .frame(
                    width: DesignTokens.Layout.toolbarControlHeight,
                    height: DesignTokens.Layout.toolbarControlHeight
                )
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .frame(height: DesignTokens.Layout.toolbarControlHeight)
        .background(DesignTokens.Surface.subtle, in: Capsule())
    }

    private var workspacePickerPopover: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
            ThemedPopoverSectionTitle("Workspace Actions")

            workspacePickerAction(
                title: "Reveal in Finder",
                systemImage: "folder",
                action: onOpenFinder
            )
            workspacePickerAction(
                title: "Open in Terminal",
                systemImage: "terminal",
                action: onOpenTerminal
            )

            if !recentProjects.isEmpty {
                Divider().padding(.vertical, DesignTokens.Spacing.xxs)

                ThemedPopoverSectionTitle("Recent Workspaces")

                ForEach(recentProjects, id: \.self) { project in
                    workspacePickerAction(
                        title: ProjectScope.displayName(for: project),
                        systemImage: "shippingbox.fill",
                        isSelected: sandboxURL.path == project.path
                    ) {
                        isWorkspacePickerPresented = false
                        onSelectProject(project)
                    }
                }
            }

            Divider().padding(.vertical, DesignTokens.Spacing.xxs)

            workspacePickerAction(
                title: "Change Workspace…",
                systemImage: "plus.rectangle.on.folder"
            ) {
                isWorkspacePickerPresented = false
                chooseWorkspaceDirectory()
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.md)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .bottomAttachedPopoverContent()
        .frame(width: DesignTokens.Layout.workspacePickerPopoverWidth)
        .tint(theme.h1)
    }

    private func workspacePickerAction(
        title: String,
        systemImage: String,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        ThemedPopoverActionRow(
            title: title,
            systemImage: systemImage,
            selectionTint: theme.h1,
            isSelected: isSelected,
            trailingSystemImage: isSelected ? "checkmark" : nil,
            action: action
        )
    }

    private func handleReturnKey(_ keyPress: KeyPress) -> KeyPress.Result {
        let isHandled = PromptInputKeyboardPolicy.handleReturn(
            modifiers: keyPress.modifiers,
            context: commandContext,
            insertNewline: { text.append("\n") },
            onSend: onSend
        )
        return isHandled ? .handled : .ignored
    }
}

enum PromptInputKeyboardAction: Equatable {
    case sendMessage
    case insertNewline
    case ignored
}

enum PromptInputKeyboardPolicy {
    static func action(
        for modifiers: EventModifiers,
        context: AppCommandContext
    ) -> PromptInputKeyboardAction {
        if matches(
            AppCommands.insertNewline,
            modifiers: modifiers,
            context: context
        ) {
            return .insertNewline
        }
        if matches(
            AppCommands.sendMessage,
            modifiers: modifiers,
            context: context
        ) {
            return .sendMessage
        }
        return .ignored
    }

    @discardableResult
    static func handleReturn(
        modifiers: EventModifiers,
        context: AppCommandContext,
        insertNewline: () -> Void,
        onSend: () -> Void
    ) -> Bool {
        switch action(for: modifiers, context: context) {
        case .sendMessage:
            onSend()
        case .insertNewline:
            insertNewline()
        case .ignored:
            return false
        }
        return true
    }

    private static func matches(
        _ command: AppCommandDescriptor,
        modifiers: EventModifiers,
        context: AppCommandContext
    ) -> Bool {
        command.shortcut.key == .returnKey
            && command.shortcut.modifiers.eventModifiers == modifiers
            && command.isEnabled(in: context)
    }
}
