import SwiftUI
import AppKit

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

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Text Entry Area
            TextField("Message Qwen Prime", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(.system(size: DesignTokens.Typography.body))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .accessibilityIdentifier("chat_input")
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .onSubmit {
                    if !isStreaming && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                    }
                }

            // 2. Action Footer Bar (Codex / Antigravity Style)
            HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                // Interactive Workspace Pill
                Menu {
                    Section("Workspace Actions") {
                        Button(action: onOpenFinder) {
                            Label("Reveal in Finder", systemImage: "folder")
                        }
                        Button(action: onOpenTerminal) {
                            Label("Open in Terminal", systemImage: "terminal")
                        }
                    }

                    if !recentProjects.isEmpty {
                        Section("Recent Workspaces") {
                            ForEach(recentProjects, id: \.self) { proj in
                                Button {
                                    onSelectProject(proj)
                                } label: {
                                    HStack {
                                        Text(proj.lastPathComponent)
                                        if sandboxURL.path == proj.path {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Divider()

                    Button {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.prompt = "Choose Workspace"
                        if panel.runModal() == .OK, let url = panel.url {
                            onSelectProject(url)
                        }
                    } label: {
                        Label("Change Workspace...", systemImage: "plus.rectangle.on.folder")
                    }
                } label: {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: DesignTokens.Typography.caption))
                            .foregroundStyle(theme.h1)

                        Text(sandboxURL.lastPathComponent)
                            .font(.system(size: DesignTokens.Typography.caption, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7.5))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .frame(height: DesignTokens.Layout.toolbarControlHeight)
                    .background(DesignTokens.Surface.subtle, in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Workspace: \(sandboxURL.path)")

                // Reasoning / Direct Fast Toggle Pill
                Button {
                    withAnimation(reduceMotion ? nil : DesignTokens.AnimationCurve.standard) {
                        isThinkingEnabled.toggle()
                    }
                } label: {
                    Image(systemName: isThinkingEnabled ? "brain.head.profile" : "bolt.fill")
                        .font(.system(size: DesignTokens.Typography.subheadline, weight: .semibold))
                        .foregroundStyle(isThinkingEnabled ? Color.cyan : Color.orange)
                        .frame(width: DesignTokens.Layout.toolbarControlHeight, height: DesignTokens.Layout.toolbarControlHeight)
                        .background(
                            (isThinkingEnabled ? Color.cyan : Color.orange).opacity(0.12),
                            in: Circle()
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chat_reasoning_toggle")
                .help(isThinkingEnabled ? "Reasoning Mode (<think> enabled)" : "Direct Fast Mode (skips the reasoning phase)")
                .accessibilityLabel(isThinkingEnabled ? "Reasoning mode" : "Direct mode")

                // Workspace Agent Preview Toggle Pill
                if isAgentPreviewVisible {
                    Button {
                        withAnimation(reduceMotion ? nil : DesignTokens.AnimationCurve.standard) {
                            onToggleAgentPreview()
                        }
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: DesignTokens.Typography.subheadline))
                                .foregroundStyle(
                                    !isAgentPreviewAvailable
                                        ? Color.secondary.opacity(0.4)
                                        : (isAgentPreviewEnabled ? Color.cyan : Color.secondary)
                                )

                            Text("Agent")
                                .font(.system(size: DesignTokens.Typography.caption, weight: isAgentPreviewEnabled ? .semibold : .medium))
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
                                ? Color.cyan.opacity(0.14)
                                : DesignTokens.Surface.subtle,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .stroke(
                                    isAgentPreviewEnabled ? Color.cyan.opacity(0.4) : Color.clear,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(!isAgentPreviewAvailable || isStreaming)
                    .accessibilityIdentifier("chat_agent_preview_toggle")
                    .accessibilityLabel(isAgentPreviewEnabled ? "Agent mode enabled" : "Agent mode disabled")
                    .help(agentHelpText)
                }

                Spacer()

                // Send / Stop Action Button (Bottom Right)
                if isStreaming {
                    Button(action: onStop) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: DesignTokens.Typography.caption, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 30, height: 30)
                            .background(Color.red.opacity(0.86), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat_stop_button")
                    .accessibilityLabel("Stop generation")
                    .help("Stop Generation (Esc)")
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
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(
                                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.secondary.opacity(0.4)
                                    : Color.black
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("chat_send_button")
                    .accessibilityLabel("Send message")
                    .help("Send Message (Return)")
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
    }
}
