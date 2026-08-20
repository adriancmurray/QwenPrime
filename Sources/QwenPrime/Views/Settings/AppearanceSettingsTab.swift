import SwiftUI

// MARK: - 2. Appearance Tab (Visual Interactive Theme Cards)
struct AppearanceSettingsTab: View {
  @Bindable var appState: AppState
  private let themeColumns = [
    GridItem(.flexible()),
    GridItem(.flexible()),
  ]

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.section) {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
          SettingsSectionLabel(title: "Theme Palettes")

          LazyVGrid(
            columns: themeColumns,
            spacing: DesignTokens.Spacing.lg
          ) {
            ForEach(ThemeType.allCases) { theme in
              ThemePaletteCard(
                theme: theme,
                isSelected: appState.currentThemeType == theme,
                onSelect: { appState.currentThemeType = theme }
              )
            }
          }
        }

        SettingsGroup("Design System", spacing: DesignTokens.Spacing.sm) {
          HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "sparkles")
              .foregroundStyle(DesignTokens.Status.reasoning)
            Text("Shared Interface Foundations")
              .font(
                DesignTokens.TextStyle.callout.weight(.semibold)
              )
          }

          SettingsHelpText(
            text: "Shared typography, spacing, surfaces, and interaction "
              + "states keep the core interface consistent across windows."
          )
        }
      }
      .padding(DesignTokens.Spacing.gutter)
    }
  }
}

struct ThemePaletteCard: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  let theme: ThemeType
  let isSelected: Bool
  let onSelect: () -> Void

  private var themeModel: MarkdownTheme {
    MarkdownTheme.theme(for: theme)
  }

  var body: some View {
    Button {
      onSelect()
    } label: {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
        // Header
        HStack {
          Text(theme.rawValue)
            .font(DesignTokens.TextStyle.body.weight(.bold))
            .foregroundStyle(themeModel.text)

          Spacer()

          if isSelected {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(themeModel.h1)
              .font(DesignTokens.TextStyle.headline)
          }
        }

        // Swatches
        HStack(spacing: DesignTokens.Spacing.sm) {
          Circle().fill(themeModel.h1).frame(width: 14, height: 14)
          Circle().fill(themeModel.userTextColor).frame(width: 14, height: 14)
          Circle().fill(themeModel.quoteBorder).frame(width: 14, height: 14)
          Circle().fill(themeModel.codeBlockBackground).frame(width: 14, height: 14)
        }

        // Mini Preview
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
          Text("Heading 1 Title")
            .font(DesignTokens.TextStyle.footnote.weight(.bold))
            .foregroundStyle(themeModel.h1)

          Text("Theme response preview.")
            .font(DesignTokens.TextStyle.caption)
            .foregroundStyle(themeModel.secondaryText)
        }
        .padding(DesignTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
          themeModel.codeBlockBackground,
          in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
        )
      }
      .padding(DesignTokens.Spacing.lg)
      .background(
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
          .fill(
            DesignTokens.Surface.adaptiveSubtle(
              contrast: contrast,
              reduceTransparency: reduceTransparency
            )
          )
      )
      .overlay(
        RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
          .stroke(
            isSelected
              ? themeModel.h1
              : DesignTokens.Stroke.adaptiveSeparator(
                contrast: contrast
              ),
            lineWidth: isSelected
              ? 2
              : DesignTokens.Stroke.lineWidth(contrast: contrast)
          )
      )
    }
    .buttonStyle(.plain)
  }
}
