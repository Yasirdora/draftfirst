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

    /// Greedy word wrap at `width` characters, hard-splitting tokens that
    /// cannot fit. Measured in UTF-16 code units to match the JS engine's
    /// `String.length` semantics exactly.
    static func wrapText(_ text: String, width: Int) -> [String] {
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
        let units = Array(text.utf16)
        var words: [String] = []
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
                words.append(String(decoding: units[start..<index], as: UTF16.self))
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
                    words.append(String(decoding: units[offset..<end], as: UTF16.self))
                    offset = end
                }
            }
        }
        guard !words.isEmpty else { return [""] }

        var lines: [String] = []
        var current = words[0]
        var currentLength = current.utf16.count
        for word in words.dropFirst() {
            let wordLength = word.utf16.count
            if currentLength + 1 + wordLength <= width {
                current += " " + word
                currentLength += 1 + wordLength
            } else {
                lines.append(current)
                current = word
                currentLength = wordLength
            }
        }
        lines.append(current)
        return lines
    }

    private static func alignedIndent(text: String, right: Bool) -> Int {
        let length = text.utf16.count
        if right { return Swift.max(0, pageWidthChars - length) }
        return Swift.max(0, (pageWidthChars - length) / 2)
    }

    // MARK: - Block building

    private struct FlowLine {
        var text: String
        var type: ElementKind
        var indent: Int
        var element: Int
    }

    private enum BlockKind { case scene, flow, simple }

    private struct Block {
        var kind: BlockKind
        var before: Int
        var lines: [FlowLine]
        /// Base cue name for (CONT'D) regeneration — flow blocks only.
        var cueName: String? = nil
        /// Lyrics and cue-less dialogue must never acquire synthetic
        /// dialogue markers.
        var continuationEligible: Bool? = nil
    }

    private enum BuildItem {
        case block(Block)
        case pagebreak
    }

    /// character/parenthetical/dialogue plus lyrics (TS `FLOW_TYPES`).
    private static let flowTypes: Set<ElementKind> = [
        .character, .parenthetical, .dialogue, .lyrics,
    ]

    private static func buildBlocks(_ script: Screenplay) -> [BuildItem] {
        var items: [BuildItem] = []
        var flow: Block? = nil

        func flushFlow() {
            if let existing = flow {
                items.append(.block(existing))
                flow = nil
            }
        }

        for (index, element) in script.elements.enumerated() {
            /* Page breaks are non-printing elements that still divide
               layout blocks. */
            if element.type == .pagebreak {
                flushFlow()
                items.append(.pagebreak)
                continue
            }
            guard element.type.isPrinting else { continue }

            let geo = geometry[element.type] ?? geometry[.action]!

            if flowTypes.contains(element.type) {
                if element.type == .character || flow == nil {
                    flushFlow()
                    flow = Block(
                        kind: .flow,
                        before: geometry[.character]!.before,
                        lines: [],
                        cueName: element.type == .character ? element.text : nil,
                        continuationEligible: element.type == .character
                    )
                }
                guard var activeFlow = flow else {
                    preconditionFailure("Dialogue flow could not be initialized.")
                }
                if element.type == .lyrics { activeFlow.continuationEligible = false }
                let wrapped = element.type == .character
                    ? wrapText(element.text + (element.dual == true ? " ^" : ""),
                               width: geometry[.character]!.width)
                    : wrapText(element.text, width: geo.width)
                for text in wrapped {
                    activeFlow.lines.append(FlowLine(
                        text: text, type: element.type,
                        indent: geo.indent, element: index
                    ))
                }
                flow = activeFlow
                continue
            }

            flushFlow()

            if element.type == .transition || element.type == .centered {
                let right = element.type == .transition
                items.append(.block(Block(
                    kind: .simple,
                    before: geo.before,
                    lines: wrapText(element.text, width: pageWidthChars).map { text in
                        FlowLine(
                            text: text, type: element.type,
                            indent: alignedIndent(text: text, right: right),
                            element: index
                        )
                    }
                )))
                continue
            }

            items.append(.block(Block(
                kind: element.type == .scene ? .scene : .simple,
                before: geo.before,
                lines: wrapText(element.text, width: geo.width).map { text in
                    FlowLine(text: text, type: element.type,
                             indent: geo.indent, element: index)
                }
            )))
        }

        flushFlow()
        return items
    }

    // MARK: - Pagination

    private static let moreIndent = 10  // GEOMETRY.dialogue.indent

    public static func paginate(
        _ script: Screenplay,
        linesPerPage limit: Int = linesPerPage
    ) throws -> [ScriptPage] {
        guard limit >= minLinesPerPage && limit <= maxLinesPerPage else {
            throw PaginationError.invalidLinesPerPage(limit)
        }

        let items = buildBlocks(script)
        var pages: [ScriptPage] = []
        var current: [PageLine] = []

        func newPage(allowEmpty: Bool = false) {
            if current.isEmpty && !allowEmpty { return }
            pages.append(ScriptPage(
                number: pages.count + 1, lines: current,
                continuedTop: false, continuedBottom: false
            ))
            current = []
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

        for index in items.indices {
            guard case .block(let block) = items[index] else {
                /* pagebreak */
                if !current.isEmpty { newPage() }
                continue
            }

            let before = current.isEmpty ? 0 : block.before

            /* -- scene heading: keep with at least 2 lines of content -- */
            if block.kind == .scene {
                var followNeed = 0
                if index + 1 < items.count, case .block(let next) = items[index + 1] {
                    let followLines = next.kind == .flow
                        ? flowHeadLength(next.lines)
                        : Swift.min(2, next.lines.count)
                    followNeed = next.before + followLines
                }
                if !current.isEmpty && before + block.lines.count + followNeed > spaceLeft() {
                    newPage()
                }
                try emitSimpleBlock(block, current.isEmpty ? 0 : block.before)
                continue
            }

            /* -- dialogue flow: cue keep-together + (MORE)/(CONT'D) split --
               Continuation LOOPS: a monologue longer than a page chains
               (MORE)/NAME (CONT'D) across as many pages as it needs. */
            if block.kind == .flow {
                let lines = block.lines
                let head = flowHeadLength(lines)
                let base = SmartType.stripCueExtensions(block.cueName ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let continuationEligible = block.continuationEligible == true
                    && !base.isEmpty
                    && lines.contains(where: { $0.type == .dialogue })
                    && !lines.contains(where: { $0.type == .lyrics })

                if before + lines.count <= spaceLeft() {
                    blanks(before, element: lines[0].element)
                    emitRange(lines, 0, lines.count)
                    continue
                }

                if !continuationEligible {
                    /* Preserve content and page bounds without inventing a
                       speaker or continuation for lyrics/cue-less material. */
                    if !current.isEmpty && spaceLeft() - before < head { newPage() }
                    try emitSimpleBlock(block, current.isEmpty ? 0 : before)
                    continue
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
                continue
            }

            /* -- simple block: whole, or split with widow/orphan control -- */
            try emitSimpleBlock(block, current.isEmpty ? 0 : block.before)
        }

        if !current.isEmpty || pages.isEmpty { newPage(allowEmpty: true) }
        markSceneContinues(script, &pages)
        return pages
    }

    // MARK: - Scene continuations

    /// The production convention: when a scene spans a page break, the
    /// closing page carries (CONTINUED) at the bottom and the opening page
    /// CONTINUED: at the top. Markers live in the margins — they never
    /// consume body lines, so adding them cannot shift a page break.
    private static func markSceneContinues(_ script: Screenplay, _ pages: inout [ScriptPage]) {
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
            if scenePrevious >= 0 && scenePrevious == sceneNext
                && script.elements[next.element].type != .scene {
                pages[index - 1].continuedBottom = true
                pages[index].continuedTop = true
            }
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
