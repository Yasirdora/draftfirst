import EDraftEngine
import Foundation

/// The lexical tells a plain-text script carries — one definition, shared by
/// the paste reassembly (which breaks paragraphs on them) and the editor's
/// paste classifier (which types the results). Two readers, one rule.
nonisolated enum PasteHeuristics {

    /// Reads the line in its original case: the prefix tells are
    /// case-insensitive, but the numbered heading grammar is the engine's
    /// own — `SceneNumbering.parseNumberedHeading` — and its OMITTED card
    /// is case-sensitive the way the TypeScript pattern is.
    static func looksLikeSceneHeading(_ text: String) -> Bool {
        let uppercased = text.uppercased()
        return ["INT.", "EXT.", "EST.", "INT/EXT.", "EXT/INT.", "EXT./INT.", "I/E."].contains { uppercased.hasPrefix($0) }
            || SceneNumbering.parseNumberedHeading(text) != nil
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

    /// Artifacts of a printed page, meaningful only to a reader of paper:
    /// page numbers, loose scene numbers, draft stamps, (MORE), CONTINUED.
    /// Ported from the TypeScript engine's plaintext.ts — the same shapes,
    /// answered without a regex, with ASCII digits the way JavaScript's `\d`
    /// is. 1,233 page-number lines, 88 (MORE)s and 394 CONTINUEDs stand
    /// witness across the corpus, and so do the furniture families the
    /// routing pack added: 650 draft-stamp footers, 189 lettered scene
    /// numbers and 189 page twins.
    static func isPaginationArtifact(_ text: String) -> Bool {
        // ^\d{1,4}\.?$
        let digits = text.prefix(while: { $0.isASCII && $0.isNumber })
        if !digits.isEmpty, digits.count <= 4 {
            let rest = text.dropFirst(digits.count)
            if rest.isEmpty || rest == "." { return true }
        }
        if isLooseSceneNumber(text) { return true }
        let upper = text.uppercased()
        // ^\(MORE\)$, case-insensitively
        if upper == "(MORE)" { return true }
        // ^\(CONT['’]?D\)$, case-insensitively
        if upper.hasPrefix("(CONT"), upper.hasSuffix("D)") {
            let middle = upper.dropFirst(5).dropLast(2)
            if middle.isEmpty || middle == "'" || middle == "’" { return true }
        }
        // ^\(?CONTINUED\)?[.:]?$, case-insensitively
        var continued = Substring(upper)
        if continued.hasPrefix("(") { continued = continued.dropFirst() }
        if continued.hasPrefix("CONTINUED") {
            continued = continued.dropFirst("CONTINUED".count)
            if continued.hasSuffix(")") { continued = continued.dropLast() }
            return continued.isEmpty || continued == "." || continued == ":"
        }
        return isDraftStamp(text)
    }

    /// The scene number set loose from its heading: lettered by the
    /// production ("4A", corpus-6; "57A", episode-101; "A1", lalaland ×42) or
    /// printed as the twin the page carries twice ("1 1", whiplash ×134;
    /// "1A 1A", foryourcon ×54) — the pair matches only when both numbers
    /// are equal, and only the second twin carries the period ("1 1.",
    /// never "1. 1").
    private static func isLooseSceneNumber(_ text: String) -> Bool {
        // ^(?:\d{1,4}[A-Z]|[A-Z]\d{1,4})\.?$
        var single = Substring(text)
        if single.hasSuffix(".") { single = single.dropLast() }
        if isLetteredNumberToken(single) { return true }
        // ^(\d{1,4}[A-Z]?) +\1\.?$ — both twins equal, plain spaces between
        let halves = text.split(separator: " ", omittingEmptySubsequences: true)
        guard halves.count == 2 else { return false }
        var second = halves[1]
        if second.hasSuffix(".") { second = second.dropLast() }
        return halves[0] == second && isDigitsFirstNumberToken(second)
    }

    /// 1–4 ASCII digits and exactly one ASCII capital, either order —
    /// "4A", "A1". A bare number is the page-number shape above, not this one.
    private static func isLetteredNumberToken(_ token: Substring) -> Bool {
        // \d{1,4}[A-Z]
        if let digits = leadingDigitsLength(token), digits < token.count {
            let rest = token.dropFirst(digits)
            if rest.count == 1, let letter = rest.first, isASCIICapital(letter) { return true }
        }
        // [A-Z]\d{1,4}
        if let first = token.first, isASCIICapital(first) {
            let rest = token.dropFirst()
            if let digits = leadingDigitsLength(rest), digits == rest.count { return true }
        }
        return false
    }

    /// \d{1,4}[A-Z]? anchored to the whole token — the page-twin shape.
    private static func isDigitsFirstNumberToken(_ token: Substring) -> Bool {
        guard let digits = leadingDigitsLength(token) else { return false }
        if digits == token.count { return true }
        return digits + 1 == token.count
            && token.dropFirst(digits).first.map(isASCIICapital) == true
    }

    /// The length of the leading run of 1–4 ASCII digits, or nil.
    private static func leadingDigitsLength(_ token: Substring) -> Int? {
        let digits = token.prefix(while: { $0.isASCII && $0.isNumber })
        guard !digits.isEmpty, digits.count <= 4 else { return nil }
        return digits.count
    }

    private static func isASCIICapital(_ char: Character) -> Bool {
        char.isASCII && char.isLetter && char.isUppercase
    }

    /// The production's page footer — the draft's colour, date and page:
    /// "Pink (9/10/2013) 2" (whiplash ×112), "GG- Yellow Revisions 9/27/13 4."
    /// (gone-girl ×176), "10/29/14 / 2." (foryourcon ×111), "Revision 2."
    /// (lalaland ×84), "The Irishman D1-5 SZ 9.15.09 2." (pasted-26 ×132),
    /// "FINAL SHOOTING SCRIPT Pink 7.25.06" (corpus-6 ×23), "GREEN REVISIONS
    /// 12/14/19" (episode-101 ×12) — 650 witnesses, every one a stamp.
    /// Mirrored from the TypeScript `isDraftStamp`, letter-run for letter-run.
    private static func isDraftStamp(_ text: String) -> Bool {
        guard text.utf16.count <= 64 else { return false }

        // ^Revisions? \d+\.?$, case-insensitively
        let words = text.split(separator: " ")
        if words.count == 2, ["REVISION", "REVISIONS"].contains(words[0].uppercased()) {
            var number = words[1]
            if number.hasSuffix(".") { number = number.dropLast() }
            if !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }) { return true }
        }

        // the date token: \d{1,2}[./]\d{1,2}[./](?:\d{4}|\d{2}(?!\d)) — the
        // two-digit year must not eat a following digit, or a bare
        // four-digit-year date ("1/5/1999", a title-page line) reads as
        // date-plus-page
        func dateTokenLength(at start: String.Index) -> Int? {
            var index = start
            func takeDigits(_ max: Int) -> Int {
                var count = 0
                while index < text.endIndex, count < max {
                    let char = text[index]
                    guard char.isASCII, char.isNumber else { break }
                    count += 1
                    index = text.index(after: index)
                }
                return count
            }
            guard takeDigits(2) > 0 else { return nil }
            guard index < text.endIndex, text[index] == "." || text[index] == "/" else { return nil }
            index = text.index(after: index)
            guard takeDigits(2) > 0 else { return nil }
            guard index < text.endIndex, text[index] == "." || text[index] == "/" else { return nil }
            index = text.index(after: index)
            let yearStart = index
            let year = takeDigits(4)
            if year == 4 { return text.distance(from: start, to: index) }
            if year >= 2 {
                let twoDigitEnd = text.index(yearStart, offsetBy: 2)
                let followedByDigit = twoDigitEnd < text.endIndex
                    && text[twoDigitEnd].isASCII && text[twoDigitEnd].isNumber
                if !followedByDigit { return text.distance(from: start, to: twoDigitEnd) }
            }
            return nil
        }

        var dateRanges: [Range<String.Index>] = []
        var scan = text.startIndex
        while scan < text.endIndex {
            if text[scan].isASCII, text[scan].isNumber,
               let length = dateTokenLength(at: scan) {
                let end = text.index(scan, offsetBy: length)
                dateRanges.append(scan..<end)
                scan = end
            } else {
                scan = text.index(after: scan)
            }
        }
        guard let firstDate = dateRanges.first else { return false }

        // ^date\s*/?\s*\d{1,4}\.?$ — "10/29/14 / 2.", "2/17/65 3."
        if firstDate.lowerBound == text.startIndex {
            var rest = text[firstDate.upperBound...]
            while rest.first?.isWhitespace == true { rest = rest.dropFirst() }
            if rest.first == "/" { rest = rest.dropFirst() }
            while rest.first?.isWhitespace == true { rest = rest.dropFirst() }
            var page = rest
            if page.hasSuffix(".") { page = page.dropLast() }
            if !page.isEmpty, page.allSatisfy({ $0.isASCII && $0.isNumber }), page.count <= 4 {
                return true
            }
        }

        // date anywhere + a marker word or an all-caps code anywhere. Marker
        // words read letter-runs, the way JavaScript's `\bWORD\b` does; the
        // colour list is the production's revision paper.
        let markers: Set<String> = [
            "REVISED", "REVISION", "REVISIONS", "DRAFT", "SCRIPT", "SHOOTING",
            "PRODUCTION", "FINAL", "FULL",
            "PINK", "BLUE", "WHITE", "GREEN", "YELLOW", "GOLDENROD"
        ]
        var hasMarker = false
        var hasCode = false
        var letterRun = ""
        func flushLetterRun() {
            if letterRun.isEmpty { return }
            if markers.contains(letterRun.uppercased()) { hasMarker = true }
            letterRun = ""
        }
        var previous: Character?
        for index in text.indices {
            let char = text[index]
            if char.isLetter {
                letterRun.append(char)
            } else {
                flushLetterRun()
            }
            // \b[A-Z]{1,4}-?\d+(?:-\d+)*\b — the production code: "D1-5"
            if char.isASCII, char.isLetter, char.isUppercase,
               previous.map({ !($0.isLetter || $0.isNumber || $0 == "_") }) ?? true {
                var cursor = index
                var letters = 0
                while cursor < text.endIndex, letters < 4 {
                    let c = text[cursor]
                    guard c.isASCII, c.isLetter, c.isUppercase else { break }
                    letters += 1
                    cursor = text.index(after: cursor)
                }
                if cursor < text.endIndex, text[cursor] == "-" {
                    cursor = text.index(after: cursor)
                }
                var digitsFound = 0
                while cursor < text.endIndex {
                    let c = text[cursor]
                    if c.isASCII, c.isNumber {
                        digitsFound += 1
                        cursor = text.index(after: cursor)
                    } else if c == "-", digitsFound > 0 {
                        cursor = text.index(after: cursor)
                    } else {
                        break
                    }
                }
                if digitsFound > 0 { hasCode = true }
            }
            previous = char
        }
        flushLetterRun()
        guard hasMarker || hasCode else { return false }

        /* prose guard: a stamp is furniture tokens and title words only, so
           no all-lowercase word of four letters lives in one — a sentence
           carrying a date ("He delivered the FINAL DRAFT on 9/10/2013,
           late.") is prose, and stays. The guard saves no corpus line; it
           exists for the next one. Edge punctuation is ignored, the way the
           TypeScript token strip reads it. */
        for token in text.split(whereSeparator: { $0.isWhitespace }) {
            let lettersOnly = token.drop(while: { !$0.isLetter })
            let word = lettersOnly.prefix(while: { $0.isLetter })
            let tail = lettersOnly.dropFirst(word.count)
            if word.count >= 4,
               tail.allSatisfy({ !$0.isLetter }),
               word.allSatisfy({ $0.isLowercase }) {
                return false
            }
        }
        return true
    }

    /// The revision asterisk rides a revised line's tail — "AMY wakes,
    /// turns, gives a look of alarm.*" (gone-girl ×1,426), "TRUMPETER #2 **"
    /// (whiplash ×21) — or stands alone in the margin on its own line
    /// (corpus-6 ×115). Returns the line without its mark; a body that still
    /// holds a `*` keeps its ending, because the emphasis marker's own tail
    /// ("**bold**") is formatting, never a revision mark.
    static func strippingRevisionStar(_ text: String) -> String {
        var body = Substring(text)
        var stars = 0
        while stars < 2, body.last == "*" {
            body = body.dropLast()
            stars += 1
        }
        guard stars > 0 else { return text }
        while body.last?.isWhitespace == true { body = body.dropLast() }
        guard !body.contains("*") else { return text }
        return String(body)
    }

    /* The marked card (corpus: gone-girl ×24, emilia-perez ×4, episode-101
       ×2, from-the-black ×6): a marker line opens the card, then its content
       in witnessed order — a date line, a time line, and one all-caps line
       that is the card's message and closes it. The first prose line closes
       the card unread. No witnessed card follows a time-only opening with a
       message, so after a time line with no date above it the message slot
       is shut — the all-caps line there is the next cue (from-the-black's
       "9:48 PM / MARK (V.O.)"), never the card's text. A marker carrying its
       content on the same line ("INSERT CHYRON: 1994") is the whole card at
       once. Mirrored from the TypeScript engine's plaintext.ts. */

    /// The card's opening line — "TITLE CARD:", "TITLE:", "SUPER:",
    /// "INSERT CHYRON:", case-insensitively. Returns the content riding the
    /// marker's own line (empty when the marker stands alone), or nil when
    /// the line is no marker.
    static func titleCardMarker(_ text: String) -> String? {
        var rest = Substring(text)
        /// Takes `word` case-insensitively; `spaced` requires at least one
        /// whitespace before it, the way the pattern's `\s+` reads.
        func take(_ word: String, spaced: Bool) -> Bool {
            var probe = rest
            var spaces = 0
            while probe.first?.isWhitespace == true { probe = probe.dropFirst(); spaces += 1 }
            guard probe.count >= word.count,
                  probe.prefix(word.count).uppercased() == word,
                  !spaced || spaces > 0
            else { return false }
            rest = probe.dropFirst(word.count)
            return true
        }
        if take("TITLE", spaced: false) {
            _ = take("CARD", spaced: true)
        } else if take("SUPER", spaced: false) {
            // whole marker
        } else if take("INSERT", spaced: false), take("CHYRON", spaced: true) {
            // whole marker
        } else {
            return nil
        }
        // \s* then the colon — "TITLES:" and "SUPERIMPOSE" are no markers
        while rest.first?.isWhitespace == true { rest = rest.dropFirst() }
        guard rest.first == ":" else { return nil }
        rest = rest.dropFirst()
        while rest.first?.isWhitespace == true { rest = rest.dropFirst() }
        return String(rest)
    }

    /// The card's date line: "July 6, 2012", "JULY 5th, 2012",
    /// "JULY, 5, 2012", a trailing comma tolerated.
    /// ^[A-Za-z]+,? \d{1,2}(?:st|nd|rd|th)?,? \d{4}[,.]?$
    static func isTitleCardDate(_ text: String) -> Bool {
        var rest = Substring(text)
        let month = rest.prefix(while: { $0.isASCII && $0.isLetter })
        guard !month.isEmpty else { return false }
        rest = rest.dropFirst(month.count)
        if rest.first == "," { rest = rest.dropFirst() }
        guard rest.first == " " else { return false }
        rest = rest.dropFirst()
        let day = rest.prefix(while: { $0.isASCII && $0.isNumber })
        guard !day.isEmpty, day.count <= 2 else { return false }
        rest = rest.dropFirst(day.count)
        for suffix in ["st", "nd", "rd", "th"] where rest.hasPrefix(suffix) {
            rest = rest.dropFirst(2)
            break
        }
        if rest.first == "," { rest = rest.dropFirst() }
        guard rest.first == " " else { return false }
        rest = rest.dropFirst()
        let year = rest.prefix(while: { $0.isASCII && $0.isNumber })
        guard year.count == 4 else { return false }
        rest = rest.dropFirst(4)
        if rest.first == "." || rest.first == "," { rest = rest.dropFirst() }
        return rest.isEmpty
    }

    /// The card's time line: "11:17 A.m.", "4:17 PM", "6:17PM".
    /// ^\d{1,2}:\d{2}\s*(?:[AP]\.?M\.?)?$ case-insensitively
    static func isTitleCardTime(_ text: String) -> Bool {
        var rest = Substring(text)
        let hour = rest.prefix(while: { $0.isASCII && $0.isNumber })
        guard !hour.isEmpty, hour.count <= 2 else { return false }
        rest = rest.dropFirst(hour.count)
        guard rest.first == ":" else { return false }
        rest = rest.dropFirst()
        let minute = rest.prefix(while: { $0.isASCII && $0.isNumber })
        guard minute.count == 2 else { return false }
        rest = rest.dropFirst(2)
        while rest.first?.isWhitespace == true { rest = rest.dropFirst() }
        guard !rest.isEmpty else { return true }
        let upper = rest.uppercased()
        guard let meridiem = upper.first, meridiem == "A" || meridiem == "P" else { return false }
        var tail = upper.dropFirst()
        if tail.first == "." { tail = tail.dropFirst() }
        guard tail.first == "M" else { return false }
        tail = tail.dropFirst()
        if tail.first == "." { tail = tail.dropFirst() }
        return tail.isEmpty
    }

    /// An all-caps line, the card's message shape — "ONE DAY GONE".
    static func isCardMessage(_ text: String) -> Bool {
        text.contains(where: { $0.isASCII && $0.isLetter && $0.isUppercase })
            && text == text.uppercased()
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
        var cardOpen = false
        var cardHasDate = false
        var cardSawTime = false
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
                cardOpen = false
                continue
            }
            let unstarred = PasteHeuristics.strippingRevisionStar(trimmed)
            if unstarred.isEmpty {
                // A bare revision mark is furniture of the margin: it
                // splits a speech, not a thought — the paragraph under
                // way continues across it, the way it crosses a (MORE).
                continue
            }
            let cleaned = Emphasis.parse(unstarred).text
            if PasteHeuristics.isPaginationArtifact(cleaned) {
                // A page number or a (MORE) is furniture of the printed
                // page, and it splits a speech, not a thought: the
                // paragraph under way continues across it — nothing
                // flushes, no column moves.
                continue
            }
            if Acts.isEndActCard(cleaned) {
                // An act ends where the next one begins: the closing card
                // is furniture (RFC-ACT-BREAK §5), and a hard boundary —
                // the paragraph under way ends here, nothing joins across.
                flush()
                column = -1
                cardOpen = false
                continue
            }
            if let cardInline = PasteHeuristics.titleCardMarker(unstarred) {
                // The marker is the card's meaning, not its text — a hard
                // boundary: the lines it opens print centered, whatever
                // column they sat at, and nothing continues across it.
                flush()
                column = -1
                if cardInline.isEmpty {
                    cardOpen = true
                    cardHasDate = false
                    cardSawTime = false
                } else {
                    paragraphs.append(Paragraph(text: cardInline, depth: 0, kind: .centered))
                }
                continue
            }
            if cardOpen {
                if PasteHeuristics.isTitleCardDate(unstarred) {
                    flush()
                    column = -1
                    paragraphs.append(Paragraph(text: unstarred, depth: 0, kind: .centered))
                    cardHasDate = true
                    continue
                }
                if PasteHeuristics.isTitleCardTime(unstarred) {
                    flush()
                    column = -1
                    paragraphs.append(Paragraph(text: unstarred, depth: 0, kind: .centered))
                    cardSawTime = true
                    continue
                }
                // The message slot: open at the marker and under a date —
                // shut after a bare time stamp, where the caps line is the
                // next speaker, not the card's text.
                if PasteHeuristics.isCardMessage(unstarred), cardHasDate || !cardSawTime {
                    flush()
                    column = -1
                    paragraphs.append(Paragraph(text: unstarred, depth: 0, kind: .centered))
                    cardOpen = false
                    continue
                }
                cardOpen = false  // the first prose line closes the card
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
            current.append(unstarred)
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
        // Hard-wrapped: the wrap column caps the lines, and prose in bulk
        // runs near it. Measured on the Social Network paste: longest line
        // 69, 40% of lines at 30+. The over-long line is a share, not a
        // veto — a scan fuses a line now and then (breaking-bad carries
        // four, 0.2% of its lines), and one outlier must not disown two
        // thousand wrapped ones. An unwrapped paste inverts the share:
        // whole paragraphs arrive as single long lines, and a
        // headline-length one never reaches the prose share.
        let lengths = nonBlank.map { $0.utf16.count }
        let outliers = lengths.filter { $0 > 120 }.count
        guard outliers * 50 <= nonBlank.count,
              lengths.filter({ $0 >= 30 }).count * 5 >= nonBlank.count
        else { return nil }

        var paragraphs: [Paragraph] = []
        var kind: ScreenplayKind = .action
        var current: [String] = []
        var cardOpen = false
        var cardHasDate = false
        var cardSawTime = false
        func flush() {
            guard !current.isEmpty else { return }
            paragraphs.append(Paragraph(text: current.joined(separator: " "), depth: 0, kind: kind))
            current = []
        }
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else {
                flush()
                cardOpen = false
                continue
            }
            let unstarred = PasteHeuristics.strippingRevisionStar(trimmed)
            if unstarred.isEmpty {
                // A bare revision mark is furniture of the margin: it
                // splits a speech, not a thought — the paragraph under
                // way continues across it, the way it crosses a (MORE).
                continue
            }
            // The tells read the words, not the markers: **MARK** is a cue
            // whether or not the writer bolded it. The raw line is what
            // joins, so the markers survive to the planner's own parse.
            let cleaned = Emphasis.parse(unstarred).text
            let upper = cleaned.uppercased()
            if PasteHeuristics.isPaginationArtifact(cleaned) {
                // A page number or a (MORE) is furniture of the printed
                // page, and it splits a speech, not a thought: the
                // paragraph under way continues across it — nothing
                // flushes, the kind stands.
                continue
            }
            if Acts.isEndActCard(cleaned) {
                // An act ends where the next one begins: the closing card
                // is furniture (RFC-ACT-BREAK §5), and a hard boundary —
                // the paragraph under way ends here, nothing joins across.
                flush()
                cardOpen = false
                continue
            }
            if let cardInline = PasteHeuristics.titleCardMarker(unstarred) {
                // The marker is the card's meaning, not its text — a hard
                // boundary: the lines it opens print centered, and nothing
                // continues across it.
                flush()
                kind = .action
                if cardInline.isEmpty {
                    cardOpen = true
                    cardHasDate = false
                    cardSawTime = false
                } else {
                    paragraphs.append(Paragraph(text: cardInline, depth: 0, kind: .centered))
                }
                continue
            }
            if cardOpen {
                if PasteHeuristics.isTitleCardDate(unstarred) {
                    paragraphs.append(Paragraph(text: unstarred, depth: 0, kind: .centered))
                    cardHasDate = true
                    continue
                }
                if PasteHeuristics.isTitleCardTime(unstarred) {
                    paragraphs.append(Paragraph(text: unstarred, depth: 0, kind: .centered))
                    cardSawTime = true
                    continue
                }
                // The message slot: open at the marker and under a date —
                // shut after a bare time stamp, where the caps line is the
                // next speaker, not the card's text.
                if PasteHeuristics.isCardMessage(unstarred), cardHasDate || !cardSawTime {
                    paragraphs.append(Paragraph(text: unstarred, depth: 0, kind: .centered))
                    cardOpen = false
                    continue
                }
                cardOpen = false  // the first prose line closes the card
            }
            if PasteHeuristics.looksLikeSceneHeading(cleaned) {
                flush()
                kind = .scene
                current = [unstarred]
            } else if Acts.isActCard(cleaned) {
                // The card is structural, never a speaker — without this
                // tell the cue shape below adopts ACT ONE (RFC-ACT-BREAK §5).
                flush()
                kind = .actbreak
                current = [unstarred]
            } else if PasteHeuristics.looksLikeTransition(upper) {
                flush()
                kind = .transition
                current = [unstarred]
            } else if PasteHeuristics.looksLikeCharacterCue(cleaned, uppercase: upper) {
                flush()
                kind = .character
                current = [unstarred]
            } else if trimmed.hasPrefix("(") {
                flush()
                kind = .parenthetical
                current = [unstarred]
            } else if paragraphs.isEmpty && current.isEmpty {
                kind = .action
                current = [unstarred]
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
                current.append(unstarred)
            }
        }
        flush()
        return paragraphs.isEmpty ? nil : paragraphs
    }
}
