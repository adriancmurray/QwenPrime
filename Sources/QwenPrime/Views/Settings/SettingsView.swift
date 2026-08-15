import SwiftUI

public struct SettingsView: View {
    @Bindable public var appState: AppState
    @Environment(\.dismiss) private var dismiss

    public init(appState: AppState) {
        self.appState = appState
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Color.cyan)
                    Text("Qwen Prime Settings")
                        .font(.system(size: 16, weight: .bold))
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            // Server Configuration
            VStack(alignment: .leading, spacing: 12) {
                Text("Backend Engine")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("API Base URL")
                        .font(.system(size: 11.5, weight: .medium))

                    TextField("http://127.0.0.1:8000/v1", text: $appState.baseURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Model ID")
                        .font(.system(size: 11.5, weight: .medium))

                    TextField("qwen3.8-27b", text: $appState.selectedModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }

                // Health test button
                HStack {
                    Button {
                        Task {
                            await appState.checkServerHealth()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                            Text("Test Connection")
                                .font(.system(size: 11.5))
                        }
                    }

                    Spacer()

                    if case .connected(let model, let lat) = appState.serverStatus {
                        HStack(spacing: 4) {
                            Circle().fill(Color.green).frame(width: 6, height: 6)
                            Text("\(model) (\(Int(lat))ms)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    } else if case .disconnected(let reason) = appState.serverStatus {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 6, height: 6)
                            Text(reason)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding(14)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))

            // Conversation Defaults
            if var selectedConv = appState.selectedConversation {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Active Chat Parameters")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Temperature")
                                .font(.system(size: 11.5, weight: .medium))
                            Spacer()
                            Text(String(format: "%.2f", selectedConv.temperature))
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Slider(value: Binding(
                            get: { selectedConv.temperature },
                            set: {
                                selectedConv.temperature = $0
                                appState.selectedConversation = selectedConv
                                appState.saveConversation(selectedConv)
                            }
                        ), in: 0.0...1.0, step: 0.05)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("System Prompt")
                            .font(.system(size: 11.5, weight: .medium))

                        TextEditor(text: Binding(
                            get: { selectedConv.systemPrompt ?? "" },
                            set: {
                                selectedConv.systemPrompt = $0.isEmpty ? nil : $0
                                appState.selectedConversation = selectedConv
                                appState.saveConversation(selectedConv)
                            }
                        ))
                        .font(.system(size: 12))
                        .frame(height: 70)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .padding(14)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 440, height: 480)
    }
}
