import Foundation
import Testing

@Suite("Theme color usage gate")
struct ThemeColorUsageGateTests {
    private static let prohibitedRendererColorTokens = [
        "Color.accentColor",
        "Color(nsColor:",
        "Color.black",
        "Color.blue",
        "Color.cyan",
        "Color.gray",
        "Color.green",
        "Color.indigo",
        "Color.orange",
        "Color.pink",
        "Color.purple",
        "Color.red",
        "Color.white",
        "Color.yellow",
        ".tint(.blue)",
        ".tint(.cyan)",
        ".tint(.green)",
        ".tint(.orange)",
        ".tint(.pink)",
        ".tint(.purple)",
        ".tint(.red)",
        ".tint(.yellow)",
    ]

    private static let themeTintTokens = [
        ".tint(appState.activeTheme.h1)",
        ".tint(theme.h1)",
        ".tint(tint)",
    ]

    private var projectRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    @Test("Renderers resolve colors through theme or design tokens")
    func renderersDoNotResolveRawSystemOrPaletteColors() throws {
        let rendererDirectories = [
            projectRoot.appendingPathComponent("Sources/QwenPrime/App"),
            projectRoot.appendingPathComponent("Sources/QwenPrime/Views"),
        ]
        let files = try rendererDirectories.flatMap(swiftFiles(in:))
        var violations: [String] = []

        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for token in Self.prohibitedRendererColorTokens where source.contains(token) {
                violations.append("\(relativePath(for: file)): \(token)")
            }
        }

