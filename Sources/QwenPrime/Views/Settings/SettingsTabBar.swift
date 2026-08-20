import SwiftUI

enum SettingsNavigation {
    static let sections: [SettingsSection] = [
        .systemPrompts,
        .appearance,
        .engine,
        .sandbox,
        .general,
        .shortcuts,
    ]

    static func title(for section: SettingsSection) -> LocalizedStringKey {
        switch section {
        case .systemPrompts:
            "System Prompts"
        case .appearance:
            "Appearance"
        case .engine:
            "Engine & MLX"
        case .sandbox:
            "Workspace"
        case .general:
            "General"
        case .shortcuts:
            "Shortcuts"
        }
    }

    static func symbol(for section: SettingsSection) -> String {
        switch section {
        case .systemPrompts:
            "text.bubble.fill"
        case .appearance:
            "paintpalette.fill"
        case .engine:
            "bolt.horizontal.fill"
        case .sandbox:
            "shippingbox.fill"
        case .general:
            "gearshape.fill"
        case .shortcuts:
            "command"
        }
    }
}

struct SettingsTabBar: View {
    @Binding var selection: SettingsSection
    let theme: MarkdownTheme

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(SettingsNavigation.sections, id: \.self) { section in
                SettingsTabButton(
                    section: section,
                    isSelected: selection == section,
                    theme: theme
                ) {
                    selection = section
                }
            }
        }
        .padding(.horizontal, DesignTokens.Spacing.xxl)
        .padding(.vertical, DesignTokens.Spacing.lg)
        .background(DesignTokens.Surface.opaqueFallback)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }
}

private struct SettingsTabButton: View {
    let section: SettingsSection
    let isSelected: Bool
    let theme: MarkdownTheme
    let action: () -> Void

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Button(action: action) {
            VStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: SettingsNavigation.symbol(for: section))
                    .font(DesignTokens.TextStyle.title2)
                    .frame(height: DesignTokens.Layout.settingsTabIconHeight)

                Text(SettingsNavigation.title(for: section))
                    .font(DesignTokens.TextStyle.subheadline.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .foregroundStyle(isSelected ? theme.h1 : .secondary)
            .frame(
                maxWidth: .infinity,
                minHeight: DesignTokens.Layout.settingsTabHeight
            )
            .background(
                isSelected
                    ? DesignTokens.Surface.adaptiveSelected(
                        tint: theme.h1,
                        contrast: contrast,
                        reduceTransparency: reduceTransparency
                    )
                    : .clear,
                in: RoundedRectangle(
                    cornerRadius: DesignTokens.Radius.lg,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: DesignTokens.Radius.lg,
                    style: .continuous
                )
                .stroke(
                    isSelected ? theme.h1.opacity(DesignTokens.Opacity.prominent) : .clear,
                    lineWidth: 1
                )
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(SettingsNavigation.title(for: section))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
