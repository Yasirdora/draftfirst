import Foundation

/// Whether Fountain parsing keeps marker characters in element text or
/// converts them to style runs (TypeScript `FountainParseOptions.emphasis`).
public enum EmphasisMode: Sendable, Equatable {
    case preserve
    case runs
}

/// Mirror of the TypeScript engine's `style.ts` — emphasis, runs-in-model
/// (RFC v2.1). Behaviour is pinned case-for-case by `Fixtures/emphasis.json`,
/// `emphasis-synthesise.json` and `emphasis-roundtrip.json`; the module's
/// doc comment in `style.ts` carries the full grammar and the canonical-form
/// rules, and any change must land in both ports with the corpus regenerated.
///
/// All scanning is UTF-16 code units — the ContentIndex space — matching the
/// TypeScript engine's string offsets and `NSRange` exactly. Flanking uses
/// the JS `\s` set via `JSWhitespace` (U+0085 NEL is NOT whitespace here).
public enum Emphasis {

    public typealias ParseResult = (text: String, runs: [StyleRun])

    /* The JS `\s` probe for one UTF-16 code unit. */
    private static func isWhitespace(_ unit: UInt16?) -> Bool {
        guard let unit else { return false }
        return JSWhitespace.matches(unit: unit)
    }

    /* Markdown's backslash convention: `\` escapes ASCII punctuation only;
       before anything else it is a literal backslash. The set is written as
       a literal so every member stays visible in review. */
    private static let asciiPunctuation: Set<UInt16> = Set(
        Array("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".utf16)
    )

    private static func isASCIIPunctuation(_ unit: UInt16) -> Bool {
        asciiPunctuation.contains(unit)
    }

    /// `[UInt16] → String`, preserving lone surrogates exactly (the pointer-
    /// based initialiser — `String(decoding:as:)` would repair them and
    /// silently shift ContentIndex offsets).
    private static func string(_ units: [UInt16]) -> String {
        String(utf16CodeUnits: units, count: units.count)
    }

    private static func string(_ slice: ArraySlice<UInt16>) -> String {
        string(Array(slice))
    }

    // MARK: - parse

    private enum DelimKind {
        case star, under, tilde

        var marker: UInt16 {
            switch self {
            case .star: return 0x2A   // *
            case .under: return 0x5F  // _
            case .tilde: return 0x7E  // ~
            }
        }
    }

    private struct Piece {
        enum Kind { case text, delim }
        var kind: Kind
        var text: [UInt16] = []        // text pieces, escapes resolved
        var delim: DelimKind = .star
        var rawCount = 0
        var canOpen = false
        var canClose = false
        var closerConsumed = 0
        var openerConsumed = 0
        /// Chars the run contributes to content: the never-consumed middle.
        var literalCount: Int { rawCount - closerConsumed - openerConsumed }
    }

    private struct StyleSpan {
        var opener: Int                // piece indices
        var closer: Int
        var styles: StyleSet
    }

    /// Styles for `consumed` star delimiters (TypeScript `starStyles`).
    private static func starStyles(_ consumed: Int) -> StyleSet {
        if consumed == 2 { return .bold }
        if consumed >= 3 { return [.bold, .italic] }
        return .italic
    }

