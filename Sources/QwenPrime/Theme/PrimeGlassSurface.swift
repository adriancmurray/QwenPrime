import SwiftUI

public struct PrimeGlassSurface: ViewModifier {
    public let cornerRadius: CGFloat
    public let tint: Color?
    public let isInteractive: Bool

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

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
            .stroke(
                DesignTokens.Stroke.adaptiveSeparator(contrast: contrast),
                lineWidth: DesignTokens.Stroke.lineWidth(contrast: contrast)
            )
    }
}

public struct PrimeCardSurface: ViewModifier {
    public let cornerRadius: CGFloat
    public let tint: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    public func body(content: Content) -> some View {
        content
            .background(
                tint.map {
                    DesignTokens.Surface.adaptiveSelected(
                        tint: $0,
                        contrast: contrast,
                        reduceTransparency: reduceTransparency
                    )
                } ?? DesignTokens.Surface.adaptiveSubtle(
                    contrast: contrast,
                    reduceTransparency: reduceTransparency
                ),
                in: RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .stroke(
                    DesignTokens.Stroke.adaptiveSeparator(contrast: contrast),
                    lineWidth: DesignTokens.Stroke.lineWidth(contrast: contrast)
                )
            )
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

    func primeCardSurface(
        cornerRadius: CGFloat = DesignTokens.Radius.md,
        tint: Color? = nil
    ) -> some View {
        modifier(PrimeCardSurface(cornerRadius: cornerRadius, tint: tint))
    }
}
