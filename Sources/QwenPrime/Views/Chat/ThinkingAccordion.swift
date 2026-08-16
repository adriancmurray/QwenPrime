import SwiftUI
import AppKit

public struct ThinkingAccordion: View {
    public let thinking: String
    public let isStreaming: Bool
    public let duration: Double?
    public let tokenCount: Int?
    public let theme: MarkdownTheme
    @Binding public var isExpanded: Bool

    @State private var isPulsing: Bool = false
    @State private var isCopied: Bool = false
    @State private var isHovered: Bool = false
    @State private var liveTimerSeconds: Double = 0.0
    @State private var timer: Timer?

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

    private var tokenEstimate: Int {
        max(1, thinking.count / 4)
    }

    private var tokenLabel: String {
        if let tokenCount {
            return "\(tokenCount) tokens"
        }
        return "~\(tokenEstimate) tokens"
    }

    private var headerTitle: String {
        if isStreaming {
            return String(format: "Thinking... (%.1fs)", liveTimerSeconds)
        } else if let duration = duration, duration > 0 {
            return String(format: "Thought for %.1fs", duration)
        } else {
            return "Thought Process"
        }
    }

    public var body: some View {
        if !thinking.isEmpty || isStreaming {
            VStack(alignment: .leading, spacing: 0) {
                // Entire Header Bar is Clickable
                HStack(spacing: 8) {
                    HStack(spacing: 7) {
                        if isStreaming {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.cyan, .indigo],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .scaleEffect(isPulsing ? 1.15 : 1.0)
                        } else {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }

                        Text(headerTitle)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(isStreaming ? .primary : .secondary)

                        if !thinking.isEmpty {
                            Text(tokenLabel)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.05), in: Capsule())
                        }
                    }

                    Spacer()

                    // Copy Icon Button on Hover
                    if !thinking.isEmpty {
                        Button {
                            copyThinkingToClipboard()
                        } label: {
                            Image(systemName: isCopied ? "checkmark" : "square.on.square")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(isCopied ? .green : .secondary)
                                .padding(4)
                                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                        .help("Copy thought process")
                        .opacity(isHovered || isCopied ? 1.0 : 0.0)
                        .animation(.easeInOut(duration: 0.15), value: isHovered || isCopied)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 2)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
                )

                // Expanded Thought Body
                if isExpanded && !thinking.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Divider()
                            .opacity(0.2)
                            .padding(.vertical, 2)

                        MarkdownView(content: thinking, theme: theme)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isStreaming ? Color.cyan.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .onHover { isHovered = $0 }
            .onAppear {
                if isStreaming {
                    startTimer()
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
            }
            .onChange(of: isStreaming) { _, newValue in
                if newValue {
                    startTimer()
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                } else {
                    stopTimer()
                    isPulsing = false
                }
            }
            .onDisappear {
                stopTimer()
            }
        }
    }

    private func startTimer() {
        liveTimerSeconds = 0.0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            Task { @MainActor in
                liveTimerSeconds += 0.1
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func copyThinkingToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(thinking, forType: .string)
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
