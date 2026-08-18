import SwiftUI

struct MCPServersSettingsSection: View {
    @Bindable var appState: AppState

    var body: some View {
        GroupBox("Local MCP Servers") {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
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
                .controlSize(.small)

                Text("This preview accepts localhost only. Every MCP call pauses for Allow Once approval.")
                    .font(.system(size: DesignTokens.Typography.caption))
                    .foregroundStyle(.secondary)

                Text("An MCP server does not receive the workspace path or workspace roots automatically.")
                    .font(.system(size: DesignTokens.Typography.caption))
                    .foregroundStyle(.tertiary)
            }
            .padding(DesignTokens.Spacing.md)
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
                    Toggle("", isOn: binding(for: \.isEnabled, default: profile.isEnabled))
                        .labelsHidden()
                        .help(profile.isEnabled ? "Disable this MCP server" : "Enable this MCP server")

                    TextField(
                        "Server name",
                        text: binding(for: \.displayName, default: profile.displayName)
                    )
                        .textFieldStyle(.roundedBorder)

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
                    .controlSize(.small)
                    .disabled(state == .testing)

                    Button(role: .destructive) {
                        appState.removeMCPServer(id: profileID)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Remove MCP server")
                    .help("Remove MCP server")
                }

                TextField(
                    "http://127.0.0.1:3001/mcp",
                    text: binding(for: \.endpoint, default: profile.endpoint)
                )
                .textFieldStyle(.roundedBorder)
                .font(.system(size: DesignTokens.Typography.caption, design: .monospaced))

                connectionStatus

                if case .connected(let tools) = state, !tools.isEmpty {
                    DisclosureGroup(isExpanded: $showsTools) {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                            ForEach(tools) { tool in
                                VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                                    Text(tool.name)
                                        .font(.system(size: DesignTokens.Typography.caption, weight: .semibold, design: .monospaced))
                                    if let description = tool.description, !description.isEmpty {
                                        Text(description)
                                            .font(.system(size: DesignTokens.Typography.caption))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .padding(.top, DesignTokens.Spacing.xs)
                    } label: {
                        Text("Discovered Tools")
                            .font(.system(size: DesignTokens.Typography.caption, weight: .medium))
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
            Label("Connected · \(tools.count) tools", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
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
