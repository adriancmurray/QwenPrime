import SwiftUI

public struct ToolExecutionCard: View {
    public let execution: ToolExecution
    public let theme: MarkdownTheme

    @State private var isExpanded: Bool = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(execution: ToolExecution, theme: MarkdownTheme = MarkdownTheme.theme(for: .primeDark)) {
        self.execution = execution
        self.theme = theme
    }

    private var isWorkspaceTool: Bool {
        execution.toolName.hasPrefix("workspace_")
    }

    private var toolCategoryLabel: String {
        isWorkspaceTool ? "Workspace Read" : "Tool"
    }

    private var toolIcon: String {
        isWorkspaceTool ? "doc.text.magnifyingglass" : "wrench.and.screwdriver"
    }

    private var statusDescription: String {
        if execution.isRunning { return "Running" }
        if let success = execution.isSuccess {
            return success ? "Success" : "Failed"
        }
        return "Pending"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Bar
            Button {
                withAnimation(reduceMotion ? nil : DesignTokens.AnimationCurve.spring) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DesignTokens.Spacing.md) {
                    HStack(spacing: DesignTokens.Spacing.xs) {
                        Image(systemName: toolIcon)
                            .font(.system(size: DesignTokens.Typography.footnote))
                            .foregroundStyle(Color.cyan)

                        Text("\(toolCategoryLabel) (\(execution.toolName))")
                            .font(.system(size: DesignTokens.Typography.subheadline, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                    }

                    Spacer()

                    // Status Pill
                    if execution.isRunning {
                        HStack(spacing: DesignTokens.Spacing.xs) {
                            ProgressView()
                                .controlSize(.mini)
                            Text("Running")
                                .font(.system(size: DesignTokens.Typography.caption2, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    } else if let success = execution.isSuccess {
                        HStack(spacing: DesignTokens.Spacing.xxs) {
                            Image(systemName: success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.system(size: DesignTokens.Typography.caption))
                                .foregroundStyle(success ? Color.green : Color.red)
                            Text(success ? "Success" : "Failed")
                                .font(.system(size: DesignTokens.Typography.caption2, weight: .medium))
                                .foregroundStyle(success ? Color.green : Color.red)
                        }
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: DesignTokens.Typography.caption2))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, DesignTokens.Spacing.base)
                .padding(.vertical, DesignTokens.Spacing.sm)
                .background(Color.black.opacity(DesignTokens.Opacity.prominent))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(toolCategoryLabel): \(execution.toolName), \(statusDescription)")
            .help("\(toolCategoryLabel): \(execution.toolName)")

            if isExpanded {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                    // Code Input
                    Text(execution.input)
                        .font(.system(size: DesignTokens.Typography.subheadline, weight: .regular, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(DesignTokens.Opacity.high))
                        .padding(DesignTokens.Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base))

                    // Output Logs
                    if let output = execution.output, !output.isEmpty {
                        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
                            Text("OUTPUT:")
                                .font(.system(size: DesignTokens.Typography.micro, weight: .bold, design: .monospaced))
                                .foregroundStyle(.tertiary)

                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(output)
                                    .font(.system(size: DesignTokens.Typography.footnote, weight: .regular, design: .monospaced))
                                    .foregroundStyle(execution.isSuccess == false ? Color.red.opacity(0.9) : Color.cyan.opacity(0.9))
                                    .lineSpacing(DesignTokens.Typography.lineSpacingCode)
                                    .textSelection(.enabled)
                            }
                            .padding(DesignTokens.Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.4), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xs))
                        }
                        .padding(.top, DesignTokens.Spacing.xxs)
                    }
                }
                .padding(DesignTokens.Spacing.md)
                .background(Color.white.opacity(DesignTokens.Opacity.faint))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.md)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .padding(.vertical, DesignTokens.Spacing.xs)
    }
}
