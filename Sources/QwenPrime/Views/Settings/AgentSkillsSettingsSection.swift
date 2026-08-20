import SwiftUI

struct AgentSkillsSettingsSection: View {
  @Bindable var appState: AppState

  var body: some View {
    SettingsGroup("Agent Skills") {
      HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
          Text(
            "Enable reusable instruction packages, then invoke one explicitly with `$skill-name` in Agent mode."
          )
          .font(DesignTokens.TextStyle.caption)
          .foregroundStyle(.secondary)

          Text(
            "Skills add instructions only. They cannot add tools, run scripts, expand workspace access, use the network, or bypass approval."
          )
          .font(DesignTokens.TextStyle.caption)
          .foregroundStyle(.tertiary)
        }

        Spacer()

        IconActionButton(
          "arrow.clockwise",
          label: "Refresh agent skills"
        ) {
          Task { await appState.refreshAgentSkills() }
        }
      }

      if appState.agentSkills.isEmpty {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
          Label("No skills found", systemImage: "books.vertical")
            .font(DesignTokens.TextStyle.callout.weight(.medium))
          Text(
            "Add SKILL.md packages to `.qwenprime/skills` in the workspace or `~/Library/Application Support/QwenPrime/skills`."
          )
          .font(DesignTokens.TextStyle.caption)
          .foregroundStyle(.secondary)
        }
      } else {
        VStack(spacing: 0) {
          ForEach(Array(appState.agentSkills.enumerated()), id: \.element.id) { index, skill in
            if index > 0 {
              Divider()
            }
            skillRow(skill)
          }
        }
      }
    }
    .task {
      await appState.refreshAgentSkills()
    }
  }

  private func skillRow(_ skill: AgentSkill) -> some View {
    Toggle(
      isOn: Binding(
        get: { appState.enabledAgentSkillIDs.contains(skill.id) },
        set: { appState.setAgentSkill(skill, enabled: $0) }
      )
    ) {
      HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
          Text("$\(skill.name)")
            .font(DesignTokens.TextStyle.calloutMonospaced.weight(.semibold))

          if !skill.description.isEmpty {
            Text(skill.description)
              .font(DesignTokens.TextStyle.caption)
              .foregroundStyle(.secondary)
              .lineLimit(2)
          }
        }

        Spacer()

        Text(skill.source == .workspace ? "Workspace" : "User")
          .font(DesignTokens.TextStyle.caption2.weight(.medium))
          .foregroundStyle(.secondary)
          .padding(.horizontal, DesignTokens.Spacing.sm)
          .padding(.vertical, DesignTokens.Spacing.xxs)
          .background(.quaternary, in: Capsule())
      }
    }
    .toggleStyle(.switch)
    .padding(.vertical, DesignTokens.Spacing.sm)
    .accessibilityHint("Enable this skill for explicit use in Agent mode")
  }
}
