import SwiftUI

public struct PromptInputBar: View {
    @Binding public var text: String
    public let isStreaming: Bool
    public let modelName: String
    public let onSend: () -> Void
    public let onStop: () -> Void

    @FocusState private var isFocused: Bool

    public init(
        text: Binding<String>,
        isStreaming: Bool,
        modelName: String,
        onSend: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        self._text = text
        self.isStreaming = isStreaming
        self.modelName = modelName
        self.onSend = onSend
        self.onStop = onStop
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                // Input TextField with auto-expansion
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Ask Qwen Prime anything... (⇧⏎ for newline, ⏎ to send)")
                            .font(.system(size: 13.5))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                    }

                    TextEditor(text: $text)
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .focused($isFocused)
                        .frame(minHeight: 28, maxHeight: 160)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)

                // Send or Stop Button
                if isStreaming {
                    Button(action: onStop) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.85))
                                .frame(width: 32, height: 32)
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 10, height: 10)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
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
                                    : Color.blue.opacity(0.9)
                                )
                                .frame(width: 32, height: 32)

                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(
                                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.secondary.opacity(0.4)
                                    : Color.white
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send Message (Return)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.7))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isFocused ? Color.blue.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1)
            )

            // Footer pills
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                    Text(modelName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.04), in: Capsule())

                Spacer()

                Text("Qwen 3.8 27B MLX Speculative Engine")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .onAppear {
            isFocused = true
        }
    }
}
