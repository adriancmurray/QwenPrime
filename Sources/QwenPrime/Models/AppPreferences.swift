import Foundation
import OSLog

/// User-facing preferences that are shared across every app scene.
public struct AppPreferences: Codable, Equatable, Sendable {
  public static let defaultBaseURL = "http://127.0.0.1:8000/v1"
  public static let defaultModel = "qwen3.8-27b"
  public static let defaultSystemPromptText = """
    You are Qwen Prime, an elite AI systems and software engineering assistant running natively on Apple Silicon with MLX and DFlash speculative acceleration.

    Guidelines:
    1. Provide precise, production-grade implementations with clean explanations.
    2. In Swift code, strictly enforce Swift 6 concurrency safety, actor isolation, and Sendable conformance. Avoid force-unwrapping.
    3. In Rust and Python, follow zero-cost abstractions, idiomatic design, and proper error handling.
    4. When reasoning, use your <think> chain-of-thought to explore edge cases and architectural trade-offs thoroughly before answering.
    """

  public var theme: ThemeType
  public var selectedModel: String
  public var baseURL: String
  public var isAutoScrollEnabled: Bool
  public var isThinkingExpandedByDefault: Bool
  public var defaultThinkingEnabled: Bool
  public var defaultAgentModeEnabled: Bool
  public var defaultSystemPrompt: String
  public var defaultSystemPromptPresetId: UUID?
  public var isAgentPreviewEnabled: Bool
  public var isWorkspaceInstructionsEnabled: Bool

  enum CodingKeys: String, CodingKey, CaseIterable {
    case theme
    case selectedModel
    case baseURL
    case isAutoScrollEnabled
    case isThinkingExpandedByDefault
    case defaultThinkingEnabled
    case defaultAgentModeEnabled
    case defaultSystemPrompt
    case defaultSystemPromptPresetId
    case isAgentPreviewEnabled
    case isWorkspaceInstructionsEnabled
  }

  public init(
    theme: ThemeType = .primeDark,
    selectedModel: String = Self.defaultModel,
    baseURL: String = Self.defaultBaseURL,
    isAutoScrollEnabled: Bool = true,
    isThinkingExpandedByDefault: Bool = false,
    defaultThinkingEnabled: Bool = false,
    defaultAgentModeEnabled: Bool = true,
    defaultSystemPrompt: String = Self.defaultSystemPromptText,
    defaultSystemPromptPresetId: UUID? = nil,
    isAgentPreviewEnabled: Bool = true,
    isWorkspaceInstructionsEnabled: Bool = true
  ) {
    self.theme = theme
    self.selectedModel = selectedModel
    self.baseURL = baseURL
    self.isAutoScrollEnabled = isAutoScrollEnabled
    self.isThinkingExpandedByDefault = isThinkingExpandedByDefault
    self.defaultThinkingEnabled = defaultThinkingEnabled
    self.defaultAgentModeEnabled = defaultAgentModeEnabled
    self.defaultSystemPrompt = defaultSystemPrompt
    self.defaultSystemPromptPresetId = defaultSystemPromptPresetId
    self.isAgentPreviewEnabled = isAgentPreviewEnabled
    self.isWorkspaceInstructionsEnabled = isWorkspaceInstructionsEnabled
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let rawTheme = try values.decodeIfPresent(String.self, forKey: .theme)
    self.init(
      theme: rawTheme.flatMap(ThemeType.init(rawValue:)) ?? .primeDark,
      selectedModel: try values.decodeIfPresent(
        String.self,
        forKey: .selectedModel
      ) ?? Self.defaultModel,
      baseURL: try values.decodeIfPresent(String.self, forKey: .baseURL)
        ?? Self.defaultBaseURL,
      isAutoScrollEnabled: try values.decodeIfPresent(
        Bool.self,
        forKey: .isAutoScrollEnabled
      ) ?? true,
      isThinkingExpandedByDefault: try values.decodeIfPresent(
        Bool.self,
        forKey: .isThinkingExpandedByDefault
      ) ?? false,
      defaultThinkingEnabled: try values.decodeIfPresent(
        Bool.self,
        forKey: .defaultThinkingEnabled
      ) ?? false,
      defaultAgentModeEnabled: try values.decodeIfPresent(
        Bool.self,
        forKey: .defaultAgentModeEnabled
      ) ?? true,
      defaultSystemPrompt: try values.decodeIfPresent(
        String.self,
        forKey: .defaultSystemPrompt
      ) ?? Self.defaultSystemPromptText,
      defaultSystemPromptPresetId: try values.decodeIfPresent(
        UUID.self,
        forKey: .defaultSystemPromptPresetId
      ),
      isAgentPreviewEnabled: try values.decodeIfPresent(
        Bool.self,
        forKey: .isAgentPreviewEnabled
      ) ?? true,
      isWorkspaceInstructionsEnabled: try values.decodeIfPresent(
        Bool.self,
        forKey: .isWorkspaceInstructionsEnabled
      ) ?? true
    )
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(theme, forKey: .theme)
    try values.encode(selectedModel, forKey: .selectedModel)
    try values.encode(baseURL, forKey: .baseURL)
    try values.encode(isAutoScrollEnabled, forKey: .isAutoScrollEnabled)
    try values.encode(
      isThinkingExpandedByDefault,
      forKey: .isThinkingExpandedByDefault
    )
    try values.encode(defaultThinkingEnabled, forKey: .defaultThinkingEnabled)
    try values.encode(defaultAgentModeEnabled, forKey: .defaultAgentModeEnabled)
    try values.encode(defaultSystemPrompt, forKey: .defaultSystemPrompt)
    try values.encode(
      defaultSystemPromptPresetId,
      forKey: .defaultSystemPromptPresetId
    )
    try values.encode(isAgentPreviewEnabled, forKey: .isAgentPreviewEnabled)
    try values.encode(
      isWorkspaceInstructionsEnabled,
      forKey: .isWorkspaceInstructionsEnabled
    )
  }
}

