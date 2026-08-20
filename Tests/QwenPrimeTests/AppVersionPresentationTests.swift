import Foundation
import Testing

@testable import QwenPrime

@Suite("App version presentation")
struct AppVersionPresentationTests {
  @Test("Short version resolves the bundle value")
  func shortVersionResolvesBundleValue() {
    let version = AppVersionPresentation.shortVersion(
      in: ["CFBundleShortVersionString": "2.4.1"]
    )

    #expect(version == "2.4.1")
  }

  @Test("Missing or empty bundle versions use the development fallback")
  func invalidVersionsUseDevelopmentFallback() {
    #expect(
      AppVersionPresentation.shortVersion(in: nil)
        == "Development"
    )
    #expect(
      AppVersionPresentation.shortVersion(
        in: ["CFBundleShortVersionString": "  "]
      ) == "Development"
    )
  }

  @Test("About description extends the shared short version")
  func aboutDescriptionUsesShortVersion() {
    #expect(
      AppVersionPresentation.aboutDescription
        == "\(AppVersionPresentation.shortVersion) (Apple Silicon Native)"
    )
  }

  @Test("UI and service consumers use the shared version API")
  func consumersUseSharedVersionAPI() throws {
    let sourceRoot = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let quickSettings = try String(
      contentsOf: sourceRoot.appendingPathComponent(
        "Sources/QwenPrime/Views/Chat/QuickSettingsPopover.swift"
      ),
      encoding: .utf8
    )
    let generalSettings = try String(
      contentsOf: sourceRoot.appendingPathComponent(
        "Sources/QwenPrime/Views/Settings/GeneralSettingsTab.swift"
      ),
      encoding: .utf8
    )
    let mcpClient = try String(
      contentsOf: sourceRoot.appendingPathComponent(
        "Sources/QwenPrime/Services/MCPHTTPClient.swift"
      ),
      encoding: .utf8
    )

    #expect(
      quickSettings.contains("AppVersionPresentation.shortVersion")
    )
    #expect(
      generalSettings.contains(
        "AppVersionPresentation.aboutDescription"
      )
    )
    #expect(!quickSettings.contains("CFBundleShortVersionString"))
    #expect(!generalSettings.contains("CFBundleShortVersionString"))
    #expect(mcpClient.contains("AppVersionPresentation.shortVersion"))
    #expect(!mcpClient.contains("CFBundleShortVersionString"))
  }
}
