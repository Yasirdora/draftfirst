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
        /// Where the run begins in the raw source — liveCollapse needs raw
        /// coordinates to remove exactly the markers it paired.
        var rawStart = 0
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

    /// Scan source into text/delimiter pieces: escapes resolved, delimiter
    /// runs recognised, flanking judged from raw neighbours.
    private static func scan(_ units: [UInt16]) -> [Piece] {
        var pieces: [Piece] = []

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
                        rawStart: i,
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
        return pieces
    }

    /// Match spans: a closing run pairs with the nearest open run of its
    /// kind, consuming leftmost-closer against rightmost-opener.
    private static func match(_ pieces: inout [Piece]) -> [StyleSpan] {
        var spans: [StyleSpan] = []
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
        return spans
    }

    /// Parse one line of Fountain content into marker-free text plus
    /// canonical style runs (TypeScript `parseEmphasis`). Per-line by
    /// contract — emphasis never crosses element bounds.
    public static func parse(_ source: String) -> ParseResult {
        let units = Array(source.utf16)
        var pieces = scan(units)
        let spans = match(&pieces)

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
            /* One color per point: where covering runs disagree, the
               earliest-starting wins — the revisionID rule
               (RFC HIGHLIGHTER §2). */
            let highlight = covering.first(where: { $0.highlight != nil })?.highlight

            if styles.isEmpty, tags.isEmpty, revisionID == nil, highlight == nil { continue }
            let candidate = StyleRun(
                start: start, end: end, styles: styles,
                revisionID: revisionID, tagNumbers: tags.isEmpty ? nil : tags,
                highlight: highlight
            )

            let last = out.last
            if let last, last.end == start, last.styles == candidate.styles,
               last.revisionID == candidate.revisionID,
               last.tagNumbers ?? [] == candidate.tagNumbers ?? [],
               last.highlight == candidate.highlight {
                out[out.count - 1].end = end
            } else {
                out.append(candidate)
            }
        }
        return out
    }

    // MARK: - edit arithmetic (RFC v2.1 §4 — runs under typing)

    /// Re-seat runs after an element-local edit (TypeScript
    /// `propagateRuns`): `replaced` (old coordinates) was swapped for
    /// `insertedLength` new characters, yielding a text of `newLength`.
    ///
    /// Deleted text takes its runs with it; text after the edit shifts.
    /// Inserted characters inherit their donor per the platform's own rule
    /// (§4), so the model and the text view cannot disagree: the character
    /// before the insertion point, or — at content position 0 — the
    /// character after it. The donor's whole property set transfers, and
    /// normalisation merges the new span back into the donor run when they
    /// abut: "typing extends the bold run".
    ///
    /// Precondition: `runs` are canonical over the pre-edit text.
    public static func propagate(
        _ runs: [StyleRun],
        replacing replaced: (start: Int, end: Int),
        insertedLength: Int,
        newLength: Int
    ) -> [StyleRun] {
        let (start, end) = replaced
        let delta = insertedLength - (end - start)
        let canonical = normalise(runs, textLength: Int.max)

        let donor = start > 0
            ? canonical.first(where: { $0.start <= start - 1 && start - 1 < $0.end })
            : canonical.first(where: { $0.start <= end && end < $0.end })

        var out: [StyleRun] = []
        for run in canonical {
            if run.start < start {
                var before = run
                before.end = min(run.end, start)
                out.append(before)
            }
            if run.end > end {
                var after = run
                after.start = max(run.start, end) + delta
                after.end = run.end + delta
                out.append(after)
            }
        }
        if insertedLength > 0, let donor {
            out.append(StyleRun(
                start: start, end: start + insertedLength, styles: donor.styles,
                revisionID: donor.revisionID, tagNumbers: donor.tagNumbers,
                highlight: donor.highlight
            ))
        }
        return normalise(out, textLength: newLength)
    }

    /// The runs' coverage of `range`, rebased to 0 (TypeScript `sliceRuns`)
    /// — the planner's head/tail extraction when an element splits.
    /// Precondition: canonical.
    public static func slice(_ runs: [StyleRun], _ range: Range<Int>) -> [StyleRun] {
        runs.compactMap { run in
            let start = max(run.start, range.lowerBound)
            let end = min(run.end, range.upperBound)
            guard end > start else { return nil }
            var sliced = run
            sliced.start = start - range.lowerBound
            sliced.end = end - range.lowerBound
            return sliced
        }
    }

    /// Whether every offset in `[start, end)` carries `style` (TypeScript
    /// `styleCovered`) — the format bar's toggle decision and active-state
    /// query. Empty ranges cover nothing. Precondition: canonical runs.
    public static func isCovered(
        _ runs: [StyleRun],
        from start: Int,
        to end: Int,
        style: StyleSet
    ) -> Bool {
        guard end > start else { return false }
        var cursor = start
        for run in runs {
            if run.end <= start { continue }
            if run.start >= end { break }
            if run.start > cursor { return false }   // a gap inside the range
            if !run.styles.contains(style) { return false }
            cursor = max(cursor, run.end)
            if cursor >= end { return true }
        }
        return cursor >= end
    }

    /// The format bar's verb (TypeScript `toggleStyle`). Fully covered takes
    /// the style off (a run left with no styles but a revisionID or
    /// tagNumbers survives — it is still a run); otherwise the style is
    /// overlaid on the whole range and normalisation unions it with whatever
    /// was there. Precondition: canonical.
    public static func toggle(
        _ runs: [StyleRun],
        from start: Int,
        to end: Int,
        style: StyleSet,
        textLength: Int
    ) -> [StyleRun] {
        let canonical = normalise(runs, textLength: textLength)
        guard end > start else { return canonical }

        guard isCovered(canonical, from: start, to: end, style: style) else {
            return normalise(
                canonical + [StyleRun(start: start, end: end, styles: style)],
                textLength: textLength
            )
        }

        var out: [StyleRun] = []
        for run in canonical {
            if run.end <= start || run.start >= end {
                out.append(run)
                continue
            }
            if run.start < start {
                var before = run
                before.end = start
                out.append(before)
            }
            var inner = run
            inner.start = max(run.start, start)
            inner.end = min(run.end, end)
            inner.styles.subtract(style)
            if inner.end > inner.start,
               !inner.styles.isEmpty || inner.revisionID != nil
                   || !(inner.tagNumbers ?? []).isEmpty || inner.highlight != nil {
                out.append(inner)
            }
            if run.end > end {
                var after = run
                after.start = end
                out.append(after)
            }
        }
        return normalise(out, textLength: textLength)
    }

    // MARK: - the attention mark (docs/RFC-HIGHLIGHTER.md)

    /// Whether the range is fully covered by the mark — the toggle's one
    /// decision per selection: fully covered takes it off.
    public static func highlightCovered(
        _ runs: [StyleRun], from start: Int, to end: Int
    ) -> Bool {
        guard end > start else { return false }
        var cursor = start
        for run in runs where run.highlight != nil {
            if run.start > cursor { return false }
            cursor = max(cursor, run.end)
            if cursor >= end { return true }
        }
        return false
    }

    /// Apply the mark over the range, or clear it when `color` is nil.
    /// One color per point: an apply clears first and then sets, so a
    /// marked span never carries two. A run left with no styles,
    /// revision, tags or highlight is destroyed — the empty-run rule the
    /// styles live by.
    public static func toggleHighlight(
        _ runs: [StyleRun],
        from start: Int, to end: Int,
        color: HighlightColor?,
        textLength: Int
    ) -> [StyleRun] {
        let canonical = normalise(runs, textLength: textLength)
        guard end > start else { return canonical }

        var cleared: [StyleRun] = []
        for run in canonical {
            if run.end <= start || run.start >= end {
                cleared.append(run)
                continue
            }
            if run.start < start {
                var before = run
                before.end = start
                cleared.append(before)
            }
            var inner = run
            inner.start = max(run.start, start)
            inner.end = min(run.end, end)
            inner.highlight = nil
            if inner.end > inner.start,
               !inner.styles.isEmpty || inner.revisionID != nil
                   || !(inner.tagNumbers ?? []).isEmpty {
                cleared.append(inner)
            }
            if run.end > end {
                var after = run
                after.start = end
                cleared.append(after)
            }
        }
        guard let color else { return normalise(cleared, textLength: textLength) }
        return normalise(
            cleared + [StyleRun(start: start, end: end, styles: [], highlight: color)],
            textLength: textLength
        )
    }

    // MARK: - live collapse (RFC v2.1 §3.3 — D6, an input transformation)

    public struct CollapseResult: Equatable, Sendable {
        /// The line with the paired markers removed — all other text,
        /// including any other delimiter characters, is verbatim.
        public let text: String
        /// The styled span the pair became, in the new text's coordinates.
        public let run: StyleRun
        /// The raw ranges removed from the input, ascending — the surface
        /// propagates the element's pre-existing runs through these
        /// deletions.
        public let removed: [RemovedSpan]
        /// Where the caret belongs afterwards: the end of the styled span.
        public let caret: Int

        public struct RemovedSpan: Equatable, Sendable {
            public let start: Int
            public let end: Int
            public init(start: Int, end: Int) {
                self.start = start
                self.end = end
            }
        }
    }

    /// The typed character at `insertedAt` may complete a marker pair
    /// (TypeScript `liveCollapse`). If it is part of a closing delimiter
    /// that pairs — and the pair's delimiters serve no other span — the
    /// markers collapse into a style run and cease to exist as text.
    /// Otherwise nil: the character is literal and the edit proceeds
    /// untouched.
    ///
    /// Sole-consumer restriction, deliberately: delimiter runs shared
    /// between spans (`*a**b*`-style soup, reachable only from pasted marker
    /// text) are left for the writer to see rather than half-converted by a
    /// convenience. Whole delimiters only: a half-consumed `**` — the
    /// grammar's literal-middle answer to `**word*` — would italicise the
    /// word the moment the first closer key arrives, and typing `**word**`
    /// would end italic, never bold. At the keyboard a pair waits for its
    /// full delimiter or does not happen. Collapse is an input
    /// transformation, never a parser second-guess.
    public static func liveCollapse(_ text: String, insertedAt: Int) -> CollapseResult? {
        let units = Array(text.utf16)
        var pieces = scan(units)
        let spans = match(&pieces)

        for span in spans {
            let opener = pieces[span.opener]
            let closer = pieces[span.closer]
            /* The typed character must be one of the closer's consumed
               chars — they are the run's leftmost. */
            guard insertedAt >= closer.rawStart,
                  insertedAt < closer.rawStart + closer.closerConsumed else { continue }
            /* Sole consumers only: a piece serving another span stays
               literal. (A span always shares its own pieces with itself —
               look for a DIFFERENT span holding one.) */
            let sharedByAnother = spans.contains { other in
                !(other.opener == span.opener && other.closer == span.closer) &&
                    (other.opener == span.opener || other.opener == span.closer ||
                        other.closer == span.opener || other.closer == span.closer)
            }
            if sharedByAnother { continue }
            guard opener.rawCount == opener.openerConsumed,
                  closer.rawCount == closer.closerConsumed else { continue }

            /* Consumed chars: an opener's are its rightmost, a closer's its
               leftmost — and the whole-delimiter rule above means there is
               no surviving literal middle. */
            let openerLiteral = opener.rawCount - opener.openerConsumed
            let removedOpener = CollapseResult.RemovedSpan(
                start: opener.rawStart + openerLiteral,
                end: opener.rawStart + opener.rawCount
            )
            let removedCloser = CollapseResult.RemovedSpan(
                start: closer.rawStart,
                end: closer.rawStart + closer.closerConsumed
            )

            let start = opener.rawStart + openerLiteral
            let end = start + (closer.rawStart - (opener.rawStart + opener.rawCount))
            /* An empty match styles nothing — the markers stay literal. */
            guard end > start else { continue }

            let collapsed: [UInt16] =
                Array(units[0..<removedOpener.start]) +
                Array(units[removedOpener.end..<removedCloser.start]) +
                Array(units[removedCloser.end...])
            return CollapseResult(
                text: string(collapsed),
                run: StyleRun(start: start, end: end, styles: span.styles),
                removed: [removedOpener, removedCloser],
                caret: end
            )
        }
        return nil
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
