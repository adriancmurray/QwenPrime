import Foundation
import Testing

@testable import QwenPrime

@Suite("UI and UX behavior")
struct UIUXBehaviorTests {
  @Test("Conversation drafts remain scoped to their conversation")
  @MainActor
  func conversationDraftsAreIndependent() {
    let viewModel = ChatViewModel()
    let firstConversationID = UUID()
    let secondConversationID = UUID()

    viewModel.setDraft("First draft", for: firstConversationID)
    viewModel.setDraft("Second draft", for: secondConversationID)

    #expect(viewModel.draft(for: firstConversationID) == "First draft")
    #expect(viewModel.draft(for: secondConversationID) == "Second draft")

    viewModel.draftBinding(for: firstConversationID).wrappedValue = "Updated"
    #expect(viewModel.draft(for: firstConversationID) == "Updated")
    #expect(viewModel.draft(for: secondConversationID) == "Second draft")

    viewModel.setDraft("  \n ", for: firstConversationID)
    #expect(viewModel.draft(for: firstConversationID).isEmpty)
    #expect(viewModel.draft(for: secondConversationID) == "Second draft")
  }

  @Test(
    "Draft cleanup removes deleted conversations and preserves active drafts"
  )
  @MainActor
  func conversationDraftCleanupUsesActiveIdentities() {
    let viewModel = ChatViewModel()
    let retainedConversationID = UUID()
    let deletedConversationID = UUID()
    let addedConversationID = UUID()
    viewModel.setDraft("Keep me", for: retainedConversationID)
    viewModel.setDraft("Remove me", for: deletedConversationID)

    viewModel.retainDrafts(
      for: [retainedConversationID, deletedConversationID, addedConversationID]
    )
    #expect(viewModel.draft(for: retainedConversationID) == "Keep me")
    #expect(viewModel.draft(for: deletedConversationID) == "Remove me")

    viewModel.retainDrafts(for: [retainedConversationID, addedConversationID])
    #expect(viewModel.draft(for: retainedConversationID) == "Keep me")
    #expect(viewModel.draft(for: deletedConversationID).isEmpty)
    #expect(viewModel.draft(for: addedConversationID).isEmpty)
  }

