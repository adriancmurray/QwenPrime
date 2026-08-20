import SwiftUI

struct ShortcutsSettingsTab: View {
  var body: some View {
    VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
      SettingsGroup("Keyboard Shortcuts") {
        ForEach(AppCommands.shortcuts) { command in
          SettingsLabeledRow(command.title) {
            SettingsKeyBadge(label: command.shortcut.displayName)
          }
        }
      }

      Spacer()
    }
    .padding(DesignTokens.Spacing.gutter)
  }

}