        #expect(violations.isEmpty)
    }

    @Test("Native controls are enclosed by a theme-tinted renderer")
    func nativeControlsHaveThemeTint() throws {
        let viewsDirectory = projectRoot.appendingPathComponent(
            "Sources/QwenPrime/Views"
        )
        let nativeControlTokens = [
            ".buttonStyle(.bordered)",
            ".buttonStyle(.borderedProminent)",
            ".pickerStyle(.menu)",
            ".textFieldStyle(.roundedBorder)",
        ]
        let files = try swiftFiles(in: viewsDirectory)
        let violations = try files.compactMap { file -> String? in
            let source = try String(contentsOf: file, encoding: .utf8)
            let isSettingsRenderer = file.path.contains("/Views/Settings/")
            let hasNativeControl = nativeControlTokens.contains { source.contains($0) }
            let hasThemeTint = Self.themeTintTokens.contains { source.contains($0) }

            guard hasNativeControl, !isSettingsRenderer, !hasThemeTint else {
                return nil
            }
            return relativePath(for: file)
        }

        let settings = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Sources/QwenPrime/Views/Settings/SettingsView.swift"
            ),
            encoding: .utf8
        )

        #expect(violations.isEmpty)
        #expect(settings.contains(".tint(appState.activeTheme.h1)"))
    }

    @Test("Settings navigation never delegates selection color to native tabs")
    func settingsNavigationRendersTheThemeAccentExplicitly() throws {
        let settings = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Sources/QwenPrime/Views/Settings/SettingsView.swift"
            ),
            encoding: .utf8
        )
        let tabBar = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Sources/QwenPrime/Views/Settings/SettingsTabBar.swift"
            ),
            encoding: .utf8
        )

        #expect(!settings.contains("TabView"))
        #expect(settings.contains("SettingsTabBar("))
        #expect(settings.contains("theme: appState.activeTheme"))
        #expect(tabBar.contains(".foregroundStyle(isSelected ? theme.h1 : .secondary)"))
        #expect(tabBar.contains("tint: theme.h1"))
        #expect(tabBar.contains(".buttonStyle(.plain)"))
    }

    @Test("Themed renderers never use native accent-controlled menus")
    func rendererActionMenusAreThemeOwned() throws {
        let viewsDirectory = projectRoot.appendingPathComponent(
            "Sources/QwenPrime/Views"
        )
        let files = try swiftFiles(in: viewsDirectory)
        let nativeMenuUsers = try files.filter { file in
            let source = try String(contentsOf: file, encoding: .utf8)
            return source.contains("Menu {") || source.contains(".contextMenu")
        }
        let row = try String(
            contentsOf: viewsDirectory.appendingPathComponent(
                "Sidebar/ConversationRow.swift"
            ),
            encoding: .utf8
        )
        let actions = try String(
            contentsOf: viewsDirectory.appendingPathComponent(
                "Sidebar/ConversationRowActions.swift"
            ),
            encoding: .utf8
        )
        let promptInput = try String(
            contentsOf: viewsDirectory.appendingPathComponent(
                "Chat/PromptInputBar.swift"
            ),
            encoding: .utf8
        )
        let messageBubble = try String(
            contentsOf: viewsDirectory.appendingPathComponent(
                "Chat/MessageBubble.swift"
            ),
            encoding: .utf8
        )
        let themedPopoverRow = try String(
            contentsOf: viewsDirectory.appendingPathComponent(
                "Shared/ThemedPopoverActionRow.swift"
            ),
            encoding: .utf8
        )
        let quickSettings = try String(
            contentsOf: viewsDirectory.appendingPathComponent(
                "Chat/QuickSettingsPopover.swift"
            ),
            encoding: .utf8
        )

        #expect(nativeMenuUsers.isEmpty)
        #expect(row.contains(".popover("))
        #expect(row.contains("ConversationActionPopover("))
        #expect(actions.contains("ThemedPopoverActionRow("))
        #expect(promptInput.contains("workspacePickerPopover"))
        #expect(promptInput.contains(".popover("))
        #expect(promptInput.contains("ThemedPopoverActionRow("))
        #expect(
            themedPopoverRow.contains(
                "selectionTint.opacity(DesignTokens.Opacity.hover)"
            )
        )
        #expect(quickSettings.contains("ThemedPopoverActionRow("))
        #expect(quickSettings.contains("ThemedPopoverSectionTitle("))
        #expect(messageBubble.contains("CopyFeedbackButton("))
    }

    @Test("MarkdownTheme owns renderer-facing system surface roles")
    func themeOwnsRendererFacingSystemSurfaceRoles() throws {
        let theme = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Sources/QwenPrime/Models/MarkdownTheme.swift"
            ),
            encoding: .utf8
        )

        #expect(theme.contains("public var windowBackground: Color"))
        #expect(theme.contains("public var controlBackground: Color"))
        #expect(theme.contains("public var selectedControlText: Color"))
    }

    @Test("Product code has no fallback to the system accent color")
    func productCodeDoesNotUseSystemAccentColor() throws {
        let sourceDirectory = projectRoot.appendingPathComponent("Sources/QwenPrime")
        let files = try swiftFiles(in: sourceDirectory)
        let accentUsers = try files.filter { file in
            try String(contentsOf: file, encoding: .utf8)
                .contains("Color.accentColor")
        }

        #expect(accentUsers.isEmpty)
    }

    @Test("Settings controls inherit the active theme tint")
    func settingsControlsUseActiveThemeTint() throws {
        let settings = try String(
            contentsOf: projectRoot.appendingPathComponent(
                "Sources/QwenPrime/Views/Settings/SettingsView.swift"
            ),
            encoding: .utf8
        )

        #expect(settings.contains("selection: $appState.settingsSelection"))
        #expect(settings.contains(".tint(appState.activeTheme.h1)"))
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey]
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )

        return try files.flatMap { file in
            let values = try file.resourceValues(forKeys: keys)
            if values.isRegularFile == true {
                return file.pathExtension == "swift" ? [file] : []
            }
            return try swiftFiles(in: file)
        }
    }

    private func relativePath(for file: URL) -> String {
        file.path.replacingOccurrences(
            of: projectRoot.path + "/",
            with: ""
        )
    }
}
