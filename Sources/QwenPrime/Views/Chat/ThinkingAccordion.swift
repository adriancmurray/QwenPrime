import SwiftUI

public struct ThinkingAccordion: View {
    public let thinking: String
    public let isStreaming: Bool
    @Binding public var isExpanded: Bool

    @State private var isPulsing: Bool = false

    public init(thinking: String, isStreaming: Bool = false, isExpanded: Binding<Bool>) {
        self.thinking = thinking
        self.isStreaming = isStreaming
        self._isExpanded = isExpanded
    }

    private var tokenEstimate: Int {
        max(1, thinking.count / 4)
    }

    public var body: some View {
        if !thinking.isEmpty || isStreaming {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(isStreaming && isPulsing ? 1.15 : 1.0)

                        Text(isStreaming && thinking.isEmpty ? "Thinking..." : "Thought Process")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)

                        if !thinking.isEmpty {
                            Text("(\(tokenEstimate) tokens)")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.indigo.opacity(0.07))
                    )
                }
                .buttonStyle(.plain)

                if isExpanded && !thinking.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Divider()
                            .opacity(0.15)
                            .padding(.vertical, 2)

                        Text(thinking)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Color.secondary.opacity(0.9))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .background(Color.indigo.opacity(0.03))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isStreaming ? Color.cyan.opacity(0.35) : Color.white.opacity(0.06), lineWidth: 1)
            )
            .onAppear {
                if isStreaming {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                }
            }
            .onChange(of: isStreaming) { _, newValue in
                if newValue {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        isPulsing = true
                    }
                } else {
                    isPulsing = false
                }
            }
        }
    }
}
