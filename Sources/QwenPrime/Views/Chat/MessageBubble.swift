import SwiftUI
import AppKit

public struct MessageBubble: View {
    public let message: ChatMessage
    public let theme: MarkdownTheme
    @Binding public var isThinkingExpanded: Bool

    @State private var isCopied: Bool = false
    @State private var isHovered: Bool = false

    private var presentation: ReasoningPresentation {
        ReasoningPresentation.resolve(
            hiddenThinking: message.thinkingContent,
            content: message.content
        )
    }

    public init(
        message: ChatMessage,
        theme: MarkdownTheme = MarkdownTheme.theme(for: .primeDark),
        isThinkingExpanded: Binding<Bool>
    ) {
        self.message = message
        self.theme = theme
        self._isThinkingExpanded = isThinkingExpanded
    }

    private var hasThinking: Bool {
        if !presentation.thinking.isEmpty { return true }
        if message.isStreaming && presentation.answer.isEmpty { return true }
        return false
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .assistant {
                // Assistant Message
                VStack(alignment: .leading, spacing: 10) {
                    // 1. Thinking Accordion if thinking exists or active
                    if hasThinking {
                        ThinkingAccordion(
                            thinking: presentation.thinking,
                            isStreaming: message.isStreaming && presentation.answer.isEmpty,
                            duration: presentation.usesPolishedRecap ? nil : message.stats?.reasoningSeconds,
                            tokenCount: presentation.usesPolishedRecap ? nil : message.stats?.reasoningTokens,
                            theme: theme,
                            isExpanded: $isThinkingExpanded
                        )
                    }

                    // 2. Tool activity, with low-risk read sequences compacted.
                    ForEach(ToolExecutionPresentation.items(for: message.toolExecutions)) { item in
                        switch item {
                        case .execution(let toolExec):
                            ToolExecutionCard(execution: toolExec, theme: theme)
                        case .workspaceReadGroup(let executions):
                            WorkspaceReadGroupCard(executions: executions, theme: theme)
                        }
                    }

                    // 3. Main Response Content
                    if !presentation.answer.isEmpty {
                        MarkdownView(content: presentation.answer, theme: theme)
                    }

                    // 4. Clean Footer Bar (Stats on Left, Copy Icon on Hover on Right)
                    if let stats = message.stats {
                        HStack(spacing: 12) {
                            // Live Telemetry / Stats
                            HStack(spacing: 8) {
                                HStack(spacing: 3.5) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 9))
                                        .foregroundStyle(message.isStreaming ? .green : .yellow)
                                    Text("\(String(format: "%.1f", stats.tokensPerSecond)) \(stats.isThroughputEstimated == true ? "est. tok/s" : "tok/s")")
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(message.isStreaming ? .green : theme.secondaryText)
                                }

                                HStack(spacing: 3.5) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 9))
                                    Text("\(String(format: "%.2f", stats.latencySeconds))s")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                }

                                    Text("\(stats.completionTokens) generated")
                                        .font(.system(size: 9.5))

                                    if let prefill = stats.prefillSeconds {
                                        Text("\(String(format: "%.1f", prefill))s prefill")
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .help("Time spent processing \(stats.promptTokens) prompt and tool-schema tokens before generation")
                                    }

                                if let acceptance = stats.speculativeAcceptanceRate {
                                    Text("\(String(format: "%.0f", acceptance * 100))% accepted")
                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                        .help("Share of generated tokens accepted from the speculative drafter")
                                }

                                if let cached = stats.prefixCacheHitTokens, cached > 0 {
                                    Text("\(cached) cached")
                                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                                        .help("Prompt tokens restored from the DFlash prefix cache")
                                }
                            }
                            .foregroundStyle(theme.secondaryText.opacity(0.8))

                            Spacer()

                            // Copy Button with square.on.square icon (Appears on Hover when not streaming)
                            if !message.isStreaming {
                                Button {
                                    copyMessageToClipboard()
                                } label: {
                                    Image(systemName: isCopied ? "checkmark" : "square.on.square")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(isCopied ? .green : theme.secondaryText)
                                        .padding(4.5)
                                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                                }
                                .buttonStyle(.plain)
                                .help("Copy full response")
                                .opacity(isHovered || isCopied ? 1.0 : 0.0)
                                .animation(.easeInOut(duration: 0.15), value: isHovered || isCopied)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onHover { isHovered = $0 }

            } else {
                // User Message
                Spacer(minLength: 48)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(message.content)
                        .font(.system(size: 13.5, weight: .regular))
                        .lineSpacing(3)
                        .foregroundStyle(theme.userTextColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(
                            LinearGradient(
                                colors: theme.userBubbleGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .contextMenu {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(message.content, forType: .string)
                            } label: {
                                Label("Copy Message", systemImage: "square.on.square")
                            }
                        }
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func copyMessageToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(presentation.answer, forType: .string)
        withAnimation(.easeInOut(duration: 0.2)) {
            isCopied = true
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopied = false
            }
        }
    }
}
