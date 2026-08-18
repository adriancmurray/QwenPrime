import Foundation

public struct WorkspaceInstructionDocument: Sendable, Equatable {
    public let content: String
    public let fileURL: URL

    public init(content: String, fileURL: URL) {
        self.content = content
        self.fileURL = fileURL.standardizedFileURL
    }
}
