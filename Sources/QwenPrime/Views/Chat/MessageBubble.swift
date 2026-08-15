import SwiftUI

public struct MessageBubble: View {
    public let message: ChatMessage
    @Binding public var isThinkingExpanded: Bool

    public init(message: ChatMessage, isThinkingExpanded: Binding<Bool>) {
        self.message = message
        self._isThinkingExpanded = isThinkingExpanded
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                // Assistant Avatar
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.cyan.opacity(0.85), Color.indigo.opacity(0.95)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 24, height: 24)

                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.top, 2)
            } else {
                Spacer(minLength: 40)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // User Message Box
                if message.role == .user {
                    Text(message.content)
                        .font(.system(size: 13.5, weight: .regular))
                        .lineSpacing(3)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.85), Color.indigo.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // Assistant Message Box
                    VStack(alignment: .leading, spacing: 8) {
                        // 1. Thinking block if present
                        if let thinking = message.thinkingContent, !thinking.isEmpty || (message.isStreaming && message.content.isEmpty) {
                            ThinkingAccordion(
                                thinking: thinking,
                                isStreaming: message.isStreaming && message.content.isEmpty,
                                isExpanded: $isThinkingExpanded
                            )
                        }

                        // 2. Content
                        if !message.content.isEmpty {
                            MarkdownContentView(content: message.content)
                        } else if message.isStreaming && (message.thinkingContent?.isEmpty ?? true) {
                            HStack(spacing: 4) {
                                Circle().fill(Color.cyan).frame(width: 4, height: 4)
                                Circle().fill(Color.cyan.opacity(0.6)).frame(width: 4, height: 4)
                                Circle().fill(Color.cyan.opacity(0.3)).frame(width: 4, height: 4)
                            }
                            .padding(.vertical, 4)
                        }

                        // 3. Stats
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
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                        }
                    }
                }
            }

            if message.role == .user {
                // Compact User Indicator
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 24, height: 24)

                    Image(systemName: "person.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.top, 2)
            } else {
                Spacer(minLength: 40)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
                // Normal text
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    result.append(ContentSegment(isCode: false, language: "", text: part))
                }
            }
        }
        return result
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                if segment.isCode {
                    CodeBlockView(language: segment.language, code: segment.text)
                } else {
                    Text(LocalizedStringKey(segment.text))
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .foregroundStyle(Color.primary.opacity(0.95))
                        .textSelection(.enabled)
                }
            }
        }
    }
}
