import AppKit
import Foundation
import SwiftUI
import Testing

@testable import QwenPrime

@Suite("Sidebar Accessibility Contracts")
struct SidebarAccessibilityContractTests {
  @Test("Rendered sidebar exposes search and conversation accessibility")
  @MainActor
  func renderedSidebarAccessibility() throws {
    let suiteName = "QwenPrimeTests-SidebarAX-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    appState.searchText = "query"
    appState.conversations = [Conversation(title: "Accessible conversation")]

    let hostingView = NSHostingView(rootView: SidebarView(appState: appState))
    hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 700)
    let window = NSWindow(
      contentRect: hostingView.frame,
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    window.contentView = hostingView
    hostingView.layoutSubtreeIfNeeded()
    hostingView.displayIfNeeded()

    let labels = accessibilityLabels(in: hostingView)
    let roles = accessibilityRoles(in: hostingView)
    #expect(labels.contains("query"))
    #expect(roles.contains(.textField))
    #expect(roles.contains(.scrollArea))
  }

  @Test("Project scope is typed and follows the active workspace")
  @MainActor
  func typedProjectScopeContract() throws {
    let suiteName = "QwenPrimeTests-ProjectScope-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let appState = AppState(startServices: false, userDefaults: defaults)
    let first = Conversation(projectPath: "/work/first-project")
    let second = Conversation(projectPath: "/work/second-project")
    appState.conversations = [first, second]
    appState.selectedProjectScope = .currentProject

    appState.sandboxDirectory = URL(fileURLWithPath: "/work/first-project")
    #expect(appState.filteredConversations.map(\.id) == [first.id])

    appState.sandboxDirectory = URL(fileURLWithPath: "/work/second-project")
    #expect(appState.filteredConversations.map(\.id) == [second.id])
  }

  @Test("Project scope compares normalized paths instead of folder substrings")
  func projectScopeUsesExactNormalizedPaths() {
    let workspace = URL(fileURLWithPath: "/work/app")

    #expect(
      ProjectScope.all.includes(
        projectPath: nil,
        currentProjectDirectory: workspace
      ))
    #expect(
      ProjectScope.currentProject.includes(
        projectPath: "/work/app",
        currentProjectDirectory: workspace
      ))
    #expect(
      ProjectScope.currentProject.includes(
        projectPath: "/work/temporary/../app",
        currentProjectDirectory: workspace
      ))
    #expect(
      !ProjectScope.currentProject.includes(
        projectPath: "/work/app-v2",
        currentProjectDirectory: workspace
      ))
    #expect(
      !ProjectScope.currentProject.includes(
        projectPath: "/work/apple",
        currentProjectDirectory: workspace
      ))
    #expect(
      !ProjectScope.currentProject.includes(
        projectPath: nil,
        currentProjectDirectory: workspace
      ))
    #expect(
      !ProjectScope.currentProject.includes(
        projectPath: "",
        currentProjectDirectory: workspace
      ))
    #expect(
      !ProjectScope.currentProject.includes(
        projectPath: "   \n",
        currentProjectDirectory: workspace
      ))
  }

  @Test("Project scope presents filesystem names without changing paths")
  func projectScopeDisplayNameIsHumanReadable() {
    let sandbox = URL(fileURLWithPath: "/Users/example/prime-sandbox")
    let workspace = URL(fileURLWithPath: "/Users/example/agent_workspace")

    #expect(ProjectScope.displayName(for: sandbox) == "Prime Sandbox")
    #expect(ProjectScope.displayName(for: workspace) == "Agent Workspace")
  }

  @MainActor
  private func accessibilityLabels(
    in element: any NSAccessibilityProtocol,
    depth: Int = 0
  ) -> Set<String> {
    guard depth < 16 else { return [] }
    var labels: Set<String> = []
    if let label = element.accessibilityLabel(), !label.isEmpty {
      labels.insert(label)
    }
    if let title = element.accessibilityTitle(), !title.isEmpty {
      labels.insert(title)
    }
    if let identifier = element.accessibilityIdentifier(), !identifier.isEmpty {
      labels.insert(identifier)
    }
    if let help = element.accessibilityHelp(), !help.isEmpty {
      labels.insert(help)
    }
    if let value = element.accessibilityValue() as? String, !value.isEmpty {
      labels.insert(value)
    }
    for child in element.accessibilityChildren() ?? [] {
      guard let accessibleChild = child as? any NSAccessibilityProtocol else {
        continue
      }
      labels.formUnion(
        accessibilityLabels(in: accessibleChild, depth: depth + 1)
      )
    }
    if let view = element as? NSView {
      for subview in view.subviews {
        labels.formUnion(
          accessibilityLabels(in: subview, depth: depth + 1)
        )
      }
    }
    return labels
  }

  @MainActor
  private func accessibilityRoles(
    in element: any NSAccessibilityProtocol,
    depth: Int = 0
  ) -> Set<NSAccessibility.Role> {
    guard depth < 16 else { return [] }
    var roles: Set<NSAccessibility.Role> = []
    if let role = element.accessibilityRole() {
      roles.insert(role)
    }
    for child in element.accessibilityChildren() ?? [] {
      guard let accessibleChild = child as? any NSAccessibilityProtocol else {
        continue
      }
      roles.formUnion(
        accessibilityRoles(in: accessibleChild, depth: depth + 1)
      )
    }
    if let view = element as? NSView {
      for subview in view.subviews {
        roles.formUnion(
          accessibilityRoles(in: subview, depth: depth + 1)
        )
      }
    }
    return roles
  }
}
