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
    /// `scriptNotes(in:)` reads, by the same rules — and where the notes and
    /// their container sit, and which are eDraft's.
    static func scriptNoteRangeValues(
        in source: String, limits: Limits
    ) -> (values: [ScriptNoteRangeValue?], places: ScriptNotesPlaces) {
        let collector = ScriptNoteCollector(limits: limits, text: ScriptText([]))
        collector.units = Array(source.utf16)
        collector.places = ScriptNotesPlaces()
        FdxXmlScanner.scan(
            source,
            handlers: FdxXmlScanner.Handlers(
                start: { tag, offset in collector.start(tag, offset: offset) },
                end: { name, offset in collector.end(name, offset: offset) },
                text: { value, cdata in collector.text(value, cdata: cdata) }
            ),
            diagnostics: DiagnosticCollector(limit: 1)
        )
        collector.finishNote(closing: nil)
        return (collector.rangeValues, collector.places ?? ScriptNotesPlaces())
    }

    /// Where the file's <ScriptNotes> sit, so a save can take one out or add
    /// one (TypeScript `ScriptNotesPlaces`).
    struct ScriptNotesPlaces: Sendable {
        /// A <ScriptNote>: from the line break in front of it (when only its
        /// indent is between) to the end of its closing tag.
        struct Note: Sendable {
            let start: Int
            let end: Int
            let id: Int?
            let owned: OwnedNote?
        }
        var notes: [Note] = []
        /// The <ScriptNotes> container: where it opens, and where its closing
        /// tag starts — nil when it closes itself.
        var container: (open: Int, close: Int?, selfClosing: Bool)?
        /// Just past the top-level </Characters>, where Final Draft keeps them.
        var afterCharacters: Int?
        /// Where </FinalDraft> starts.
        var rootClose: Int?
    }

    private final class ScriptNoteCollector {
        let limits: Limits
        let text: ScriptText
        /// The source, when Range value locations are collected.
        var units: [UInt16]?
        var rangeValues: [ScriptNoteRangeValue?] = []
        /// Where each note sits, when a save needs to know.
        var places: ScriptNotesPlaces?

        var notes: [ScriptNote] = []
        var open: [String] = []
        var note: (attributes: [(name: String, value: String)], depth: Int, paragraphs: [String], start: Int)?
        var paragraph: (text: String, depth: Int)?
        var run: (uppercases: Bool, depth: Int)?
        var paragraphCount = 0
        var textRunCount = 0
        var limitReached = false

        init(limits: Limits, text: ScriptText) {
            self.limits = limits
            self.text = text
        }

        func finishNote(closing: Int?) {
            guard var finished = note else { return }
            if let paragraph { finished.paragraphs.append(paragraph.text) }
            notes.append(Fdx.scriptNote(
                attributes: finished.attributes, paragraphs: finished.paragraphs, text: text
            ))
            if places != nil {
                let source = units ?? []
                var end = source.count
                if let closing {
                    var at = closing
                    while at < source.count && source[at] != 62 { at += 1 }   // >
                    end = at < source.count ? at + 1 : source.count
                }
                var lineStart = finished.start - 1
                while lineStart >= 0 && source[lineStart] != 10 { lineStart -= 1 }   // \n
                let indentOnly = lineStart >= 0
                    && source[(lineStart + 1)..<finished.start].allSatisfy { $0 == 32 || $0 == 9 }
                let idText = Array(FdxXmlScanner.jsTrimmed(ArraySlice(
                    (finished.attributes.last { $0.name == "id" }?.value ?? "").utf16
                )))
                let digits = !idText.isEmpty && idText.allSatisfy { $0 >= 48 && $0 <= 57 }
                places?.notes.append(ScriptNotesPlaces.Note(
                    start: indentOnly ? lineStart : finished.start,
                    end: end,
                    id: digits ? Int(String(decoding: idText, as: UTF16.self)) : nil,
                    owned: Fdx.ownedNote(
                        title: finished.attributes.last { $0.name == "name" }?.value,
                        writerName: finished.attributes.last { $0.name == "writername" }?.value,
                        type: finished.attributes.last { $0.name == "type" }?.value,
                        paragraphs: finished.paragraphs
                    )
                ))
            }
            note = nil
            paragraph = nil
            run = nil
        }

        func start(_ tag: FdxXmlScanner.Tag, offset: Int = 0) -> Bool {
            let parent = open.last
            open.append(tag.name)
            let opensNote = tag.name == "scriptnote" && parent == "scriptnotes" && note == nil
            if places != nil, open.count == 2, tag.name == "scriptnotes", places?.container == nil {
                places?.container = (open: offset, close: nil, selfClosing: tag.selfClosing)
            }
            let opensParagraph = note.map { tag.name == "paragraph" && open.count == $0.depth + 1 } ?? false
            if opensNote || opensParagraph {
                if paragraphCount >= limits.maxParagraphs {
                    limitReached = true
                    return false
                }
                paragraphCount += 1
            }
            if opensNote {
                note = (attributes: tag.attributes, depth: open.count, paragraphs: [], start: offset)
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

        func end(_ name: String, offset: Int = 0) -> Bool {
            if let run, name == "text", open.count == run.depth {
                self.run = nil
            } else if note != nil, let paragraph, name == "paragraph", open.count == paragraph.depth {
                note?.paragraphs.append(paragraph.text)
                self.paragraph = nil
            } else if let note, name == "scriptnote", open.count == note.depth {
                finishNote(closing: offset)
            }
            if places != nil, open.count == 2, open[1] == name {
                if name == "scriptnotes", let container = places?.container, !container.selfClosing, container.close == nil {
                    places?.container?.close = offset
                }
                if name == "characters", let source = units {
                    var at = offset
                    while at < source.count && source[at] != 62 { at += 1 }
                    places?.afterCharacters = at < source.count ? at + 1 : nil
                }
            }
            if places != nil, open.count == 1, name == "finaldraft" { places?.rootClose = offset }
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
    ) -> (notes: [ScriptNote], ownership: [OwnedNote?]) {
        let collector = ScriptNoteCollector(limits: limits, text: ScriptText(layout))
        collector.units = Array(source.utf16)
        collector.places = ScriptNotesPlaces()
        FdxXmlScanner.scan(
            source,
            handlers: FdxXmlScanner.Handlers(
                start: { tag, offset in collector.start(tag, offset: offset) },
                end: { name, offset in collector.end(name, offset: offset) },
                text: { value, cdata in collector.text(value, cdata: cdata) }
            ),
            diagnostics: DiagnosticCollector(limit: 1)
        )
        collector.finishNote(closing: nil)
        if collector.limitReached {
            diagnostics.add(.init(
                code: "FDX_SCRIPT_NOTES_LIMIT_REACHED",
                severity: .warning,
                message: "Script notes stopped at \(limits.maxParagraphs) notes and paragraphs or \(limits.maxTextRuns) Text runs.",
                count: collector.notes.count
            ))
        }
        return (collector.notes, collector.places?.notes.map(\.owned) ?? [])
    }
}

// MARK: - The writer's notes, as ScriptNotes (IL-0039)

extension Fdx {

    /// How a save writes the notes the writer left in eDraft: each one a Final
    /// Draft ScriptNote (RFC-NOTES-SYSTEM §4.2), never a paragraph of the
    /// script. Every value that is new each time is the caller's to give, so a
    /// test can pin every byte; left out, each is made fresh (TypeScript
    /// `FdxNoteWriting`).
    public struct NoteWriting: Sendable {
        /// The writer's name for notes: `Name (Role)`, or `Name` (D4). A note
        /// that does not name its author is written with it (D3). Never read
        /// from the system: without it, such a note names nobody.
        public var writer: String?
        /// `yyyyMMddTHHmmss`, local time, as Final Draft writes DateTime.
        public var now: String?
        /// A fresh lowercase UUID, for a note's RefId and each paragraph's id.
        public var newId: (@Sendable () -> String)?

        public init(
            writer: String? = nil,
            now: String? = nil,
            newId: (@Sendable () -> String)? = nil
        ) {
            self.writer = writer
            self.now = now
            self.newId = newId
        }
    }

    /// The title a note eDraft wrote carries (RFC-NOTES-SYSTEM §4.3).
    static let eDraftTitle = "[eDraft]"

    /// A note eDraft wrote: its title, Final Draft's `Name`, is `[eDraft]`
    /// (§4.3; TypeScript `OwnedNote`). Final Draft keeps a note's title when
    /// someone edits the note there, so the note stays eDraft's; it re-stamps
    /// the author field, so the note is then authored by whoever edited it (D9).
    struct OwnedNote: Equatable, Sendable {
        /// Its author: Final Draft's `WriterName`.
        let name: String?
        /// Their role: Final Draft's Type.
        let role: String?
        let message: String
    }

    private static func jsTrimmed(_ text: String) -> String {
        String(decoding: FdxXmlScanner.jsTrimmed(ArraySlice(text.utf16)), as: UTF16.self)
    }

    static func ownedNote(title: String?, writerName: String?, type: String?, paragraphs: [String]) -> OwnedNote? {
        guard jsTrimmed(title ?? "") == eDraftTitle else { return nil }
        let name = jsTrimmed(writerName ?? "")
        let role = jsTrimmed(type ?? "")
        return OwnedNote(
            name: name.isEmpty ? nil : name,
            role: role.isEmpty ? nil : role,
            message: paragraphs.joined(separator: "\n")
        )
    }

    /// How a note of eDraft's signs in the editor: `Name (Role)`, or `Name` (D4).
    static func ownedNoteAuthor(_ note: OwnedNote) -> String? {
        guard let name = note.name else { return nil }
        return note.role.map { "\(name) (\($0))" } ?? name
    }

    /// A note of eDraft's as the writer reads and edits it: `Name (Role): words`.
    static func ownedNoteText(_ note: OwnedNote) -> String {
        ownedNoteAuthor(note).map { "\($0): \(note.message)" } ?? note.message
    }

    /// `Name (Role)` into the name and the role; a signature with no role is
    /// all name (TypeScript `nameAndRole`).
    static func nameAndRole(_ signature: String) -> (name: String, role: String) {
        let units = Array(signature.utf16)
        let open = Array(" (".utf16)
        if units.last == 41, units.count >= 2 {   // )
            var at = units.count - 2
            while at > 0 && !(units[at] == open[0] && units[at + 1] == open[1]) { at -= 1 }
            if at > 0 {
                let name = jsTrimmed(String(decoding: units[0..<at], as: UTF16.self))
                if !name.isEmpty {
                    let role = jsTrimmed(String(decoding: units[(at + 2)..<(units.count - 1)], as: UTF16.self))
                    return (name, role)
                }
            }
        }
        return (jsTrimmed(signature), "")
    }

    /// The notes eDraft wrote, back as the writer's own (RFC-NOTES-SYSTEM
    /// §4.3; TypeScript `withOwnedNotes`).
    ///
    /// A ScriptNote titled `[eDraft]` is eDraft's: it becomes a note element in
    /// front of the element its Range starts in —
    /// where the editor keeps a note — reading `Name (Role): words`, and is no
    /// longer one of the file's notes. A note whose Range
    /// lands nowhere goes to the end of the script. Final Draft's notes stay
    /// as they are, their anchors moved past the elements put in.
    static func withOwnedNotes(
        _ elements: [ScreenplayElement],
        _ notes: [ScriptNote],
        _ ownership: [OwnedNote?]
    ) -> (elements: [ScreenplayElement], scriptNotes: [ScriptNote], movedTo: [Int]?) {
        var inFront: [Int: [ScreenplayElement]] = [:]
        var theirs: [ScriptNote] = []
        for (index, note) in notes.enumerated() {
            guard index < ownership.count, let owned = ownership[index] else {
                theirs.append(note)
                continue
            }
            let at = note.anchor?.start.element ?? elements.count
            /* The words its Range covers, back as the anchor the editor
               holds (§5.4). A Range over the whole paragraph carries none. */
            let anchor = note.anchor.flatMap { anchorOfRange(elements, $0) }
            inFront[at, default: []].append(
                ScreenplayElement(type: .note, text: ownedNoteText(owned), anchor: anchor)
            )
        }
        guard !inFront.isEmpty else { return (elements, notes, nil) }
        var result: [ScreenplayElement] = []
        var movedTo: [Int] = []
        for (index, element) in elements.enumerated() {
            result += inFront[index] ?? []
            movedTo.append(result.count)
            result.append(element)
        }
        result += inFront[elements.count] ?? []
        func moved(_ position: ScriptNote.Position) -> ScriptNote.Position {
            ScriptNote.Position(element: movedTo[position.element], offset: position.offset)
        }
        return (result, theirs.map { note in
            var note = note
            if let anchor = note.anchor {
                note.anchor = ScriptNote.Anchor(start: moved(anchor.start), end: moved(anchor.end))
            }
            return note
        }, movedTo)
    }

    /// An omission span, after the notes read in front of their lines have
    /// moved the elements it covers (TypeScript `movedOmissions`).
    static func movedOmissions(_ omissions: [Omission], _ movedTo: [Int]?, _ total: Int) -> [Omission] {
        guard let movedTo else { return omissions }
        return omissions.map { omission in
            Omission(
                start: movedTo[omission.start],
                /* `end` is exclusive: where the element after the span went,
                   or the end of the script when the span runs to it. */
                end: omission.end < movedTo.count ? movedTo[omission.end] : total
            )
        }
    }

    struct ResolvedNoteWriting {
        let writer: String?
        let now: String
        let newId: () -> String
    }

    /// Final Draft's `20260918T120000`: local time, no zone.
    static func noteTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter.string(from: date)
    }

    static func resolvedNoteWriting(_ writing: NoteWriting?) -> ResolvedNoteWriting {
        let writer = writing?.writer.map { String(decoding: FdxXmlScanner.jsTrimmed(ArraySlice($0.utf16)), as: UTF16.self) }
        return ResolvedNoteWriting(
            writer: (writer?.isEmpty ?? true) ? nil : writer,
            now: writing?.now ?? noteTimestamp(Date()),
            newId: writing?.newId ?? { UUID().uuidString.lowercased() }
        )
    }

    /// Who wrote a note and what it says, from the words the editor holds
    /// (TypeScript `noteAuthorship`). A `Name: ` prefix names the author when
    /// the name is the writer's own or one the file's eDraft notes already
    /// carry — the longest that fits. Any other note is the writer's (D3),
    /// prefix and all: a colon in a sentence is not a person.
    static func noteAuthorship(_ text: String, names: [String], writer: String?) -> (author: String?, message: String) {
        let units = Array(text.utf16)
        var author: String?
        for name in names {
            let prefix = Array("\(name): ".utf16)
            if units.starts(with: prefix), author == nil || name.utf16.count > author!.utf16.count { author = name }
        }
        if let author {
            return (author, String(decoding: units[(author.utf16.count + 2)...], as: UTF16.self))
        }
        return (writer, text)
    }

    /// Where a paragraph sits as a Range counts it: its first unit, and its last.
    static func paragraphRange(_ lengths: [Int], at: Int) -> ScriptNote.Range {
        guard at >= 0, !lengths.isEmpty else { return ScriptNote.Range(start: 0, end: 0) }
        var start = 0
        for index in 0..<at { start += lengths[index] + 1 }
        return ScriptNote.Range(start: start, end: start + lengths[at])
    }

    /// A text offset inside one paragraph, as a ScriptNote Range counts it —
    /// the inverse of `ParagraphLayout.textOffset`. An embedded block's two
    /// units sit where the block sits, so an offset at a block's own position
    /// is the text after it (`inclusive`), while a span ending there stops in
    /// front of it (TypeScript `unitOffsetIn`).
    static func unitOffset(_ blocks: [Int], _ offset: Int, inclusive: Bool) -> Int {
        var units = offset
        for at in blocks where inclusive ? at <= offset : at < offset { units += Fdx.blockUnits }
        return units
    }

    /// The Range one of the writer's notes takes (RFC-NOTES-SYSTEM §5.1):
    /// its anchored words when it has an anchor and those words are still in
    /// the paragraph, and the whole paragraph otherwise.
    ///
    /// §5.3 rule 5, said out loud: words that are gone do not move the note
    /// to another paragraph and are never guessed at. The note falls back to
    /// its paragraph and the save says so (TypeScript `noteRange`).
    static func noteRange(
        _ whole: ScriptNote.Range,
        paragraph: (text: String, blocks: [Int])?,
        anchor: NoteAnchor?,
        diagnostics: DiagnosticCollector
    ) -> ScriptNote.Range {
        guard let anchor, let paragraph else { return whole }
        guard let span = NoteAnchor.resolve(paragraph.text, anchor) else {
            diagnostics.add(Diagnostic(
                code: "FDX_NOTE_ANCHOR_WORDS_CHANGED",
                severity: .info,
                message: "A note anchored to \(NoteAnchor.quoteWords(anchor.on)) was written on its "
                    + "whole paragraph: those words are no longer in it."
            ))
            return whole
        }
        return ScriptNote.Range(
            start: whole.start + unitOffset(paragraph.blocks, span.start, inclusive: true),
            end: whole.start + unitOffset(paragraph.blocks, span.end, inclusive: false)
        )
    }

    /// The anchor a Range carries, for a note eDraft owns (§5.4).
    ///
    /// A Range over the whole paragraph is no anchor at all — that is every
    /// note written before stage 4. A Range that spans paragraphs anchors to
    /// the words it covers in the first (§5.3 rule 6); FDX keeps its full
    /// span (TypeScript `anchorOfRange`).
    static func anchorOfRange(
        _ elements: [ScreenplayElement],
        _ anchor: ScriptNote.Anchor
    ) -> NoteAnchor? {
        guard anchor.start.element >= 0, anchor.start.element < elements.count else { return nil }
        let element = elements[anchor.start.element]
        let end = anchor.end.element == anchor.start.element
            ? anchor.end.offset
            : element.text.utf16.count
        return NoteAnchor.forSpan(element.text, start: anchor.start.offset, end: end)
    }

    private static let noteParagraphAttributes =
        "Alignment=\"Left\" FirstIndent=\"0.00\" Leading=\"Regular\" LeftIndent=\"0.00\" OutlineLevel=\"1\" RightIndent=\"1.39\" SpaceBefore=\"0\" Spacing=\"1\" StartsNewPage=\"No\""
    private static let noteTextAttributes = "AdornmentStyle=\"0\" Font=\"Arial\" RevisionID=\"0\" Size=\"12\" Style=\"\""
    /// WriterID carries nothing (IL-0024): one fixed value, never an identity.
    private static let noteWriterID = "00000000-0000-4000-8000-000000000001"

    /// One of the writer's notes as a Final Draft ScriptNote (RFC-NOTES-SYSTEM
    /// §4.2), in the shape Final Draft 13.4 opened, showed and kept whole:
    /// titled `[eDraft]`, the writer's name as its author, their role as the
    /// Type Final Draft shows in the note's dropdown, and one paragraph for each
    /// line of the message — the writer's words, once, and nothing else. Its
    /// lines, each with its depth under the note (TypeScript `scriptNoteLines`).
    static func scriptNoteLines(
        id: Int,
        author: String?,
        message: String,
        range: ScriptNote.Range,
        writing: ResolvedNoteWriting,
        diagnostics: DiagnosticCollector
    ) -> [(depth: Int, text: String)] {
        let refId = writing.newId()
        let (name, role) = nameAndRole(author ?? "")
        func value(_ text: String, _ context: String) -> String {
            encodeXmlValue(text, diagnostics: diagnostics, context: context)
        }
        var lines: [(depth: Int, text: String)] = [(0,
            "<ScriptNote Color=\"#000000000000\" DateModified=\"\(writing.now)\" DateTime=\"\(writing.now)\" Id=\"\(id)\""
            + " Name=\"\(eDraftTitle)\" Range=\"\(range.start),\(range.end)\""
            + " RefId=\"\(refId)\" Type=\"\(value(role, "note role"))\" WriterID=\"\(noteWriterID)\""
            + " WriterName=\"\(value(name, "note author"))\">"
        )]
        for text in message.components(separatedBy: "\n") {
            lines.append((1, "<Paragraph \(noteParagraphAttributes) id=\"\(writing.newId())\">"))
            lines.append((2, "<Text \(noteTextAttributes)>\(value(text, "note"))</Text>"))
            lines.append((1, "</Paragraph>"))
        }
        lines.append((0, "</ScriptNote>"))
        return lines
    }
}
