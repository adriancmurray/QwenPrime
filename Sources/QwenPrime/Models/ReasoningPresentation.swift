import Foundation

struct ReasoningPresentation: Equatable, Sendable {
    let thinking: String
    let answer: String
    let usesPolishedRecap: Bool

    static func resolve(hiddenThinking: String?, content: String) -> ReasoningPresentation {
        let hiddenThinking = hiddenThinking?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !hiddenThinking.isEmpty else {
            return ReasoningPresentation(thinking: "", answer: content, usesPolishedRecap: false)
        }

        let lines = content.components(separatedBy: .newlines)
        guard let firstContentIndex = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
              let reasoningHeading = heading(in: lines[firstContentIndex]),
              isReasoningTitle(reasoningHeading.title) else {
            return ReasoningPresentation(
                thinking: hiddenThinking,
                answer: content,
                usesPolishedRecap: false
            )
        }

        var isInsideCodeFence = false
        var answerStartIndex: Int?
        for index in lines.indices where index > firstContentIndex {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                isInsideCodeFence.toggle()
                continue
            }
            guard !isInsideCodeFence,
                  let candidate = heading(in: line),
                  candidate.level <= reasoningHeading.level else {
                continue
            }
            answerStartIndex = index
            break
        }

        let reasoningEndIndex = answerStartIndex ?? lines.endIndex
        var reasoningLines = Array(lines[(firstContentIndex + 1)..<reasoningEndIndex])
        while let last = reasoningLines.last {
            let trimmed = last.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || isDivider(trimmed) {
                reasoningLines.removeLast()
            } else {
                break
            }
        }

        let polishedThinking = reasoningLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !polishedThinking.isEmpty else {
            return ReasoningPresentation(
                thinking: hiddenThinking,
                answer: content,
                usesPolishedRecap: false
            )
        }

        let answer = answerStartIndex.map {
            lines[$0...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? ""
        return ReasoningPresentation(
            thinking: polishedThinking,
            answer: answer,
            usesPolishedRecap: true
        )
    }

    private static func heading(in line: String) -> (level: Int, title: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes) else { return nil }

        let titleStart = trimmed.index(trimmed.startIndex, offsetBy: hashes)
        guard titleStart < trimmed.endIndex, trimmed[titleStart].isWhitespace else { return nil }
        let title = trimmed[titleStart...]
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        return (hashes, title)
    }

    private static func isReasoningTitle(_ title: String) -> Bool {
        switch title.lowercased() {
        case "design reasoning", "reasoning", "analysis": true
        default: false
        }
    }

    private static func isDivider(_ line: String) -> Bool {
        line == "---" || line == "***" || line == "___"
    }
}
