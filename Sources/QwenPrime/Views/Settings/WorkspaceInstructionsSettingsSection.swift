import SwiftUI

struct WorkspaceInstructionsSettingsSection: View {
    @Bindable var appState: AppState

    var body: some View {
        GroupBox("Workspace Instructions") {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                        Toggle(
                            "Use root AGENTS.md in Agent mode",
                            isOn: $appState.isWorkspaceInstructionsEnabled
                        )
                        .font(.system(size: DesignTokens.Typography.callout))

                        Text("Qwen Prime loads only the selected workspace's root AGENTS.md. It does not add tools, expand access, or bypass review.")
                            .font(.system(size: DesignTokens.Typography.caption))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task { await appState.refreshWorkspaceInstructions() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh workspace instructions")
                    .accessibilityLabel("Refresh workspace instructions")
                }

                HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(
                        systemName: appState.workspaceInstructions == nil
                            ? "doc.badge.ellipsis"
                            : "checkmark.circle.fill"
                    )
                    .foregroundStyle(
                        appState.workspaceInstructions == nil ? Color.secondary : Color.green
                    )

                    Text(
                        appState.workspaceInstructions == nil
                            ? "No root AGENTS.md found"
                            : "Root AGENTS.md found"
                    )
                    .font(.system(size: DesignTokens.Typography.caption, weight: .medium))

                    if let document = appState.workspaceInstructions {
                        Text(document.fileURL.path)
                            .font(.system(size: DesignTokens.Typography.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(DesignTokens.Spacing.md)
        }
        .task {
            await appState.refreshWorkspaceInstructions()
        }
    }
}
