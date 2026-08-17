import Foundation

public struct ResolvedWorkspaceBookmark: Sendable, Equatable {
    public let url: URL
    public let isStale: Bool

    public init(url: URL, isStale: Bool) {
        self.url = url
        self.isStale = isStale
    }
}

public protocol WorkspaceBookmarking: Sendable {
    func createBookmark(for url: URL) throws -> Data
    func resolveBookmark(_ data: Data) throws -> ResolvedWorkspaceBookmark
}

public protocol WorkspaceSecurityScopeAccessing: Sendable {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

public struct SystemWorkspaceSecurityScopeAccessor: WorkspaceSecurityScopeAccessing {
    public init() {}

    public func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    public func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

public struct SecurityScopedWorkspaceBookmarker: WorkspaceBookmarking {
    public init() {}

    public func createBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    public func resolveBookmark(_ data: Data) throws -> ResolvedWorkspaceBookmark {
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return ResolvedWorkspaceBookmark(url: url, isStale: isStale)
    }
}

@MainActor
public final class WorkspaceAuthorizationService {
    private static let defaultsKey = "workspaceSecurityScopedBookmarks"

    private let userDefaults: UserDefaults
    private let bookmarker: any WorkspaceBookmarking
    private let scopeAccessor: any WorkspaceSecurityScopeAccessing
    private var bookmarks: [String: Data]
    private var activeURLs: [String: URL] = [:]
    private var activeSecurityScopes: Set<String> = []

    public init(
        userDefaults: UserDefaults = .standard,
        bookmarker: any WorkspaceBookmarking = SecurityScopedWorkspaceBookmarker(),
        scopeAccessor: any WorkspaceSecurityScopeAccessing = SystemWorkspaceSecurityScopeAccessor()
    ) {
        self.userDefaults = userDefaults
        self.bookmarker = bookmarker
        self.scopeAccessor = scopeAccessor
        if let data = userDefaults.data(forKey: Self.defaultsKey),
           let decoded = try? PropertyListDecoder().decode([String: Data].self, from: data) {
            self.bookmarks = decoded
        } else {
            self.bookmarks = [:]
        }
    }

    deinit {
        for path in activeSecurityScopes {
            if let url = activeURLs[path] {
                scopeAccessor.stopAccessing(url)
            }
        }
    }

    public var authorizedURLs: [URL] {
        bookmarks.keys.sorted().map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    @discardableResult
    public func authorize(_ url: URL) throws -> URL {
        let standardizedURL = url.standardizedFileURL
        let bookmark = try bookmarker.createBookmark(for: standardizedURL)
        bookmarks[standardizedURL.path] = bookmark
        persist()
        do {
            return try activate(bookmark: bookmark, expectedPath: standardizedURL.path)
        } catch {
            bookmarks.removeValue(forKey: standardizedURL.path)
            persist()
            throw error
        }
    }

    public func isAuthorized(path: String) -> Bool {
        resolveAuthorizedURL(path: path) != nil
    }

    public func resolveAuthorizedURL(path: String) -> URL? {
        let standardizedPath = URL(fileURLWithPath: path, isDirectory: true)
            .standardizedFileURL.path
        if let active = activeURLs[standardizedPath] {
            return active
        }
        guard let bookmark = bookmarks[standardizedPath] else { return nil }
        return try? activate(bookmark: bookmark, expectedPath: standardizedPath)
    }

    private func activate(bookmark: Data, expectedPath: String) throws -> URL {
        if let active = activeURLs[expectedPath] {
            return active
        }
        var resolved = try bookmarker.resolveBookmark(bookmark)
        let resolvedURL = resolved.url.standardizedFileURL
        guard resolvedURL.path == expectedPath else {
            throw WorkspaceAccessError.accessDenied(path: expectedPath)
        }

        if resolved.isStale {
            let refreshed = try bookmarker.createBookmark(for: resolvedURL)
            bookmarks[expectedPath] = refreshed
            persist()
            resolved = try bookmarker.resolveBookmark(refreshed)
        }

        let finalURL = resolved.url.standardizedFileURL
        guard finalURL.path == expectedPath else {
            throw WorkspaceAccessError.accessDenied(path: expectedPath)
        }
        guard scopeAccessor.startAccessing(finalURL) else {
            throw WorkspaceAccessError.accessDenied(path: expectedPath)
        }
        activeSecurityScopes.insert(expectedPath)
        activeURLs[expectedPath] = finalURL
        return finalURL
    }

    private func persist() {
        guard let data = try? PropertyListEncoder().encode(bookmarks) else { return }
        userDefaults.set(data, forKey: Self.defaultsKey)
    }
}
