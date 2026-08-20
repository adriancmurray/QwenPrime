import Foundation
import Testing

@testable import QwenPrime

@Suite("Asynchronous panels and app termination contracts")
struct AsyncPanelAndTerminationContractTests {
  private actor StopRecorder {
    private(set) var count = 0

    func record() {
      count += 1
    }
  }

  @MainActor
  private final class ReplyRecorder {
    private(set) var count = 0

    func record() {
      count += 1
    }
  }

  private func source(_ relativePath: String) throws -> String {
    let repositoryRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return try String(
      contentsOf: repositoryRoot.appendingPathComponent(relativePath),
      encoding: .utf8
    )
  }

  @Test("Workspace folder panels are nonblocking and update on MainActor")
  func workspacePanelsAreAsynchronous() throws {
    let sandboxSource = try source(
      "Sources/QwenPrime/Views/Settings/SandboxSettingsTab.swift"
    )
    let promptInputSource = try source(
      "Sources/QwenPrime/Views/Chat/PromptInputBar.swift"
    )

    for panelSource in [sandboxSource, promptInputSource] {
      #expect(panelSource.contains("panel.begin { response in"))
      #expect(panelSource.contains("Task { @MainActor in"))
      #expect(!panelSource.contains("runModal()"))
    }
    #expect(sandboxSource.contains("appState.setSandboxDirectory(url)"))
    #expect(promptInputSource.contains("onSelectProject(url)"))
  }

  @Test("Termination is bounded and replies from the main actor")
  func terminationReplySemantics() throws {
    let appSource = try source(
      "Sources/QwenPrime/App/QwenPrimeApp.swift"
    )

    #expect(appSource.contains("ApplicationTerminationCoordinator"))
    #expect(appSource.contains("await waitForStopOrTimeout(stop: stop)"))
    #expect(appSource.contains("await ServerHealthService.shared.stopEngine()"))
    #expect(
      appSource.contains("sender.reply(toApplicationShouldTerminate: true)")
    )
    #expect(appSource.contains("return .terminateLater"))
    #expect(!appSource.contains("withTaskGroup"))
    #expect(!appSource.contains("MainActor.run"))
  }

  @Test(
    "Graceful termination completes before timeout and replies exactly once"
  )
  @MainActor
  func immediateTerminationCompletionRepliesOnce() async throws {
    let coordinator = ApplicationTerminationCoordinator(
      timeout: .milliseconds(20)
    )
    let stopRecorder = StopRecorder()
    let replyRecorder = ReplyRecorder()

    await coordinator.stopThenReply(
      stop: {
        await stopRecorder.record()
      },
      reply: {
        replyRecorder.record()
      }
    )
    try await Task.sleep(for: .milliseconds(40))

    #expect(await stopRecorder.count == 1)
    #expect(replyRecorder.count == 1)
  }

  @Test("Termination timeout replies even when cleanup never completes")
  @MainActor
  func stalledTerminationStillRepliesOnce() async throws {
    let coordinator = ApplicationTerminationCoordinator(
      timeout: .milliseconds(20)
    )
    let replyRecorder = ReplyRecorder()

    Task {
      await coordinator.stopThenReply(
        stop: {
          await Self.suspendForever()
        },
        reply: {
          replyRecorder.record()
        }
      )
    }
    try await AsyncCondition.wait(
      timeout: .seconds(2),
      description: "bounded termination reply"
    ) {
      replyRecorder.count == 1
    }
    try await Task.sleep(for: .milliseconds(40))

    #expect(replyRecorder.count == 1)
  }

  private static func suspendForever() async {
    await withUnsafeContinuation { (_: UnsafeContinuation<Void, Never>) in }
  }
}
