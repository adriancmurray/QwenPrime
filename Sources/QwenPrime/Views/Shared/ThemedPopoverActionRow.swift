import SwiftUI

/// A compact, theme-owned action row for popovers with one-line choices.
///
/// Workspace actions and conversation actions share the same interaction
/// density while retaining their respective container widths and grouping.
public struct ThemedPopoverActionRow: View {
    public let title: String
    public let systemImage: String
    public let selectionTint: Color
    public let foregroundColor: Color
    public let isSelected: Bool
    public let isEnabled: Bool
    public let trailingSystemImage: String?
    public let accessibilityLabel: String
    public let action: () -> Void

    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        title: String,
        systemImage: String,
        selectionTint: Color,
        foregroundColor: Color = .primary,
        isSelected: Bool = false,
        isEnabled: Bool = true,
        trailingSystemImage: String? = nil,
        accessibilityLabel: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.selectionTint = selectionTint
        self.foregroundColor = foregroundColor
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.trailingSystemImage = trailingSystemImage
        self.accessibilityLabel = accessibilityLabel ?? title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Image(systemName: systemImage)
                    .frame(width: DesignTokens.Layout.popoverActionIconWidth)
                    .accessibilityHidden(true)

                Text(title)
                    .lineLimit(1)

                Spacer()

                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .foregroundStyle(selectionTint)
                        .accessibilityHidden(true)
                }
            }
            .font(DesignTokens.TextStyle.callout.weight(.medium))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .frame(minHeight: DesignTokens.Layout.popoverActionRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHighlighted
                    ? selectionTint.opacity(DesignTokens.Opacity.hover)
                    : .clear,
                in: RoundedRectangle(
                    cornerRadius: DesignTokens.Radius.base,
                    style: .continuous
                )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : DesignTokens.Opacity.disabled)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        isSelected || isHovered || isFocused
    }
}

/// A shared compact label for grouped choices in a theme-owned popover.
public struct ThemedPopoverSectionTitle: View {
    public let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(DesignTokens.TextStyle.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(
                .leading,
                DesignTokens.Spacing.sm
                    + DesignTokens.Layout.popoverActionIconWidth
                    + DesignTokens.Spacing.sm
            )
    }
}

/// Adds the compact amount of clearance needed above pickers that open below
/// their triggering control.
public struct BottomAttachedPopoverContent: ViewModifier {
    public func body(content: Content) -> some View {
        content.padding(.top, DesignTokens.Layout.popoverTopArrowClearance)
    }
}

public extension View {
    func bottomAttachedPopoverContent() -> some View {
        modifier(BottomAttachedPopoverContent())
    }
}
