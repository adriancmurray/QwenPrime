import Foundation
import SwiftUI

public enum MarkdownBlock: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case codeBlock(language: String, code: String)
    case blockquote(text: String)
    case bulletList(items: [String])
    case numberedList(items: [String])
    case divider
    case table(headers: [String], rows: [[String]])

}

public actor MarkdownDocumentCache {
    public static let shared = MarkdownDocumentCache()

    private static let maximumDocumentCount = 24
    private var blocksByMarkdown: [String: [MarkdownBlock]] = [:]
    private var recency: [String] = []

    var cachedDocumentCount: Int {
        blocksByMarkdown.count
    }

    func containsCachedDocument(_ markdown: String) -> Bool {
        blocksByMarkdown[markdown] != nil
    }

    public func blocks(for markdown: String) -> [MarkdownBlock]? {
        guard !Task.isCancelled else { return nil }
        if let cached = blocksByMarkdown[markdown] {
            markRecentlyUsed(markdown)
            return cached
        }

        let blocks = MarkdownParser.parse(markdown: markdown)
        guard !Task.isCancelled else { return nil }
        blocksByMarkdown[markdown] = blocks
        markRecentlyUsed(markdown)
        evictOldDocumentsIfNeeded()
        return blocks
    }

    private func markRecentlyUsed(_ markdown: String) {
        recency.removeAll(where: { $0 == markdown })
        recency.append(markdown)
    }

    private func evictOldDocumentsIfNeeded() {
        guard recency.count > Self.maximumDocumentCount else { return }
        let staleKeys = recency.prefix(recency.count - Self.maximumDocumentCount)
        for key in staleKeys {
            blocksByMarkdown.removeValue(forKey: key)
        }
        recency.removeFirst(recency.count - Self.maximumDocumentCount)
    }
}

enum MarkdownInlineFormatting {
    static func attributedString(for text: String) -> AttributedString {
        (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }
}

struct MarkdownRenderState: Equatable {
    enum PlainTextFallbackKind: Equatable {
        case fullContent
        case appendedSuffix
    }

    static let blockSpacing: CGFloat = 10

    let shouldRenderParsedBlocks: Bool
    let plainTextFallback: String?
    let plainTextFallbackKind: PlainTextFallbackKind?

    var topLevelSpacing: CGFloat {
        plainTextFallbackKind == .appendedSuffix ? 0 : Self.blockSpacing
    }

    init(
        content: String,
        parsedContent: String,
        isStreaming: Bool = false
    ) {
        guard !content.isEmpty else {
            shouldRenderParsedBlocks = false
            plainTextFallback = nil
            plainTextFallbackKind = nil
            return
        }

        if isStreaming {
            shouldRenderParsedBlocks = true
            plainTextFallback = nil
            plainTextFallbackKind = nil
            return
        }

        guard !parsedContent.isEmpty, content.hasPrefix(parsedContent) else {
            shouldRenderParsedBlocks = false
            plainTextFallback = content
            plainTextFallbackKind = .fullContent
            return
        }

        shouldRenderParsedBlocks = true
        let suffix = content.dropFirst(parsedContent.count)
        plainTextFallback = suffix.isEmpty ? nil : String(suffix)
        plainTextFallbackKind = suffix.isEmpty ? nil : .appendedSuffix
    }
}

private struct MarkdownRenderTaskID: Hashable {
    let content: String
    let isStreaming: Bool
}

enum MarkdownAccessibility {
    static func tableRowLabel(
        rowNumber: Int,
        headers: [String],
        cells: [String]
    ) -> String {
        let columnCount = max(headers.count, cells.count)
        guard columnCount > 0 else {
            return String(
                localized: "Row \(rowNumber)",
                comment: "VoiceOver summary for an empty Markdown table row."
            )
        }

        let values = (0..<columnCount).map { index in
            let header = accessibleHeader(at: index, headers: headers)
            let cell = accessibleCell(at: index, cells: cells)
            return String(
                localized: "\(header): \(cell)",
                comment: "VoiceOver summary for one Markdown table cell."
            )
        }
        return String(
            localized: "Row \(rowNumber), \(values.joined(separator: ", "))",
            comment: "VoiceOver summary for a Markdown table row."
        )
    }

    private static func accessibleHeader(
        at index: Int,
        headers: [String]
    ) -> String {
        if headers.indices.contains(index) {
            let header = headers[index].trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            if !header.isEmpty {
                return header
            }
        }
        return String(
            localized: "Column \(index + 1)",
            comment: "Fallback name for an unlabeled Markdown table column."
        )
    }