@MainActor
public enum AppPreferencesPersistence {
  private static let preferencesKey = "appPreferences.v1"
  private static let legacyAutoScrollKey = "autoScroll"
  private static let legacyThinkingExpandedKey = "expandThinkingByDefault"
  private static let logger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "QwenPrime",
    category: "Preferences"
  )

  public static func load(from userDefaults: UserDefaults) -> AppPreferences {
    if let data = userDefaults.data(forKey: preferencesKey) {
      do {
        var preferences = try JSONDecoder().decode(
          AppPreferences.self,
          from: data
        )
        let storedKeys = jsonKeys(in: data)
        migrateLegacyValues(
          into: &preferences,
          from: userDefaults,
          missingStoredKeys: allStoredKeys.subtracting(storedKeys)
        )
        if !allStoredKeys.isSubset(of: storedKeys) {
          save(preferences, to: userDefaults)
        }
        return preferences
      } catch {
        let failure = failureDescription(for: error)
        logger.error(
          "Decode failed; repaired preferences. \(failure, privacy: .public)"
        )
      }
    }

    var preferences = AppPreferences()
    migrateLegacyValues(
      into: &preferences,
      from: userDefaults,
      missingStoredKeys: allStoredKeys
    )
    save(preferences, to: userDefaults)
    return preferences
  }

  public static func save(
    _ preferences: AppPreferences,
    to userDefaults: UserDefaults
  ) {
    do {
      let data = try JSONEncoder().encode(preferences)
      userDefaults.set(data, forKey: preferencesKey)
    } catch {
      let failure = failureDescription(for: error)
      logger.error(
        "Preference encode failed. \(failure, privacy: .public)"
      )
    }
  }

  /// Reports the failure category and coding path without preference values.
  static func failureDescription(for error: Error) -> String {
    switch error {
    case DecodingError.typeMismatch(_, let context):
      return "typeMismatch at \(codingPathDescription(context.codingPath))"
    case DecodingError.valueNotFound(_, let context):
      return "valueNotFound at \(codingPathDescription(context.codingPath))"
    case DecodingError.keyNotFound(let key, let context):
      let path = context.codingPath + [key]
      return "keyNotFound at \(codingPathDescription(path))"
    case DecodingError.dataCorrupted(let context):
      return "dataCorrupted at \(codingPathDescription(context.codingPath))"
    case EncodingError.invalidValue(_, let context):
      return "invalidValue at \(codingPathDescription(context.codingPath))"
    default:
      return String(reflecting: type(of: error))
    }
  }

  private static var allStoredKeys: Set<AppPreferences.CodingKeys> {
    Set(AppPreferences.CodingKeys.allCases)
  }

  private static func jsonKeys(
    in data: Data
  ) -> Set<AppPreferences.CodingKeys> {
    guard let object = try? JSONSerialization.jsonObject(with: data),
      let dictionary = object as? [String: Any]
    else {
      return []
    }
    return Set(
      dictionary.keys.compactMap(AppPreferences.CodingKeys.init(rawValue:))
    )
  }

  private static func codingPathDescription(
    _ codingPath: [any CodingKey]
  ) -> String {
    guard !codingPath.isEmpty else { return "<root>" }
    return codingPath.map(\.stringValue).joined(separator: ".")
  }

  private static func migrateLegacyValues(
    into preferences: inout AppPreferences,
    from userDefaults: UserDefaults,
    missingStoredKeys: Set<AppPreferences.CodingKeys>
  ) {
    if missingStoredKeys.contains(.isAutoScrollEnabled),
      let value = userDefaults.object(forKey: legacyAutoScrollKey) as? Bool
    {
      preferences.isAutoScrollEnabled = value
    }
    if missingStoredKeys.contains(
      .isThinkingExpandedByDefault
    ), let value = userDefaults.object(forKey: legacyThinkingExpandedKey) as? Bool {
      preferences.isThinkingExpandedByDefault = value
    }
    migrateLegacyPreference(
      key: .defaultThinkingEnabled,
      missingStoredKeys: missingStoredKeys,
      userDefaults: userDefaults,
      assign: { preferences.defaultThinkingEnabled = $0 }
    )
    migrateLegacyPreference(
      key: .defaultAgentModeEnabled,
      missingStoredKeys: missingStoredKeys,
      userDefaults: userDefaults,
      assign: { preferences.defaultAgentModeEnabled = $0 }
    )
    if missingStoredKeys.contains(.defaultSystemPrompt),
      let value = userDefaults.string(
        forKey: AppPreferences.CodingKeys.defaultSystemPrompt.rawValue
      )
    {
      preferences.defaultSystemPrompt = value
    }
    migrateLegacyPreference(
      key: .isAgentPreviewEnabled,
      missingStoredKeys: missingStoredKeys,
      userDefaults: userDefaults,
      assign: { preferences.isAgentPreviewEnabled = $0 }
    )
    migrateLegacyPreference(
      key: .isWorkspaceInstructionsEnabled,
      missingStoredKeys: missingStoredKeys,
      userDefaults: userDefaults,
      assign: { preferences.isWorkspaceInstructionsEnabled = $0 }
    )
  }

  private static func migrateLegacyPreference(
    key: AppPreferences.CodingKeys,
    missingStoredKeys: Set<AppPreferences.CodingKeys>,
    userDefaults: UserDefaults,
    assign: (Bool) -> Void
  ) {
    guard missingStoredKeys.contains(key),
      let value = userDefaults.object(forKey: key.rawValue) as? Bool
    else {
      return
    }
    assign(value)
  }
}
