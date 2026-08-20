import SwiftUI

struct SettingsSectionLabel: View {
  let title: String

  var body: some View {
    Text(title.uppercased())
      .font(DesignTokens.TextStyle.footnote.weight(.bold))
      .foregroundStyle(.secondary)
  }
}
