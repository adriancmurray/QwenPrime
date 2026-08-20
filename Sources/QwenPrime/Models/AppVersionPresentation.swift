import Foundation

public enum AppVersionPresentation {
  public static var shortVersion: String {
    shortVersion(in: Bundle.main.infoDictionary)
  }

  public static var aboutDescription: String {
    "\(shortVersion) (Apple Silicon Native)"
  }

  static func shortVersion(in infoDictionary: [String: Any]?) -> String {
    guard let version = infoDictionary?["CFBundleShortVersionString"] as? String,
      !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else {
      return "Development"
    }
    return version
  }
}
