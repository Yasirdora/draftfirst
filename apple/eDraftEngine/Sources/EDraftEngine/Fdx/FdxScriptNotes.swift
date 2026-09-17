import Foundation

extension Fdx {

    // MARK: - The model

    /// A Final Draft ScriptNote — a comment the file keeps beside the script
    /// (TypeScript `FdxScriptNote`), pinned by `Fixtures/fdx.json`.
    ///
    /// Final Draft does not put these in the script's <Content>. They live in a
    /// top-level <ScriptNotes> container and point back into the script with a
    /// character Range, so they are read here as what they are: a reading of
    /// the file, not part of the screenplay. A screenplay field would evaporate
    /// the moment the app turns the file into Fountain, and a `note` element
    /// cannot hold one — measured on a real feature, a note of nine paragraphs,
    /// four of them blank, came back from Fountain as five printed Action
    /// lines. Nothing here is ever written: the preserving save copies
    /// <ScriptNotes> byte for byte, because it lies outside the paragraphs a
    /// save rewrites.
    ///
    /// Every field is the file's own, verbatim, and `nil` when the file leaves
    /// it empty. What the file does not say is not inferred:
    ///
    /// - `author` is `WriterName`. `WriterID` is not read — all eleven notes in
    ///   the measured file shared one WriterID across two different writers.
    /// - `category` is `Type`, and it is free text, not a role: one writer's
    ///   notes were typed both "Writer" and "Alt Scenes".
    /// - `color` is `#RRRRGGGGBBBB`, sixteen bits a channel, no alpha; the
    ///   all-zero value means unset and reads as `nil`. It says what kind of
    ///   note this is, never who wrote it — one writer's eight notes came in
    ///   four colours.
    /// - `range` is the file's Range. `anchor` is where it lands (see
    ///   `ScriptText.position`), and is `nil` when the Range starts past the
    ///   script — a stale Range is kept rather than guessed at.
    /// - `text` is the body's paragraphs joined with "\n", blank paragraphs
    ///   kept.
    public struct ScriptNote: Codable, Equatable, Sendable {
        /// A place in the imported screenplay: an index into
        /// `script.elements` and a ContentIndex into that element's text.
        public struct Position: Codable, Equatable, Sendable {
            public var element: Int
            public var offset: Int

            public init(element: Int, offset: Int) {
                self.element = element
                self.offset = offset
            }
        }

        public struct Range: Codable, Equatable, Sendable {
            public var start: Int
            public var end: Int

            public init(start: Int, end: Int) {
                self.start = start
                self.end = end
            }
        }

        public struct Anchor: Codable, Equatable, Sendable {
            public var start: Position
            public var end: Position

            public init(start: Position, end: Position) {
                self.start = start
                self.end = end
            }
        }

        public var id: String?
        public var author: String?
        public var title: String?
        public var category: String?
        public var color: String?
        public var created: String?
        public var modified: String?
        public var range: Range?
        public var anchor: Anchor?
        public var text: String

        public init(
            id: String? = nil, author: String? = nil, title: String? = nil,
            category: String? = nil, color: String? = nil,
            created: String? = nil, modified: String? = nil,
            range: Range? = nil, anchor: Anchor? = nil, text: String
        ) {
            self.id = id
            self.author = author
            self.title = title
            self.category = category
            self.color = color
            self.created = created
            self.modified = modified
            self.range = range
            self.anchor = anchor
            self.text = text
        }
    }

    // MARK: - Where a Range lands

    /// The blocks Final Draft embeds inside a script paragraph, and what each
    /// counts in a ScriptNote Range: two units, wherever it sits, its own
    /// paragraphs' text nothing (TypeScript `EMBEDDED_BLOCKS`, `BLOCK_UNITS`).
    ///
    /// Measured on files Final Draft wrote. Counted as zero, every position
    /// after a block landed two units late for each block before it: in each
    /// of two files, two notes began mid-word and one fell past the script's
    /// end. Counted as two, every note lands on whole words or is empty.
    static let embeddedBlocks: Set<String> = ["dualdialogue", "omittedscene"]
    static let blockUnits = 2

