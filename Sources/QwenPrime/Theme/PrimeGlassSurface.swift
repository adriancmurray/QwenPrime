import SwiftUI

public struct PrimeGlassSurface: ViewModifier {
    public let cornerRadius: CGFloat
    public let tint: Color?
    public let isInteractive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(
                    DesignTokens.Surface.opaqueFallback,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(surfaceStroke)
        } else if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    Glass.regular.tint(tint).interactive(isInteractive),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(surfaceStroke)
        } else {
            content
                .background(
                    .ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(surfaceStroke)
        }
    }

    private var surfaceStroke: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(DesignTokens.Stroke.separator, lineWidth: 0.75)
    }
}

public extension View {
    func primeGlassSurface(
        cornerRadius: CGFloat,
        tint: Color? = nil,
        isInteractive: Bool = false
    ) -> some View {
        modifier(
            PrimeGlassSurface(
                cornerRadius: cornerRadius,
                tint: tint,
                isInteractive: isInteractive
            )
        )
    }
}
