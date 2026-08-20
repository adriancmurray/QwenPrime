import AppKit
import SwiftUI

// MARK: - 4. Sandbox Tab
struct SandboxSettingsTab: View {
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast
  @Bindable var appState: AppState

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
        SettingsGroup("Active Project Workspace") {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
            Text(appState.sandboxDirectory.path)
              .font(DesignTokens.TextStyle.subheadlineMonospaced)
              .foregroundStyle(.secondary)
              .padding(DesignTokens.Spacing.sm)
              .frame(maxWidth: .infinity, alignment: .leading)
              .background(
                DesignTokens.Surface.recessed(
                  contrast: contrast,
                  reduceTransparency: reduceTransparency
                ),
                in: RoundedRectangle(
                  cornerRadius: DesignTokens.Radius.base
                )
              )

            HStack(spacing: DesignTokens.Spacing.base) {
              Button("Choose Folder...") {
                chooseSandboxDirectory()
              }

              Button("Reveal in Finder") {
                appState.openSandboxInFinder()
              }

              Button("Open Terminal") {
                appState.openSandboxInTerminal()
              }
            }
          }
        }

        SettingsGroup("Workspace Isolation & Guardrails") {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
              Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(DesignTokens.Status.success)
              Text("Ordinary chat does not read files or access the filesystem.")
                .font(DesignTokens.TextStyle.subheadline)
            }

            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
              Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(DesignTokens.Status.success)
              Text(
                "Agent reads and proposed text changes are strictly "
                  + "scoped to the selected workspace folder."
              )
              .font(DesignTokens.TextStyle.subheadline)
            }

            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
              Image(systemName: "lock.shield.fill")
                .foregroundStyle(DesignTokens.Status.warning)
              Text(
                "Secret and sensitive paths (.git, .env, private "
                  + "keys) are blocked and denied access."
              )
              .font(DesignTokens.TextStyle.subheadline)
            }

            HStack(alignment: .top, spacing: DesignTokens.Spacing.sm) {
              Image(systemName: "hand.raised.shield.fill")
                .foregroundStyle(DesignTokens.Status.reasoning)
              Text(
                "The agent pauses for diff or command review, then "
                  + "resumes with the Apply, Run, or Reject result. "
                  + "Approved commands use a network-disabled "
                  + "App-Sandboxed helper; arbitrary shell execution "
                  + "remains unavailable."
              )
              .font(DesignTokens.TextStyle.subheadline)
            }
          }
          .foregroundStyle(.secondary)
        }

        Spacer()
      }
      .padding(DesignTokens.Spacing.gutter)
    }
  }

  private func chooseSandboxDirectory() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Choose Workspace"
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        appState.setSandboxDirectory(url)
      }
    }
  }
}
