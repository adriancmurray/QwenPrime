import Foundation

/// Locale-aware formatting for compact chat and tool presentation values.
public enum PresentationFormatting {
  public enum CountUnit: Sendable, Equatable {
    case token
    case tool
    case step
    case character
    case promptAndToolSchemaToken
  }

  public static func estimatedTokenCount(for text: String) -> Int {
    TokenEstimation.characterBasedCount(for: text)
  }

  public static func count(
    _ value: Int,
    unit: CountUnit,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    switch unit {
    case .token:
      localizedCount(
        LocalizedStringResource(
          "^[\(value) token](inflect: true)",
          locale: locale,
          bundle: .module
        )
      )
    case .tool:
      localizedCount(
        LocalizedStringResource(
          "^[\(value) tool](inflect: true)",
          locale: locale,
          bundle: .module
        )
      )
    case .step:
      localizedCount(
        LocalizedStringResource(
          "^[\(value) step](inflect: true)",
          locale: locale,
          bundle: .module
        )
      )
    case .character:
      localizedCount(
        LocalizedStringResource(
          "^[\(value) character](inflect: true)",
          locale: locale,
          bundle: .module
        )
      )
    case .promptAndToolSchemaToken:
      localizedCount(
        LocalizedStringResource(
          "^[\(value) prompt and tool-schema token](inflect: true)",
          locale: locale,
          bundle: .module
        )
      )
    }
  }

  public static func approximateCount(
    _ value: Int,
    unit: CountUnit,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    "~\(count(value, unit: unit, locale: locale))"
  }

  public static func duration(
    _ seconds: Double,
    fractionDigits: Int = 1,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    guard seconds.isFinite else { return "—" }
    let value = max(0, seconds)
    return "\(decimal(value, fractionDigits: fractionDigits, locale: locale)) s"
  }

  public static func percentage(
    _ ratio: Double,
    fractionDigits: Int = 0,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    guard ratio.isFinite else { return "—" }
    let digits = normalizedFractionDigits(fractionDigits)
    return ratio.formatted(
      .percent
        .precision(.fractionLength(digits))
        .locale(locale)
    )
  }

  public static func throughput(
    _ tokensPerSecond: Double,
    isEstimated: Bool,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    guard tokensPerSecond.isFinite else { return "—" }
    let value = decimal(
      max(0, tokensPerSecond),
      fractionDigits: 1,
      locale: locale
    )
    return "\(value) \(isEstimated ? "est. tok/s" : "tok/s")"
  }

  public static func decimal(
    _ value: Double,
    fractionDigits: Int,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    guard value.isFinite else { return "—" }
    let digits = normalizedFractionDigits(fractionDigits)
    return value.formatted(
      .number
        .precision(.fractionLength(digits))
        .locale(locale)
    )
  }

  public static func integer(
    _ value: Int,
    locale: Locale = .autoupdatingCurrent
  ) -> String {
    value.formatted(.number.locale(locale))
  }

  private static func normalizedFractionDigits(_ value: Int) -> Int {
    min(max(value, 0), 6)
  }

  /// SwiftPM copies string catalogs as resources instead of compiling them.
  /// Grammatical inflection preserves the source-language fallback while
  /// `String(localized:)` uses catalog plural variations in app builds.
  private static func localizedCount(
    _ resource: LocalizedStringResource
  ) -> String {
    let localized = String(localized: resource)
    guard localized.hasPrefix("^["),
      localized.hasSuffix("](inflect: true)")
    else {
      return localized
    }
    let inflected = AttributedString(localized: resource)
    return String(inflected.characters)
  }
}
