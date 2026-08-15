import SwiftUI

public struct PromptInputBar: View {
    @Binding public var text: String
    public let isStreaming: Bool
    public let modelName: String
    public let theme: MarkdownTheme
    public let onSend: () -> Void
    public let onStop: () -> Void

    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        isStreaming: Bool,
        modelName: String,
        theme: MarkdownTheme = MarkdownTheme.theme(for: .primeDark),
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        self._text = text
        self.isStreaming = isStreaming
        self.modelName = modelName
        self.theme = theme
        self.onSend = onSend
        self.onStop = onStop
    }

    public var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 6) {
                // Expanding native multi-line textfield
                TextField("Ask Qwen Prime anything... (⏎ to send, ⇧⏎ for newline)", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.system(size: 13.5))
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .padding(.leading, 12)
                    .padding(.trailing, 4)
                    .padding(.vertical, 8)
                    .onSubmit {
                        if !isStreaming && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onSend()
                        }
                    }

                // Send / Stop button aligned perfectly with text field
                VStack {
                    if isStreaming {
                        Button(action: onStop) {
                            ZStack {
                                Circle()
                                    .fill(Color.red.opacity(0.85))
                                    .frame(width: 26, height: 26)
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: 8, height: 8)
                                    .clipShape(RoundedRectangle(cornerRadius: 1.5))
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Stop Generation")
                    } else {
                        Button(action: onSend) {
                            ZStack {
                                Circle()
                                    .fill(
                                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? Color.secondary.opacity(0.15)
                                        : theme.h1.opacity(0.9)
                                    )
                                    .frame(width: 26, height: 26)

                                Image(systemName: "arrow.up")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(
                                        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                        ? Color.secondary.opacity(0.4)
                                        : Color.black
                                    )
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("Send (Return)")
                    }
                }
                .padding(.trailing, 7)
                .padding(.bottom, 6)
            }
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isFocused ? theme.h1.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
            )

            // Minimal Footer Info
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                    Text(modelName)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("Apple Silicon MLX Engine")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
        }
        .frame(maxWidth: 780)
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .onAppear {
            isFocused = true
        }
    }
}