    private static func accessibleCell(
        at index: Int,
        cells: [String]
    ) -> String {
        guard cells.indices.contains(index) else {
            return emptyCellLabel
        }
        let cell = cells[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return cell.isEmpty ? emptyCellLabel : cell
    }

    private static var emptyCellLabel: String {
        String(
            localized: "Empty",
            comment: "VoiceOver value for an empty or missing Markdown table cell."
        )
    }
}

enum MarkdownTableParsing {
    static func cells(in line: String) -> [String] {
        let trimmedLine = line.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        var cells = trimmedLine.split(
            separator: "|",
            omittingEmptySubsequences: false
        ).map { cell in
            cell.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if trimmedLine.hasPrefix("|") {
            cells.removeFirst()
        }
        if trimmedLine.hasSuffix("|") {
            cells.removeLast()
        }
        return cells
    }
}

enum MarkdownTablePresentation {
    static func cells(headers: [String], row: [String]) -> [String] {
        guard row.count < headers.count else { return row }
        return row + Array(
            repeating: "",
            count: headers.count - row.count
        )
    }
}

public struct MarkdownParser {
    public static func parse(markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = markdown.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let rawLine = lines[i]
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // 1. Code Block
            if line.hasPrefix("```") {
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count && !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: lang, code: codeLines.joined(separator: "\n")))
                i += 1
                continue
            }

            // 2. Headings
            if line.hasPrefix("# ") {
                blocks.append(.heading(level: 1, text: String(line.dropFirst(2))))
                i += 1
                continue
            } else if line.hasPrefix("## ") {
                blocks.append(.heading(level: 2, text: String(line.dropFirst(3))))
                i += 1
                continue
            } else if line.hasPrefix("### ") {
                blocks.append(.heading(level: 3, text: String(line.dropFirst(4))))
                i += 1
                continue
            } else if line.hasPrefix("#### ") {
                blocks.append(.heading(level: 4, text: String(line.dropFirst(5))))
                i += 1
                continue
            }

            // 3. Horizontal Rule
            if line == "---" || line == "***" || line == "___" {
                blocks.append(.divider)
                i += 1
                continue
            }

            // 4. Blockquote
            if line.hasPrefix("> ") {
                var quoteLines: [String] = [String(line.dropFirst(2))]
                i += 1
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("> ") {
                    quoteLines.append(String(lines[i].trimmingCharacters(in: .whitespaces).dropFirst(2)))
                    i += 1
                }
                blocks.append(.blockquote(text: quoteLines.joined(separator: "\n")))
                continue
            }

            // 5. Bullet List
            if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") {
                var items: [String] = [String(line.dropFirst(2))]
                i += 1
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    if next.hasPrefix("- ") || next.hasPrefix("* ") || next.hasPrefix("+ ") {
                        items.append(String(next.dropFirst(2)))
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            // 6. Numbered List
            if let match = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                var items: [String] = [String(line[match.upperBound...])]
                i += 1
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    if let nextMatch = next.range(of: #"^\d+\.\s+"#, options: .regularExpression) {
                        items.append(String(next[nextMatch.upperBound...]))
                        i += 1
                    } else {
                        break
                    }
                }
                blocks.append(.numberedList(items: items))
                continue
            }

            // 7. Table detection (starts with | and has | separator)
            if line.hasPrefix("|"),
               line.hasSuffix("|"),
               i + 1 < lines.count,
               lines[i + 1].contains("---") {
                let headers = MarkdownTableParsing.cells(in: line)
                i += 2 // skip header and delimiter line
                var rows: [[String]] = []
                while i < lines.count,
                      lines[i].trimmingCharacters(in: .whitespaces)
                        .hasPrefix("|") {
                    rows.append(MarkdownTableParsing.cells(in: lines[i]))
                    i += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            // 8. Normal Paragraph
            if !line.isEmpty {
                var pLines: [String] = [rawLine]
                i += 1
                while i < lines.count {
                    let next = lines[i].trimmingCharacters(in: .whitespaces)
                    if next.isEmpty || next.hasPrefix("```") || next.hasPrefix("#") || next.hasPrefix(">") || next.hasPrefix("- ") || next.hasPrefix("* ") || next == "---" {
                        break
                    }
                    pLines.append(lines[i])
                    i += 1
                }
                blocks.append(.paragraph(text: pLines.joined(separator: "\n")))
                continue
            }

            i += 1
        }

        return blocks
    }
}

public struct MarkdownView: View {
    public let content: String
    public let theme: MarkdownTheme
    public let isStreaming: Bool
    @State private var blocks: [MarkdownBlock] = []
    @State private var parsedContent = ""

    public init(
        content: String,
        theme: MarkdownTheme = MarkdownTheme.theme(for: .primeDark),
        isStreaming: Bool = false
    ) {
        self.content = content
        self.theme = theme
        self.isStreaming = isStreaming
    }

