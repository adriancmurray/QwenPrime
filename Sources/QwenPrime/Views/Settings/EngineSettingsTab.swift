import AppKit
import SwiftUI

// MARK: - 3. Engine & MLX Tab
struct EngineSettingsTab: View {
  @Bindable var appState: AppState
  @State private var endpointDraft: String
  @FocusState private var isEndpointFocused: Bool

  init(appState: AppState) {
    self.appState = appState
    _endpointDraft = State(initialValue: appState.baseURL)
  }

  private var currentProfile: RuntimeModelProfile {
    appState.editingModelProfile ?? appState.activeModelProfile ?? RuntimeModelProfile()
  }

  private var isActiveProfile: Bool {
    currentProfile.id == appState.runtimeConfiguration.activeProfileId
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
        SettingsGroup("Local Runtime") {
          HStack(spacing: DesignTokens.Spacing.base) {
            Image(systemName: runtimeStatusIcon)
              .foregroundStyle(runtimeStatusColor)
              .font(DesignTokens.TextStyle.title3)

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
              Text(runtimeStatusTitle)
                .font(DesignTokens.TextStyle.callout.weight(.semibold))
              Text(appState.runtimeSetupStatus.message)
                .font(DesignTokens.TextStyle.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }

            Spacer()

            Button(appState.runtimeLifecycleAction.title) {
              appState.toggleEngine()
            }
            .disabled(
              appState.serverStatus.isConnected
                ? !appState.isRuntimeManaged
                : appState.runtimeSetupStatus != .ready
            )
          }
        }

        SettingsGroup("Model Profiles") {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
            Text(
              "Model weights stay outside the app and are never replaced by an update. Select your Qwen3.8 target and matching native-MTP draft (Hybrid Q8/Q4 or 6-bit recommended)."
            )
            .font(DesignTokens.TextStyle.subheadline)
            .foregroundStyle(.secondary)

            HStack(spacing: DesignTokens.Spacing.md) {
              Picker(
                "Profile:",
                selection: Binding(
                  get: {
                    appState.selectedEditingProfileId ?? appState.runtimeConfiguration
                      .activeProfileId ?? currentProfile.id
                  },
                  set: { newId in
                    appState.selectedEditingProfileId = newId
                  }
                )
              ) {
                ForEach(appState.runtimeConfiguration.profiles) { profile in
                  HStack {
                    Text(profile.name)
                    if profile.id == appState.runtimeConfiguration.activeProfileId {
                      Text("(Active)")
                    }
                  }
                  .tag(profile.id)
                }
              }
              .pickerStyle(.menu)
              .standardFormControl()
              .frame(maxWidth: 240)

              Button {
                appState.addModelProfile(
                  name: "New Profile",
                  targetPath: "",
                  draftPath: ""
                )
              } label: {
                Image(systemName: "plus")
                Text("New Profile")
              }
              .buttonStyle(.bordered)
              .standardFormControl()

              if appState.runtimeConfiguration.profiles.count > 1 && !isActiveProfile {
                Button(role: .destructive) {
                  appState.requestDeleteModelProfile(
                    id: currentProfile.id,
                    presentationScope: .settingsWindow
                  )
                } label: {
                  Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.Status.danger.opacity(0.8))
                .help("Delete this profile")
              }

              Spacer()

              if isActiveProfile {
                HStack(spacing: DesignTokens.Spacing.xs) {
                  Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.Status.success)
                  Text("Active Profile")
                    .font(DesignTokens.TextStyle.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Status.success)
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.vertical, DesignTokens.Spacing.xxs)
                .background(
                  DesignTokens.Status.success.opacity(DesignTokens.Opacity.faint),
                  in: Capsule()
                )
              }
            }

            Divider().opacity(DesignTokens.Opacity.divider)

            HStack {
              Text("Profile Name")
                .font(DesignTokens.TextStyle.callout.weight(.medium))
              Spacer()
              TextField(
                "Profile Name",
                text: Binding(
                  get: { currentProfile.name },
                  set: { newName in
                    var updated = currentProfile
                    updated.name = newName
                    appState.saveModelProfile(updated)
                  }
                )
              )
              .textFieldStyle(.roundedBorder)
              .standardFormControl()
              .frame(width: 260)
            }

            modelPathRow(
              title: "Target Model Folder",
              path: currentProfile.targetModelPath,
              buttonTitle: "Choose Target…"
            ) {
              let profileID = currentProfile.id
              chooseModelDirectory(
                prompt: "Choose Qwen3.8 27B target model folder"
              ) { url in
                RuntimeModelFolderSelection.apply(
                  url,
                  to: profileID,
                  kind: .target,
                  appState: appState
                )
              }
            }

            Divider().opacity(DesignTokens.Opacity.divider)

            modelPathRow(
              title: "Native-MTP Draft Folder",
              path: currentProfile.draftModelPath,
              buttonTitle: "Choose Draft…"
            ) {
              let profileID = currentProfile.id
              chooseModelDirectory(
                prompt: "Choose matching Qwen3.8 native-MTP draft folder"
              ) { url in
                RuntimeModelFolderSelection.apply(
                  url,
                  to: profileID,
                  kind: .draft,
                  appState: appState
                )
              }
            }

            if let identity = appState.verifiedRuntimeIdentity,
              isActiveProfile && appState.serverStatus.isConnected
            {
              HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "cpu")
                  .foregroundStyle(DesignTokens.Status.reasoning)
                Text("Verified Runtime Quantization: \(identity.quantizationSummary)")
                  .font(DesignTokens.TextStyle.caption)
                  .foregroundStyle(.secondary)
                Text(identity.featureSummary)
                  .font(DesignTokens.TextStyle.captionMonospaced)
                  .foregroundStyle(.tertiary)
              }
            }

            HStack {
              Text(
                "Validation checks directories locally, then asks the bundled runtime to verify model identity, quantization, and the draft checksum."
              )
              .font(DesignTokens.TextStyle.caption)
              .foregroundStyle(.tertiary)
              Spacer()

              if !isActiveProfile {
                Button("Activate Profile") {
                  appState.activateProfile(id: currentProfile.id)
                }
                .buttonStyle(.borderedProminent)
                .standardFormControl()
                .disabled(
                  appState.isGenerating
                    || !currentProfile.isConfigured
                    || appState.runtimeSetupStatus == .validating
                )
                .help(
                  appState.isGenerating
                    ? "Cannot switch profile while generating" : "Activate this model profile")
              } else {
                Button("Save & Validate") {
                  appState.saveAndValidateRuntimeConfiguration()
                }
                .buttonStyle(.borderedProminent)
                .standardFormControl()
                .disabled(
                  appState.isGenerating
                    || !currentProfile.isConfigured
                    || appState.runtimeSetupStatus == .validating
                )
                .help(
                  appState.isGenerating
                    ? "Cannot switch profile while generating" : "Save and validate active profile")
              }
            }
          }
        }

        SettingsGroup("Connection & Response Mode") {
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.base) {
            HStack {
              Text("Endpoint")
                .font(DesignTokens.TextStyle.callout)
              Spacer()
              TextField(AppPreferences.defaultBaseURL, text: $endpointDraft)
                .textFieldStyle(.roundedBorder)
                .standardFormControl()
                .frame(width: 260)
                .font(DesignTokens.TextStyle.subheadlineMonospaced)
                .focused($isEndpointFocused)
                .onSubmit(commitEndpointDraft)
            }

            Toggle(
              "Use direct mode for new conversations", isOn: $appState.defaultDirectModeEnabled
            )
            .font(DesignTokens.TextStyle.callout)

            Text(
              "Turn this off to use reasoning mode for new conversations. Actual throughput varies with context, thermals, and native-MTP acceptance."
            )
            .font(DesignTokens.TextStyle.caption)
            .foregroundStyle(.secondary)
          }
        }
      }
      .padding(DesignTokens.Spacing.gutter)
    }
    .onChange(of: isEndpointFocused) { wasFocused, isFocused in
      guard wasFocused && !isFocused else { return }
      commitEndpointDraft()
    }
    .onChange(of: appState.baseURL) { _, endpoint in
      guard !isEndpointFocused else { return }
      endpointDraft = endpoint
    }
  }

  private func commitEndpointDraft() {
    appState.baseURL = endpointDraft
    endpointDraft = appState.baseURL
  }

  private var runtimeStatusTitle: String {
    switch appState.runtimeSetupStatus {
    case .notConfigured: "Setup required"
    case .validating: "Checking runtime"
    case .ready: appState.serverStatus.isConnected ? "Runtime active" : "Ready to start"
    case .invalid: "Setup needs attention"
    }
  }

  private var runtimeStatusIcon: String {
    switch appState.runtimeSetupStatus {
    case .notConfigured: "folder.badge.questionmark"
    case .validating: "hourglass"
    case .ready: appState.serverStatus.isConnected ? "checkmark.circle.fill" : "checkmark.circle"
    case .invalid: "exclamationmark.triangle.fill"
    }
  }

  private var runtimeStatusColor: Color {
    switch appState.runtimeSetupStatus {
    case .notConfigured: .secondary
    case .validating: DesignTokens.Status.reasoning
    case .ready: DesignTokens.Status.success
    case .invalid: DesignTokens.Status.warning
    }
  }

  private func modelPathRow(
    title: String,
    path: String,
    buttonTitle: String,
    action: @escaping () -> Void
  ) -> some View {
    HStack(spacing: DesignTokens.Spacing.base) {
      VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
        Text(title)
          .font(DesignTokens.TextStyle.callout.weight(.semibold))
        Text(path.isEmpty ? "No folder selected" : path)
          .font(DesignTokens.TextStyle.captionMonospaced)
          .foregroundStyle(path.isEmpty ? .tertiary : .secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(path)
      }
      Spacer(minLength: DesignTokens.Spacing.md)
      Button(buttonTitle, action: action)
        .standardFormControl()
    }
  }

  private func chooseModelDirectory(
    prompt: String,
    onSelection: @escaping @MainActor @Sendable (URL) -> Void
  ) {
    let panel = NSOpenPanel()
    panel.message = prompt
    panel.prompt = "Choose"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      Task { @MainActor in
        onSelection(url)
      }
    }
  }
}

enum RuntimeModelFolderKind: Sendable {
  case target
  case draft
}

@MainActor
enum RuntimeModelFolderSelection {
  @discardableResult
  static func apply(
    _ url: URL,
    to profileID: UUID,
    kind: RuntimeModelFolderKind,
    appState: AppState
  ) -> Bool {
    guard
      var profile = appState.runtimeConfiguration.profiles.first(
        where: { $0.id == profileID }
      )
    else {
      return false
    }
    switch kind {
    case .target:
      profile.targetModelPath = url.path
    case .draft:
      profile.draftModelPath = url.path
    }
    return appState.saveModelProfile(profile)
  }
}
