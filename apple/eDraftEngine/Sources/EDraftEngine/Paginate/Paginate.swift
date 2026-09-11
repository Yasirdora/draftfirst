import Foundation

/// Errors thrown by `Paginator.paginate`.
public enum PaginationError: Error, Equatable, Sendable {
    /// `linesPerPage` outside 10…10 000 (TypeScript `RangeError`).
    case invalidLinesPerPage(Int)
    /// Defensive: the paginator could not advance. Unreachable for valid
    /// input; thrown instead of looping forever.
    case cannotProgress
}

/// The type tag carried by a printed line: an element kind, a spacing
/// `blank`, or a generated `(MORE)` marker. Encodes as the element's raw
/// string or `"blank"` / `"more"` to match the TypeScript wire format.
public enum PageLineKind: Equatable, Sendable {
    case element(ElementKind)
    case blank
    case more
}

extension PageLineKind: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "blank": self = .blank
        case "more": self = .more
        default:
            guard let kind = ElementKind(rawValue: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Unknown page line kind: \(raw)"
                )
            }
            self = .element(kind)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .element(let kind): try container.encode(kind.rawValue)
        case .blank: try container.encode("blank")
        case .more: try container.encode("more")
        }
    }
}

public struct PageLine: Codable, Equatable, Sendable {
    public var text: String
    public var type: PageLineKind
    public var indent: Int
    /// Index into `script.elements` for provenance; -1 for generated lines.
    public var element: Int

    public init(text: String, type: PageLineKind, indent: Int, element: Int) {
        self.text = text
        self.type = type
        self.indent = indent
        self.element = element
    }
}

public struct ScriptPage: Codable, Equatable, Sendable {
    public var number: Int
    public var lines: [PageLine]
    /// This page opens mid-scene — print CONTINUED: at the top margin.
    public var continuedTop: Bool
    /// This page ends mid-scene — print (CONTINUED) at the bottom margin.
    public var continuedBottom: Bool

    public init(number: Int, lines: [PageLine], continuedTop: Bool, continuedBottom: Bool) {
        self.number = number
        self.lines = lines
        self.continuedTop = continuedTop
        self.continuedBottom = continuedBottom
    }
}

/// Deterministic screenplay pagination, ported line-for-line from the
/// TypeScript engine's `paginate.ts`. Behaviour is pinned by
/// `Fixtures/paginate.json`.
///
///   · 55 lines per US Letter page (Courier 12pt, 1.5″/1″ margins)
///   · a scene heading never sits alone at a page bottom
///   · a character cue never separates from its dialogue
///   · split dialogue closes with (MORE) and reopens with NAME (CONT'D)
///   · action blocks split with at least 2 lines on each side
///   · scene continuations mark (CONTINUED) / CONTINUED: in the margins
public enum Paginator {

    public static let linesPerPage = 55
    public static let pageWidthChars = 60
    private static let minLinesPerPage = 10
    private static let maxLinesPerPage = 10_000

    public struct Geometry: Equatable, Sendable {
        public let indent: Int
        public let width: Int
        public let before: Int
    }

    /// Element geometry in Courier characters from the left margin.
    public static let geometry: [ElementKind: Geometry] = [
        .scene: Geometry(indent: 0, width: 60, before: 2),
        .action: Geometry(indent: 0, width: 60, before: 1),
        .character: Geometry(indent: 22, width: 38, before: 1),
        .dialogue: Geometry(indent: 10, width: 35, before: 0),
        .parenthetical: Geometry(indent: 16, width: 26, before: 0),
        .transition: Geometry(indent: 0, width: 60, before: 1),
        .shot: Geometry(indent: 0, width: 60, before: 1),
        .general: Geometry(indent: 0, width: 60, before: 1),
        .centered: Geometry(indent: 0, width: 60, before: 1),
        .lyrics: Geometry(indent: 10, width: 35, before: 0),
    ]

    // MARK: - Text wrapping

