import SwiftUI

public enum MarkdownBlock: Identifiable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(text: String)
    case codeBlock(language: String, code: String)
    case blockquote(text: String)
    case bulletList(items: [String])
    case numberedList(items: [String])
    case divider
    case table(headers: [String], rows: [[String]])

    public var id: String {
        switch self {
        case .heading(let level, let text): return "h-\(level)-\(text.prefix(20))"
        case .paragraph(let text): return "p-\(text.prefix(20))-\(text.count)"
        case .codeBlock(let lang, let code): return "code-\(lang)-\(code.prefix(20))"
        case .blockquote(let text): return "quote-\(text.prefix(20))"
        case .bulletList(let items): return "ul-\(items.count)-\(items.first?.prefix(10) ?? "")"
        case .numberedList(let items): return "ol-\(items.count)-\(items.first?.prefix(10) ?? "")"
        case .divider: return "hr-\(UUID().uuidString)"
        case .table(let headers, _): return "table-\(headers.joined())"
        }
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
            if line.hasPrefix("|") && line.hasSuffix("|") && i + 1 < lines.count && lines[i+1].contains("---") {
                let headers = line.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                i += 2 // skip header and delimiter line
                var rows: [[String]] = []
                while i < lines.count && lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    let rowCells = lines[i].split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                    rows.append(rowCells)
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

    public init(content: String, theme: MarkdownTheme = MarkdownTheme.theme(for: .primeDark)) {
        self.content = content
        self.theme = theme
    }

    public var body: some View {
        let blocks = MarkdownParser.parse(markdown: content)

        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let text):
                    switch level {
                    case 1:
                        Text(LocalizedStringKey(text))
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(theme.h1)
                            .padding(.top, 4)
                    case 2:
                        Text(LocalizedStringKey(text))
                            .font(.system(size: 15.5, weight: .bold))
                            .foregroundStyle(theme.h2)
                            .padding(.top, 3)
                    default:
                        Text(LocalizedStringKey(text))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(theme.h3)
                            .padding(.top, 2)
                    }

                case .paragraph(let text):
                    Text(LocalizedStringKey(text))
                        .font(.system(size: 13.5, weight: .regular))
                        .lineSpacing(4)
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
                        Text(LocalizedStringKey(text))
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(theme.secondaryText)
                            .italic()
                            .lineSpacing(3)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(theme.quoteBackground, in: RoundedRectangle(cornerRadius: 6))

                case .bulletList(let items):
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Circle()
                                    .fill(theme.bulletColor)
                                    .frame(width: 4.5, height: 4.5)
                                    .padding(.top, 6)

                                Text(LocalizedStringKey(item))
                                    .font(.system(size: 13.5))
                                    .lineSpacing(3)
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
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(theme.bulletColor)
                                    .frame(minWidth: 18, alignment: .leading)

                                Text(LocalizedStringKey(item))
                                    .font(.system(size: 13.5))
                                    .lineSpacing(3)
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
                                ForEach(headers, id: \.self) { header in
                                    Text(header)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(theme.h2)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .frame(minWidth: 100, alignment: .leading)
                                }
                            }
                            .background(Color.white.opacity(0.06))

                            Divider().opacity(0.2)

                            // Rows
                            ForEach(Array(rows.enumerated()), id: \.offset) { rIdx, row in
                                HStack(spacing: 0) {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                        Text(cell)
                                            .font(.system(size: 12))
                                            .foregroundStyle(theme.text)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 6)
                                            .frame(minWidth: 100, alignment: .leading)
                                    }
                                }
                                .background(rIdx % 2 == 1 ? Color.white.opacity(0.02) : Color.clear)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
}
