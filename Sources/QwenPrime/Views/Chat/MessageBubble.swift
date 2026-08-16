import SwiftUI

public struct MessageBubble: View {
    public let message: ChatMessage
    public let theme: MarkdownTheme
    @Binding public var isThinkingExpanded: Bool

    public init(
        message: ChatMessage,
        theme: MarkdownTheme = MarkdownTheme.theme(for: .primeDark),
        isThinkingExpanded: Binding<Bool>
    ) {
        self.message = message
        self.theme = theme
        self._isThinkingExpanded = isThinkingExpanded
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .assistant {
                // Assistant Message (No Avatar, Pure Formatted Content)
                VStack(alignment: .leading, spacing: 8) {
                    // 1. Thinking block if present
                    if let thinking = message.thinkingContent, !thinking.isEmpty || (message.isStreaming && message.content.isEmpty) {
                        ThinkingAccordion(
                            thinking: thinking,
                            isStreaming: message.isStreaming && message.content.isEmpty,
                            isExpanded: $isThinkingExpanded
                        )
                    }

                    // 2. Tool Executions (Interactive IPython / Sandbox cards)
                    ForEach(message.toolExecutions) { toolExec in
                        ToolExecutionCard(execution: toolExec, theme: theme)
                    }

                    // 3. Markdown Rich Content
                    if !message.content.isEmpty {
                        MarkdownView(content: message.content, theme: theme)
                    } else if message.isStreaming && (message.thinkingContent?.isEmpty ?? true) && message.toolExecutions.isEmpty {
                        HStack(spacing: 4) {
                            Circle().fill(theme.h1).frame(width: 4, height: 4)
                            Circle().fill(theme.h1.opacity(0.6)).frame(width: 4, height: 4)
                            Circle().fill(theme.h1.opacity(0.3)).frame(width: 4, height: 4)
                        }
                        .padding(.vertical, 4)
                    }

                    // 4. Stats Footer
                    if let stats = message.stats {
                        HStack(spacing: 10) {
                            HStack(spacing: 3) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 8.5))
                                Text("\(String(format: "%.1f", stats.tokensPerSecond)) tok/s")
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            }

                            HStack(spacing: 3) {
                                Image(systemName: "timer")
                                    .font(.system(size: 8.5))
                                Text("\(String(format: "%.2f", stats.latencySeconds))s")
                                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            }

                            Text("(\(stats.totalTokens) tokens)")
                                .font(.system(size: 9.5))
                        }
                        .foregroundStyle(theme.secondaryText.opacity(0.7))
                        .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

            } else {
                // User Message (Right-aligned, No Avatar, Tight Wrap)
                Spacer(minLength: 48)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(message.content)
                        .font(.system(size: 13.5, weight: .regular))
                        .lineSpacing(3)
                        .foregroundStyle(theme.userTextColor)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
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
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
    }
}
