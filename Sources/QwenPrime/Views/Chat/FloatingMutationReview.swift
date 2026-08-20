import SwiftUI

enum FloatingToolApprovalPresentation {
    static func systemImage(for toolName: String) -> String {
        ToolExecutionCategory(toolName: toolName).systemImage
    }
}

public struct FloatingToolApprovalReview: View {
    public let request: WorkspaceApprovalRequest
    public let pendingCount: Int
    public let tint: Color
    public let onApprove: () -> Void
    public let onReject: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    public init(
        request: WorkspaceApprovalRequest,
        pendingCount: Int,
        tint: Color,
        onApprove: @escaping () -> Void,
        onReject: @escaping () -> Void
    ) {
        self.request = request
        self.pendingCount = pendingCount
        self.tint = tint
        self.onApprove = onApprove
        self.onReject = onReject
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(spacing: DesignTokens.Spacing.sm) {
                    Image(systemName: FloatingToolApprovalPresentation.systemImage(
                        for: request.toolName
                    ))
                        .foregroundStyle(tint)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(title)
                            .font(DesignTokens.TextStyle.callout.weight(.semibold))
                        Text(subject)
                            .font(DesignTokens.TextStyle.captionMonospaced)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if pendingCount > 1 {
                        Text("1 of \(pendingCount)")
                            .font(DesignTokens.TextStyle.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView([.horizontal, .vertical]) {
                    Text(preview)
                        .font(DesignTokens.TextStyle.footnoteMonospaced)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 132)
                .padding(DesignTokens.Spacing.sm)
                .background(
                    DesignTokens.Surface.recessed(
                        contrast: contrast,
                        reduceTransparency: reduceTransparency
                    ),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
                )

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(footnote)
                        .font(DesignTokens.TextStyle.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Reject", action: onReject)
                        .buttonStyle(.bordered)
                        .help(rejectHelp)

                    Button(approveTitle, action: onApprove)
                        .buttonStyle(.borderedProminent)
                        .help(approveHelp)
                }
            }
            .padding(DesignTokens.Spacing.lg)
            .frame(maxWidth: DesignTokens.Layout.composerMaxWidth)
            .primeGlassSurface(
                cornerRadius: DesignTokens.Radius.xl,
                tint: tint.opacity(0.1),
                isInteractive: true
            )
            .tint(tint)
            .shadow(
                color: DesignTokens.Elevation.floatingShadow,
                radius: DesignTokens.Elevation.floatingRadius,
                y: DesignTokens.Elevation.floatingOffset
            )
            .padding(.horizontal, DesignTokens.Spacing.section)
            .transition(
                reduceMotion
                    ? .opacity
                    : .opacity.combined(with: .move(edge: .bottom))
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(title): \(subject)")
    }

    private var title: String {
        switch request.payload {
        case .mutation(let proposal):
            proposal.operation == .changeSet
                ? "Agent paused · Review workspace changes"
                : "Agent paused · Review workspace change"
        case .command:
            "Agent paused · Review process"
        case .externalTool:
            "Agent paused · Review external tool"
        }
    }

    private var subject: String {
        switch request.payload {
        case .mutation(let proposal): proposal.relativePath
        case .command(let proposal): proposal.command
        case .externalTool(let proposal):
            "\(proposal.providerDisplayName) / \(proposal.toolName)"
        }
    }

    private var preview: String {
        switch request.payload {
        case .mutation(let proposal): proposal.preview
        case .command(let proposal): proposal.preview
        case .externalTool(let proposal): proposal.argumentsPreview
        }
    }

    private var footnote: String {
        switch request.payload {
        case .mutation: "Nothing changes until you apply this diff."
        case .command:
            "The argv-only process action runs only after approval in the network-disabled sandboxed helper."
        case .externalTool:
            "The arguments are sent to the local MCP server only after approval. No workspace root is shared automatically."
        }
    }

    private var approveTitle: String {
        switch request.payload {
        case .mutation: "Apply"
        case .command: isWorkspaceStop ? "Stop" : "Run"
        case .externalTool: "Allow Once"
        }
    }

    private var approveHelp: String {
        switch request.payload {
        case .mutation(let proposal):
            proposal.operation == .changeSet
                ? "Apply all reviewed workspace changes"
                : "Apply the reviewed change to \(proposal.relativePath)"
        case .command:
            isWorkspaceStop
                ? "Stop the reviewed workspace process"
                : "Run the reviewed argv-only process in the sandboxed helper"
        case .externalTool(let proposal):
            "Allow one call to \(proposal.toolName) through \(proposal.providerDisplayName)"
        }
    }

    private var rejectHelp: String {
        switch request.payload {
        case .externalTool:
            "Reject this external tool call"
        default:
            "Reject this action"
        }
    }

    private var isWorkspaceStop: Bool {
        request.toolName == ToolName.workspaceProcessStop
    }
}