    public var body: some View {
        let renderState = MarkdownRenderState(
            content: content,
            parsedContent: parsedContent,
            isStreaming: isStreaming
        )
        let visibleBlocks = isStreaming
            ? MarkdownParser.parse(markdown: content)
            : blocks

        VStack(alignment: .leading, spacing: renderState.topLevelSpacing) {
            if renderState.shouldRenderParsedBlocks {
                VStack(
                    alignment: .leading,
                    spacing: MarkdownRenderState.blockSpacing
                ) {
                    ForEach(Array(visibleBlocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                case .heading(let level, let text):
                    switch level {
                    case 1:
                        Text(MarkdownInlineFormatting.attributedString(for: text))
                            .font(DesignTokens.TextStyle.title2.weight(.bold))
                            .foregroundStyle(theme.h1)
                            .padding(.top, 4)
                            .accessibilityAddTraits(.isHeader)
                    case 2:
                        Text(MarkdownInlineFormatting.attributedString(for: text))
                            .font(DesignTokens.TextStyle.title3.weight(.bold))
                            .foregroundStyle(theme.h2)
                            .padding(.top, 3)
                            .accessibilityAddTraits(.isHeader)
                    default:
                        Text(MarkdownInlineFormatting.attributedString(for: text))
                            .font(DesignTokens.TextStyle.headline.weight(.semibold))
                            .foregroundStyle(theme.h3)
                            .padding(.top, 2)
                            .accessibilityAddTraits(.isHeader)
                    }

                case .paragraph(let text):
                    Text(MarkdownInlineFormatting.attributedString(for: text))
                        .font(DesignTokens.TextStyle.body)
                        .lineSpacing(DesignTokens.TextStyle.bodyLineSpacing)
                        .foregroundStyle(theme.text)
                        .textSelection(.enabled)

                case .codeBlock(let language, let code):
                    CodeBlockView(language: language, code: code)
                        .padding(.vertical, 3)

                case .blockquote(let text):
                    HStack(spacing: 10) {
                        Rectangle()
                            .fill(theme.quoteBorder)
                            .frame(width: 3)
                        Text(MarkdownInlineFormatting.attributedString(for: text))
                            .font(DesignTokens.TextStyle.body)
                            .foregroundStyle(theme.secondaryText)
                            .italic()
                            .lineSpacing(DesignTokens.TextStyle.bodyLineSpacing)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(theme.quoteBackground, in: RoundedRectangle(cornerRadius: 6))

                case .bulletList(let items):
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(theme.bulletColor)
                                    .frame(width: 4.5, height: 4.5)
                                    .padding(.top, 6)

                                Text(MarkdownInlineFormatting.attributedString(for: item))
                                    .font(DesignTokens.TextStyle.body)
                                    .lineSpacing(DesignTokens.TextStyle.bodyLineSpacing)
                                    .foregroundStyle(theme.text)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.leading, 4)

                case .numberedList(let items):
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(index + 1).")
                                    .font(
                                        DesignTokens.TextStyle.calloutMonospaced
                                            .weight(.semibold)
                                    )
                                    .foregroundStyle(theme.bulletColor)
                                    .frame(minWidth: 18, alignment: .leading)

                                Text(MarkdownInlineFormatting.attributedString(for: item))
                                    .font(DesignTokens.TextStyle.body)
                                    .lineSpacing(DesignTokens.TextStyle.bodyLineSpacing)
                                    .foregroundStyle(theme.text)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    .padding(.leading, 4)

                case .divider:
                    Divider()
                        .padding(.vertical, 4)
                        .opacity(0.3)

                case .table(let headers, let rows):
                    ScrollView(.horizontal, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            // Headers
                            HStack(spacing: 0) {
                                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                                    Text(header)
                                        .font(DesignTokens.TextStyle.callout.weight(.bold))
                                        .foregroundStyle(theme.h2)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .frame(minWidth: 100, alignment: .leading)
                                }
                            }
                            .background(DesignTokens.Surface.subtle)

                            Divider().opacity(0.2)

                            // Rows
                            ForEach(Array(rows.enumerated()), id: \.offset) { rIdx, row in
                                let cells = MarkdownTablePresentation.cells(
                                    headers: headers,
                                    row: row
                                )
                                HStack(spacing: 0) {
                                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                                        Text(cell)
                                            .font(DesignTokens.TextStyle.callout)
                                            .foregroundStyle(theme.text)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .frame(minWidth: 100, alignment: .leading)
                                    }
                                }
                                .background(
                                    rIdx % 2 == 1
                                        ? Color.primary.opacity(
                                            DesignTokens.Opacity.faint
                                        )
                                        : Color.clear
                                )
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(MarkdownAccessibility.tableRowLabel(
                                    rowNumber: rIdx + 1,
                                    headers: headers,
                                    cells: cells
                                ))
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    DesignTokens.Stroke.separator,
                                    lineWidth: 1
                                )
                        )
                    }
                        }
                    }
                }
            }

            if let plainTextFallback = renderState.plainTextFallback {
                Text(verbatim: plainTextFallback)
                    .font(DesignTokens.TextStyle.body)
                    .foregroundStyle(theme.text)
                    .textSelection(.enabled)
            }
        }
        .task(id: MarkdownRenderTaskID(
            content: content,
            isStreaming: isStreaming
        )) {
            guard !isStreaming else { return }
            guard let parsedBlocks = await MarkdownDocumentCache.shared.blocks(
                for: content
            ), !Task.isCancelled else { return }
            blocks = parsedBlocks
            parsedContent = content
        }
    }
}
