import SwiftUI

public struct ToolExecutionCard: View {
    public let execution: ToolExecution
    public let theme: MarkdownTheme

    @State private var isExpanded: Bool = true

    public init(execution: ToolExecution, theme: MarkdownTheme = MarkdownTheme.theme(for: .primeDark)) {
        self.execution = execution
        self.theme = theme
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Color.cyan)

                        Text("Sandbox Action (\(execution.toolName))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    // Status Pill
                    if execution.isRunning {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Running")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    } else if let success = execution.isSuccess {
                        HStack(spacing: 3) {
                            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(success ? Color.green : Color.red)
                            Text(success ? "Success" : "Failed")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(success ? Color.green : Color.red)
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.35))
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    // Code Input
                    Text(execution.input)
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))

                    // Output Logs
                    if let output = execution.output, !output.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("OUTPUT:")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(.tertiary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(output)
                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                    .foregroundStyle(execution.isSuccess == false ? Color.red.opacity(0.9) : Color.cyan.opacity(0.9))
                                    .lineSpacing(2)
                                    .textSelection(.enabled)
                            }
                            .padding(6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 4))
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(8)
                .background(Color.white.opacity(0.02))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .padding(.vertical, 3)
    }
}
