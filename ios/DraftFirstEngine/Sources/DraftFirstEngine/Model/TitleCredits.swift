import Foundation

/// How a writer joins the previous one on the credit line. The distinction
/// is WGA convention, not typography: `&` joins a writing team (one
/// entity), `and` joins writers of separate drafts. The writer never types
/// the joiner — the model owns it, and the rendered `Author:` line is the
/// only form that reaches the document.
public enum WriterJoiner: String, Codable, Sendable, CaseIterable {
    case team
    case separate

    public var rendered: String { self == .team ? " & " : " and " }
}

/// One name on the credit line. `joiner` describes how this writer joins
/// the previous one; the first writer's joiner is inert (never rendered).
public struct WriterCredit: Equatable, Sendable, Codable {
    public var name: String
    public var joiner: WriterJoiner

    public init(name: String, joiner: WriterJoiner = .team) {
        self.name = name
        self.joiner = joiner
    }
}

/// The title-page credit model: parses the flat `Author:` string into
/// structured writers and renders them back losslessly. Plain Fountain text
/// stays the single source of truth — no custom keys, so a screenplay
/// written here reads correctly in every other Fountain tool.
///
///     Jane Smith & John Smith and Mary Jones
///
/// parses to Jane (first), John (.team), Mary (.separate) — and renders
/// back to exactly that string.
public enum TitleCredits {
    /// Splits on " and " first (separate writers), then " & " inside each
    /// segment (team members) — both with mandatory surrounding whitespace,
    /// so names like "Sandy" or "AT&T" can never split. Joiner matching is
    /// case-insensitive; rendering always normalizes to lowercase.
    public static func parseAuthors(_ text: String) -> [WriterCredit] {
        text
            .splitCaseInsensitively(on: " and ")
            .flatMap { segment in
                segment
                    .splitCaseInsensitively(on: " & ")
                    .map { name in name.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
            .enumerated()
            .map { index, name in
                WriterCredit(name: name, joiner: joiner(at: index, in: text))
            }
    }

    /// Renders writers back to the flat credit line. The first writer's
    /// joiner is skipped by construction.
    public static func renderAuthors(_ writers: [WriterCredit]) -> String {
        writers
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .enumerated()
            .map { index, writer in
                index == 0
                    ? writer.name.trimmingCharacters(in: .whitespaces)
                    : writer.joiner.rendered + writer.name.trimmingCharacters(in: .whitespaces)
            }
            .joined()
    }

    /// Recovers each writer's joiner from the original string: a writer is
    /// `.team` when the delimiter immediately before its name is "&",
    /// otherwise `.separate`. Position-based, so identical names never
    /// confuse it.
    private static func joiner(at writerIndex: Int, in text: String) -> WriterJoiner {
        guard writerIndex > 0 else { return .team }
        var found = 0
        for match in text.caseInsensitiveMatches(of: #"\s+(?:and|&)\s+"#) {
            if found == writerIndex - 1 {
                return match.trimmingCharacters(in: .whitespaces).hasPrefix("&")
                    ? .team
                    : .separate
            }
            found += 1
        }
        return .team
    }

    /// The credit phrases a writer chooses from — the picker's fixed set.
    /// Anything else is a custom string stored verbatim.
    public enum StandardCredit: String, CaseIterable, Sendable {
        case writtenBy = "written by"
        case screenplayBy = "screenplay by"
        case teleplayBy = "teleplay by"
        case storyBy = "story by"
        case basedOnStory = "based on a story by"
        case basedOnNovel = "based on the novel by"
        case adaptedFrom = "adapted from"

        /// Display form: the stored phrase with an initial capital.
        public var displayTitle: String {
            rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }

        /// Case-insensitive membership test for the picker's checkmark.
        public static func matching(_ credit: String) -> StandardCredit? {
            let needle = credit.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return allCases.first { $0.rawValue == needle }
        }
    }
}

private extension String {
    func splitCaseInsensitively(on delimiter: String) -> [String] {
        var parts: [String] = []
        var cursor = startIndex
        while let range = range(of: delimiter, options: .caseInsensitive, range: cursor..<endIndex) {
            parts.append(String(self[cursor..<range.lowerBound]))
            cursor = range.upperBound
        }
        parts.append(String(self[cursor...]))
        return parts
    }

    func caseInsensitiveMatches(of pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return []
        }
        let nsRange = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: nsRange).compactMap {
            Range($0.range, in: self).map { String(self[$0]) }
        }
    }
}