    /// One wrapped line and where it begins in the original UTF-16.
    ///
    /// The editor's text view is the original string, not the paginator's
    /// printed lines. A page break mid-element has to name a character in
    /// that string, which is this offset — not a search for the printed
    /// text, which can appear twice.
    public struct WrappedLine: Equatable, Sendable {
        public let text: String
        public let utf16Start: Int
    }

    /// Greedy word wrap at `width` characters, hard-splitting tokens that
    /// cannot fit. Measured in UTF-16 code units to match the JS engine's
    /// `String.length` semantics exactly.
    public static func wrapLines(_ text: String, width: Int) -> [WrappedLine] {
        precondition(
            width >= 1 && width <= pageWidthChars,
            "width must be an integer between 1 and \(pageWidthChars)."
        )
        /* Separate in UTF-16 code units, exactly as JS `split(/\s+/)` does.
           A Character-level split cannot express this: `" " + U+0301` is one
           grapheme cluster, so Swift either refuses to break there (wrap points
           drift) or drops the whole cluster (the combining mark is lost). JS
           breaks on the space and keeps the mark as the next word's first unit.
           Empty runs are skipped, matching the TS `.filter((w) => w !== '')`. */
        struct Word {
            let text: String
            let utf16Start: Int
        }
        let units = Array(text.utf16)
        var words: [Word] = []
        var index = 0
        while index < units.count {
            while index < units.count, JSWhitespace.matches(unit: units[index]) {
                index += 1
            }
            guard index < units.count else { break }
            let start = index
            while index < units.count, !JSWhitespace.matches(unit: units[index]) {
                index += 1
            }
            if index - start <= width {
                words.append(Word(
                    text: String(decoding: units[start..<index], as: UTF16.self),
                    utf16Start: start
                ))
            } else {
                /* Hard split. NOTE: a boundary landing between a surrogate pair
                   (dialogue's width of 35 is odd, so this is reachable) yields
                   an unpaired surrogate in JS, which Swift's String cannot
                   represent — `String(decoding:)` substitutes U+FFFD. UTF-16
                   counts still agree, so pagination matches; the glyph does
                   not. Fixing this needs the TS side to stop splitting inside
                   a pair, so it is deliberately left divergent rather than
                   silently forked here. */
                var offset = start
                while offset < index {
                    let end = Swift.min(offset + width, index)
                    words.append(Word(
                        text: String(decoding: units[offset..<end], as: UTF16.self),
                        utf16Start: offset
                    ))
                    offset = end
                }
            }
        }
        guard !words.isEmpty else { return [WrappedLine(text: "", utf16Start: 0)] }

        var lines: [WrappedLine] = []
        var current = words[0].text
        var currentStart = words[0].utf16Start
        var currentLength = current.utf16.count
        for word in words.dropFirst() {
            let wordLength = word.text.utf16.count
            if currentLength + 1 + wordLength <= width {
                current += " " + word.text
                currentLength += 1 + wordLength
            } else {
                lines.append(WrappedLine(text: current, utf16Start: currentStart))
                current = word.text
                currentStart = word.utf16Start
                currentLength = wordLength
            }
        }
        lines.append(WrappedLine(text: current, utf16Start: currentStart))
        return lines
    }

    static func wrapText(_ text: String, width: Int) -> [String] {
        wrapLines(text, width: width).map(\.text)
    }

    private static func alignedIndent(text: String, right: Bool) -> Int {
        let length = text.utf16.count
        if right { return Swift.max(0, pageWidthChars - length) }
        return Swift.max(0, (pageWidthChars - length) / 2)
    }

    // MARK: - Block building

    struct FlowLine {
        var text: String
        var type: ElementKind
        var indent: Int
        var element: Int
    }

    enum BlockKind { case scene, flow, simple }

    struct Block {
        var kind: BlockKind
        var before: Int
        var lines: [FlowLine]
        /// Base cue name for (CONT'D) regeneration — flow blocks only.
        var cueName: String? = nil
        /// Lyrics and cue-less dialogue must never acquire synthetic
        /// dialogue markers.
        var continuationEligible: Bool? = nil
    }