  @Test("Chat view wires draft cleanup to conversation identity changes")
  func chatViewWiresDraftCleanup() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/QwenPrime/Views/Chat/ChatView.swift"
      ),
      encoding: .utf8
    )

    #expect(source.contains("Set(appState.conversations.map(\\.id))"))
    #expect(source.contains("viewModel.retainDrafts(for: conversationIDs)"))
  }

  @Test("Conversation header softly obscures only the detail content")
  func conversationHeaderUsesFeatheredDetailBackdrop() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let chatView = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/QwenPrime/Views/Chat/ChatView.swift"
      ),
      encoding: .utf8
    )
    let splitView = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/QwenPrime/Views/MainSplitView.swift"
      ),
      encoding: .utf8
    )

    #expect(chatView.contains("private struct ConversationPathHeader: View"))
    #expect(chatView.contains("ProjectScope.displayName(for: workspaceURL)"))
    #expect(!chatView.contains(".primeGlassSurface("))
    #expect(chatView.contains("FeatheredDetailHeaderBackdrop"))
    #expect(
      chatView.contains("DesignTokens.Layout.detailHeaderBackdropHeight")
    )
    #expect(chatView.contains(".ignoresSafeArea(edges: .top)"))
    #expect(chatView.contains("struct UntintedVisualEffectView"))
    #expect(chatView.contains("view.material = .contentBackground"))
    #expect(chatView.contains("location: 0.04"))
    #expect(
      splitView.contains(
        ".toolbarBackgroundVisibility(.hidden, for: .windowToolbar)"
      )
    )
    #expect(!splitView.contains(".toolbarBackground(.ultraThinMaterial"))
  }

  @Test("Bottom-attached popovers reserve space for their arrow")
  func bottomAttachedPopoversProtectTheirFirstTitle() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let sharedPopover = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/QwenPrime/Views/Shared/ThemedPopoverActionRow.swift"
      ),
      encoding: .utf8
    )
    let workspacePicker = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/QwenPrime/Views/Chat/PromptInputBar.swift"
      ),
      encoding: .utf8
    )
    let runtimePicker = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/QwenPrime/Views/Chat/QuickSettingsPopover.swift"
      ),
      encoding: .utf8
    )

    #expect(sharedPopover.contains("struct BottomAttachedPopoverContent"))
    #expect(
      sharedPopover.contains(
        "DesignTokens.Layout.popoverTopArrowClearance"
      )
    )
    #expect(
      sharedPopover.contains("DesignTokens.Layout.popoverActionIconWidth")
    )
    #expect(
      sharedPopover.contains(
        ".padding(\n                .leading,\n                DesignTokens.Spacing.sm"
      )
    )
    #expect(workspacePicker.contains(".bottomAttachedPopoverContent()"))
    #expect(runtimePicker.contains(".bottomAttachedPopoverContent()"))
    #expect(
      workspacePicker.contains(
        ".padding(.horizontal, DesignTokens.Spacing.md)"
      )
    )
    #expect(
      runtimePicker.contains(".padding(.horizontal, DesignTokens.Spacing.md)")
    )
    #expect(
      runtimePicker.contains(
        ".bottomAttachedPopoverContent()\n        .frame(width: DesignTokens.Layout.runtimeProfilePickerPopoverWidth)"
      )
    )
  }

  @Test("Quick Settings actions look and respond like buttons")
  func quickSettingsActionsUseThemedButtonAffordance() throws {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let source = try String(
      contentsOf: repositoryRoot.appendingPathComponent(
        "Sources/QwenPrime/Views/Chat/QuickSettingsPopover.swift"
      ),
      encoding: .utf8
    )

    #expect(source.contains("struct QuickSettingsActionRow: View"))
    #expect(source.contains(".primeCardSurface("))
    #expect(
      source.contains(
        "DesignTokens.Layout.quickSettingsActionRowHeight"
      )
    )
    #expect(source.contains("QuickSettingsActionButtonStyle()"))
    #expect(source.contains("configuration.isPressed"))
  }

  @Test("Sending clears compatibility input and the conversation draft")
  @MainActor
  func sendingClearsEveryDraftSource() throws {
    let suiteName = "QwenPrimeTests-DraftSend-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let conversation = Conversation(title: "Draft clearing")
    appState.conversations = [conversation]
    appState.selectedConversationId = conversation.id
    let viewModel = ChatViewModel()
    viewModel.inputText = "Compatibility input"
    viewModel.setDraft("Scoped draft", for: conversation.id)

    viewModel.sendMessage(appState: appState)

    #expect(viewModel.inputText.isEmpty)
    #expect(viewModel.draft(for: conversation.id).isEmpty)
    viewModel.stopGeneration(
      conversationID: conversation.id,
      appState: appState
    )
  }

  @Test("An empty scoped draft falls back to compatibility input")
  @MainActor
  func emptyScopedDraftUsesCompatibilityInput() throws {
    let suiteName = "QwenPrimeTests-EmptyDraft-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let conversation = Conversation(title: "Draft fallback")
    appState.conversations = [conversation]
    appState.selectedConversationId = conversation.id
    let viewModel = ChatViewModel()
    viewModel.inputText = "Compatibility input"

    viewModel.sendMessage(appState: appState, draftText: "  \n ")

    let sentMessage = try #require(appState.selectedConversation?.messages.first)
    #expect(sentMessage.role == .user)
    #expect(sentMessage.content == "Compatibility input")
    #expect(viewModel.inputText.isEmpty)
    #expect(viewModel.draft(for: conversation.id).isEmpty)
    viewModel.stopGeneration(
      conversationID: conversation.id,
      appState: appState
    )
  }

  @Test("Sending without explicit input uses the selected conversation draft")
  @MainActor
  func implicitSendUsesSelectedConversationDraft() throws {
    let suiteName = "QwenPrimeTests-ImplicitDraft-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let selectedConversation = Conversation(title: "Selected")
    let otherConversation = Conversation(title: "Other")
    appState.conversations = [selectedConversation, otherConversation]
    appState.selectedConversationId = selectedConversation.id
    let viewModel = ChatViewModel()
    viewModel.setDraft(
      "Selected conversation draft",
      for: selectedConversation.id
    )
    viewModel.setDraft(
      "Other conversation draft",
      for: otherConversation.id
    )

    viewModel.sendMessage(appState: appState)

    let sentMessage = try #require(
      appState.selectedConversation?.messages.first
    )
    #expect(sentMessage.role == .user)
    #expect(sentMessage.content == "Selected conversation draft")
    #expect(viewModel.draft(for: selectedConversation.id).isEmpty)
    #expect(
      viewModel.draft(for: otherConversation.id) == "Other conversation draft"
    )
    viewModel.stopGeneration(
      conversationID: selectedConversation.id,
      appState: appState
    )
  }

  @Test("Repeated Markdown list values remain distinct rows")
  func repeatedMarkdownListValuesArePreserved() throws {
    let blocks = MarkdownParser.parse(markdown: "- repeated\n- repeated")
    let block = try #require(blocks.first)

    guard case .bulletList(let items) = block else {
      Issue.record("Expected a bullet list")
      return
    }
    #expect(items == ["repeated", "repeated"])
  }

  @Test("Dynamic Markdown preserves percent format characters")
  func dynamicMarkdownPercentCharacters() {
    let source = "100% ready with %s, %@, and %d"
    let attributed = MarkdownInlineFormatting.attributedString(for: source)

    #expect(String(attributed.characters) == source)
  }

  @Test("Append-only Markdown keeps parsed blocks and shows only its suffix")
  func appendOnlyMarkdownPreservesParsedBlocks() {
    let state = MarkdownRenderState(
      content: "# Parsed heading\n\nStreaming suffix",
      parsedContent: "# Parsed heading"
    )

    #expect(state.shouldRenderParsedBlocks)
    #expect(state.plainTextFallback == "\n\nStreaming suffix")
    #expect(state.plainTextFallbackKind == .appendedSuffix)
    #expect(state.topLevelSpacing == 0)
    #expect(MarkdownRenderState.blockSpacing == 10)
  }

  @Test("Replacement Markdown hides stale blocks and shows current plain text")
  func replacementMarkdownRejectsStaleBlocks() {
    let currentContent = "Replacement content"
    let state = MarkdownRenderState(
      content: currentContent,
      parsedContent: "Unrelated parsed content"
    )

    #expect(!state.shouldRenderParsedBlocks)
    #expect(state.plainTextFallback == currentContent)
    #expect(state.plainTextFallbackKind == .fullContent)
    #expect(state.topLevelSpacing == MarkdownRenderState.blockSpacing)
  }

  @Test("Initial Markdown shows the full current content as plain text")
  func initialMarkdownUsesPlainTextFallback() {
    let currentContent = "# Partial heading\n\n[unfinished link]("
    let state = MarkdownRenderState(
      content: currentContent,
      parsedContent: ""
    )

    #expect(!state.shouldRenderParsedBlocks)
    #expect(state.plainTextFallback == currentContent)
  }

  @Test("Caught-up Markdown shows parsed blocks without fallback text")
  func caughtUpMarkdownUsesParsedBlocksOnly() {
    let content = "# Fully parsed"
    let state = MarkdownRenderState(
      content: content,
      parsedContent: content
    )

    #expect(state.shouldRenderParsedBlocks)
    #expect(state.plainTextFallback == nil)
    #expect(state.plainTextFallbackKind == nil)
  }

  @Test("Streaming Markdown parses the current document without a raw suffix")
  func streamingMarkdownUsesCurrentBlocksDirectly() {
    let state = MarkdownRenderState(
      content: "## Streaming heading\n\n- current item",
      parsedContent: "## Stale heading",
      isStreaming: true
    )

    #expect(state.shouldRenderParsedBlocks)
    #expect(state.plainTextFallback == nil)
    #expect(state.plainTextFallbackKind == nil)
  }

  @Test("Markdown table row labels cover empty and mismatched columns")
  func markdownTableRowLabelsHandleColumnMismatch() {
    let emptyRow = MarkdownAccessibility.tableRowLabel(
      rowNumber: 1,
      headers: [],
      cells: []
    )
    let missingCells = MarkdownAccessibility.tableRowLabel(
      rowNumber: 2,
      headers: ["Name", "Role"],
      cells: []
    )
    let extraCell = MarkdownAccessibility.tableRowLabel(
      rowNumber: 3,
      headers: ["Name"],
      cells: ["Ana", "Owner"]
    )
    let unlabeledAndEmpty = MarkdownAccessibility.tableRowLabel(
      rowNumber: 4,
      headers: ["", "Status"],
      cells: ["Ana", ""]
    )

    #expect(emptyRow == "Row 1")
    #expect(!emptyRow.hasSuffix(","))
    #expect(missingCells == "Row 2, Name: Empty, Role: Empty")
    #expect(extraCell == "Row 3, Name: Ana, Column 2: Owner")
    #expect(unlabeledAndEmpty == "Row 4, Column 1: Ana, Status: Empty")
  }

  @Test("Markdown tables preserve empty interior cells and column labels")
  func markdownTablesPreserveEmptyInteriorCells() throws {
    let borderedCells = MarkdownTableParsing.cells(
      in: "| Ana | | Active |"
    )
    let unborderedCells = MarkdownTableParsing.cells(
      in: "Ana | | Active"
    )
    let blocks = MarkdownParser.parse(
      markdown: """
        | Name | Role | Status |
        | --- | --- | --- |
        | Ana | | Active |
        """)
    let block = try #require(blocks.first)
    guard case .table(let headers, let rows) = block else {
      Issue.record("Expected a Markdown table")
      return
    }
    let firstRow = try #require(rows.first)
    let accessibilityLabel = MarkdownAccessibility.tableRowLabel(
      rowNumber: 1,
      headers: headers,
      cells: firstRow
    )

    #expect(borderedCells == ["Ana", "", "Active"])
    #expect(unborderedCells == borderedCells)
    #expect(headers == ["Name", "Role", "Status"])
    #expect(firstRow == borderedCells)
    #expect(
      accessibilityLabel == "Row 1, Name: Ana, Role: Empty, Status: Active"
    )
  }

  @Test("Markdown tables pad short rows without losing intentional empties")
  func markdownTablesPadShortRows() throws {
    let blocks = MarkdownParser.parse(
      markdown: """
        | Name | Role | Status |
        | --- | --- | --- |
        | Ana | |
        """)
    let block = try #require(blocks.first)
    guard case .table(let headers, let rows) = block else {
      Issue.record("Expected a Markdown table")
      return
    }
    let parsedRow = try #require(rows.first)
    let presentedCells = MarkdownTablePresentation.cells(
      headers: headers,
      row: parsedRow
    )
    let accessibilityLabel = MarkdownAccessibility.tableRowLabel(
      rowNumber: 1,
      headers: headers,
      cells: presentedCells
    )

    #expect(parsedRow == ["Ana", ""])
    #expect(presentedCells == ["Ana", "", ""])
    #expect(
      accessibilityLabel == "Row 1, Name: Ana, Role: Empty, Status: Empty"
    )
  }

  @Test("Markdown documents are cached without changing parsed content")
  func markdownDocumentCacheIsStable() async {
    let markdown = "# Heading\n\nA paragraph"
    let first = await MarkdownDocumentCache.shared.blocks(for: markdown)
    let second = await MarkdownDocumentCache.shared.blocks(for: markdown)

    #expect(first == second)
    #expect(first?.count == 2)
  }

  @Test("Markdown cache evicts the least recently used document at capacity")
  func markdownCacheEvictsLeastRecentlyUsedDocument() async {
    let cache = MarkdownDocumentCache()
    for index in 0..<24 {
      _ = await cache.blocks(for: "Document \(index)")
    }
    _ = await cache.blocks(for: "Document 0")
    _ = await cache.blocks(for: "Document 24")

    let cachedCount = await cache.cachedDocumentCount
    let containsFirst = await cache.containsCachedDocument("Document 0")
    let containsSecond = await cache.containsCachedDocument("Document 1")
    let containsNewest = await cache.containsCachedDocument("Document 24")
    #expect(cachedCount == 24)
    #expect(containsFirst)
    #expect(!containsSecond)
    #expect(containsNewest)
  }

  @Test("Scroll pinning supports flipped and non-flipped coordinate systems")
  func scrollPositionPinning() {
    let document = CGRect(x: 0, y: 0, width: 600, height: 1_000)

    #expect(
      ChatScrollPositionPolicy.isPinned(
        documentBounds: document,
        visibleRect: CGRect(x: 0, y: 680, width: 600, height: 300),
        isFlipped: true
      ))
    #expect(
      !ChatScrollPositionPolicy.isPinned(
        documentBounds: document,
        visibleRect: CGRect(x: 0, y: 600, width: 600, height: 300),
        isFlipped: true
      ))
    #expect(
      ChatScrollPositionPolicy.isPinned(
        documentBounds: document,
        visibleRect: CGRect(x: 0, y: 20, width: 600, height: 300),
        isFlipped: false
      ))
    #expect(
      !ChatScrollPositionPolicy.isPinned(
        documentBounds: document,
        visibleRect: CGRect(x: 0, y: 100, width: 600, height: 300),
        isFlipped: false
      ))
  }
}
