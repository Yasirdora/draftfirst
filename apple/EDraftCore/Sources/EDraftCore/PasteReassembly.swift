import Foundation

/// What a hard-wrapped paste means.
///
/// Plain-text scripts copied from the web or a PDF are wrapped at a fixed
/// column: one screenplay paragraph arrives as several source lines, each
/// carrying the courier's margin in leading spaces. Splitting such a paste
/// on newlines alone stores the margin inside the text — every line then
/// wraps again inside the page's own sixty-character measure, which is the
/// staggered, doubly-paged wreck the 8,582-line Kane paste was reported as:
/// the words were right and the paragraphs were gone.
///
/// When — and only when — the paste carries an indentation scheme, its
/// paragraphs are reassembled here. A blank line ends a paragraph, and so
/// does a change of column: a cue and its speech are neighbours without a
/// blank between them, and only the margin says so. Continuation lines keep
/// their paragraph's column, so they join, with one space, margins off.
/// The depth the first line sat at is kept, because action and dialogue
/// read alike once joined and the scheme is the only thing left that tells
/// them apart. A paste without a scheme (Fountain text, an unindented
/// copy) answers nil, and the planner keeps its line-per-element reading
/// untouched.
public nonisolated enum PasteReassembly {

    public struct Paragraph: Equatable {
        /// The paragraph's words, unwrapped: margins off, continuation
        /// lines joined with single spaces.
        public let text: String
        /// How far past the scheme's base column the paragraph's first
        /// line sat — 0 for action, the dialogue depth for a speech.
        public let depth: Int
    }

    /// The paste's paragraphs, or nil when there is no indentation scheme.
    public static func paragraphs(from source: String) -> [Paragraph]? {
        let lines = source.components(separatedBy: "\n")
        let indents = lines.compactMap { line -> Int? in
            line.trimmingCharacters(in: .whitespaces).isEmpty ? nil : leadingIndent(of: line)
        }
        // A one-line paste is never a scheme; neither is a paste where the
        // margins live on a minority of lines.
        guard indents.count >= 3,
              indents.filter({ $0 >= 6 }).count * 5 >= indents.count * 3
        else { return nil }

        // The base column is the action margin: the shallowest indent a
        // real share of the lines use. The plain minimum is an outlier's
        // answer — Kane's opener "FADE IN:" sits at zero whatever the
        // scheme — and the mode is dialogue's answer, because a script
        // talks more than it describes.
        let floor = indents.min() ?? 0
        let threshold = max(2, indents.count / 7)
        let base = (0...15).lazy
            .map { column in (column: column, share: indents.filter { $0 == column }.count) }
            .filter { $0.share >= threshold }
            .first?.column ?? mode(of: indents) ?? floor

        var paragraphs: [Paragraph] = []
        var current: [String] = []
        var depth = 0
        var column = -1
        func flush() {
            guard !current.isEmpty else { return }
            paragraphs.append(Paragraph(text: current.joined(separator: " "), depth: depth))
            current = []
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                flush()
                column = -1
                continue
            }
            let indent = leadingIndent(of: line)
            // A column change is a paragraph break: the cue and its speech
            // share no blank line. One column of drift is the copier's
            // noise, not the writer's structure.
            if column >= 0, abs(indent - column) > 1 { flush() }
            if current.isEmpty {
                depth = max(0, indent - base)
                column = indent
            }
            current.append(trimmed)
        }
        flush()
        return paragraphs.isEmpty ? nil : paragraphs
    }

    /// The margin in columns. A tab stands for the eight it is set to.
    private static func leadingIndent(of line: String) -> Int {
        var columns = 0
        for unit in line.utf16 {
            switch unit {
            case 32: columns += 1
            case 9: columns += 8
            default: return columns
            }
        }
        return columns
    }

    /// The commonest value, the smallest on a tie — deterministic.
    private static func mode(of values: [Int]) -> Int? {
        values.reduce(into: [:] as [Int: Int]) { $0[$1, default: 0] += 1 }
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .first?.key
    }
}