    /// Parse one line of Fountain content into marker-free text plus
    /// canonical style runs (TypeScript `parseEmphasis`). Per-line by
    /// contract — emphasis never crosses element bounds.
    public static func parse(_ source: String) -> ParseResult {
        let units = Array(source.utf16)
        var pieces: [Piece] = []
        var spans: [StyleSpan] = []

        /* ---- scan: escapes resolved, delimiter runs recognised -------- */
        var buffer: [UInt16] = []
        func flushText() {
            if !buffer.isEmpty {
                pieces.append(Piece(kind: .text, text: buffer))
                buffer = []
            }
        }

        var i = 0
        while i < units.count {
            let unit = units[i]
            if unit == 0x5C, i + 1 < units.count, isASCIIPunctuation(units[i + 1]) {   // \
                buffer.append(units[i + 1])
                i += 2
                continue
            }
            if unit == 0x2A || unit == 0x5F || unit == 0x7E {                          // * _ ~
                var end = i + 1
                while end < units.count, units[end] == unit { end += 1 }
                let count = end - i
                let isDelim = unit == 0x2A ? count <= 3 : unit == 0x5F ? count == 1 : count == 2
                if isDelim {
                    flushText()
                    pieces.append(Piece(
                        kind: .delim,
                        delim: unit == 0x2A ? .star : unit == 0x5F ? .under : .tilde,
                        rawCount: count,
                        /* Flanking reads the raw source neighbours; escapes
                           cannot hide whitespace (`\` escapes punctuation only). */
                        canOpen: !isWhitespace(end < units.count ? units[end] : nil),
                        canClose: !isWhitespace(i > 0 ? units[i - 1] : nil)
                    ))
                } else {
                    buffer.append(contentsOf: units[i..<end])
                }
                i = end
                continue
            }
            buffer.append(unit)
            i += 1
        }
        flushText()

        /* ---- match: a closing run pairs with the nearest open run of its
           kind, consuming leftmost-closer against rightmost-opener ------- */
        var openStack: [Int] = []   // piece indices
        for pieceIndex in pieces.indices where pieces[pieceIndex].kind == .delim {
            if pieces[pieceIndex].canClose {
                while pieces[pieceIndex].closerConsumed < pieces[pieceIndex].rawCount {
                    var openerIndex: Int?
                    for stackIndex in openStack.indices.reversed() {
                        let candidate = openStack[stackIndex]
                        if pieces[candidate].delim == pieces[pieceIndex].delim,
                           pieces[candidate].canOpen,
                           pieces[candidate].openerConsumed < pieces[candidate].rawCount {
                            openerIndex = candidate
                            break
                        }
                    }
                    guard let opener = openerIndex else { break }
                    let use: Int
                    if pieces[pieceIndex].delim == .star {
                        use = min(
                            pieces[opener].rawCount - pieces[opener].openerConsumed,
                            pieces[pieceIndex].rawCount - pieces[pieceIndex].closerConsumed
                        )
                    } else {
                        use = pieces[pieceIndex].rawCount   // under/tilde consume whole
                    }
                    pieces[opener].openerConsumed += use
                    pieces[pieceIndex].closerConsumed += use
                    let styles: StyleSet
                    switch pieces[pieceIndex].delim {
                    case .star: styles = starStyles(use)
                    case .under: styles = .underline
                    case .tilde: styles = .strikeout
                    }
                    spans.append(StyleSpan(opener: opener, closer: pieceIndex, styles: styles))
                }
            }
            /* Leftover that cannot close: opens if it may, else literal. */
            let piece = pieces[pieceIndex]
            if piece.closerConsumed + piece.openerConsumed < piece.rawCount, piece.canOpen {
                openStack.append(pieceIndex)
            }
        }

        /* ---- assemble: content string, then spans in content
           coordinates. A run's chars order as [closer-consumed][literal
           middle][opener-consumed]; only the literal middle reaches
           content. */
        var pieceStart = [Int](repeating: 0, count: pieces.count)
        var content: [UInt16] = []
        for (index, piece) in pieces.enumerated() {
            pieceStart[index] = content.count
            switch piece.kind {
            case .text:
                content.append(contentsOf: piece.text)
            case .delim:
                content.append(contentsOf: [UInt16](
                    repeating: piece.delim.marker, count: piece.literalCount
                ))
            }
        }

        var runs: [StyleRun] = []
        for span in spans {
            let start = pieceStart[span.opener] + pieces[span.opener].literalCount
            let end = pieceStart[span.closer]
            if end > start {
                runs.append(StyleRun(start: start, end: end, styles: span.styles))
            }
        }

        return (string(content), normalise(runs, textLength: content.count))
    }

    // MARK: - normalise

    /// Bring runs to canonical form (TypeScript `normaliseRuns`): clamp to
    /// the text, drop empties, split overlaps into union segments, merge
    /// adjacent runs whose every property is equal. Deterministic under
    /// conflict: where covering runs disagree on `revisionID`, the
    /// earliest-starting run wins (styles and tagNumbers union).
    public static func normalise(_ runs: [StyleRun], textLength: Int) -> [StyleRun] {
        let clamped = runs
            .map { run in
                var run = run
                run.start = max(0, run.start)
                run.end = min(textLength, run.end)
                return run
            }
            .filter { $0.end > $0.start }
        if clamped.isEmpty { return [] }

        var boundaries = Set<Int>()
        for run in clamped {
            boundaries.insert(run.start)
            boundaries.insert(run.end)
        }
        let points = boundaries.sorted()

        var out: [StyleRun] = []
        for boundary in 0..<(points.count - 1) {
            let start = points[boundary]
            let end = points[boundary + 1]
            let covering = clamped
                .filter { $0.start <= start && $0.end >= end }
                .sorted { $0.start < $1.start }
            if covering.isEmpty { continue }

            var styles: StyleSet = []
            var tagNumbers = Set<Int>()
            for run in covering {
                styles.formUnion(run.styles)
                tagNumbers.formUnion(run.tagNumbers ?? [])
            }
            let revisionID = covering.first(where: { $0.revisionID != nil })?.revisionID
            let tags = tagNumbers.sorted()

            if styles.isEmpty, tags.isEmpty, revisionID == nil { continue }
            let candidate = StyleRun(
                start: start, end: end, styles: styles,
                revisionID: revisionID, tagNumbers: tags.isEmpty ? nil : tags
            )

            let last = out.last
            if let last, last.end == start, last.styles == candidate.styles,
               last.revisionID == candidate.revisionID,
               last.tagNumbers ?? [] == candidate.tagNumbers ?? [] {
                out[out.count - 1].end = end
            } else {
                out.append(candidate)
            }
        }
        return out
    }

    // MARK: - synthesise

