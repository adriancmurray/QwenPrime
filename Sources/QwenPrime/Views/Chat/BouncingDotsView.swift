import SwiftUI

public struct BouncingDotsView: View {
    public let color: Color
    public let size: CGFloat

    @State private var isAnimating: Bool = false

    public init(color: Color = .cyan, size: CGFloat = 5.5) {
        self.color = color
        self.size = size
    }

    public var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .offset(y: isAnimating ? -4.5 : 0)
                    .opacity(isAnimating ? 1.0 : 0.4)
                    .animation(
                        Animation.easeInOut(duration: 0.45)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.15),
                        value: isAnimating
                    )
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .onAppear {
            isAnimating = true
        }
    }
}
