import Foundation
import Testing

@testable import QwenPrime

@Suite("Shared token estimation and runtime lifecycle labels")
struct TokenAndRuntimePresentationTests {
  @Test("Token estimation preserves character and UTF-8 budget semantics")
  func tokenEstimationSemantics() {
    #expect(TokenEstimation.characterBasedCount(for: "") == 0)
    for characterCount in 1...8 {
      let text = String(repeating: "x", count: characterCount)
      let expectedCount = characterCount <= 4 ? 1 : 2
      #expect(
        TokenEstimation.characterBasedCount(for: text) == expectedCount
      )
    }
    #expect(TokenEstimation.utf8BasedCount(for: "1234567") == 1)
    #expect(TokenEstimation.utf8BasedCount(for: "") == 0)
    #expect(TokenEstimation.utf8BudgetCount(for: "") == 0)
    #expect(TokenEstimation.utf8BudgetCount(for: "1234567") == 2)

    let multibyteText = "éééé"
    #expect(TokenEstimation.characterBasedCount(for: multibyteText) == 1)
    #expect(TokenEstimation.utf8BasedCount(for: multibyteText) == 2)
    #expect(TokenEstimation.utf8BudgetCount(for: multibyteText) == 2)
  }

  @Test("Streaming estimates are invariant across one to three character chunks")
  func streamingTokenEstimationIsChunkInvariant() {
    let completeText = "1234567"
    let fragmentations = [
      [completeText],
      ["1", "2", "3", "4", "5", "6", "7"],
      ["12", "34", "56", "7"],
      ["123", "456", "7"],
    ]

    for fragments in fragmentations {
      var estimator = StreamingTokenEstimator()
      for fragment in fragments {
        let didAppend = estimator.append(fragment)
        #expect(didAppend)
      }
      #expect(
        estimator.estimatedTokenCount
          == TokenEstimation.characterBasedCount(for: completeText)
      )
      let didAppendEmptyDelta = estimator.append("")
      #expect(!didAppendEmptyDelta)
      #expect(
        estimator.estimatedTokenCount
          == TokenEstimation.characterBasedCount(for: completeText)
      )
    }
  }

  @Test("Long fragmented streams retain only their trailing grapheme")
  func streamingTokenEstimationDoesNotRetainTheFullResponse() {
    let completeText = String(repeating: "a", count: 20_000)
    var fragmentedEstimator = StreamingTokenEstimator()
    var singleChunkEstimator = StreamingTokenEstimator()

    for character in completeText {
      let didAppend = fragmentedEstimator.append(String(character))
      #expect(didAppend)
    }
    let didAppendSingleChunk = singleChunkEstimator.append(completeText)
    #expect(didAppendSingleChunk)

    #expect(
      fragmentedEstimator.estimatedTokenCount
        == singleChunkEstimator.estimatedTokenCount
    )
    #expect(
      fragmentedEstimator.estimatedTokenCount
        == TokenEstimation.characterBasedCount(for: completeText)
    )
    #expect(fragmentedEstimator.retainedBoundaryUTF8CountForTesting == 1)
    #expect(singleChunkEstimator.retainedBoundaryUTF8CountForTesting == 1)
  }

  @Test("Streaming estimates remain invariant across grapheme boundaries")
  func streamingTokenEstimationHandlesSplitGraphemes() {
    let combinedCharacter = "e\u{301}"
    let completeText = String(repeating: combinedCharacter, count: 8)
    let fragments = Array(
      repeating: ["e", "\u{301}"],
      count: 8
    ).flatMap { $0 }
    var estimator = StreamingTokenEstimator()

    for fragment in fragments {
      _ = estimator.append(fragment)
    }

    #expect(completeText.count == 8)
    #expect(
      estimator.estimatedTokenCount
        == TokenEstimation.characterBasedCount(for: completeText)
    )
  }

  @Test("Oversized combining streams use bounded grapheme state")
  func streamingTokenEstimationBoundsZalgoState() {
    let combiningMark = "\u{301}"
    let combiningMarks = String(repeating: combiningMark, count: 20_000)
    let completeText = "e" + combiningMarks + "x"
    var fragmentedEstimator = StreamingTokenEstimator()
    var singleChunkEstimator = StreamingTokenEstimator()

    let didAppendBase = fragmentedEstimator.append("e")
    #expect(didAppendBase)
    for _ in 0..<20_000 {
      let didAppendMark = fragmentedEstimator.append(combiningMark)
      #expect(didAppendMark)
    }
    let didAppendFinalCharacter = fragmentedEstimator.append("x")
    #expect(didAppendFinalCharacter)
    let didAppendSingleChunk = singleChunkEstimator.append(completeText)
    #expect(didAppendSingleChunk)

    #expect(
      fragmentedEstimator.estimatedTokenCount
        == singleChunkEstimator.estimatedTokenCount
    )
    #expect(
      fragmentedEstimator.estimatedTokenCount
        == TokenEstimation.characterBasedCount(for: completeText)
    )
    #expect(
      fragmentedEstimator.retainedBoundaryUTF8CountForTesting
        <= StreamingTokenEstimator.maximumRetainedBoundaryUTF8Count
    )
    #expect(
      singleChunkEstimator.retainedBoundaryUTF8CountForTesting
        <= StreamingTokenEstimator.maximumRetainedBoundaryUTF8Count
    )
  }

  @Test("Leading combining and long ZWJ streams keep bounded state")
  func streamingTokenEstimationBoundsPathologicalLeadingState() {
    let leadingMarks = String(repeating: "\u{301}", count: 10_000)
    var leadingEstimator = StreamingTokenEstimator()
    let didAppendLeadingMarks = leadingEstimator.append(leadingMarks)
    #expect(didAppendLeadingMarks)
    #expect(leadingEstimator.estimatedTokenCount == 1)
    #expect(
      leadingEstimator.retainedBoundaryUTF8CountForTesting
        <= StreamingTokenEstimator.maximumRetainedBoundaryUTF8Count
    )

    var completeEmoji = "👩"
    var fragmentedEmojiEstimator = StreamingTokenEstimator()
    let didAppendFirstEmoji = fragmentedEmojiEstimator.append("👩")
    #expect(didAppendFirstEmoji)
    for _ in 0..<1_000 {
      completeEmoji += "\u{200D}💻"
      let didAppendJoiner = fragmentedEmojiEstimator.append("\u{200D}")
      #expect(didAppendJoiner)
      let didAppendEmoji = fragmentedEmojiEstimator.append("💻")
      #expect(didAppendEmoji)
    }
    var singleEmojiEstimator = StreamingTokenEstimator()
    let didAppendCompleteEmoji = singleEmojiEstimator.append(completeEmoji)
    #expect(didAppendCompleteEmoji)

    #expect(completeEmoji.count == 1)
    #expect(
      fragmentedEmojiEstimator.estimatedTokenCount
        == singleEmojiEstimator.estimatedTokenCount
    )
    #expect(
      fragmentedEmojiEstimator.retainedBoundaryUTF8CountForTesting
        <= StreamingTokenEstimator.maximumRetainedBoundaryUTF8Count
    )
    #expect(
      singleEmojiEstimator.retainedBoundaryUTF8CountForTesting
        <= StreamingTokenEstimator.maximumRetainedBoundaryUTF8Count
    )
  }

  @Test("Streaming estimates preserve split ZWJ emoji and regional flags")
  func streamingTokenEstimationHandlesEmojiBoundaries() {
    let completeText = "👩‍💻🇵🇷"
    let fragments = ["👩", "\u{200D}", "💻", "🇵", "🇷"]
    var estimator = StreamingTokenEstimator()

    for fragment in fragments {
      let didAppend = estimator.append(fragment)
      #expect(didAppend)
    }

    #expect(completeText.count == 2)
    #expect(
      estimator.estimatedTokenCount
        == TokenEstimation.characterBasedCount(for: completeText)
    )
    #expect(
      estimator.retainedBoundaryUTF8CountForTesting == "🇵🇷".utf8.count
    )
  }

  @Test("Empty streaming deltas preserve estimate and retained boundary")
  func streamingTokenEstimationIgnoresEmptyDeltas() {
    var estimator = StreamingTokenEstimator()
    let didAppendText = estimator.append("hello")
    #expect(didAppendText)
    let tokenCount = estimator.estimatedTokenCount
    let retainedByteCount = estimator.retainedBoundaryUTF8CountForTesting

    let didAppendEmpty = estimator.append("")

    #expect(!didAppendEmpty)
    #expect(estimator.estimatedTokenCount == tokenCount)
    #expect(estimator.retainedBoundaryUTF8CountForTesting == retainedByteCount)
  }

  @Test("Runtime lifecycle titles have one state mapping")
  func runtimeLifecycleTitles() {
    #expect(
      RuntimeLifecycleAction.resolve(
        isConnected: false,
        isManaged: false
      ).title == "Start Runtime"
    )
    #expect(
      RuntimeLifecycleAction.resolve(
        isConnected: true,
        isManaged: true
      ).title == "Stop Runtime"
    )
    #expect(
      RuntimeLifecycleAction.resolve(
        isConnected: true,
        isManaged: false
      ).title == "External Runtime"
    )
  }

  @Test("AppState owns runtime lifecycle resolution and execution")
  @MainActor
  func appStateOwnsRuntimeLifecycleToggle() throws {
    let suiteName = "QwenPrimeTests-RuntimeToggle-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    appState.runtimeSetupStatus = .notConfigured
    appState.serverStatus = .disconnected(reason: "Offline")

    #expect(appState.runtimeLifecycleAction == .start)
    #expect(appState.toggleEngine() == .start)
    #expect(appState.settingsSelection == .engine)
    #expect(!appState.serverStatus.isConnected)

    appState.serverStatus = .connected(model: "External", latencyMs: 1)

    #expect(appState.runtimeLifecycleAction == .external)
    #expect(appState.toggleEngine() == .external)
    #expect(appState.serverStatus.isConnected)
  }
}
