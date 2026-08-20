import SwiftUI

#Preview("No Conversation Selected") {
  NoConversationSelectedView(theme: .theme(for: .primeDark))
    .frame(width: 720, height: 500)
}

#Preview("Empty Conversation") {
  EmptyConversationView(
    modelName: AppPreferences.defaultModel,
    theme: .theme(for: .primeDark)
  )
  .frame(width: 720, height: 500)
}

#Preview("Streaming Response") {
  MessageBubble(
    message: ChatMessage(
      role: .assistant,
      content: "",
      thinkingContent: "Comparing the available approaches…",
      isThinkingExpanded: true,
      isStreaming: true
    ),
    isThinkingExpanded: .constant(true)
  )
  .padding()
  .frame(width: 720)
}

#Preview("Long Markdown Response") {
  MessageBubble(
    message: ChatMessage(
      role: .assistant,
      content: """
        # Implementation notes

        A long response should remain readable, selectable, and stable while
        the window changes size.

        - Repeated item
        - Repeated item

        ```swift
        let greeting = "Hello from Qwen Prime"
        ```
        """
    ),
    isThinkingExpanded: .constant(false)
  )
  .padding()
  .frame(width: 720)
}

#Preview("Tool Error") {
  MessageBubble(
    message: ChatMessage(
      role: .assistant,
      content: "I couldn’t finish that workspace operation.",
      toolExecutions: [
        ToolExecution(
          toolName: ToolName.workspaceReadFile,
          input: #"{"path":"Sources/App.swift"}"#,
          output: "The requested file could not be read.",
          isSuccess: false
        )
      ]
    ),
    isThinkingExpanded: .constant(false)
  )
  .padding()
  .frame(width: 720)
}

#Preview("Approval Required") {
  FloatingToolApprovalReview(
    request: WorkspaceApprovalRequest(
      conversationID: UUID(),
      messageID: UUID(),
      callID: "preview-change",
      toolName: ToolName.workspaceApplyPatch,
      proposal: WorkspaceMutationProposal(
        operation: .applyPatch,
        relativePath: "Sources/App.swift",
        expectedContent: nil,
        proposedContent: "",
        preview: "- old title\n+ improved title"
      )
    ),
    pendingCount: 1,
    tint: .accentColor,
    onApprove: {},
    onReject: {}
  )
  .padding()
  .frame(width: 720, height: 360)
}
