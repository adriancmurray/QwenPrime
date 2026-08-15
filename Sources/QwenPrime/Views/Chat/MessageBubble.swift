import SwiftUI

public struct MessageBubble: View {
    public let message: ChatMessage
    @Binding public var isThinkingExpanded: Bool

    public init(message: ChatMessage, isThinkingExpanded: Binding<Bool>) {
        self.message = message
        self._isThinkingExpanded = isThinkingExpanded
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .assistant {
                // Assistant Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.8), Color.indigo.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)

                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
                .shadow(color: Color.cyan.opacity(0.25), radius: 4, x: 0, y: 2)
            } else {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                // User Message Box
                if message.role == .user {
                    Text(message.content)
                        .font(.system(size: 13.5, weight: .regular))
                        .lineSpacing(4)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.9), Color.indigo.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .textSelection(.enabled)
                } else {
                    // Assistant Message
                    VStack(alignment: .leading, spacing: 10) {
                        // 1. Thinking block if present
                        if let thinking = message.thinkingContent, !thinking.isEmpty || message.isStreaming {
                            ThinkingAccordion(
                                thinking: thinking,
                                isStreaming: message.isStreaming && message.content.isEmpty,
                                isExpanded: $isThinkingExpanded
                            )
                        }

                        // 2. Parsed Markdown & Code Blocks
                        if !message.content.isEmpty {
                            MarkdownContentView(content: message.content)
                        } else if message.isStreaming {
                            HStack(spacing: 4) {
                                Circle().fill(Color.cyan).frame(width: 4, height: 4)
                                Circle().fill(Color.cyan.opacity(0.6)).frame(width: 4, height: 4)
                                Circle().fill(Color.cyan.opacity(0.3)).frame(width: 4, height: 4)
                            }
                            .padding(.vertical, 4)
                        }

                        // 3. Stats Badge (TTFT, tok/s, latency)
                        if let stats = message.stats {
                            HStack(spacing: 12) {
                                HStack(spacing: 4) {
                                    Image(systemName: "bolt.fill")
                                        .font(.system(size: 9))
                                    Text("\(String(format: "%.1f", stats.tokensPerSecond)) tok/s")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                }

                                HStack(spacing: 4) {
                                    Image(systemName: "timer")
                                        .font(.system(size: 9))
                                    Text("\(String(format: "%.2f", stats.latencySeconds))s")
                                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                                }

                                Text("\(stats.totalTokens) tokens")
                                    .font(.system(size: 10, weight: .regular))
                            }
                            .foregroundStyle(.tertiary)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            if message.role == .user {
                // User Avatar
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 28, height: 28)

                    Image(systemName: "person.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                }
            } else {
                Spacer(minLength: 60)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

public struct MarkdownContentView: View {
    public let content: String

    public init(content: String) {
        self.content = content
    }

    private struct ContentSegment: Identifiable {
        let id = UUID()
        let isCode: Bool
        let language: String
        let text: String
    }

    private var segments: [ContentSegment] {
        var result: [ContentSegment] = []
        let parts = content.components(separatedBy: "```")

        for (index, part) in parts.enumerated() {
            if index % 2 == 1 {
                // Code block
                let lines = part.components(separatedBy: .newlines)
                let firstLine = lines.first?.trimmingCharacters(in: .whitespaces) ?? ""
                let codeBody = lines.dropFirst().joined(separator: "\n")
                result.append(ContentSegment(isCode: true, language: firstLine, text: codeBody))
            } else {
                // Normal markdown text
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    result.append(ContentSegment(isCode: false, language: "", text: part))
                }
            }
        }
        return result
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments) { segment in
                if segment.isCode {
                    CodeBlockView(language: segment.language, code: segment.text)
                } else {
                    Text(LocalizedStringKey(segment.text))
                        .font(.system(size: 13.5))
                        .lineSpacing(4)
                        .foregroundStyle(Color.primary.opacity(0.95))
                        .textSelection(.enabled)
                }
            }
        }
    }
}
