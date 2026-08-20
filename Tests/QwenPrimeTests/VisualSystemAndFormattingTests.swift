import Foundation
import Testing

@testable import QwenPrime

@Suite("Centralized visual system and presentation formatting")
struct VisualSystemAndFormattingTests {
  private let locale = Locale(identifier: "en_US_POSIX")

  @Test("Estimated token counts share one empty and minimum-value policy")
  func estimatedTokenCount() {
    #expect(PresentationFormatting.estimatedTokenCount(for: "") == 0)
    #expect(PresentationFormatting.estimatedTokenCount(for: "a") == 1)
    #expect(
      PresentationFormatting.estimatedTokenCount(
        for: String(repeating: "a", count: 7)
      ) == 2
    )
    #expect(
      PresentationFormatting.estimatedTokenCount(
        for: String(repeating: "a", count: 8)
      ) == 2
    )
  }

  @Test("Counts use locale-aware numbers and correct singular or plural labels")
  func countFormatting() {
    #expect(
      PresentationFormatting.count(
        1,
        unit: .token,
        locale: locale
      ) == "1 token"
    )
    #expect(
      PresentationFormatting.count(
        2,
        unit: .token,
        locale: locale
      ) == "2 tokens"
    )
    #expect(
      PresentationFormatting.count(
        0,
        unit: .character,
        locale: locale
      ) == "0 characters"
    )
    #expect(
      PresentationFormatting.approximateCount(
        1,
        unit: .token,
        locale: locale
      ) == "~1 token"
    )
    #expect(
      PresentationFormatting.approximateCount(
        2,
        unit: .token,
        locale: locale
      ) == "~2 tokens"
    )
    #expect(
      PresentationFormatting.count(
        1_234,
        unit: .tool,
        locale: Locale(identifier: "en_US")
      ) == "1,234 tools"
    )
    #expect(
      PresentationFormatting.count(1, unit: .step, locale: locale)
        == "1 step"
    )
    #expect(
      PresentationFormatting.count(
        2,
        unit: .promptAndToolSchemaToken,
        locale: locale
      ) == "2 prompt and tool-schema tokens"
    )
  }

  @Test("Durations percentages and throughput share stable compact formatting")
  func compactMeasurementFormatting() {
    #expect(
      PresentationFormatting.duration(
        1.25,
        fractionDigits: 2,
        locale: locale
      ) == "1.25 s"
    )
    #expect(
      PresentationFormatting.duration(
        -1.5,
        locale: locale
      ) == "0.0 s"
    )
    #expect(
      PresentationFormatting.duration(
        -1,
        fractionDigits: -2,
        locale: locale
      ) == "0 s"
    )
    #expect(
      PresentationFormatting.decimal(
        1.5,
        fractionDigits: 10,
        locale: locale
      ) == "1.500000"
    )
    #expect(
      PresentationFormatting.percentage(
        0.42,
        locale: locale
      ) == "42%"
    )
    #expect(
      PresentationFormatting.throughput(
        12.34,
        isEstimated: true,
        locale: locale
      ) == "12.3 est. tok/s"
    )
  }

  @Test("Invalid floating-point presentation values fail closed")
  func invalidValues() {
    #expect(PresentationFormatting.duration(.infinity) == "—")
    #expect(PresentationFormatting.percentage(.nan) == "—")
    #expect(
      PresentationFormatting.throughput(
        -.infinity,
        isEstimated: false
      ) == "—"
    )
  }

  @Test("Every content palette keeps semantic appearance resolution")
  func themeResolution() {
    for type in ThemeType.allCases {
      let theme = MarkdownTheme.theme(for: type)
      let standard = theme.resolved(for: .standard)
      let increased = theme.resolved(for: .increased)

      #expect(standard.id == type)
      #expect(standard.name == type.rawValue)
      #expect(increased.id == type)
      #expect(increased.name == type.rawValue)
    }
  }

  @Test("Clipboard writes support empty and multiline values and report failures")
  @MainActor
  func clipboardWriting() {
    let pasteboard = RecordingPasteboard()

    #expect(PresentationClipboard.copy("", using: pasteboard))
    #expect(pasteboard.values == [""])

    #expect(PresentationClipboard.copy("Line one\nLine two", using: pasteboard))
    #expect(pasteboard.values == ["", "Line one\nLine two"])

    pasteboard.shouldSucceed = false
    #expect(!PresentationClipboard.copy("Rejected", using: pasteboard))
    #expect(pasteboard.values.last == "Rejected")
  }
}

private final class RecordingPasteboard: PresentationPasteboardWriting {
  var values: [String] = []
  var shouldSucceed = true

  func replaceContents(with value: String) -> Bool {
    values.append(value)
    return shouldSucceed
  }
}
