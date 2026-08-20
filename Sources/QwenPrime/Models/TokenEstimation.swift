import Foundation

/// Shared approximate token counts for UI telemetry and tool-schema budgets.
public enum TokenEstimation {
  private static let unitsPerToken = 4

  public static func characterBasedCount(for text: String) -> Int {
    characterBasedCount(unitCount: text.count)
  }

  public static func utf8BasedCount(for text: String) -> Int {
    guard !text.isEmpty else { return 0 }
    return minimumOneFloorCount(unitCount: text.utf8.count)
  }

  public static func utf8BudgetCount(for text: String) -> Int {
    let unitCount = text.utf8.count
    guard unitCount > 0 else { return 0 }
    return roundedUpCount(unitCount: unitCount)
  }

  private static func minimumOneFloorCount(unitCount: Int) -> Int {
    return max(1, unitCount / unitsPerToken)
  }

  static func characterBasedCount(unitCount: Int) -> Int {
    guard unitCount > 0 else { return 0 }
    return roundedUpCount(unitCount: unitCount)
  }

  private static func roundedUpCount(unitCount: Int) -> Int {
    let quotient = unitCount / unitsPerToken
    let remainder = unitCount % unitsPerToken
    return quotient + (remainder == 0 ? 0 : 1)
  }
}

/// Incremental completion estimate based on all non-empty streamed text units.
struct StreamingTokenEstimator: Sendable {
  static let maximumRetainedBoundaryUTF8Count = 128

  private var finalizedCharacterCount = 0
  private var trailingBoundary = ""

  var estimatedTokenCount: Int {
    TokenEstimation.characterBasedCount(
      unitCount: finalizedCharacterCount + (trailingBoundary.isEmpty ? 0 : 1)
    )
  }

  /// The only response text retained is the final boundary-sensitive grapheme.
  var retainedBoundaryUTF8CountForTesting: Int {
    trailingBoundary.utf8.count
  }

  @discardableResult
  mutating func append(_ delta: String) -> Bool {
    guard !delta.isEmpty else { return false }

    if delta.unicodeScalars.allSatisfy({ $0.properties.isGraphemeExtend }) {
      trailingBoundary = Self.compactExtensions(
        delta,
        onto: trailingBoundary
      )
      return true
    }

    var boundaryInput = trailingBoundary
    boundaryInput.append(contentsOf: delta)

    var lastCharacter: Character?
    var newlyFinalizedCount = 0
    for character in boundaryInput {
      if lastCharacter != nil {
        newlyFinalizedCount += 1
      }
      lastCharacter = character
    }

    finalizedCharacterCount += newlyFinalizedCount
    trailingBoundary = lastCharacter.map(Self.compactBoundary) ?? ""
    return true
  }

  /// Retains only the state that can affect the next grapheme boundary.
  private static func compactBoundary(_ character: Character) -> String {
    let boundary = String(character)
    guard boundary.utf8.count > maximumRetainedBoundaryUTF8Count else {
      return boundary
    }

    var previousNonExtension: Unicode.Scalar?
    var lastNonExtension: Unicode.Scalar?
    var trailingVirama: Unicode.Scalar?
    var trailingExtension: Unicode.Scalar?

    for scalar in boundary.unicodeScalars {
      if scalar.properties.isGraphemeExtend {
        trailingExtension = scalar
        if scalar.properties.canonicalCombiningClass == .virama {
          trailingVirama = scalar
        }
      } else {
        previousNonExtension = lastNonExtension
        lastNonExtension = scalar
        trailingVirama = nil
        trailingExtension = nil
      }
    }

    var summary: [Unicode.Scalar] = []
    if lastNonExtension?.value == 0x200D,
      let previousNonExtension
    {
      summary.append(previousNonExtension)
    }
    if let lastNonExtension {
      summary.append(lastNonExtension)
    }
    Self.appendExtensionSummary(
      virama: trailingVirama,
      lastExtension: trailingExtension,
      to: &summary
    )
    return singleGraphemeSummary(from: summary)
  }

  private static func compactExtensions(
    _ extensions: String,
    onto boundary: String
  ) -> String {
    var boundaryScalars = Array(boundary.unicodeScalars)
    var retainedVirama: Unicode.Scalar?
    while let scalar = boundaryScalars.last,
      scalar.properties.isGraphemeExtend
    {
      if retainedVirama == nil,
        scalar.properties.canonicalCombiningClass == .virama
      {
        retainedVirama = scalar
      }
      boundaryScalars.removeLast()
    }

    var lastExtension: Unicode.Scalar?
    for scalar in extensions.unicodeScalars {
      lastExtension = scalar
      if scalar.properties.canonicalCombiningClass == .virama {
        retainedVirama = scalar
      }
    }
    Self.appendExtensionSummary(
      virama: retainedVirama,
      lastExtension: lastExtension,
      to: &boundaryScalars
    )
    return singleGraphemeSummary(from: boundaryScalars)
  }

  private static func appendExtensionSummary(
    virama: Unicode.Scalar?,
    lastExtension: Unicode.Scalar?,
    to scalars: inout [Unicode.Scalar]
  ) {
    if let virama {
      scalars.append(virama)
    }
    if let lastExtension, lastExtension != virama {
      scalars.append(lastExtension)
    }
  }

  private static func singleGraphemeSummary(
    from scalars: [Unicode.Scalar]
  ) -> String {
    var summary = ""
    for scalar in scalars {
      summary.unicodeScalars.append(scalar)
    }
    guard summary.count == 1 else {
      return scalars.last.map(String.init) ?? ""
    }
    return summary
  }
}
