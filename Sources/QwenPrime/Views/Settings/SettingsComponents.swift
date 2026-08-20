import SwiftUI

struct SettingsGroup<Content: View>: View {
  private let title: String
  private let spacing: CGFloat
  private let content: Content

  init(
    _ title: String,
    spacing: CGFloat = DesignTokens.Spacing.md,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.spacing = spacing
    self.content = content()
  }

  var body: some View {
    GroupBox(title) {
      VStack(alignment: .leading, spacing: spacing) {
        content
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(DesignTokens.Spacing.md)
    }
  }
}

struct SettingsLabeledRow<Content: View>: View {
  private let title: String
  private let content: Content

  init(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    HStack(spacing: DesignTokens.Spacing.md) {
      Text(title)
        .font(DesignTokens.TextStyle.callout)
      Spacer(minLength: DesignTokens.Spacing.md)
      content
    }
  }
}

struct SettingsHelpText: View {
  let text: String

  var body: some View {
    Text(text)
      .font(DesignTokens.TextStyle.caption)
      .foregroundStyle(.secondary)
  }
}

struct SettingsKeyBadge: View {
  let label: String

  var body: some View {
    Text(label)
      .font(
        DesignTokens.TextStyle.subheadlineMonospaced.weight(.semibold)
      )
      .padding(.horizontal, DesignTokens.Spacing.md)
      .padding(.vertical, DesignTokens.Spacing.xs)
      .background(
        Color.primary.opacity(DesignTokens.Opacity.subtle),
        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm)
      )
  }
}
