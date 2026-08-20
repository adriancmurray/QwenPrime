import SwiftUI

// MARK: - 5. General Tab
struct GeneralSettingsTab: View {
  @Bindable var appState: AppState

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
        SettingsGroup(
          "Chat Behavior",
          spacing: DesignTokens.Spacing.lg
        ) {
          SettingsLabeledRow("Default Model") {
            TextField("Model ID", text: $appState.selectedModel)
              .textFieldStyle(.roundedBorder)
              .standardFormControl()
              .frame(width: 220)
              .font(
                DesignTokens.TextStyle.subheadlineMonospaced
              )
          }

          Toggle(
            "Auto-scroll to latest token while streaming",
            isOn: $appState.isAutoScrollEnabled
          )
          .font(DesignTokens.TextStyle.callout)

          Toggle(
            "Expand reasoning details by default",
            isOn: $appState.isThinkingExpandedByDefault
          )
          .font(DesignTokens.TextStyle.callout)
        }

        SettingsGroup("Workspace Agent Preview") {
          Toggle(
            "Workspace Agent Preview",
            isOn: $appState.isAgentPreviewEnabled
          )
          .font(DesignTokens.TextStyle.callout)

          Toggle(
            "Use Agent mode for new conversations",
            isOn: $appState.defaultAgentModeEnabled
          )
          .font(DesignTokens.TextStyle.callout)
          .disabled(!appState.isAgentPreviewEnabled)

          SettingsHelpText(
            text: "Agent mode can inspect text files and propose "
              + "bounded changes. It can request sandboxed argv-only "
              + "workspace processes. Mutating actions pause for diff "
              + "review; the run resumes after Apply, Run, or Reject. "
              + "Shell execution is unavailable; Qwen Prime does not "
              + "parse shell command strings."
          )

          HStack(spacing: DesignTokens.Spacing.xs) {
            Image(
              systemName: appState.runtimeSupportsStructuredToolCalls
                ? "checkmark.circle.fill"
                : "info.circle"
            )
            .foregroundStyle(
              appState.runtimeSupportsStructuredToolCalls
                ? DesignTokens.Status.success
                : DesignTokens.Status.warning
            )
            Text(
              appState.runtimeSupportsStructuredToolCalls
                ? "Runtime structured tool calls supported."
                : "Runtime structured tool support unavailable."
            )
            .font(DesignTokens.TextStyle.caption)
            .foregroundStyle(.secondary)
          }

          SettingsHelpText(
            text: "Ordinary chat remains available regardless of this "
              + "preview setting."
          )
        }

        WorkspaceInstructionsSettingsSection(appState: appState)

        AgentSkillsSettingsSection(appState: appState)

        MCPServersSettingsSection(appState: appState)

        SettingsGroup(
          "About Qwen Prime",
          spacing: DesignTokens.Spacing.sm
        ) {
          SettingsLabeledRow("Version") {
            Text(AppVersionPresentation.aboutDescription)
              .font(DesignTokens.TextStyle.callout)
              .foregroundStyle(.secondary)
          }

          SettingsLabeledRow("Engine Support") {
            Text("Apple Metal MLX & DFlash")
              .font(DesignTokens.TextStyle.callout)
              .foregroundStyle(.secondary)
          }
        }

        Spacer()
      }
      .padding(DesignTokens.Spacing.gutter)
    }
  }

}
