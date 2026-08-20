import Foundation

/// Redacts local filesystem roots before workspace tool content reaches a consumer.
struct WorkspacePathSanitizer: Sendable {
  private struct Replacement: Sendable {
    let path: String
    let token: String
  }

  private let replacements: [Replacement]

  init(
    workspaceRoot: URL,
    temporaryRoot: URL = FileManager.default.temporaryDirectory
  ) {
    var seenPaths: Set<String> = []
    var replacements: [Replacement] = []

    Self.appendReplacements(
      for: workspaceRoot,
      token: "<workspace_root>",
      seenPaths: &seenPaths,
      replacements: &replacements
    )
    Self.appendReplacements(
      for: temporaryRoot,
      token: "<task_temp>",
      seenPaths: &seenPaths,
      replacements: &replacements
    )

    self.replacements = replacements.sorted { left, right in
      if left.path.count == right.path.count {
        return left.token < right.token
      }
      return left.path.count > right.path.count
    }
  }

  func sanitize(_ text: String) -> String {
    replacements.reduce(text) { result, replacement in
      // macOS volumes commonly preserve path casing while comparing it
      // case-insensitively. Literal, non-localized matching mirrors that
      // behavior without interpreting path characters as patterns.
      Self.replacingPathOccurrences(
        in: result,
        path: replacement.path,
        token: replacement.token
      )
    }
  }

  private static func replacingPathOccurrences(
    in text: String,
    path: String,
    token: String
  ) -> String {
    var sanitized = ""
    var copiedThrough = text.startIndex
    var searchStart = text.startIndex

    while searchStart < text.endIndex,
      let match = text.range(
        of: path,
        options: [.caseInsensitive, .literal],
        range: searchStart..<text.endIndex
      )
    {
      guard isPathBoundary(in: text, after: match.upperBound) else {
        searchStart = text.index(after: match.lowerBound)
        continue
      }

      sanitized.append(contentsOf: text[copiedThrough..<match.lowerBound])
      sanitized.append(contentsOf: token)
      copiedThrough = match.upperBound
      searchStart = match.upperBound
    }

    sanitized.append(contentsOf: text[copiedThrough..<text.endIndex])
    return sanitized
  }

  private static func isPathBoundary(
    in text: String,
    after index: String.Index
  ) -> Bool {
    guard index < text.endIndex else { return true }
    let nextCharacter = text[index]
    if nextCharacter == "/" || nextCharacter.isWhitespace {
      return true
    }
    return "\"'`,;:)]}>|?#".contains(nextCharacter)
  }

  static func pathVariants(for root: URL) -> [String] {
    [
      root.path,
      root.standardizedFileURL.path,
      root.resolvingSymlinksInPath().path,
    ]
  }

  private static func appendReplacements(
    for root: URL,
    token: String,
    seenPaths: inout Set<String>,
    replacements: inout [Replacement]
  ) {
    for path in pathVariants(for: root) where isSensitiveRoot(path) {
      guard seenPaths.insert(path).inserted else { continue }
      replacements.append(Replacement(path: path, token: token))
    }
  }

  /// The filesystem root contains no identifying path information. Replacing it
  /// would instead corrupt every POSIX path and URL in otherwise safe output.
  private static func isSensitiveRoot(_ path: String) -> Bool {
    !path.isEmpty && path != "/"
  }
}
