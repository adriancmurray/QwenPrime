import SwiftUI

struct SystemPromptSettingsTab: View {
  @Bindable var appState: AppState
  @State private var selectedPresetId = SystemPromptPreset.builtInPresets.first?.id
  @State private var isAppliedFeedback: Bool = false
  @State private var appliedFeedbackTask: Task<Void, Never>?

  private var selectedPreset: SystemPromptPreset? {
    appState.promptPresets.first(where: { $0.id == selectedPresetId })
      ?? appState.promptPresets.first
  }

  private var canApplyToActiveChat: Bool {
    AppCommandAvailability.conversationIdle.isEnabled(
      in: appState.commandContext()
    )
  }

  var body: some View {
    HSplitView {
      // Left Master Sidebar: Prompt Preset List
      VStack(spacing: 0) {
        // Header & Add Button
        HStack {
          SettingsSectionLabel(title: "Prompts")

          Spacer()

          Button {
            let newPreset = SystemPromptPreset(
              name: "New Prompt",
              category: "Custom",
              description: "Custom system instructions.",
              icon: "pencil.line",
              promptText: "You are a custom AI assistant.",
              isBuiltIn: false
            )
            appState.savePromptPreset(newPreset)
            selectedPresetId = newPreset.id
          } label: {
            Image(systemName: "plus")
              .font(DesignTokens.TextStyle.subheadline.weight(.semibold))
              .foregroundStyle(DesignTokens.Status.reasoning)
              .padding(DesignTokens.Spacing.xs)
              .background(
                DesignTokens.Surface.subtle,
                in: RoundedRectangle(
                  cornerRadius: DesignTokens.Radius.sm
                )
              )
          }
          .buttonStyle(.plain)
          .help("Add Custom Prompt")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.base)
        .background(
          appState.activeTheme.controlBackground
            .opacity(DesignTokens.Opacity.strong)
        )

        Divider().opacity(DesignTokens.Opacity.divider)

        // List of presets
        ScrollView {
          LazyVStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(appState.promptPresets) { preset in
              let isSelected = preset.id == selectedPresetId
              let isDefault = appState.isDefaultPromptPreset(id: preset.id)

              Button {
                selectedPresetId = preset.id
              } label: {
                VStack(alignment: .leading, spacing: 2) {
                  HStack(spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: preset.icon)
                      .font(DesignTokens.TextStyle.subheadline)
                      .foregroundStyle(
                        isSelected
                          ? DesignTokens.Status.reasoning
                          : .secondary
                      )
                      .frame(width: 18)
                      .accessibilityHidden(true)

                    Text(preset.name)
                      .font(
                        DesignTokens.TextStyle.callout
                          .weight(
                            isSelected
                              ? .semibold
                              : .regular
                          )
                      )
                      .foregroundStyle(.primary)
                      .lineLimit(1)

                    if isDefault {
                      Circle()
                        .fill(DesignTokens.Status.reasoning)
                        .frame(width: 5, height: 5)
                        .help("Active Default")
                    }

                    Spacer(minLength: 0)
                  }

                  Text(preset.category)
                    .font(DesignTokens.TextStyle.caption)
                    .foregroundStyle(.tertiary)
                    .padding(
                      .leading,
                      18 + DesignTokens.Spacing.xs
                    )
                }
                .padding(.horizontal, DesignTokens.Spacing.base)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(
                  RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
                    .fill(
                      isSelected
                        ? appState.activeTheme.h1.opacity(0.14)
                        : Color.clear
                    )
                )
              }
              .buttonStyle(.plain)
            }
          }
          .padding(DesignTokens.Spacing.sm)
        }

        Divider().opacity(DesignTokens.Opacity.divider)

        // Footer Actions
        HStack {
          Button("Reset Defaults") {
            appState.requestResetPromptPresets(
              presentationScope: .settingsWindow
            )
          }
          .font(DesignTokens.TextStyle.footnote)
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)

          Spacer()
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.sm)
      }
      .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
      .background(appState.activeTheme.windowBackground.opacity(0.6))

      // Right Detail Editor
      if let preset = selectedPreset {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
          // Header Bar (Name, Category, Actions)
          HStack(spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: preset.icon)
                  .font(DesignTokens.TextStyle.title3)
                  .foregroundStyle(DesignTokens.Status.reasoning)
                  .frame(width: 24)
                  .accessibilityHidden(true)

                if preset.isBuiltIn {
                  Text(preset.name)
                    .font(DesignTokens.TextStyle.headline.weight(.bold))
                } else {
                  TextField(
                    "Prompt Name",
                    text: Binding(
                      get: { preset.name },
                      set: { name in
                        var updatedPreset = preset
                        updatedPreset.name = name
                        appState.savePromptPreset(updatedPreset)
                      }
                    )
                  )
                  .font(DesignTokens.TextStyle.headline.weight(.bold))
                  .textFieldStyle(.plain)
                }
              }

              Text(preset.description)
                .font(DesignTokens.TextStyle.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(
                  .leading,
                  24 + DesignTokens.Spacing.md
                )
            }

            Spacer()

            if !preset.isBuiltIn {
              Button(role: .destructive) {
                appState.requestDeletePromptPreset(
                  id: preset.id,
                  presentationScope: .settingsWindow
                )
              } label: {
                Image(systemName: "trash")
                  .font(DesignTokens.TextStyle.subheadline)
                  .foregroundStyle(DesignTokens.Status.danger.opacity(0.8))
                  .padding(DesignTokens.Spacing.xs)
              }
              .buttonStyle(.plain)
              .help("Delete Custom Prompt")
            }
          }
          .padding(.bottom, DesignTokens.Spacing.xs)

          // Text Editor Container
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
              SettingsSectionLabel(title: "Instructions")

              Spacer()

              Text(SystemPromptPresentation.lengthSummary(preset.promptText))
                .font(DesignTokens.TextStyle.footnoteMonospaced)
                .foregroundStyle(.tertiary)
            }

            TextEditor(
              text: Binding(
                get: {
                  appState.promptPresets.first(where: {
                    $0.id == preset.id
                  })?.promptText ?? ""
                },
                set: { promptText in
                  appState.updatePromptPresetText(
                    id: preset.id,
                    promptText: promptText
                  )
                }
              )
            )
            .font(DesignTokens.TextStyle.calloutMonospaced)
            .lineSpacing(DesignTokens.TextStyle.codeLineSpacing)
            .padding(DesignTokens.Spacing.sm)
            .background(
              appState.activeTheme.controlBackground,
              in: RoundedRectangle(
                cornerRadius: DesignTokens.Radius.base
              )
            )
            .overlay(
              RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
                .stroke(
                  DesignTokens.Stroke.separator,
                  lineWidth: 1
                )
            )
          }

          // Action Toolbar
          HStack(spacing: DesignTokens.Spacing.md) {
            let isDefault = appState.isDefaultPromptPreset(id: preset.id)

            Button {
              appState.setDefaultPromptPreset(id: preset.id)
            } label: {
              HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(
                    isDefault ? DesignTokens.Status.success : Color.secondary
                  )
                Text(isDefault ? "Default for New Chats" : "Set as Global Default")
              }
            }
            .buttonStyle(.bordered)
            .standardFormControl()

            Spacer()

            if isAppliedFeedback {
              Text("Applied to Active Chat!")
                .font(DesignTokens.TextStyle.subheadline.weight(.semibold))
                .foregroundStyle(DesignTokens.Status.success)
            }

            Button("Apply to Active Chat") {
              guard canApplyToActiveChat,
                var conversation = appState.selectedConversation
              else {
                return
              }
              conversation.systemPrompt = preset.promptText
              conversation.touch()
              appState.selectedConversation = conversation
              appState.saveConversation(conversation)
              showAppliedFeedback()
            }
            .buttonStyle(.borderedProminent)
            .standardFormControl()
            .disabled(!canApplyToActiveChat)
          }
        }
        .padding(DesignTokens.Spacing.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView("Select a Prompt", systemImage: "text.bubble")
      }
    }
    .onChange(of: appState.promptPresets.map(\.id)) { _, ids in
      selectedPresetId = SystemPromptSelection.resolved(
        current: selectedPresetId,
        available: ids
      )
    }
    .onDisappear(perform: cancelAppliedFeedback)
  }

  private func showAppliedFeedback() {
    appliedFeedbackTask?.cancel()
    withAnimation { isAppliedFeedback = true }
    appliedFeedbackTask = Task { @MainActor in
      do {
        try await Task.sleep(
          for: DesignTokens.Motion.feedbackDuration
        )
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      withAnimation { isAppliedFeedback = false }
      appliedFeedbackTask = nil
    }
  }

  private func cancelAppliedFeedback() {
    appliedFeedbackTask?.cancel()
    appliedFeedbackTask = nil
    isAppliedFeedback = false
  }
}

enum SystemPromptPresentation {
  static func lengthSummary(
    _ prompt: String,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    let tokenCount = PresentationFormatting.estimatedTokenCount(for: prompt)
    let characterSummary = PresentationFormatting.count(
      prompt.count,
      unit: .character,
      locale: locale
    )
    let tokenSummary = PresentationFormatting.approximateCount(
      tokenCount,
      unit: .token,
      locale: locale
    )
    return "\(characterSummary) • \(tokenSummary)"
  }
}

enum SystemPromptSelection {
  static func resolved(
    current: UUID?,
    available: [UUID]
  ) -> UUID? {
    guard let current, available.contains(current) else {
      return available.first
    }
    return current
  }
}
