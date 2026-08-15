import Foundation
import SwiftUI
import AppKit
import Observation

@Observable
@MainActor
public final class AppState {
    public var conversations: [Conversation] = []
    public var selectedConversationId: UUID?
    public var serverStatus: ServerStatus = .connecting
    public var baseURL: String = "http://127.0.0.1:8000/v1"
    public var selectedModel: String = "qwen3.8-27b"
    public var isSettingsPresented: Bool = false
    public var searchText: String = ""
    public var currentThemeType: ThemeType = .primeDark
    public var sandboxDirectory: URL

    private let storage = StorageService.shared
    private let healthService = ServerHealthService.shared
    private var healthCheckTask: Task<Void, Never>?

    public init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultSandbox = home.appendingPathComponent("prime-sandbox", isDirectory: true)
        if !FileManager.default.fileExists(atPath: defaultSandbox.path) {
            try? FileManager.default.createDirectory(at: defaultSandbox, withIntermediateDirectories: true)
        }
        self.sandboxDirectory = defaultSandbox

        Task {
            await loadConversations()
            startHealthCheckLoop()
        }
    }

    public var activeTheme: MarkdownTheme {
        MarkdownTheme.theme(for: currentThemeType)
    }

    public var selectedConversation: Conversation? {
        get {
            guard let id = selectedConversationId else { return nil }
            return conversations.first(where: { $0.id == id })
        }
        set {
            guard let id = selectedConversationId, let newValue = newValue else { return }
            if let index = conversations.firstIndex(where: { $0.id == id }) {
                conversations[index] = newValue
            }
        }
    }

    public var filteredConversations: [Conversation] {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return conversations
        }
        return conversations.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.messages.contains { $0.content.localizedCaseInsensitiveContains(searchText) }
        }
    }

    public func loadConversations() async {
        do {
            let loaded = try await storage.loadAllConversations()
            self.conversations = loaded
            if selectedConversationId == nil {
                if let first = loaded.first {
                    self.selectedConversationId = first.id
                } else {
                    createNewConversation()
                }
            }
        } catch {
            print("[AppState] Error loading conversations: \(error)")
            if conversations.isEmpty {
                createNewConversation()
            }
        }
    }

    @discardableResult
    public func createNewConversation() -> Conversation {
        let newConv = Conversation(
            title: "New Chat",
            modelId: selectedModel
        )
        conversations.insert(newConv, at: 0)
        selectedConversationId = newConv.id
        saveConversation(newConv)
        return newConv
    }

    public func deleteConversation(id: UUID) {
        conversations.removeAll(where: { $0.id == id })
        if selectedConversationId == id {
            selectedConversationId = conversations.first?.id
            if selectedConversationId == nil {
                createNewConversation()
            }
        }
        Task {
            try? await storage.deleteConversation(id: id)
        }
    }

    public func renameConversation(id: UUID, newTitle: String) {
        if let index = conversations.firstIndex(where: { $0.id == id }) {
            conversations[index].title = newTitle
            conversations[index].touch()
            saveConversation(conversations[index])
        }
    }

    public func saveConversation(_ conversation: Conversation) {
        Task {
            try? await storage.saveConversation(conversation)
        }
    }

    public func checkServerHealth() async {
        let status = await healthService.checkHealth(baseURL: baseURL)
        self.serverStatus = status
    }

    public func openSandboxInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: sandboxDirectory.path)
    }

    public func openSandboxInTerminal() {
        let script = "tell application \"Terminal\" to do script \"cd \(sandboxDirectory.path)\""
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
        }
    }

    public func exportConversationAsMarkdown() {
        guard let conv = selectedConversation else { return }
        var md = "# \(conv.title)\n\n"
        md += "_Generated on \(conv.createdAt.formatted(date: .abbreviated, time: .shortened)) via Qwen Prime_\n\n---\n\n"

        for msg in conv.messages {
            let roleHeader = msg.role == .user ? "### 👤 User" : "### 🤖 Qwen Prime"
            md += "\(roleHeader)\n\n"
            if let thinking = msg.thinkingContent, !thinking.isEmpty {
                md += "<details><summary>Thought Process</summary>\n\n\(thinking)\n\n</details>\n\n"
            }
            md += "\(msg.content)\n\n---\n\n"
        }

        let savePanel = NSSavePanel()
        savePanel.title = "Export Conversation as Markdown"
        savePanel.nameFieldStringValue = "\(conv.title.replacingOccurrences(of: "/", with: "-")).md"
        savePanel.allowedContentTypes = [.plainText]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? md.data(using: .utf8)?.write(to: url)
        }
    }

    private func startHealthCheckLoop() {
        healthCheckTask?.cancel()
        healthCheckTask = Task {
            while !Task.isCancelled {
                await checkServerHealth()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}
