import SwiftUI

public struct IconActionButton: View {
    public let systemImage: String
    public let label: String
    public let tint: Color
    public let role: ButtonRole?
    public let isEnabled: Bool
    public let action: () -> Void

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                .font(.system(size: DesignTokens.Typography.subheadline, weight: .semibold))
                .foregroundStyle(tint)
                .frame(
                    width: DesignTokens.Layout.toolbarControlHeight,
                    height: DesignTokens.Layout.toolbarControlHeight
                )
                .background(
                    isHovered ? DesignTokens.Surface.selected : DesignTokens.Surface.subtle,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .help(label)
        .accessibilityLabel(label)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : DesignTokens.AnimationCurve.hover) {
                isHovered = hovering
            }
        }
    }
}
