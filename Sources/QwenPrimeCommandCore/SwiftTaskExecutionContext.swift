import Foundation

public struct SwiftTaskExecutionContext: Sendable {
    public let rootURL: URL
    public let scratchURL: URL
    public let homeURL: URL
    public let moduleCacheURL: URL
    public let profileDataURL: URL
    private let allowedRootURL: URL

    public static func create(
        id: UUID,
        temporaryRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("QwenPrimeCommandTasks", isDirectory: true)
    ) throws -> SwiftTaskExecutionContext {
        let rootURL = temporaryRoot
            .appendingPathComponent(id.uuidString, isDirectory: true)
            .standardizedFileURL
        let scratchURL = rootURL.appendingPathComponent("scratch", isDirectory: true)
        let homeURL = rootURL.appendingPathComponent("home", isDirectory: true)
        let moduleCacheURL = rootURL.appendingPathComponent("module-cache", isDirectory: true)
        let profileDataURL = rootURL.appendingPathComponent("profiles", isDirectory: true)
        let cacheURL = rootURL.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(
            at: scratchURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: homeURL,
            withIntermediateDirectories: true
        )
        for directory in [moduleCacheURL, profileDataURL, cacheURL] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
        return SwiftTaskExecutionContext(
            rootURL: rootURL,
            scratchURL: scratchURL,
            homeURL: homeURL,
            moduleCacheURL: moduleCacheURL,
            profileDataURL: profileDataURL,
            allowedRootURL: temporaryRoot.standardizedFileURL.resolvingSymlinksInPath()
        )
    }

    public func environment(base: [String: String]) -> [String: String] {
        var result = base
        result["HOME"] = homeURL.path
        result["CFFIXED_USER_HOME"] = homeURL.path
        result["TMPDIR"] = rootURL.path
        result["SWIFTPM_MODULECACHE_OVERRIDE"] = moduleCacheURL.path
        result["SWIFTPM_TESTS_MODULECACHE"] = moduleCacheURL.path
        result["CLANG_MODULE_CACHE_PATH"] = moduleCacheURL.path
        result["XDG_CACHE_HOME"] = rootURL.appendingPathComponent("cache").path
        result["LLVM_PROFILE_FILE"] = profileDataURL
            .appendingPathComponent("%p.profraw").path
        return result
    }

    public func remove() throws {
        let temporaryRootPath = allowedRootURL.path
        let resolvedRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        guard resolvedRootURL.path.hasPrefix(temporaryRootPath + "/") else {
            throw CommandPolicyError.pathEscape(resolvedRootURL.path)
        }
        if FileManager.default.fileExists(atPath: resolvedRootURL.path) {
            try FileManager.default.removeItem(at: resolvedRootURL)
        }
    }
}
