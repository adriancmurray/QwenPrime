import SwiftUI

struct MCPServersSettingsSection: View {
  @Bindable var appState: AppState

  var body: some View {
    SettingsGroup("Local MCP Servers") {
      ForEach(appState.mcpServers) { profile in
        MCPServerSettingsRow(appState: appState, profileID: profile.id)

        if profile.id != appState.mcpServers.last?.id {
          Divider().opacity(DesignTokens.Opacity.divider)
        }
      }

      Button {
        appState.addMCPServer()
      } label: {
        Label("Add Server", systemImage: "plus")
      }
      .buttonStyle(.bordered)
      .standardFormControl()

      Text("This preview accepts localhost only. Every MCP call pauses for Allow Once approval.")
        .font(DesignTokens.TextStyle.caption)
        .foregroundStyle(.secondary)

      Text("An MCP server does not receive the workspace path or workspace roots automatically.")
        .font(DesignTokens.TextStyle.caption)
        .foregroundStyle(.tertiary)
    }
  }
}

private struct MCPServerSettingsRow: View {
  @Bindable var appState: AppState
  let profileID: String
  @State private var showsTools = false

  private var profile: MCPServerProfile? {
    appState.mcpServers.first(where: { $0.id == profileID })
  }

  private var state: MCPServerConnectionState {
    appState.mcpServerConnectionStates[profileID] ?? .idle
  }

  var body: some View {
    if let profile {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
        HStack(spacing: DesignTokens.Spacing.sm) {
          Toggle(
            "Enable \(profile.displayName) MCP server",
            isOn: binding(for: \.isEnabled, default: profile.isEnabled)
          )
          .labelsHidden()
          .help(profile.isEnabled ? "Disable this MCP server" : "Enable this MCP server")

          TextField(
            "Server name",
            text: binding(for: \.displayName, default: profile.displayName)
          )
          .textFieldStyle(.roundedBorder)
          .standardFormControl()

          Button {
            Task { await appState.testMCPServer(id: profileID) }
          } label: {
            if state == .testing {
              ProgressView().controlSize(.small)
            } else {
              Text("Test Connection")
            }
          }
          .buttonStyle(.bordered)
          .standardFormControl()
          .disabled(state == .testing)

          IconActionButton(
            "trash",
            label: "Remove \(profile.displayName) MCP server",
            tint: DesignTokens.Status.danger,
            role: .destructive
          ) {
            appState.requestRemoveMCPServer(
              id: profileID,
              presentationScope: .settingsWindow
            )
          }
        }

        TextField(
          MCPServerProfile.defaultEndpoint,
          text: binding(for: \.endpoint, default: profile.endpoint)
        )
        .textFieldStyle(.roundedBorder)
        .standardFormControl()
        .font(DesignTokens.TextStyle.captionMonospaced)

        connectionStatus

        if case .connected(let tools) = state, !tools.isEmpty {
          DisclosureGroup(isExpanded: $showsTools) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
              ForEach(tools) { tool in
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                  Text(tool.name)
                    .font(DesignTokens.TextStyle.captionMonospaced.weight(.semibold))
                  if let description = tool.description, !description.isEmpty {
                    Text(description)
                      .font(DesignTokens.TextStyle.caption)
                      .foregroundStyle(.secondary)
                  }
                }
              }
            }
            .padding(.top, DesignTokens.Spacing.xs)
          } label: {
            Text("Discovered Tools")
              .font(DesignTokens.TextStyle.caption.weight(.medium))
          }
        }
      }
    }
  }

  @ViewBuilder
  private var connectionStatus: some View {
    switch state {
    case .idle:
      Label("Not tested", systemImage: "circle.dashed")
        .foregroundStyle(.secondary)
    case .testing:
      Label("Connecting and discovering tools…", systemImage: "network")
        .foregroundStyle(.secondary)
    case .connected(let tools):
      Label(
        "Connected · \(PresentationFormatting.count(tools.count, unit: .tool))",
        systemImage: "checkmark.circle.fill"
      )
        .foregroundStyle(DesignTokens.Status.success)
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(DesignTokens.Status.warning)
    }
  }

  private func binding<Value>(
    for keyPath: WritableKeyPath<MCPServerProfile, Value>,
    default defaultValue: Value
  ) -> Binding<Value> {
    Binding(
      get: {
        appState.mcpServers.first(where: { $0.id == profileID })?[keyPath: keyPath]
          ?? defaultValue
      },
      set: { value in
        guard var updated = appState.mcpServers.first(where: { $0.id == profileID }) else {
          return
        }
        updated[keyPath: keyPath] = value
        appState.updateMCPServer(updated)
      }
    )
  }
}
