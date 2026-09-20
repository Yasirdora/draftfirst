import Foundation

/// Errors thrown by `Fountain.parse`.
public enum FountainParseError: Error, Equatable, Sendable {
    /// Source exceeded the configured `maxSourceCharacters` limit
    /// (TypeScript `FOUNTAIN_SOURCE_LIMIT_EXCEEDED`).
    case sourceLimitExceeded(limit: Int, actual: Int)
    /// `maxSourceCharacters` was not a positive integer.
    case invalidLimit(Int)
}

/// Fountain (fountain.io) authoring-format I/O — the wire format of the
/// `.draft` document. This parser implements the same authoring subset as the
/// TypeScript engine's `parse.ts`; behaviour is pinned line-for-line by
/// `Fixtures/parse.json`.
public enum Fountain {

    public static let defaultMaxSourceCharacters = 16 * 1024 * 1024

    // MARK: - Title page

    /// `TITLE_KEY` = `/^([A-Za-z][A-Za-z0-9 '&./_-]*):[ \t]*(.*)$/`
    private static let titleKeyCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 '&./_-"
    )

    private static func matchTitleKey(_ line: String) -> (key: String, value: String)? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon]
        guard let first = key.first, first.isASCII, first.isLetter else { return nil }
        guard key.dropFirst().unicodeScalars.allSatisfy({ titleKeyCharacters.contains($0) }) else {
            return nil
        }
        var value = line[line.index(after: colon)...]
        while value.first == " " || value.first == "\t" { value = value.dropFirst() }
        return (String(key), String(value))
    }

    /// Keys that unambiguously open a title page on their own.
    private static let knownTitleKeys: Set<String> = [
        "title", "credit", "author", "authors", "written by", "source",
        "contact", "address", "draft", "draft date", "date", "revision",
        "copyright",
    ]

    /// `/^\s+\S/` — leading whitespace followed by a non-whitespace char.
    private static func isIndentedContinuation(_ line: String) -> Bool {
        var sawWhitespace = false
        for char in line {
            if char.isWhitespace {
                sawWhitespace = true
            } else {
                return sawWhitespace
            }
        }
        return false
    }

    private static func parseTitlePage(_ lines: [String]) -> (entries: [TitlePage.LegacyEntry], consumed: Int) {
        var entries: [TitlePage.LegacyEntry] = []
        var i = 0
        while i < lines.count && lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            i += 1
        }
        if i >= lines.count { return ([], i) }

        let firstTrimmed = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
        guard matchTitleKey(lines[i]) != nil, !FountainDetect.isTransition(firstTrimmed) else {
            return ([], 0)
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                i += 1
                break
            }
            if let match = matchTitleKey(line), line.first?.isWhitespace == false {
                let value = match.value.trimmingCharacters(in: .whitespacesAndNewlines)
                entries.append(TitlePage.LegacyEntry(
                    key: match.key.trimmingCharacters(in: .whitespacesAndNewlines),
                    values: value.isEmpty ? [] : [value]
                ))
                i += 1
                continue
            }
            if isIndentedContinuation(line), !entries.isEmpty {
                entries[entries.count - 1].values.append(trimmed)
                i += 1
                continue
            }
            break
        }

        /* One key alone is metadata only when the key is a known one —
           otherwise `FADE IN:` would be eaten as metadata. */
        if entries.count == 1 && !knownTitleKeys.contains(entries[0].key.lowercased()) {
            return ([], 0)
        }
        return (entries, i)
    }

    // MARK: - Boneyard + notes

    /// Remove boneyard `/* … */` blocks entirely (JS `/\/\*[\s\S]*?\*\//g`):
    /// each opener pairs with the next closer. The regex needs a closing
    /// `*/` to match at all, so an unclosed `/*` stays verbatim.
    private static func stripBoneyard(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        var cursor = text.startIndex
        while let open = text.range(of: "/*", range: cursor..<text.endIndex) {
            result += text[cursor..<open.lowerBound]
            guard let close = text.range(of: "*/", range: open.upperBound..<text.endIndex) else {
                result += text[open.lowerBound...]
                return result
            }
            cursor = close.upperBound
        }
        result += text[cursor...]
        return result
    }

    /// A note may cross a normal line ending, but not a genuinely empty line
    /// (two spaces are Fountain's explicit connected blank line syntax).
    private static func hasNoteCloseBeforeParagraphBreak(
        lines: [String],
        startLine: Int,
        startColumn: String.Index
    ) -> Bool {
        for lineIndex in startLine..<lines.count {
            let line = lines[lineIndex]
            let from = lineIndex == startLine ? startColumn : line.startIndex
            if line.range(of: "]]", range: from..<line.endIndex) != nil { return true }
            let expandedWidth = line.replacingOccurrences(of: "\t", with: "    ").utf16.count
            if lineIndex > startLine
                && line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && expandedWidth < 2 {
                return false
            }
        }
        return false
    }

    private struct LogicalLine {
        var text: String
        var notes: [String]
    }

    /// A note's text as the writer wrote it: `] ]` is the serialiser's
    /// spelling of `]]`, which inside a note would close it. Lossy by choice,
    /// one way: a note whose own text holds `] ]` comes back as `]]`
    /// (RFC-NOTES-SYSTEM §13).
    private static func noteText(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\] (?=\\])", with: "]", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Split into lines, extracting `[[ notes ]]` (which may span lines).
    /// Standalone notes become their own note lines; inline notes are lifted
    /// out of the surrounding text.
    private static func logicalLines(_ raw: String) -> [LogicalLine] {
        var out: [LogicalLine] = []
        var inNote = false
        var noteBuf = ""
        /* JS `split("\n")` operates on code units, so CRLF files split at the
           LF and keep a trailing CR (cleaned below). Swift's Character split
           cannot express that: "\r\n" is ONE grapheme cluster, so a Windows
           file would collapse into a single line. `components(separatedBy:)`
           matches JS exactly. */
        let lines = raw.components(separatedBy: "\n").map { line -> String in
            var line = line
            if line.hasSuffix("\r") { line.removeLast() }
            return line
        }

        for lineIndex in lines.indices {
            let line = lines[lineIndex]
            var notes: [String] = []
            var rebuilt = ""

            var i = line.startIndex
            while i < line.endIndex {
                let char = line[i]
                let next = line.index(after: i)
                if inNote {
                    if char == "]", next < line.endIndex, line[next] == "]" {
                        /* A run of `]` closes the note at its end; the ones
                           before the last two are its text. The writer before
                           IL-0038 put `]]]` on disk for a note ending in `]`,
                           and only that. */
                        var end = line.index(after: next)
                        while end < line.endIndex, line[end] == "]" { end = line.index(after: end) }
                        noteBuf += line[i..<line.index(end, offsetBy: -2)]
                        notes.append(noteText(noteBuf))
                        noteBuf = ""
                        inNote = false
                        i = end
                    } else {
                        noteBuf.append(char)
                        i = next
                    }
                    continue
                }
                if char == "[", next < line.endIndex, line[next] == "[",
                   hasNoteCloseBeforeParagraphBreak(
                       lines: lines, startLine: lineIndex, startColumn: line.index(after: next)
                   ) {
                    inNote = true
                    noteBuf = ""
                    i = line.index(after: next)
                    continue
                }
                rebuilt.append(char)
                i = next
            }
            if inNote { noteBuf.append("\n") }

            out.append(LogicalLine(text: rebuilt, notes: notes))
        }
        return out
    }

    // MARK: - Element helpers

    /// `SCENE_NUMBER` = `/#([^#]+)#\s*$/` — strip a trailing `#12#`.
    private static func splitSceneNumber(_ text: String) -> (text: String, sceneNumber: String?) {
        var end = text.endIndex
        while end > text.startIndex, text[text.index(before: end)].isWhitespace {
            end = text.index(before: end)
        }
        guard end > text.startIndex, text[text.index(before: end)] == "#" else {
            return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        let closingHash = text.index(before: end)
        /* `[^#]+` cannot contain a `#`, so ONLY the nearest preceding `#` can
           open the number. If its interior is empty the regex fails outright —
           continuing to walk left would capture a `#` and diverge:
           `INT. HOUSE #1##` has no scene number in JS, but a longer walk
           would report "1#". */
        var cursor = closingHash
        while cursor > text.startIndex {
            cursor = text.index(before: cursor)
            guard text[cursor] == "#" else { continue }
            let interior = text[text.index(after: cursor)..<closingHash]
            guard !interior.isEmpty else { break }
            /* JS `sceneNumber ? { sceneNumber } : undefined` — an all-blank
               interior trims to "", which is falsy, so the key is absent
               rather than empty. `.SCENE #  #` must stay a round-trip fixed
               point. */
            let number = interior.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                String(text[..<cursor]).trimmingCharacters(in: .whitespacesAndNewlines),
                number.isEmpty ? nil : number
            )
        }
        return (text.trimmingCharacters(in: .whitespacesAndNewlines), nil)
    }

    /// A trailing `^` marks dual dialogue; strip and report it.
    private static func splitDual(_ text: String) -> (text: String, dual: Bool) {
        if text.hasSuffix("^") {
            return (
                String(text.dropLast()).trimmingCharacters(in: .whitespacesAndNewlines),
                true
            )
        }
        return (text, false)
    }

    /// `CENTERED` = `/^>\s*(.+?)\s*<$/`, disabled by the serializer's `\<`
    /// escape for forced transitions ending in a literal `<`.
    private static func centeredMatch(_ text: String) -> String? {
        if text.hasSuffix("\\<") { return nil }
        guard text.hasPrefix(">"), text.hasSuffix("<"), text.count >= 2 else { return nil }
        /* Everything between the anchors. `<$` pins the CLOSING bracket to the
           final character, so take it directly — stripping leading whitespace
           first (as this used to) makes `raw` empty exactly when `capture` is,
           which left the all-whitespace branch below unreachable. */
        let inner = text.dropFirst().dropLast()
        guard !inner.isEmpty else { return nil }   // `.+?` needs one character

        var capture = inner
        while capture.first?.isJSWhitespace == true { capture = capture.dropFirst() }
        while capture.last?.isJSWhitespace == true { capture = capture.dropLast() }
        if !capture.isEmpty { return String(capture) }

        /* All whitespace: the leading `\s*` is greedy, then backtracks exactly
           one character so `.+?` has something to match — so the capture is
           the LAST character of the run. `>  <` captures " "; `>  \t<`
           captures "\t". */
        return String(inner.suffix(1))
    }

    /// `unescapeForcedTransition`: trailing `\<` becomes a literal `<`.
    private static func unescapeForcedTransition(_ text: String) -> String {
        text.hasSuffix("\\<") ? String(text.dropLast(2)) + "<" : text
    }

    /// `isIntentionalDialogueBlank`: a two-space (or tab-expanded) blank line
    /// inside a dialogue block intentionally continues the dialogue.
    private static func isIntentionalDialogueBlank(_ raw: String, inDialogue: Bool) -> Bool {
        guard inDialogue, !raw.isEmpty, raw.allSatisfy({ $0 == " " || $0 == "\t" }) else {
            return false
        }
        return FountainDetect.expandTabs(raw).utf16.count >= 2
    }

    // MARK: - Main parse

    /// Parse Fountain source into a `Screenplay`. Mirrors
    /// `parseFountain(source, options)` in the TypeScript engine.
    ///
    /// `emphasis` defaults to `.preserve` (markers stay in element text —
    /// the historical behaviour); `.runs` converts emphasis to style runs
    /// and marker-free content (RFC v2.1). Transitional: the viewport work
    /// flips the app to `.runs`; the option is removed once no caller
    /// preserves.
    public static func parse(
        _ source: String,
        maxSourceCharacters: Int = defaultMaxSourceCharacters,
        emphasis: EmphasisMode = .preserve
    ) throws -> Screenplay {
        guard maxSourceCharacters > 0 else {
            throw FountainParseError.invalidLimit(maxSourceCharacters)
        }
        guard source.utf16.count <= maxSourceCharacters else {
            throw FountainParseError.sourceLimitExceeded(
                limit: maxSourceCharacters, actual: source.utf16.count
            )
        }

        let cleaned = stripBoneyard(source)
        let logical = logicalLines(cleaned)
        let rawLines = logical.map(\.text)
        let (entries, consumed) = parseTitlePage(rawLines)

        var elements: [ScreenplayElement] = []
        /* Emphasis is parsed at the single funnel every element passes
           through, AFTER the type-specific transforms (uppercasing, trims,
           dual carets), so runs always index the final content text. */
        func push(_ type: ElementKind, _ text: String, dual: Bool = false,
                  sceneNumber: String? = nil, depth: Int? = nil, anchor: NoteAnchor? = nil) {
            if emphasis == .runs {
                let parsed = Emphasis.parse(text)
                elements.append(ScreenplayElement(
                    type: type, text: parsed.text,
                    runs: parsed.runs.isEmpty ? nil : parsed.runs,
                    dual: dual ? true : nil,
                    sceneNumber: sceneNumber, depth: depth, anchor: anchor
                ))
            } else {
                elements.append(ScreenplayElement(
                    type: type, text: text,
                    dual: dual ? true : nil,
                    sceneNumber: sceneNumber, depth: depth, anchor: anchor
                ))
            }
        }

        /* Standalone notes captured during line splitting, attached to the
           source line they appeared on. */
        let noteQueue = Array(logical.dropFirst(consumed)).map(\.notes)

        var prev: ElementKind? = nil   // previous *printing/flow* element
        var i = consumed

        /// A character cue is only a cue when dialogue-capable content
        /// follows directly.
        func directDialogueFollower(_ from: Int) -> String? {
            guard from < rawLines.count else { return nil }
            let raw = rawLines[from]
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                return FountainDetect.expandTabs(raw).utf16.count >= 2 ? raw : nil
            }
            if text.allSatisfy({ $0 == "=" }) && text.count >= 3 { return nil }
            for marker: Character in ["#", "=", ">", "~", "!", "@"] where text.hasPrefix(String(marker)) {
                return nil
            }
            if FountainDetect.hasForcedSceneMarker(text) { return nil }
            return text
        }

        while i < rawLines.count {
            let notes = (i - consumed) < noteQueue.count ? noteQueue[i - consumed] : []
            for note in notes {
                /* A header line this stage owns is the note's anchor, not
                   its words (RFC-NOTES-SYSTEM §4.1, §5.2). Taken off before
                   the emphasis pass, so a quoted `on:` is never read as
                   markup. */
                if let header = NoteAnchor.readHeader(note) {
                    push(.note, header.body, anchor: header.anchor)
                } else {
                    push(.note, note)
                }
            }

            let raw = rawLines[i]
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let inDialogue = prev == .character || prev == .parenthetical || prev == .dialogue
            let blankBefore = i == consumed
                || rawLines[i - 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let blankAfter = i == rawLines.count - 1
                || rawLines[i + 1].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            /* Two spaces on an otherwise empty line intentionally continue Dialogue. */
            if isIntentionalDialogueBlank(raw, inDialogue: inDialogue) {
                push(.dialogue, "")
                prev = .dialogue
                i += 1
                continue
            }

            if line.isEmpty {
                prev = nil
                i += 1
                continue
            }

            /* page break */
            if line.allSatisfy({ $0 == "=" }) && line.count >= 3 {
                push(.pagebreak, "")
                prev = nil
                i += 1
                continue
            }

            /* section */
            if line.hasPrefix("#") {
                let depth = line.prefix(while: { $0 == "#" }).count
                push(.section, String(line.dropFirst(depth))
                    .trimmingCharacters(in: .whitespacesAndNewlines), depth: depth)
                prev = nil
                i += 1
                continue
            }

            /* synopsis (page break handled above) */
            if line.hasPrefix("=") {
                // JS: strip the leading run of '=' and following whitespace.
                let stripped = line.drop(while: { $0 == "=" }).drop(while: { $0.isWhitespace })
                push(.synopsis, String(stripped))
                prev = nil
                i += 1
                continue
            }

            /* centered  > THE END < */
            if let centered = centeredMatch(line) {
                push(.centered, centered)
                prev = .centered
                i += 1
                continue
            }

            /* forced transition  > SMASH CUT TO BLACK. */
            if line.hasPrefix(">") {
                var rest = line.dropFirst()
                while rest.first?.isWhitespace == true { rest = rest.dropFirst() }
                if !rest.isEmpty {
                    push(.transition, unescapeForcedTransition(
                        String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                    prev = .transition
                    i += 1
                    continue
                }
            }

            /* lyrics  ~la la la */
            if line.hasPrefix("~") {
                push(.lyrics, String(line.dropFirst())
                    .trimmingCharacters(in: .whitespacesAndNewlines))
                prev = .lyrics
                i += 1
                continue
            }

            /* forced action  !Molly's Diner */
            if line.hasPrefix("!") {
                /* JS: `expandActionTabs(raw.trimStart().slice(1))` */
                let t = FountainDetect.expandTabs(
                    String(raw.drop(while: { $0.isWhitespace }).dropFirst())
                )
                push(.action, t)
                prev = .action
                i += 1
                continue
            }

            /* forced character  @McCready */
            if line.hasPrefix("@") {
                let (text, dual) = splitDual(String(line.dropFirst())
                    .trimmingCharacters(in: .whitespacesAndNewlines))
                push(.character, text, dual: dual)
                prev = .character
                i += 1
                continue
            }

            /* Only one dot followed by an alphanumeric forces a scene. */
            if FountainDetect.hasForcedSceneMarker(line) {
                let (text, sceneNumber) = splitSceneNumber(String(line.dropFirst()))
                push(.scene, text.uppercased(), sceneNumber: sceneNumber)
                prev = .scene
                i += 1
                continue
            }

            /* Inside a dialogue block, a parenthetical attaches to the
               cue/dialogue; anything else is dialogue text. */
            if inDialogue && line.hasPrefix("(") {
                push(.parenthetical, line)
                prev = .parenthetical
                i += 1
                continue
            }
            if inDialogue {
                push(.dialogue, line)
                prev = .dialogue
                i += 1
                continue
            }

            /* Unforced block types require their Fountain blank-line context. */
            if blankBefore && blankAfter && FountainDetect.isSceneHeading(line) {
                let (text, sceneNumber) = splitSceneNumber(line)
                push(.scene, text.uppercased(), sceneNumber: sceneNumber)
                prev = .scene
                i += 1
                continue
            }

            /* detected transition  CUT TO: / DISSOLVE TO: / FADE IN: */
            if blankBefore && blankAfter
                && (FountainDetect.isTransition(line) || FountainDetect.isFadeOpener(line))
                && FountainDetect.isUpper(line) {
                push(.transition, line)
                prev = .transition
                i += 1
                continue
            }

            /* Character context wins over the native shot extension: POV
               followed directly by speech is a valid Fountain cue. */
            let follower = directDialogueFollower(i + 1)
            if blankBefore && FountainDetect.isUpper(line) && follower != nil {
                let (text, dual) = splitDual(line)
                push(.character, text, dual: dual)
                prev = .character
                i += 1
                continue
            }

            /* Known shot language is an eDraft extension. */
            if FountainDetect.looksLikeShot(line) {
                push(.shot, line)
                prev = .shot
                i += 1
                continue
            }

            push(.action, FountainDetect.expandTabs(raw))
            prev = .action
            i += 1
        }

        /* The keyed entries the source declares become the page's lines —
           the classic renderer's template, frozen as the model (D8). */
        return Screenplay(titlePage: TitlePage.lines(from: entries), elements: elements)
    }
}
