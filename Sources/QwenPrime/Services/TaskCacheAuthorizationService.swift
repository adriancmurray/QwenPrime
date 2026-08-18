import Foundation

@MainActor
public final class TaskCacheAuthorizationService {
    private static let defaultsKey = "taskCacheSecurityScopedBookmark"

    private let userDefaults: UserDefaults
    private let bookmarker: any WorkspaceBookmarking
    private let scopeAccessor: any WorkspaceSecurityScopeAccessing
    private var bookmark: Data?
    private var activeURL: URL?
    private var hasActiveScope = false

    public init(
        userDefaults: UserDefaults = .standard,
        bookmarker: any WorkspaceBookmarking = SecurityScopedWorkspaceBookmarker(),
        scopeAccessor: any WorkspaceSecurityScopeAccessing = SystemWorkspaceSecurityScopeAccessor()
    ) {
        self.userDefaults = userDefaults
        self.bookmarker = bookmarker
        self.scopeAccessor = scopeAccessor
        self.bookmark = userDefaults.data(forKey: Self.defaultsKey)
    }

    deinit {
        if hasActiveScope, let activeURL {
            scopeAccessor.stopAccessing(activeURL)
        }
    }

    public var authorizedURL: URL? {
        if let activeURL { return activeURL }
        guard let bookmark else { return nil }
        return try? activate(bookmark)
    }

    @discardableResult
    public func authorize(_ url: URL) throws -> URL {
        let standardizedURL = url.standardizedFileURL
        try Self.validateCacheURL(standardizedURL)
        let newBookmark = try bookmarker.createBookmark(for: standardizedURL)
        if hasActiveScope, let activeURL {
            scopeAccessor.stopAccessing(activeURL)
        }
        activeURL = nil
        hasActiveScope = false

        let resolvedURL = try activate(newBookmark)
        bookmark = newBookmark
        userDefaults.set(newBookmark, forKey: Self.defaultsKey)
        return resolvedURL
    }

    private static func validateCacheURL(_ url: URL) throws {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let homePath = FileManager.default.homeDirectoryForCurrentUser
            .standardizedFileURL.resolvingSymlinksInPath().path
        guard path != "/",
              path != "/Users",
              path != homePath,
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw WorkspaceAccessError.accessDenied(path: path)
        }
    }

    private func activate(_ bookmark: Data) throws -> URL {
        var resolved = try bookmarker.resolveBookmark(bookmark)
        var resolvedURL = resolved.url.standardizedFileURL
        if resolved.isStale {
            let refreshed = try bookmarker.createBookmark(for: resolvedURL)
            self.bookmark = refreshed
            userDefaults.set(refreshed, forKey: Self.defaultsKey)
            resolved = try bookmarker.resolveBookmark(refreshed)
            resolvedURL = resolved.url.standardizedFileURL
        }
        guard scopeAccessor.startAccessing(resolvedURL) else {
            throw WorkspaceAccessError.accessDenied(path: resolvedURL.path)
        }
        activeURL = resolvedURL
        hasActiveScope = true
        return resolvedURL
    }
}
