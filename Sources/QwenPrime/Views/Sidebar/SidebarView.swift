import AppKit
import SwiftUI

public struct SidebarView: View {
  @Bindable public var appState: AppState
  @Environment(\.openSettings) private var openSettings
  @State private var isQuickSettingsPresented: Bool = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(appState: AppState) {
    self.appState = appState
  }

  private var groupedConversations: [(String, [Conversation])] {
    let calendar = Calendar.current
    let now = Date()

    var today: [Conversation] = []
    var yesterday: [Conversation] = []
    var past7Days: [Conversation] = []
    var older: [Conversation] = []

    for conv in appState.filteredConversations {
      if calendar.isDateInToday(conv.updatedAt) {
        today.append(conv)
      } else if calendar.isDateInYesterday(conv.updatedAt) {
        yesterday.append(conv)
      } else if let days = calendar.dateComponents([.day], from: conv.updatedAt, to: now).day,
        days <= 7
      {
        past7Days.append(conv)
      } else {
        older.append(conv)
      }
    }

    var result: [(String, [Conversation])] = []
    if !today.isEmpty { result.append(("Today", today)) }
    if !yesterday.isEmpty { result.append(("Yesterday", yesterday)) }
    if !past7Days.isEmpty { result.append(("Previous 7 Days", past7Days)) }
    if !older.isEmpty { result.append(("Older", older)) }
    return result
  }

  private var themeTint: Color {
    appState.activeTheme.h1
  }

  public var body: some View {
    VStack(spacing: 0) {
      // 1. Search Bar at Top
      HStack(spacing: 6) {
        Image(systemName: "magnifyingglass")
          .font(DesignTokens.TextStyle.caption)
          .foregroundStyle(.secondary)

        TextField("Search", text: $appState.searchText)
          .font(DesignTokens.TextStyle.callout)
          .textFieldStyle(.plain)

        if !appState.searchText.isEmpty {
          Button {
            appState.searchText = ""
          } label: {
            Image(systemName: "xmark.circle.fill")
              .font(DesignTokens.TextStyle.caption)
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Clear search")
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .background(
        DesignTokens.Surface.subtle,
        in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
      )
      .padding(.horizontal, DesignTokens.Layout.sidebarContentInset)
      .padding(.top, 10)
      .padding(.bottom, 6)

      // 2. New Chat Action
      Button {
        appState.createNewConversation()
      } label: {
        HStack(spacing: 7) {
          Image(systemName: "plus")
            .font(DesignTokens.TextStyle.callout.weight(.bold))
          Text("New")
            .font(DesignTokens.TextStyle.callout.weight(.semibold))
          Spacer()
          Text(AppCommands.newConversation.shortcut.displayName)
            .font(
              DesignTokens.TextStyle.caption2Monospaced
                .weight(.medium)
            )
            .foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
          themeTint.opacity(0.16),
          in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: DesignTokens.Radius.md, style: .continuous)
            .stroke(themeTint.opacity(0.22), lineWidth: 0.75)
        )
      }
      .buttonStyle(.plain)
      .appKeyboardShortcut(AppCommands.newConversation)
      .padding(.horizontal, DesignTokens.Layout.sidebarContentInset)
      .padding(.bottom, 8)

      // 3. Project Scope Selector
      HStack(spacing: DesignTokens.Spacing.sm) {
        projectScopeChip(title: "All", scope: .all)
        projectScopeChip(
          title: ProjectScope.displayName(for: appState.sandboxDirectory),
          systemImage: "shippingbox.fill",
          scope: .currentProject
        )
        Spacer(minLength: 0)
      }
      .padding(.horizontal, DesignTokens.Layout.sidebarContentInset)
      .padding(.bottom, 6)

      // 4. Conversation Threads
      ScrollView {
        LazyVStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
        ForEach(groupedConversations, id: \.0) { groupName, convs in
          VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(groupName)
              .font(DesignTokens.TextStyle.caption2.weight(.bold))
              .foregroundStyle(.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)

            LazyVStack(spacing: DesignTokens.Spacing.xs) {
            ForEach(convs) { conversation in
              ConversationRow(
                conversation: conversation,
                isSelected: appState.selectedConversationId == conversation.id,
                isGenerating: appState.isConversationGenerating(conversation.id),
                themeTint: themeTint,
                onRequestDelete: {
                  requestDeletion(of: conversation)
                },
                onRename: { newTitle in
                  appState.renameConversation(id: conversation.id, newTitle: newTitle)
                },
                onDuplicate: {
                  appState.duplicateConversation(id: conversation.id)
                },
                onSelect: {
                  appState.selectedConversationId = conversation.id
                }
              )
            }
          }
          }
        }
        }
        .padding(.horizontal, DesignTokens.Layout.sidebarContentInset)
        .padding(.vertical, DesignTokens.Spacing.xs)
      }
      .accessibilityIdentifier("conversation_list")

      Divider()
        .opacity(0.25)

      // 5. Footer
      HStack(spacing: DesignTokens.Spacing.md) {
        Button {
          isQuickSettingsPresented.toggle()
        } label: {
          Label("Settings", systemImage: "gearshape")
            .font(DesignTokens.TextStyle.caption.weight(.medium))
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(AppCommands.openSettings.helpWithShortcut)
        .accessibilityLabel("Settings and themes")
        .animation(
          reduceMotion ? nil : DesignTokens.AnimationCurve.hover, value: isQuickSettingsPresented
        )
        .popover(isPresented: $isQuickSettingsPresented, arrowEdge: .trailing) {
          QuickSettingsPopover(
            appState: appState,
            onOpenSettings: { tab in
              isQuickSettingsPresented = false
              appState.openSettings(tab: tab)
              openSettings()
            }
          )
        }

        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background(appState.activeTheme.controlBackground.opacity(0.4))
    }
  }

  private func requestDeletion(of conversation: Conversation) {
    appState.requestDeleteConversation(id: conversation.id)
  }

  private func projectScopeChip(
    title: String,
    systemImage: String? = nil,
    scope: ProjectScope
  ) -> some View {
    let isSelected = appState.selectedProjectScope == scope

    return Button {
      appState.selectedProjectScope = scope
    } label: {
      HStack(spacing: DesignTokens.Spacing.sm) {
        if let systemImage {
          Image(systemName: systemImage)
            .font(DesignTokens.TextStyle.caption2)
            .foregroundStyle(themeTint)
        }

        Text(title)
          .font(
            DesignTokens.TextStyle.caption.weight(
              isSelected ? .bold : .medium
            )
          )
          .lineLimit(1)
      }
      .foregroundStyle(isSelected ? .primary : .secondary)
      .padding(.horizontal, DesignTokens.Spacing.md)
      .padding(.vertical, DesignTokens.Spacing.xs)
      .background(
        isSelected ? themeTint.opacity(DesignTokens.Opacity.hover) : .clear,
        in: Capsule()
      )
    }
    .buttonStyle(.plain)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(title)
    .accessibilityValue(isSelected ? "Selected" : "Not selected")
    .accessibilityAddTraits(isSelected ? .isSelected : [])
    .accessibilityHint("Show conversations for \(title)")
  }
}
