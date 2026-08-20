import Testing

@testable import QwenPrime

@Suite("UTF-8-safe truncation")
struct UTF8TruncationTests {
  @Test("Empty and non-positive budgets return empty text")
  func emptyAndNonPositiveBudgets() {
    #expect(UTF8Truncation.prefix("", maximumBytes: 0) == "")
    #expect(UTF8Truncation.prefix("", maximumBytes: -1) == "")
    #expect(UTF8Truncation.prefix("content", maximumBytes: 0) == "")
    #expect(UTF8Truncation.prefix("content", maximumBytes: -1) == "")
  }

  @Test("ASCII prefixes respect exact byte boundaries")
  func asciiBoundaries() {
    #expect(UTF8Truncation.prefix("Prime", maximumBytes: 4) == "Prim")
    #expect(UTF8Truncation.prefix("Prime", maximumBytes: 5) == "Prime")
    #expect(UTF8Truncation.prefix("Prime", maximumBytes: 20) == "Prime")
  }

  @Test("Multibyte characters are included only at complete boundaries")
  func multibyteBoundaries() {
    let value = "Aé🙂B"

    #expect(UTF8Truncation.prefix(value, maximumBytes: 1) == "A")
    #expect(UTF8Truncation.prefix(value, maximumBytes: 2) == "A")
    #expect(UTF8Truncation.prefix(value, maximumBytes: 3) == "Aé")
    #expect(UTF8Truncation.prefix(value, maximumBytes: 6) == "Aé")
    #expect(UTF8Truncation.prefix(value, maximumBytes: 7) == "Aé🙂")
    #expect(UTF8Truncation.prefix(value, maximumBytes: 8) == value)
  }
}
