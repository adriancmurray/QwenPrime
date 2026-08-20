import Foundation

public enum ProjectScope: String, CaseIterable, Codable, Hashable, Sendable {
  case all
  case currentProject

  /// Presents a filesystem folder as a compact, human-readable workspace name
  /// without changing the underlying path used for filtering.
  public static func displayName(for directory: URL) -> String {
    let folderName = directory.lastPathComponent
    let words = folderName.split(whereSeparator: { $0 == "-" || $0 == "_" })
    guard !words.isEmpty else { return folderName }
    return words.map { String($0).capitalized }.joined(separator: " ")
  }

  /// Match normalized folder paths so similarly named projects never leak
  /// into the current workspace scope.
  public func includes(
    projectPath: String?,
    currentProjectDirectory: URL
  ) -> Bool {
    switch self {
    case .all:
      return true
    case .currentProject:
      guard let projectPath,
        !projectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        return false
      }
      let normalizedProjectPath = URL(fileURLWithPath: projectPath)
        .standardizedFileURL
        .resolvingSymlinksInPath()
        .standardizedFileURL.path
      let currentProjectPath = currentProjectDirectory
        .standardizedFileURL
        .resolvingSymlinksInPath()
        .standardizedFileURL.path
      return normalizedProjectPath.caseInsensitiveCompare(currentProjectPath)
        == .orderedSame
    }
  }
}
