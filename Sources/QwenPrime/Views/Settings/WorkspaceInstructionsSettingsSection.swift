import SwiftUI

struct WorkspaceInstructionsSettingsSection: View {
  @Bindable var appState: AppState

  var body: some View {
    SettingsGroup("Workspace Instructions") {
      HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
          Toggle(
            "Use root AGENTS.md in Agent mode",
            isOn: $appState.isWorkspaceInstructionsEnabled
          )
          .font(DesignTokens.TextStyle.callout)

          Text(
            "Qwen Prime loads only the selected workspace's root AGENTS.md. It does not add tools, expand access, or bypass review."
          )
          .font(DesignTokens.TextStyle.caption)
          .foregroundStyle(.secondary)
        }

        Spacer()

        IconActionButton(
          "arrow.clockwise",
          label: "Refresh workspace instructions"
        ) {
          Task { await appState.refreshWorkspaceInstructions() }
        }
      }

      HStack(spacing: DesignTokens.Spacing.xs) {
        Image(
          systemName: appState.workspaceInstructions == nil
            ? "doc.badge.ellipsis"
            : "checkmark.circle.fill"
        )
        .foregroundStyle(
          appState.workspaceInstructions == nil
            ? Color.secondary
            : DesignTokens.Status.success
        )

        Text(
          appState.workspaceInstructions == nil
            ? "No root AGENTS.md found"
            : "Root AGENTS.md found"
        )
        .font(DesignTokens.TextStyle.caption.weight(.medium))

        if let document = appState.workspaceInstructions {
          Text(document.fileURL.path)
            .font(DesignTokens.TextStyle.caption2Monospaced)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.middle)
        }
      }
    }
    .task {
      await appState.refreshWorkspaceInstructions()
    }
  }
}
