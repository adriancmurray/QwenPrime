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
        VStack(spacing: 6) {
            HStack(alignment: .bottom, spacing: 8) {
                // Expanding native multi-line textfield
                TextField("Message Qwen Prime...", text: $text, axis: .vertical)
                    .lineLimit(1...8)
                    .font(.system(size: 13.5))
                    .textFieldStyle(.plain)
                    .focused($isFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .onSubmit {
                        // If shift is not held, send
                        if !isStreaming && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onSend()
                        }
                    }

                // Send / Stop button
                if isStreaming {
                    Button(action: onStop) {
                        ZStack {
                            Circle()
                                .fill(Color.red.opacity(0.85))
                                .frame(width: 28, height: 28)
                            Rectangle()
                                .fill(Color.white)
                                .frame(width: 9, height: 9)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                    }
                    .buttonStyle(.plain)
                    .help("Stop Generation")
                    .padding(.trailing, 6)
                    .padding(.bottom, 5)
                } else {
                    Button(action: onSend) {
                        ZStack {
                            Circle()
                                .fill(
                                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.secondary.opacity(0.15)
                                    : Color.blue.opacity(0.9)
                                )
                                .frame(width: 28, height: 28)

                            Image(systemName: "arrow.up")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(
                                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? Color.secondary.opacity(0.4)
                                    : Color.white
                                )
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Send (Return)")
                    .padding(.trailing, 6)
                    .padding(.bottom, 5)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isFocused ? Color.blue.opacity(0.35) : Color.white.opacity(0.08), lineWidth: 1)
            )

            // Minimal Footer
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

                Text("Qwen 3.8 27B Speculative")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 6)
        }
        .frame(maxWidth: 780)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .onAppear {
            isFocused = true
        }
    }
}
