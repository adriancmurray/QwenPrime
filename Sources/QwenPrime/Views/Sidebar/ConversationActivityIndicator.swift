import SwiftUI

public struct ConversationActivityIndicator: View {
    public let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    public init(color: Color = .accentColor) {
        self.color = color
    }

    public var body: some View {
        Group {
            if reduceMotion {
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.35), lineWidth: 1.5)
                    Circle()
                        .trim(from: 0, to: differentiateWithoutColor ? 0.42 : 0.28)
                        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
            } else {
                ProgressView()
                    .controlSize(.mini)
                    .tint(color)
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
    }
}
