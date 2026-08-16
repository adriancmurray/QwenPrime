import Foundation

public actor StorageService {
    public static let shared = StorageService()

    private let fileManager = FileManager.default
    private let directoryURL: URL

    public init(directoryURL: URL? = nil) {
        let manager = FileManager.default
        let appSupport = manager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? manager.temporaryDirectory
        let defaultDirectory = appSupport
            .appendingPathComponent("QwenPrime", isDirectory: true)
            .appendingPathComponent("conversations", isDirectory: true)
        self.directoryURL = directoryURL ?? defaultDirectory

        try? manager.createDirectory(
            at: self.directoryURL,
            withIntermediateDirectories: true
        )
    }

    public func loadAllConversations() throws -> [Conversation] {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var conversations: [Conversation] = []
        for fileURL in fileURLs where fileURL.pathExtension == "json" {
            do {
                let data = try Data(contentsOf: fileURL)
                let conv = try decoder.decode(Conversation.self, from: data)
                conversations.append(conv)
            } catch {
                print("[StorageService] Failed to decode conversation at \(fileURL.lastPathComponent): \(error)")
            }
        }

        return conversations.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func saveConversation(_ conversation: Conversation) throws {
        let fileURL = directoryURL.appendingPathComponent("\(conversation.id.uuidString).json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(conversation)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func deleteConversation(id: UUID) throws {
        let fileURL = directoryURL.appendingPathComponent("\(id.uuidString).json")
        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    public func deleteAllConversations() throws {
        let fileURLs = try fileManager.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)
        for url in fileURLs where url.pathExtension == "json" {
            try? fileManager.removeItem(at: url)
        }
    }
}
