import SwiftUI

public struct MessageBubble: View {
    public let message: ChatMessage
    public let theme: MarkdownTheme
    @Binding public var isThinkingExpanded: Bool

    @State private var isHovered: Bool = false
    @Environment(\.colorSchemeContrast) private var contrast

    private var presentation: ReasoningPresentation {
        ReasoningPresentation.resolve(
            hiddenThinking: message.thinkingContent,
            content: message.content
        )
    }

    private var resolvedTheme: MarkdownTheme {
        theme.resolved(for: contrast)
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
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
                    // 1. Thinking Accordion if thinking exists or active
                    if hasThinking {
                        ThinkingAccordion(
                            thinking: presentation.thinking,
                            isStreaming: message.isStreaming && presentation.answer.isEmpty,
                            duration: presentation.usesPolishedRecap ? nil : message.stats?.reasoningSeconds,
                            tokenCount: presentation.usesPolishedRecap ? nil : message.stats?.reasoningTokens,
                            theme: resolvedTheme,
                            isExpanded: $isThinkingExpanded
                        )
                    }

                    // 2. Tool activity, with low-risk read sequences compacted.
                    ForEach(ToolExecutionPresentation.items(for: message.toolExecutions)) { item in
                        switch item {
                        case .execution(let toolExec):
                            ToolExecutionCard(
                                execution: toolExec,
                                theme: resolvedTheme
                            )
                        case .workspaceReadGroup(let executions):
                            WorkspaceReadGroupCard(
                                executions: executions,
                                theme: resolvedTheme
                            )
                        }
                    }

                    // 3. Main Response Content
                    if !presentation.answer.isEmpty {
                        MarkdownView(
                            content: presentation.answer,
                            theme: resolvedTheme,
                            isStreaming: message.isStreaming
                        )
                    }

                    // 4. Clean Footer Bar (Stats on Left, Copy Icon on Hover on Right)
                    if let stats = message.stats {
                        HStack(spacing: DesignTokens.Spacing.lg) {
                            telemetry(stats)

                            Spacer()

                            if !message.isStreaming {
                                CopyFeedbackButton(
                                    value: presentation.answer,
                                    label: "Copy full response",
                                    isRevealed: isHovered
                                )
                            }
                        }
                        .padding(.top, DesignTokens.Spacing.xxs)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onHover { isHovered = $0 }

            } else {
                // User Message
                Spacer(minLength: DesignTokens.Spacing.massive)

                VStack(alignment: .trailing, spacing: DesignTokens.Spacing.xs) {
                    Text(message.content)
                        .font(DesignTokens.TextStyle.body)
                        .lineSpacing(DesignTokens.TextStyle.bodyLineSpacing)
                        .foregroundStyle(resolvedTheme.userTextColor)
                        .padding(.horizontal, DesignTokens.Spacing.xl)
                        .padding(.vertical, DesignTokens.Spacing.md)
                        .background(
                            LinearGradient(
                                colors: resolvedTheme.userBubbleGradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(
                                cornerRadius: DesignTokens.Radius.xl
                            )
                        )
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .overlay(alignment: .topTrailing) {
                            CopyFeedbackButton(
                                value: message.content,
                                label: "Copy message",
                                isRevealed: isHovered
                            )
                            .padding(DesignTokens.Spacing.xs)
                        }
                }
                .onHover { isHovered = $0 }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xs)
        .padding(.vertical, DesignTokens.Spacing.xs)
    }

    private func telemetry(_ stats: GenerationStats) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Spacing.md) {
                throughput(stats)
                latency(stats)
                generatedTokenCount(stats)

                if let prefill = stats.prefillSeconds {
                    Text(
                        "\(PresentationFormatting.duration(prefill)) prefill"
                    )
                    .font(DesignTokens.TextStyle.caption2Monospaced)
                    .help(
                        "Time spent processing \(PresentationFormatting.count(stats.promptTokens, unit: .promptAndToolSchemaToken)) before generation"
                    )
                }

                if let acceptance = stats.speculativeAcceptanceRate {
                    Text(
                        "\(PresentationFormatting.percentage(acceptance)) accepted"
                    )
                    .font(
                        DesignTokens.TextStyle.caption2Monospaced
                            .weight(.medium)
                    )
                    .help(
                        "Share of generated tokens accepted from the speculative drafter"
                    )
                }

                if let cached = stats.prefixCacheHitTokens, cached > 0 {
                    Text(
                        "\(PresentationFormatting.count(cached, unit: .token)) cached"
                    )
                    .font(
                        DesignTokens.TextStyle.caption2Monospaced
                            .weight(.medium)
                    )
                    .help("Prompt tokens restored from the DFlash prefix cache")
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: DesignTokens.Spacing.md) {
                throughput(stats)
                generatedTokenCount(stats)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundStyle(resolvedTheme.secondaryText)
        .lineLimit(1)
    }

    private func throughput(_ stats: GenerationStats) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "bolt.fill")
                .font(DesignTokens.TextStyle.caption2)
                .foregroundStyle(
                    message.isStreaming
                        ? DesignTokens.Status.success
                        : DesignTokens.Status.warning
                )
            Text(
                PresentationFormatting.throughput(
                    stats.tokensPerSecond,
                    isEstimated: stats.isThroughputEstimated == true
                )
            )
            .font(
                DesignTokens.TextStyle.captionMonospaced.weight(.semibold)
            )
            .foregroundStyle(
                message.isStreaming
                    ? DesignTokens.Status.success
                    : resolvedTheme.secondaryText
            )
        }
    }

    private func latency(_ stats: GenerationStats) -> some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: "timer")
                .font(DesignTokens.TextStyle.caption2)
            Text(
                PresentationFormatting.duration(
                    stats.latencySeconds,
                    fractionDigits: 2
                )
            )
            .font(DesignTokens.TextStyle.captionMonospaced.weight(.medium))
        }
    }

    private func generatedTokenCount(_ stats: GenerationStats) -> some View {
        Text(
            "\(PresentationFormatting.count(stats.completionTokens, unit: .token)) generated"
        )
        .font(DesignTokens.TextStyle.caption2)
    }
}