    /// One body paragraph as a ScriptNote Range counts it: its text length in
    /// UTF-16 units plus two for each embedded block, where those blocks sit
    /// in its text, and the element it became — `nil` when the import
    /// absorbed it (TypeScript `ParagraphLayout`).
    struct ParagraphLayout {
        let length: Int
        let blocks: [Int]
        let element: Int?

        /// A unit of the paragraph as a Range counts it, as an offset into
        /// its text: the units of an embedded block are the place it sits
        /// (TypeScript `textOffsetIn`).
        func textOffset(_ unit: Int) -> Int {
            var passed = 0
            for at in blocks {
                if unit < at + passed { break }
                if unit < at + passed + Fdx.blockUnits { return at }
                passed += Fdx.blockUnits
            }
            return min(unit - passed, length - Fdx.blockUnits * blocks.count)
        }
    }

    /// The script's text as a ScriptNote Range counts it (TypeScript
    /// `ScriptText`).
    struct ScriptText {
        let layout: [ParagraphLayout]
        let starts: [Int]
        /// The position just past the last paragraph's text.
        let end: Int

        init(_ layout: [ParagraphLayout]) {
            var starts: [Int] = []
            starts.reserveCapacity(layout.count)
            var cursor = 0
            for paragraph in layout {
                starts.append(cursor)
                cursor += paragraph.length + 1
            }
            self.layout = layout
            self.starts = starts
            self.end = cursor - 1
        }

        /// Where a Range position lands in the imported screenplay
        /// (TypeScript `positionIn`).
        ///
        /// Final Draft counts the script paragraph by paragraph, one unit for
        /// each paragraph break — measured on a real feature, where one Range
        /// began on the first character of the shot it was about and another
        /// covered exactly one character cue. A break belongs to the paragraph
        /// before it, so every position from 0 to the end of the script lands
        /// in exactly one paragraph.
        ///
        /// A position in a paragraph the import absorbed — an End of Act —
        /// moves to the start of the next element, or to the end of the last
        /// one when nothing follows. Past the end of the script there is
        /// nothing honest to point at.
        func position(_ position: Int) -> ScriptNote.Position? {
            guard !layout.isEmpty, position >= 0, position <= end else { return nil }
            var low = 0
            var high = layout.count - 1
            while low < high {
                let middle = (low + high + 1) >> 1
                if starts[middle] <= position { low = middle } else { high = middle - 1 }
            }
            if let element = layout[low].element {
                return .init(element: element, offset: layout[low].textOffset(position - starts[low]))
            }
            for next in layout[(low + 1)...] {
                if let element = next.element { return .init(element: element, offset: 0) }
            }
            for previous in layout[..<low].reversed() {
                if let element = previous.element {
                    return .init(element: element, offset: previous.textOffset(previous.length))
                }
            }
            return nil
        }

        /// Where a Range lands. A Range that starts past the script is stale
        /// and has no anchor; one that only ends past it is held to the
        /// script's end, so the note still marks the text it does cover.
        func anchor(_ range: ScriptNote.Range) -> ScriptNote.Anchor? {
            guard let start = position(range.start),
                  let finish = position(min(range.end, end)) else { return nil }
            return .init(start: start, end: finish)
        }
    }

