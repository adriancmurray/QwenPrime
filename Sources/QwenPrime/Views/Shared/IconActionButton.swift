import SwiftUI

public struct IconActionButton: View {
    public let systemImage: String
    public let label: String
    public let tint: Color
    public let role: ButtonRole?
    public let isEnabled: Bool
    public let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    public init(
        _ systemImage: String,
        label: String,
        tint: Color = .primary,
        role: ButtonRole? = nil,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.label = label
        self.tint = tint
        self.role = role
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(DesignTokens.TextStyle.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(
                    width: DesignTokens.Layout.toolbarControlHeight,
                    height: DesignTokens.Layout.toolbarControlHeight
                )
                .background(
                    isHighlighted
                        ? DesignTokens.Surface.adaptiveSelected(
                            tint: tint,
                            contrast: contrast,
                            reduceTransparency: reduceTransparency
                        )
                        : DesignTokens.Surface.adaptiveSubtle(
                            contrast: contrast,
                            reduceTransparency: reduceTransparency
                        ),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : DesignTokens.Opacity.disabled)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovering in
            withAnimation(
                DesignTokens.Motion.animation(
                    DesignTokens.AnimationCurve.hover,
                    reduceMotion: reduceMotion
                )
            ) {
                isHovered = hovering
            }
        }
    }

    private var isHighlighted: Bool {
        isHovered || isFocused
    }
}
