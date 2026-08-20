import SwiftUI

public struct ThinkingAccordion: View {
    public let thinking: String
    public let isStreaming: Bool
    public let duration: Double?
    public let tokenCount: Int?
    public let theme: MarkdownTheme
    @Binding public var isExpanded: Bool

    @State private var isPulsing = false
    @State private var isHovered = false
    @State private var streamStartDate = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    public init(
        thinking: String,
        isStreaming: Bool = false,
        duration: Double? = nil,
        tokenCount: Int? = nil,
        theme: MarkdownTheme = MarkdownTheme.theme(for: .primeDark),
        isExpanded: Binding<Bool>
    ) {
        self.thinking = thinking
        self.isStreaming = isStreaming
        self.duration = duration
        self.tokenCount = tokenCount
        self.theme = theme
        self._isExpanded = isExpanded
    }

    public var body: some View {
        if !thinking.isEmpty || isStreaming {
            Group {
                if isStreaming {
                    TimelineView(.periodic(from: .now, by: 0.5)) { context in
                        accordion(
                            liveSeconds: context.date.timeIntervalSince(
                                streamStartDate
                            )
                        )
                    }
                } else {
                    accordion(liveSeconds: 0)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
            .primeCardSurface(
                cornerRadius: DesignTokens.Radius.md,
                tint: isStreaming ? theme.h1 : nil
            )
            .onHover { isHovered = $0 }
            .onAppear(perform: updateStreamingPresentation)
            .onChange(of: isStreaming) { _, isNowStreaming in
                if isNowStreaming {
                    streamStartDate = Date()
                }
                updatePulse()
            }
            .onChange(of: reduceMotion) { _, _ in
                updatePulse()
            }
        }
    }

    @ViewBuilder
    private func accordion(liveSeconds: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DisclosureCardHeader(
                title: headerTitle(liveSeconds: liveSeconds),
                accessibilityLabel: accessibilityHeader(
                    liveSeconds: liveSeconds
                ),
                systemImage: "brain.head.profile",
                tint: isStreaming ? theme.h1 : .secondary,
                iconScale: isPulsing && !reduceMotion ? 1.12 : 1,
                isExpanded: $isExpanded,
                metadata: {
                    if !thinking.isEmpty {
                        Text(tokenLabel)
                            .font(
                                DesignTokens.TextStyle.captionMonospaced
                                    .weight(.medium)
                            )
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, DesignTokens.Spacing.sm)
                            .padding(.vertical, DesignTokens.Spacing.xxs)
                            .background(
                                DesignTokens.Surface.adaptiveSubtle(
                                    contrast: contrast,
                                    reduceTransparency: reduceTransparency
                                ),
                                in: Capsule()
                            )
                    }
                },
                status: { EmptyView() },
                accessory: {
                    if !thinking.isEmpty {
                        CopyFeedbackButton(
                            value: thinking,
                            label: "Copy thought process",
                            isRevealed: isHovered
                        )
                    }
                }
            )

            if isExpanded && !thinking.isEmpty {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    Divider()
                        .opacity(DesignTokens.Opacity.divider)

                    MarkdownView(
                        content: thinking,
                        theme: theme,
                        isStreaming: isStreaming
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .padding(.bottom, DesignTokens.Spacing.base)
                .background(
                    DesignTokens.Surface.recessed(
                        contrast: contrast,
                        reduceTransparency: reduceTransparency
                    )
                )
                .transition(.opacity)
            }
        }
    }

    private var tokenEstimate: Int {
        PresentationFormatting.estimatedTokenCount(for: thinking)
    }

    private var tokenLabel: String {
        if let tokenCount {
            return PresentationFormatting.count(tokenCount, unit: .token)
        }
        return PresentationFormatting.approximateCount(
            tokenEstimate,
            unit: .token
        )
    }

    private func headerTitle(liveSeconds: Double) -> String {
        if isStreaming {
            return "Thinking… (\(PresentationFormatting.duration(liveSeconds)))"
        }
        if let duration, duration > 0 {
            return "Thought for \(PresentationFormatting.duration(duration))"
        }
        return "Thought Process"
    }

    private func accessibilityHeader(liveSeconds: Double) -> String {
        let title = headerTitle(liveSeconds: liveSeconds)
        guard !thinking.isEmpty else { return title }
        return "\(title), \(tokenLabel)"
    }

    private func updateStreamingPresentation() {
        if isStreaming {
            streamStartDate = Date()
        }
        updatePulse()
    }

    private func updatePulse() {
        guard isStreaming, !reduceMotion else {
            isPulsing = false
            return
        }
        withAnimation(
            DesignTokens.AnimationCurve.standard.repeatForever(
                autoreverses: true
            )
        ) {
            isPulsing = true
        }
    }
}