    /// Marker per single-token style (TypeScript `MARKER`); allCaps and
    /// hiddenText have no Fountain spelling and emit nothing.
    private static func marker(of style: StyleSet) -> String {
        switch style {
        case .bold: return "**"
        case .italic: return "*"
        case .underline: return "_"
        case .strikeout: return "~~"
        default: return ""
        }
    }

    /// Canonical token order, outermost-first (TypeScript `sortStyles`).
    private static func sortedTokens(_ set: StyleSet) -> [StyleSet] {
        var out: [StyleSet] = []
        if set.contains(.bold) { out.append(.bold) }
        if set.contains(.italic) { out.append(.italic) }
        if set.contains(.underline) { out.append(.underline) }
        if set.contains(.strikeout) { out.append(.strikeout) }
        if set.contains(.allCaps) { out.append(.allCaps) }
        if set.contains(.hiddenText) { out.append(.hiddenText) }
        return out
    }

    /// Escape content characters that would re-parse as markup (TypeScript
    /// `escapeFountainContent`): backslash first, then every `*` and `_`,
    /// then every tilde in a run of two or more.
    public static func escapeContent(_ source: String) -> String {
        let units = Array(source.utf16)
        var out: [UInt16] = []
        out.reserveCapacity(units.count)
        var i = 0
        while i < units.count {
            let unit = units[i]
            switch unit {
            case 0x5C:   // \
                out.append(contentsOf: [0x5C, 0x5C])
                i += 1
            case 0x2A:   // *
                out.append(contentsOf: [0x5C, 0x2A])
                i += 1
            case 0x5F:   // _
                out.append(contentsOf: [0x5C, 0x5F])
                i += 1
            case 0x7E:   // ~ — escaped only in runs of two or more
                var end = i + 1
                while end < units.count, units[end] == 0x7E { end += 1 }
                if end - i >= 2 {
                    for _ in i..<end { out.append(contentsOf: [0x5C, 0x7E]) }
                } else {
                    out.append(0x7E)
                }
                i = end
            default:
                out.append(unit)
                i += 1
            }
        }
        return string(out)
    }

    private struct Zone {
        var start: Int
        var end: Int
        var styles: StyleSet
    }

    /// Emit canonical Fountain source for marker-free content plus runs
    /// (TypeScript `synthesiseEmphasis`). Event-based over style-set changes:
    /// a style shared by adjacent segments stays open across the boundary;
    /// closed styles pop innermost-first, new styles open outermost-first in
    /// canonical order, so the marker stream always nests properly. Marker
    /// coverage tightens past boundary whitespace (flanking cannot hug it —
    /// a recorded Fountain-boundary loss).
    public static func synthesise(_ text: String, _ runs: [StyleRun]) -> String {
        let units = Array(text.utf16)
        let canonical = normalise(runs, textLength: units.count)

        /* Zones: run segments plus the plain gaps between them. */
        var zones: [Zone] = []
        func pushZone(_ start: Int, _ end: Int, _ styles: StyleSet) {
            if end > start { zones.append(Zone(start: start, end: end, styles: styles)) }
        }
        var pos = 0
        for run in canonical {
            pushZone(pos, run.start, [])
            pushZone(run.start, run.end, run.styles)
            pos = run.end
        }
        pushZone(pos, units.count, [])

        func escape(_ start: Int, _ end: Int) -> String {
            escapeContent(string(units[start..<end]))
        }

        var out = ""
        var active: [StyleSet] = []   // the marker stack, outermost-first
        var pendingWhitespace = ""
        for zone in zones {
            var coreStart = zone.start
            var coreEnd = zone.end
            while coreStart < coreEnd, isWhitespace(units[coreStart]) { coreStart += 1 }
            while coreEnd > coreStart, isWhitespace(units[coreEnd - 1]) { coreEnd -= 1 }
            /* An all-whitespace styled zone opens no markers at all. */
            let styles = !zone.styles.isEmpty && coreStart == coreEnd ? StyleSet() : zone.styles

            /* Longest prefix of the active stack whose styles continue —
               everything above it closes, innermost first. */
            var kept = 0
            while kept < active.count, sortedTokens(styles).contains(active[kept]) { kept += 1 }
            for i in stride(from: active.count - 1, through: kept, by: -1) {
                out += marker(of: active[i])
            }
            out += pendingWhitespace
            pendingWhitespace = ""
            if !styles.isEmpty { out += escape(zone.start, coreStart) }

            /* New styles open on top, outermost-first in canonical order. */
            let keptStyles = Set(active.prefix(kept))
            let opening = sortedTokens(styles).filter { !keptStyles.contains($0) }
            for style in opening { out += marker(of: style) }
            active = Array(active.prefix(kept)) + opening

            if !styles.isEmpty {
                out += escape(coreStart, coreEnd)
                pendingWhitespace = escape(coreEnd, zone.end)
            } else {
                out += escape(zone.start, zone.end)
            }
        }
        for i in stride(from: active.count - 1, through: 0, by: -1) {
            out += marker(of: active[i])
        }
        out += pendingWhitespace
        return out
    }
}