    enum BuildItem {
        case block(Block)
        case pagebreak
    }

    /// character/parenthetical/dialogue plus lyrics (TS `FLOW_TYPES`).
    private static let flowTypes: Set<ElementKind> = [
        .character, .parenthetical, .dialogue, .lyrics,
    ]

    /// Blocks built as the fold consumes them.
    ///
    /// Building the whole document up front was fine while pagination was
    /// always whole-document, but the incremental pass stops at the first
    /// page that matches its cache — and building blocks for the unread
    /// tail cost more than the fold saved: measured 37ms of wrap work per
    /// keystroke after the fold itself had already answered. The source
    /// produces the same stream as eagerly as the fold asks — a flow block
    /// is complete when its successor starts — so an early stop pays for
    /// the pages it read and no more.
    final class BlockSource {
        private let script: Screenplay
        private var index: Int
        private var flow: Block?
        private var buffered: [BuildItem] = []

        init(_ script: Screenplay, startIndex: Int) {
            self.script = script
            self.index = startIndex
        }

        /// The head of the stream, unconsumed — the fold's current block.
        func current() -> BuildItem? {
            fill(1)
            return buffered.first
        }

        /// The block after the head — the scene keep rule's one lookahead.
        func next() -> BuildItem? {
            fill(2)
            return buffered.count > 1 ? buffered[1] : nil
        }

        /// Consume the head.
        func advance() {
            fill(1)
            if !buffered.isEmpty { buffered.removeFirst() }
        }

        private var atEnd: Bool { index >= script.elements.count }

        private func fill(_ count: Int) {
            while buffered.count < count && !atEnd { step() }
            /* End of input completes any open flow block. */
            if atEnd { flushFlow() }
        }

        /* One element in. A block leaves the buffer only when complete: a
           flow block completes when its successor starts (or the document
           ends). */
        private func step() {
            let element = script.elements[index]
            let elementIndex = index
            index += 1

            if element.type == .pagebreak {
                flushFlow()
                buffered.append(.pagebreak)
                return
            }
            guard element.type.isPrinting else { return }

            let geo = Paginator.geometry[element.type] ?? Paginator.geometry[.action]!

            if Paginator.flowTypes.contains(element.type) {
                if element.type == .character || flow == nil {
                    flushFlow()
                    flow = Block(
                        kind: .flow,
                        before: Paginator.geometry[.character]!.before,
                        lines: [],
                        cueName: element.type == .character ? element.text : nil,
                        continuationEligible: element.type == .character
                    )
                }
                if element.type == .lyrics { flow?.continuationEligible = false }
                let wrapped = element.type == .character
                    ? Paginator.wrapText(
                        element.text + (element.dual == true ? " ^" : ""),
                        width: Paginator.geometry[.character]!.width
                      )
                    : Paginator.wrapText(element.text, width: geo.width)
                for text in wrapped {
                    flow?.lines.append(FlowLine(
                        text: text, type: element.type,
                        indent: geo.indent, element: elementIndex
                    ))
                }
                return
            }

            flushFlow()

            if element.type == .transition || element.type == .centered {
                let right = element.type == .transition
                buffered.append(.block(Block(
                    kind: .simple,
                    before: geo.before,
                    lines: Paginator.wrapText(element.text, width: Paginator.pageWidthChars).map { text in
                        FlowLine(
                            text: text, type: element.type,
                            indent: Paginator.alignedIndent(text: text, right: right),
                            element: elementIndex
                        )
                    }
                )))
                return
            }

            buffered.append(.block(Block(
                kind: element.type == .scene ? .scene : .simple,
                before: geo.before,
                lines: Paginator.wrapText(element.text, width: geo.width).map { text in
                    FlowLine(text: text, type: element.type,
                             indent: geo.indent, element: elementIndex)
                }
            )))
        }

        private func flushFlow() {
            if let existing = flow {
                buffered.append(.block(existing))
                flow = nil
            }
        }
    }

