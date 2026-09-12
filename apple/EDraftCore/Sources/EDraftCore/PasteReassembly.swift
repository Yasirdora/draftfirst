import EDraftEngine
import Foundation

/// The lexical tells a plain-text script carries — one definition, shared by
/// the paste reassembly (which breaks paragraphs on them) and the editor's
/// paste classifier (which types the results). Two readers, one rule.
nonisolated enum PasteHeuristics {

    static func looksLikeSceneHeading(_ uppercased: String) -> Bool {
        ["INT.", "EXT.", "EST.", "INT/EXT.", "I/E."].contains { uppercased.hasPrefix($0) }
    }

    static func looksLikeTransition(_ uppercased: String) -> Bool {
        uppercased == "FADE IN:" || uppercased == "FADE OUT."
            || uppercased.hasSuffix(" TO:") || uppercased.hasSuffix(" OUT:")
            || uppercased.hasSuffix("DISSOLVE:")
    }

    static func looksLikeCharacterCue(_ text: String, uppercase: String) -> Bool {
        guard !text.isEmpty,
              text == uppercase,
              text.utf16.count <= 48,
              text.rangeOfCharacter(from: .letters) != nil else { return false }
        return !text.hasSuffix(".") && !text.hasSuffix(":")
    }
}

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
        /// The kind the reassembly read from the paste's own structure, or
        /// nil to leave the classifier its say. An unindented hard-wrapped
        /// paste has no margins to measure, so its paragraphs carry their
        /// kinds instead.
        public let kind: ScreenplayKind?

        public init(text: String, depth: Int, kind: ScreenplayKind? = nil) {
            self.text = text
            self.depth = depth
            self.kind = kind
        }
    }

    /// The paste's paragraphs, or nil when there is no indentation scheme.
    public static func paragraphs(from source: String) -> [Paragraph]? {
        let lines = source.components(separatedBy: "\n")
        if let indented = indentedParagraphs(lines) { return indented }
        return hardWrappedParagraphs(lines)
    }

    /// The indented scheme — the courier's margins say what everything is.
    private static func indentedParagraphs(_ lines: [String]) -> [Paragraph]? {
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
            if Acts.isEndActCard(Emphasis.parse(trimmed).text) {
                // An act ends where the next one begins: the closing card
                // is furniture (RFC-ACT-BREAK §5), and a hard boundary —
                // the paragraph under way ends here, nothing joins across.
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

    /// The unindented hard-wrap — text copied from a page that renders no
    /// margins and no blank lines, wrapped at a fixed right edge.
    ///
    /// Without margins the structure is read from the words themselves:
    /// a heading prefix, a transition's shape, a parenthetical's bracket
    /// and an all-caps line each open a new paragraph, and everything else
    /// continues the paragraph under way — a speech runs to its last
    /// wrapped line, and dialogue stops being re-typed as a shouted cue
    /// every forty characters, which is exactly what the Social Network
    /// paste did (2,758 "cues", 1,723 of them prose).
    ///
    /// The things it cannot see, named rather than hidden: two consecutive
    /// action paragraphs with no marker between them join into one, and a
    /// scene heading long enough to wrap loses its continuation to action —
    /// margins are the only thing that tells a heading's second line from a
    /// new paragraph, and this paste has none. Both are the honest edge of a
    /// structure-less paste.
    private static func hardWrappedParagraphs(_ lines: [String]) -> [Paragraph]? {
        let nonBlank = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        // A snippet is not a structure; a paste with real blank-line
        // separation already reads line-per-element correctly.
        guard nonBlank.count >= 8,
              nonBlank.count * 50 >= lines.count * 49
        else { return nil }
        // Hard-wrapped: the wrap column caps every line, and prose in bulk
        // runs near it. Measured on the Social Network paste: longest line
        // 69, 40% of lines at 30+. An unwrapped paste breaks both rules —
        // whole paragraphs arrive as single 200-character lines — and a
        // headline-length one never reaches the prose share.
        let lengths = nonBlank.map { $0.utf16.count }
        guard let longest = lengths.max(), longest <= 120,
              lengths.filter({ $0 >= 30 }).count * 5 >= nonBlank.count
        else { return nil }

        var paragraphs: [Paragraph] = []
        var kind: ScreenplayKind = .action
        var current: [String] = []
        func flush() {
            guard !current.isEmpty else { return }
            paragraphs.append(Paragraph(text: current.joined(separator: " "), depth: 0, kind: kind))
            current = []
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                flush()
                continue
            }
            // The tells read the words, not the markers: **MARK** is a cue
            // whether or not the writer bolded it. The raw line is what
            // joins, so the markers survive to the planner's own parse.
            let cleaned = Emphasis.parse(trimmed).text
            let upper = cleaned.uppercased()
            if Acts.isEndActCard(cleaned) {
                // An act ends where the next one begins: the closing card
                // is furniture (RFC-ACT-BREAK §5), and a hard boundary —
                // the paragraph under way ends here, nothing joins across.
                flush()
                continue
            }
            if PasteHeuristics.looksLikeSceneHeading(upper) {
                flush()
                kind = .scene
                current = [trimmed]
            } else if Acts.isActCard(cleaned) {
                // The card is structural, never a speaker — without this
                // tell the cue shape below adopts ACT ONE (RFC-ACT-BREAK §5).
                flush()
                kind = .actbreak
                current = [trimmed]
            } else if PasteHeuristics.looksLikeTransition(upper) {
                flush()
                kind = .transition
                current = [trimmed]
            } else if PasteHeuristics.looksLikeCharacterCue(cleaned, uppercase: upper) {
                flush()
                kind = .character
                current = [trimmed]
            } else if trimmed.hasPrefix("(") {
                flush()
                kind = .parenthetical
                current = [trimmed]
            } else if paragraphs.isEmpty && current.isEmpty {
                kind = .action
                current = [trimmed]
            } else {
                switch kind {
                case .parenthetical where !current.joined().hasSuffix(")"):
                    break   // an open parenthetical runs to its close
                case .character, .parenthetical:
                    flush()
                    kind = .dialogue
                    current = []
                case .scene, .transition, .actbreak:
                    flush() // a card stands alone; what follows it is prose
                    kind = .action
                    current = []
                default:
                    break   // prose after prose continues the paragraph
                }
                current.append(trimmed)
            }
        }
        flush()
        return paragraphs.isEmpty ? nil : paragraphs
    }
}
