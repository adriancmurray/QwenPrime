import SwiftUI

public struct FloatingComposer<Content: View>: View {
    public let tint: Color
    @ViewBuilder public let content: Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(tint: Color, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    public var body: some View {
        content
            .frame(maxWidth: DesignTokens.Layout.composerMaxWidth)
            .primeGlassSurface(
                cornerRadius: DesignTokens.Radius.xxl,
                tint: tint.opacity(0.08),
                isInteractive: true
            )
            .shadow(
                color: DesignTokens.Elevation.floatingShadow,
                radius: DesignTokens.Elevation.floatingRadius,
                y: DesignTokens.Elevation.floatingOffset
            )
            .padding(.horizontal, DesignTokens.Spacing.section)
            .padding(.bottom, DesignTokens.Layout.composerBottomMargin)
            .transition(
                reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                        removal: .opacity.combined(
                            with: .scale(scale: 0.98, anchor: .bottom)
                        )
                    )
            )
    }
}