    /// The whole stream at once — the benchmark's eager read of the lazy
    /// source. Production paths consume `BlockSource` directly.
    static func buildBlocks(_ script: Screenplay, startIndex: Int = 0) -> [BuildItem] {
        let source = BlockSource(script, startIndex: startIndex)
        var items: [BuildItem] = []
        while let item = source.current() {
            items.append(item)
            source.advance()
        }
        return items
    }

    // MARK: - Pagination

    private static let moreIndent = 10  // GEOMETRY.dialogue.indent

    /// The pagination fold, shared by the full pass and the incremental
    /// one. Everything a page decision reads from the past is in the
    /// arguments: `startNumber` (the page being built) and `current0` (the
    /// lines already on it). `stopAfter` is consulted as each page closes;
    /// the current block still finishes, so a stop never lands mid-block.
    /// The rules are unchanged from the pass the corpus pins — the same
    /// fold, made resumable, not a second paginator.
    private static func runFold(
        _ source: BlockSource,
        limit: Int,
        startNumber: Int,
        current0: [PageLine],
        stopAfter: ((ScriptPage) -> Bool)? = nil
    ) throws -> FoldOutcome {
        guard limit >= minLinesPerPage && limit <= maxLinesPerPage else {
            throw PaginationError.invalidLinesPerPage(limit)
        }

        var pages: [ScriptPage] = []
        var current = current0
        var stoppedAfter = 0

        func newPage(allowEmpty: Bool = false) {
            guard stoppedAfter == 0 else { return }
            if current.isEmpty && !allowEmpty { return }
            let completed = ScriptPage(
                number: startNumber + pages.count, lines: current,
                continuedTop: false, continuedBottom: false
            )
            pages.append(completed)
            current = []
            if stopAfter?(completed) == true { stoppedAfter = completed.number }
        }

        func blanks(_ count: Int, element: Int) {
            for _ in 0..<count {
                current.append(PageLine(text: "", type: .blank, indent: 0, element: element))
            }
        }

        func emit(_ line: FlowLine) {
            current.append(PageLine(
                text: line.text, type: .element(line.type),
                indent: line.indent, element: line.element
            ))
        }

        func emitRange(_ lines: [FlowLine], _ start: Int, _ end: Int) {
            for index in start..<end { emit(lines[index]) }
        }

        func spaceLeft() -> Int { limit - current.count }

        /// Largest honourable chunk: at least two lines here and two left over.
        func splitSize(remaining: Int, capacity: Int) -> Int {
            if capacity < 2 || remaining < 4 { return 0 }
            let take = Swift.min(capacity, remaining - 2)
            return take >= 2 ? take : 0
        }

        func emitSimpleBlock(_ block: Block, _ initialBefore: Int) throws {
            var cursor = 0
            var pre = initialBefore
            while cursor < block.lines.count {
                let remaining = block.lines.count - cursor
                let capacity = spaceLeft() - pre
                if remaining <= capacity {
                    blanks(pre, element: block.lines[cursor].element)
                    emitRange(block.lines, cursor, block.lines.count)
                    return
                }

                let take = splitSize(remaining: remaining, capacity: capacity)
                if take > 0 {
                    blanks(pre, element: block.lines[cursor].element)
                    emitRange(block.lines, cursor, cursor + take)
                    cursor += take
                    newPage()
                    pre = 0
                    continue
                }

                if !current.isEmpty {
                    newPage()
                    pre = 0
                    continue
                }

                /* A fresh page can always advance because limit >= 10. This
                   path is reserved for pathological blocks whose shape cannot
                   satisfy the two-line widow/orphan rule. */
                let hardTake = Swift.min(capacity, remaining)
                if hardTake <= 0 { throw PaginationError.cannotProgress }
                emitRange(block.lines, cursor, cursor + hardTake)
                cursor += hardTake
                if cursor < block.lines.count { newPage() }
                pre = 0
            }
        }

        func flowHeadLength(_ lines: [FlowLine]) -> Int {
            if lines.first?.type != .character { return Swift.min(2, lines.count) }
            var head = 1
            while head < lines.count && lines[head].type == .parenthetical { head += 1 }
            /* A cue and its parentheticals must retain at least one
               spoken line. */
            return Swift.min(lines.count, head + 1)
        }

        func stepBlock(_ block: Block, _ next: BuildItem?) throws {
            let before = current.isEmpty ? 0 : block.before

            /* -- scene heading: keep with at least 2 lines of content -- */
            if block.kind == .scene {
                var followNeed = 0
                if case .block(let next) = next {
                    let followLines = next.kind == .flow
                        ? flowHeadLength(next.lines)
                        : Swift.min(2, next.lines.count)
                    followNeed = next.before + followLines
                }
                if !current.isEmpty && before + block.lines.count + followNeed > spaceLeft() {
                    newPage()
                }
                try emitSimpleBlock(block, current.isEmpty ? 0 : block.before)
                return
            }

            /* -- dialogue flow: cue keep-together + (MORE)/(CONT'D) split --
               Continuation LOOPS: a monologue longer than a page chains
               (MORE)/NAME (CONT'D) across as many pages as it needs. */
            if block.kind == .flow {
                let lines = block.lines

                /* The common case first: a block that fits whole needs no
                   cue surgery at all. */
                if before + lines.count <= spaceLeft() {
                    blanks(before, element: lines[0].element)
                    emitRange(lines, 0, lines.count)
                    return
                }

                let head = flowHeadLength(lines)
                /* Cheap shape checks before the cue name is touched: a block
                   that cannot legally continue never pays for the strip. */
                var continuationEligible = block.continuationEligible == true
                    && lines.contains(where: { $0.type == .dialogue })
                    && !lines.contains(where: { $0.type == .lyrics })
                var base = ""
                if continuationEligible {
                    base = SmartType.stripCueExtensions(block.cueName ?? "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuationEligible = !base.isEmpty
                }

                if !continuationEligible {
                    /* Preserve content and page bounds without inventing a
                       speaker or continuation for lyrics/cue-less material. */
                    if !current.isEmpty && spaceLeft() - before < head { newPage() }
                    try emitSimpleBlock(block, current.isEmpty ? 0 : before)
                    return
                }

                let contd = "\(base) (CONT'D)"
                let contdLines = wrapText(contd, width: geometry[.character]!.width)
                var cursor = 0
                var firstChunk = true

                while cursor < lines.count {
                    let pre = firstChunk ? (current.isEmpty ? 0 : block.before) : 0
                    let remaining = lines.count - cursor

                    if pre + remaining <= spaceLeft() {
                        blanks(pre, element: lines[cursor].element)
                        emitRange(lines, cursor, lines.count)
                        break
                    }

                    let avail = spaceLeft() - pre - 1  /* reserve (MORE) */
                    var take = Swift.min(avail, remaining - 1)
                    while take > 0 && lines[cursor + take - 1].type == .parenthetical {
                        take -= 1
                    }
                    let minimum = firstChunk ? head : 1

                    if take < minimum {
                        if !current.isEmpty {
                            /* cannot split honourably — fresh page, retry */
                            newPage()
                            continue
                        }
                        /* An extreme run of parentheticals cannot be split as
                           dialogue. Preserve it without fabricating markers. */
                        try emitSimpleBlock(
                            Block(kind: block.kind, before: block.before,
                                  lines: Array(lines[cursor...]),
                                  cueName: block.cueName,
                                  continuationEligible: false),
                            0
                        )
                        break
                    }

                    blanks(pre, element: lines[cursor].element)
                    emitRange(lines, cursor, cursor + take)
                    cursor += take
                    current.append(PageLine(
                        text: "(MORE)", type: .more,
                        indent: moreIndent, element: -1
                    ))
                    newPage()
                    for text in contdLines {
                        current.append(PageLine(
                            text: text, type: .element(.character),
                            indent: geometry[.character]!.indent, element: -1
                        ))
                    }
                    firstChunk = false
                }
                return
            }

            /* -- simple block: whole, or split with widow/orphan control -- */
            try emitSimpleBlock(block, current.isEmpty ? 0 : block.before)
        }

        while stoppedAfter == 0 {
            guard let item = source.current() else { break }
            switch item {
            case .pagebreak:
                if !current.isEmpty { newPage() }
            case .block(let block):
                try stepBlock(block, source.next())
            }
            source.advance()
        }

        return FoldOutcome(pages: pages, trailing: current, stoppedAfter: stoppedAfter)
    }

    /// The fold's yield: pages completed (numbered absolutely), the open
    /// page's lines at the end, and where an early stop landed.
    private struct FoldOutcome {
        let pages: [ScriptPage]
        let trailing: [PageLine]
        let stoppedAfter: Int
    }

    public static func paginate(
        _ script: Screenplay,
        linesPerPage limit: Int = linesPerPage
    ) throws -> [ScriptPage] {
        guard limit >= minLinesPerPage && limit <= maxLinesPerPage else {
            throw PaginationError.invalidLinesPerPage(limit)
        }
        let fold = try runFold(
            BlockSource(script, startIndex: 0), limit: limit, startNumber: 1, current0: []
        )
        var pages = fold.pages
        /* A document's last page closes when it ends; an empty document
           still has one. */
        if !fold.trailing.isEmpty || pages.isEmpty {
            pages.append(ScriptPage(
                number: 1 + pages.count, lines: fold.trailing,
                continuedTop: false, continuedBottom: false
            ))
        }
        markSceneContinues(script, &pages)
        return pages
    }

    // MARK: - Incremental pagination

    /* A keystroke repaginates what changed, not the document. The fold's
       whole memory is the page being built and the lines already on it, so
       a later run may begin at a block boundary whose surroundings are
       unchanged: the diff finds the first layout-relevant change, the
       checkpoint walks back to its block — and one block further, the reach
       of the keep-with-next and page-fit rules — the fold runs forward, and
       the moment a completed page provably matches its cached twin the
       cached tail is spliced on.

       The contract the tests pin in both languages:
       paginateIncrementally == paginate, always. When no checkpoint can be
       proven, the answer is the full pass, not a guess. */

    /// Where a resumed fold starts: the page being built, the lines already
    /// on it, and the block boundary to fold from.
    public struct PaginationCheckpoint {
        public let pageNumber: Int
        public let prefix: [PageLine]
        public let elementIndex: Int
    }

    /// Type, text and dualism are everything the fold reads from an element.
    private static func layoutEqual(_ a: ScreenplayElement, _ b: ScreenplayElement) -> Bool {
        a.type == b.type && a.text == b.text && (a.dual ?? false) == (b.dual ?? false)
    }

    private struct LayoutEdit {
        let firstDirty: Int
        let tailStartsAt: Int
        let tailShift: Int
    }

    /// The changed region, or nil when nothing the fold reads has changed.
    private static func layoutEditBetween(
        _ previous: [ScreenplayElement], _ current: [ScreenplayElement]
    ) -> LayoutEdit? {
        var first = 0
        let minLength = Swift.min(previous.count, current.count)
        while first < minLength && layoutEqual(previous[first], current[first]) { first += 1 }
        if first == previous.count && first == current.count { return nil }
        var tail = 0
        while tail < minLength - first
                && layoutEqual(previous[previous.count - 1 - tail], current[current.count - 1 - tail]) {
            tail += 1
        }
        return LayoutEdit(
            firstDirty: first,
            tailStartsAt: current.count - tail,
            tailShift: current.count - previous.count
        )
    }

    /// True when the element opens a block in the full block list — the
    /// resume point must be one, because a flow block is built from its cue
    /// forward.
    private static func opensBlock(_ elements: [ScreenplayElement], _ index: Int) -> Bool {
        let element = elements[index]
        if element.type == .pagebreak { return true }
        if !element.type.isPrinting { return false }
        if !flowTypes.contains(element.type) { return true }
        if element.type == .character { return true }
        var lookback = index - 1
        while lookback >= 0 {
            let prev = elements[lookback]
            if prev.type == .pagebreak { return true }
            if !prev.type.isPrinting { lookback -= 1; continue }
            return !flowTypes.contains(prev.type)
        }
        return true
    }

    /// Where a resumed fold may pick up, or nil for "repaginate from zero".
    /// The edit's block is walked back on BOTH element lists — a type change
    /// can make an element open a block in the new document while the old
    /// document folded it into a flow that began earlier — and then one
    /// block further, the reach of the keep-with-next and page-fit rules.
    public static func resumeCheckpoint(
        _ script: Screenplay,
        previous: Screenplay,
        previousPages: [ScriptPage],
        firstDirtyElement: Int
    ) -> PaginationCheckpoint? {
        let elements = script.elements
        guard !elements.isEmpty, !previousPages.isEmpty else { return nil }
        func clamped(_ i: Int, _ list: [ScreenplayElement]) -> Int {
            Swift.min(Swift.max(0, i), list.count - 1)
        }
        var startNew = clamped(firstDirtyElement, elements)
        while startNew > 0 && !opensBlock(elements, startNew) { startNew -= 1 }
        var startOld = clamped(firstDirtyElement, previous.elements)
        while startOld > 0 && !opensBlock(previous.elements, startOld) { startOld -= 1 }
        var start = Swift.min(startNew, startOld)
        guard start > 0 else { return nil }
        var before = start - 1
        while before > 0 && !opensBlock(elements, before) { before -= 1 }
        if before > 0 { start = before }

        /* The block's first printed line in the cached pages — the elements
           above it are unchanged, so old and new indices agree there. */
        for page in previousPages {
            let lines = page.lines
            for j in lines.indices where lines[j].element == start && lines[j].type != .blank {
                /* Trailing blanks before the block are its `before` spacing;
                   the resumed fold re-emits them, so the prefix ends first. */
                var cut = j
                while cut > 0 && lines[cut - 1].type == .blank { cut -= 1 }
                return PaginationCheckpoint(
                    pageNumber: page.number,
                    prefix: Array(lines[..<cut]),
                    elementIndex: start
                )
            }
        }
        return nil
    }

    /// Paginate against the previous run: identical pages at the cost of the
    /// changed region alone. The full pass runs when there is nothing proven
    /// to reuse; the early splice fires only at a page that starts in the
    /// unchanged tail with the same shape its cached twin had.
    public static func paginateIncrementally(
        _ current: Screenplay,
        previous: Screenplay,
        previousPages: [ScriptPage],
        linesPerPage limit: Int = linesPerPage
    ) throws -> [ScriptPage] {
        guard limit >= minLinesPerPage && limit <= maxLinesPerPage else {
            throw PaginationError.invalidLinesPerPage(limit)
        }
        guard !previousPages.isEmpty else { return try paginate(current, linesPerPage: limit) }

        guard let edit = layoutEditBetween(previous.elements, current.elements)
        else { return previousPages }
        guard let checkpoint = resumeCheckpoint(
            current, previous: previous, previousPages: previousPages,
            firstDirtyElement: edit.firstDirty
        ) else { return try paginate(current, linesPerPage: limit) }

        let fold = try runFold(
            BlockSource(current, startIndex: checkpoint.elementIndex),
            limit: limit,
            startNumber: checkpoint.pageNumber,
            current0: checkpoint.prefix
        ) { completed in
            guard let cached = previousPages.first(where: { $0.number == completed.number })
            else { return false }
            let firstNew = completed.lines.first(where: { $0.element >= 0 })?.element ?? -1
            let firstOld = cached.lines.first(where: { $0.element >= 0 })?.element ?? -1
            guard firstNew >= 0, firstOld >= 0 else { return false }
            /* A page starting inside the changed region is no twin,
               whatever its shape. */
            guard firstNew >= edit.tailStartsAt else { return false }
            let lastNew = completed.lines.last(where: { $0.element >= 0 })?.element ?? -1
            let lastOld = cached.lines.last(where: { $0.element >= 0 })?.element ?? -1
            return firstNew == firstOld + edit.tailShift
                && lastNew == lastOld + edit.tailShift
                && completed.lines.count == cached.lines.count
        }

        let kept = Array(previousPages.prefix(checkpoint.pageNumber - 1))
        var result: [ScriptPage]
        if fold.stoppedAfter > 0 {
            /* The page the fold stopped after is in both lists: the fold
               completed it (that is how the resync saw it) and the cache
               holds its twin. The cached tail already carries it, so the
               fold's copy drops out. */
            var tail = Array(previousPages.suffix(from: fold.stoppedAfter - 1))
            if edit.tailShift != 0 {
                /* Cached pages speak the old element indices; every line they
                   hold belongs to the unchanged tail, so each shifts by the
                   same delta. Copied line by line — the caller's cache is
                   not ours to mutate. */
                tail = tail.map { page in
                    var copy = page
                    copy.lines = page.lines.map { line in
                        var lineCopy = line
                        if line.element >= 0 { lineCopy.element += edit.tailShift }
                        return lineCopy
                    }
                    return copy
                }
            }
            result = kept + fold.pages.dropLast() + tail
        } else if !fold.trailing.isEmpty || (fold.pages.isEmpty && kept.isEmpty) {
            if !fold.trailing.isEmpty || fold.pages.isEmpty {
                let trailingPage = ScriptPage(
                    number: checkpoint.pageNumber + fold.pages.count,
                    lines: fold.trailing,
                    continuedTop: false, continuedBottom: false
                )
                result = kept + fold.pages + [trailingPage]
            } else {
                result = kept + fold.pages
            }
        } else {
            result = kept + fold.pages
        }
        markSceneContinues(current, &result)
        return result
    }


    // MARK: - Scene continuations

    /// The production convention: when a scene spans a page break, the
    /// closing page carries (CONTINUED) at the bottom and the opening page
    /// CONTINUED: at the top. Markers live in the margins — they never
    /// consume body lines, so adding them cannot shift a page break.
    static func markSceneContinues(_ script: Screenplay, _ pages: inout [ScriptPage]) {
        /* scene index per element: -1 before the first heading */
        var sceneOf: [Int] = []
        sceneOf.reserveCapacity(script.elements.count)
        var scene = -1
        for element in script.elements {
            if element.type == .scene { scene += 1 }
            sceneOf.append(scene)
        }

        func firstElemented(_ page: ScriptPage) -> PageLine? {
            page.lines.first(where: { $0.element >= 0 })
        }

        func lastElemented(_ page: ScriptPage) -> PageLine? {
            page.lines.last(where: { $0.element >= 0 })
        }

        guard pages.count > 1 else { return }
        for index in 1..<pages.count {
            guard let previous = lastElemented(pages[index - 1]),
                  let next = firstElemented(pages[index]) else { continue }
            let scenePrevious = sceneOf[previous.element]
            let sceneNext = sceneOf[next.element]
            /* A boundary is a scene continuation when both sides belong to
               the same scene and the new page does not open with a heading. */
            let spans = scenePrevious >= 0 && scenePrevious == sceneNext
                && script.elements[next.element].type != .scene
            /* Assignment, not accumulation: the incremental pass splices
               pages that carry these flags from an older document, so a
               stale true must be cleared by the same pass. */
            pages[index - 1].continuedBottom = spans
            pages[index].continuedTop = spans
        }
    }

    // MARK: - Reporting

    /// 1 page ≈ 1 minute — the industry's rule-of-thumb runtime estimate.
    public static func estimateRuntime(_ pages: [ScriptPage]) -> String {
        pages.count == 1 ? "~1 minute" : "~\(pages.count) minutes"
    }

    /// Count non-blank printed lines — a stable complexity metric.
    public static func printedLineCount(_ pages: [ScriptPage]) -> Int {
        pages.reduce(0) { sum, page in
            sum + page.lines.filter { $0.type != .blank }.count
        }
    }
}
