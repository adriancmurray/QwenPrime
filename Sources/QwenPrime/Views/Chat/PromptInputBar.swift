import SwiftUI
import AppKit

public struct PromptInputBar: View {
    @Binding public var text: String
    public let isStreaming: Bool
    public let modelName: String
    public let theme: MarkdownTheme
    public let sandboxURL: URL
    public let recentProjects: [URL]
    public let onSelectProject: (URL) -> Void
    public let onOpenFinder: () -> Void
    public let onOpenTerminal: () -> Void
    public let onSend: () -> Void
    public let onStop: () -> Void

    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        isStreaming: Bool,
        modelName: String,
        theme: MarkdownTheme = MarkdownTheme.theme(for: .primeDark),
        sandboxURL: URL,
        recentProjects: [URL] = [],
        onSelectProject: @escaping (URL) -> Void,
        onOpenFinder: @escaping () -> Void,
        onOpenTerminal: @escaping () -> Void,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        self._text = text
        self.isStreaming = isStreaming
        self.modelName = modelName
        self.theme = theme
        self.sandboxURL = sandboxURL
        self.recentProjects = recentProjects
        self.onSelectProject = onSelectProject
        self.onOpenFinder = onOpenFinder
        self.onOpenTerminal = onOpenTerminal
        self.onSend = onSend
        self.onStop = onStop
    }

    public var body: some View {
        VStack(spacing: 0) {
            // 1. Text Entry Area
            TextField("Ask Qwen Prime anything... (⏎ to send, ⇧⏎ for newline)", text: $text, axis: .vertical)
                .lineLimit(1...10)
                .font(.system(size: 13.5))
                .textFieldStyle(.plain)
                .focused($isFocused)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .onSubmit {
                    if !isStreaming && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSend()
                    }
                }

            // 2. Action Footer Bar (Codex / Antigravity Style)
            HStack(alignment: .center, spacing: 8) {
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
                    HStack(spacing: 4) {
                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(theme.h1)

                        Text(sandboxURL.lastPathComponent)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 7.5))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help("Workspace: \(sandboxURL.path)")

                // Model Chip
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)

                    Text(modelName)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04), in: Capsule())

                Spacer()

                // Send / Stop Action Button (Bottom Right)
                if isStreaming {
                    Button(action: onStop) {
                        HStack(spacing: 5) {
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 8, height: 8)
                                .clipShape(RoundedRectangle(cornerRadius: 1.5))

                            Text("Stop")
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.85), in: Capsule())
                    }
                    .buttonStyle(.plain)
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
                                .frame(width: 28, height: 28)

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
                    .help("Send Message (Return)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isFocused ? theme.h1.opacity(0.4) : Color.white.opacity(0.09), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 3)
        .frame(maxWidth: 780)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .onAppear {
            isFocused = true
        }
    }
}
