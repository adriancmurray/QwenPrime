import SwiftUI

public struct FloatingToolApprovalReview: View {
    public let request: WorkspaceApprovalRequest
    public let pendingCount: Int
    public let tint: Color
    public let onApprove: () -> Void
    public let onReject: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                    Image(systemName: "pencil.and.list.clipboard")
                        .foregroundStyle(tint)

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                        Text(title)
                            .font(.system(size: DesignTokens.Typography.callout, weight: .semibold))
                        Text(subject)
                            .font(.system(size: DesignTokens.Typography.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if pendingCount > 1 {
                        Text("1 of \(pendingCount)")
                            .font(.system(size: DesignTokens.Typography.caption2, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView([.horizontal, .vertical]) {
                    Text(preview)
                        .font(.system(size: DesignTokens.Typography.footnote, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 132)
                .padding(DesignTokens.Spacing.sm)
                .background(
                    Color.black.opacity(DesignTokens.Opacity.prominent),
                    in: RoundedRectangle(cornerRadius: DesignTokens.Radius.base)
                )

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(footnote)
                        .font(.system(size: DesignTokens.Typography.caption))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Reject", action: onReject)
                        .buttonStyle(.bordered)
                        .help("Reject this change without modifying the workspace")

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
            .shadow(color: .black.opacity(0.16), radius: 14, y: 6)
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
        case .mutation: "Agent paused · Review workspace change"
        case .command: "Agent paused · Review command"
        }
    }

    private var subject: String {
        switch request.payload {
        case .mutation(let proposal): proposal.relativePath
        case .command(let proposal): proposal.command
        }
    }

    private var preview: String {
        switch request.payload {
        case .mutation(let proposal): proposal.preview
        case .command(let proposal): proposal.preview
        }
    }

    private var footnote: String {
        switch request.payload {
        case .mutation: "Nothing changes until you apply this diff."
        case .command: "The command runs only after approval and remains sandboxed to this workspace."
        }
    }

    private var approveTitle: String {
        switch request.payload {
        case .mutation: "Apply"
        case .command: "Run"
        }
    }

    private var approveHelp: String {
        switch request.payload {
        case .mutation(let proposal):
            "Apply the reviewed change to \(proposal.relativePath)"
        case .command:
            "Run the reviewed command in the sandboxed helper"
        }
    }
}
