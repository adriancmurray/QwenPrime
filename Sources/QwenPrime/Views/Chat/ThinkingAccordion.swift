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
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Pulsing or static brain icon
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.cyan, .indigo],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .scaleEffect(isStreaming && isPulsing ? 1.2 : 1.0)

                        Text(isStreaming ? "Thinking..." : "Thought Process")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    if !thinking.isEmpty {
                        Text("• ~\(tokenEstimate) tokens")
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.indigo.opacity(0.08))
                )
            }
            .buttonStyle(.plain)

            if isExpanded && !thinking.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                        .opacity(0.2)
                        .padding(.vertical, 4)

                    Text(thinking)
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.secondary.opacity(0.9))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .background(Color.indigo.opacity(0.04))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isStreaming ? Color.cyan.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1)
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