    /// A Range attribute, `start,end` in digits; a reversed pair is the same
    /// span (TypeScript `rangeOf`). Bounded by JavaScript's safe integers, so
    /// both engines refuse the same values.
    static func scriptNoteRange(_ value: String) -> ScriptNote.Range? {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            let digits = String(part).jsTrimmed
            guard !digits.isEmpty,
                  digits.unicodeScalars.allSatisfy({ ("0"..."9").contains($0) }),
                  let number = Int(digits), number <= 9_007_199_254_740_991
            else { return nil }
            numbers.append(number)
        }
        return .init(start: min(numbers[0], numbers[1]), end: max(numbers[0], numbers[1]))
    }

    static func scriptNote(
        attributes: [(name: String, value: String)],
        paragraphs: [String],
        text: ScriptText
    ) -> ScriptNote {
        func value(_ name: String) -> String { attributes.last { $0.name == name }?.value ?? "" }
        func verbatim(_ name: String) -> String? {
            let found = value(name)
            return found.jsTrimmed.isEmpty ? nil : found
        }
        var note = ScriptNote(text: paragraphs.joined(separator: "\n"))
        note.id = verbatim("id")
        let author = value("writername").jsTrimmed
        note.author = author.isEmpty ? nil : author
        note.title = verbatim("name")
        note.category = verbatim("type")
        if let color = verbatim("color"),
           !(color.count > 1 && color.hasPrefix("#") && color.dropFirst().allSatisfy { $0 == "0" }) {
            note.color = color
        }
        note.created = verbatim("datetime")
        note.modified = verbatim("datemodified")
        if let range = scriptNoteRange(value("range")) {
            note.range = range
            note.anchor = text.anchor(range)
        }
        return note
    }

    // MARK: - Reading them

    /// The scan state for `scriptNotes(in:)`, held by reference so the
    /// tokeniser's handlers can mutate it — the port of the closure captures
    /// in TypeScript `scriptNotesOf`.
    /// Where a ScriptNote's Range value sits in the source, in UTF-16 units,
    /// and what it says (TypeScript `ScriptNoteRangeValue`).
    struct ScriptNoteRangeValue: Sendable {
        let valueStart: Int
        let valueEnd: Int
        let range: ScriptNote.Range
        /// Written end first. Kept that way when the Range is rewritten.
        let reversed: Bool
    }

    private static let rangeAttribute = try! NSRegularExpression(
        pattern: #"\srange\s*=\s*(?:"([^"]*)"|'([^']*)')"#, options: [.caseInsensitive]
    )

    /// The Range value of the <ScriptNote> tag opening at `tagStart` — the
    /// last one, as the tag's attributes read — or nil when it has none
    /// readable (TypeScript `rangeValueIn`).
    static func rangeValue(in units: [UInt16], tagStart: Int) -> ScriptNoteRangeValue? {
        var tagEnd = units.count
        var quote: UInt16 = 0
        var index = tagStart + 1
        while index < units.count {
            let unit = units[index]
            if quote != 0 {
                if unit == quote { quote = 0 }
            } else if unit == 34 || unit == 39 {   // " and '
                quote = unit
            } else if unit == 62 {                 // >
                tagEnd = index
                break
            }
            index += 1
        }
        let tag = String(decoding: units[tagStart..<tagEnd], as: UTF16.self) as NSString
        guard let found = rangeAttribute.matches(in: tag as String, range: NSRange(location: 0, length: tag.length)).last
        else { return nil }
        let group = found.range(at: 1).location != NSNotFound ? found.range(at: 1) : found.range(at: 2)
        let decoded = Fdx.decodeXmlEntities(tag.substring(with: group))
        guard let range = scriptNoteRange(decoded) else { return nil }
        let numbers = decoded.split(separator: ",", omittingEmptySubsequences: false).map { Int(String($0).jsTrimmed) ?? 0 }
        return ScriptNoteRangeValue(
            valueStart: tagStart + group.location,
            valueEnd: tagStart + group.location + group.length,
            range: range,
            reversed: numbers.count == 2 && numbers[0] > numbers[1]
        )
    }

    /// Where each ScriptNote's Range value sits, in note order — the notes
    /// `scriptNotes(in:)` reads, by the same rules.
    static func scriptNoteRangeValues(in source: String, limits: Limits) -> [ScriptNoteRangeValue?] {
        let collector = ScriptNoteCollector(limits: limits, text: ScriptText([]))
        collector.units = Array(source.utf16)
        FdxXmlScanner.scan(
            source,
            handlers: FdxXmlScanner.Handlers(
                start: { tag, offset in collector.start(tag, offset: offset) },
                end: { name, _ in collector.end(name) },
                text: { value, cdata in collector.text(value, cdata: cdata) }
            ),
            diagnostics: DiagnosticCollector(limit: 1)
        )
        collector.finishNote()
        return collector.rangeValues
    }

    private final class ScriptNoteCollector {
        let limits: Limits
        let text: ScriptText
        /// The source, when Range value locations are collected.
        var units: [UInt16]?
        var rangeValues: [ScriptNoteRangeValue?] = []

        var notes: [ScriptNote] = []
        var open: [String] = []
        var note: (attributes: [(name: String, value: String)], depth: Int, paragraphs: [String])?
        var paragraph: (text: String, depth: Int)?
        var run: (uppercases: Bool, depth: Int)?
        var paragraphCount = 0
        var textRunCount = 0
        var limitReached = false

        init(limits: Limits, text: ScriptText) {
            self.limits = limits
            self.text = text
        }

        func finishNote() {
            guard var finished = note else { return }
            if let paragraph { finished.paragraphs.append(paragraph.text) }
            notes.append(Fdx.scriptNote(
                attributes: finished.attributes, paragraphs: finished.paragraphs, text: text
            ))
            note = nil
            paragraph = nil
            run = nil
        }

        func start(_ tag: FdxXmlScanner.Tag, offset: Int = 0) -> Bool {
            let parent = open.last
            open.append(tag.name)
            let opensNote = tag.name == "scriptnote" && parent == "scriptnotes" && note == nil
            let opensParagraph = note.map { tag.name == "paragraph" && open.count == $0.depth + 1 } ?? false
            if opensNote || opensParagraph {
                if paragraphCount >= limits.maxParagraphs {
                    limitReached = true
                    return false
                }
                paragraphCount += 1
            }
            if opensNote {
                note = (attributes: tag.attributes, depth: open.count, paragraphs: [])
                if let units { rangeValues.append(Fdx.rangeValue(in: units, tagStart: offset)) }
            } else if opensParagraph {
                paragraph = (text: "", depth: open.count)
            } else if let paragraph, tag.name == "text", open.count == paragraph.depth + 1 {
                if textRunCount >= limits.maxTextRuns {
                    limitReached = true
                    return false
                }
                textRunCount += 1
                run = (uppercases: Fdx.runIsAllCaps(tag.attribute("style")), depth: open.count)
            }
            return true
        }

        func end(_ name: String) -> Bool {
            if let run, name == "text", open.count == run.depth {
                self.run = nil
            } else if note != nil, let paragraph, name == "paragraph", open.count == paragraph.depth {
                note?.paragraphs.append(paragraph.text)
                self.paragraph = nil
            } else if let note, name == "scriptnote", open.count == note.depth {
                finishNote()
            }
            if open.last == name { open.removeLast() }
            return true
        }

        func text(_ value: String, cdata: Bool) -> Bool {
            if let run, paragraph != nil, open.count == run.depth {
                let decoded = cdata ? value : Fdx.decodeXmlEntities(value)
                paragraph?.text += run.uppercases ? decoded.uppercased() : decoded
            }
            return true
        }
    }

    /// The file's ScriptNotes (TypeScript `scriptNotesOf`).
    ///
    /// A second, narrow scan, so the reader the preserving save depends on is
    /// not touched to serve it. A note is a <ScriptNote> directly inside
    /// <ScriptNotes>; its body is its direct-child paragraphs' direct-child
    /// <Text>, the same rule the script's own paragraphs follow. Notes and
    /// their paragraphs are bounded by `maxParagraphs`, their runs by
    /// `maxTextRuns`, counted apart from the script's.
    static func scriptNotes(
        in source: String,
        layout: [ParagraphLayout],
        limits: Limits,
        diagnostics: DiagnosticCollector
    ) -> [ScriptNote] {
        let collector = ScriptNoteCollector(limits: limits, text: ScriptText(layout))
        FdxXmlScanner.scan(
            source,
            handlers: FdxXmlScanner.Handlers(
                start: { tag, _ in collector.start(tag) },
                end: { name, _ in collector.end(name) },
                text: { value, cdata in collector.text(value, cdata: cdata) }
            ),
            diagnostics: DiagnosticCollector(limit: 1)
        )
        collector.finishNote()
        if collector.limitReached {
            diagnostics.add(.init(
                code: "FDX_SCRIPT_NOTES_LIMIT_REACHED",
                severity: .warning,
                message: "Script notes stopped at \(limits.maxParagraphs) notes and paragraphs or \(limits.maxTextRuns) Text runs.",
                count: collector.notes.count
            ))
        }
        return collector.notes
    }
}
