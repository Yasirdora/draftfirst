import Foundation
import Testing
import EDraftEngine

/// A Final Draft file's ScriptNotes, read beside the screenplay.
///
/// Conformance against the `scriptNotes` section of `Fixtures/fdx.json`, and
/// the facts measured on `Fixtures/sample0-2.fdx` — a real feature's eleven
/// notes, anonymised so that every paragraph keeps its length and every Range
/// still lands where it did.
@Suite("FDX ScriptNotes")
struct FdxScriptNotesTests {

    private static let corpus: FdxCorpus.Root = {
        do { return try FixtureStore.load("fdx.json") }
        catch {
            Issue.record("Failed to load fdx.json: \(error)")
            return FdxCorpus.Root(importCases: [], exportCases: [])
        }
    }()

    private static let sample: String = {
        do {
            return try String(
                contentsOf: FixtureStore.directory.appendingPathComponent("sample0-2.fdx"),
                encoding: .utf8
            )
        } catch {
            Issue.record("Failed to load sample0-2.fdx: \(error)")
            return ""
        }
    }()

    private static let notes: [String: Fdx.ScriptNote] = Dictionary(
        uniqueKeysWithValues: Fdx.parse(sample).scriptNotes.compactMap { note in
            note.id.map { ($0, note) }
        }
    )

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.scriptNoteCases.count == 12)
    }

    @Test("reading", arguments: Self.corpus.scriptNoteCases)
    func reading(_ case_: FdxCorpus.ScriptNotesCase) throws {
        let result = Fdx.parse(try case_.xml(), options: case_.importOptions)
        #expect(result.scriptNotes == case_.expected.scriptNotes,
                "\(case_.name): script notes differ from the TypeScript engine")
        #expect(result.diagnostics == case_.expected.diagnostics,
                "\(case_.name): diagnostics differ from the TypeScript engine")
        if let script = case_.expected.script {
            #expect(result.script == script,
                    "\(case_.name): imported screenplay differs from the TypeScript engine")
        }
    }

    @Test("eleven notes in file order, each by the writer the file names")
    func authors() {
        let notes = Fdx.parse(Self.sample).scriptNotes
        #expect(notes.compactMap(\.id)
            == ["107", "113", "143", "119", "152", "137", "108", "109", "110", "111", "112"])
        #expect(notes.filter { $0.author == "Writer A" }.compactMap(\.id)
            == ["107", "143", "152", "108", "109", "110", "111", "112"])
        #expect(notes.filter { $0.author == "Writer B" }.compactMap(\.id) == ["113", "119", "137"])
    }

    /* The Ranges in sample0-2.fdx were measured before an eDraft save moved
       its text; the files Final Draft wrote are where a Range can be held to
       the words it was written on (TypeScript: the same proofs). */
    private static func finalDraftWritten(_ name: String) -> Fdx.ImportResult {
        do {
            return Fdx.parse(try String(
                contentsOf: FixtureStore.directory.appendingPathComponent(name), encoding: .utf8
            ))
        } catch {
            Issue.record("Failed to load \(name): \(error)")
            return Fdx.parse("")
        }
    }

    @Test("Every note in a file Final Draft wrote lands on whole words, or is empty",
          arguments: [("finaldraft-sample02.fdx", 11, 10), ("finaldraft-sample01.fdx", 12, 11)])
    func wholeWords(_ name: String, notes: Int, onWords: Int) {
        let result = Self.finalDraftWritten(name)
        let elements = result.script.elements
        func midWord(_ at: Fdx.ScriptNote.Position) -> Bool {
            let units = Array(elements[at.element].text.utf16)
            func letter(_ index: Int) -> Bool {
                guard index >= 0, index < units.count,
                      let scalar = Unicode.Scalar(units[index]) else { return false }
                return scalar.properties.isAlphabetic || scalar.properties.numericType != nil
            }
            return letter(at.offset - 1) && letter(at.offset)
        }
        #expect(result.scriptNotes.count == notes)
        #expect(result.scriptNotes.filter { $0.anchor == nil }.compactMap(\.id) == [], "\(name): notes with no anchor")
        #expect(result.scriptNotes.filter { note in
            guard let anchor = note.anchor else { return false }
            return midWord(anchor.start) || midWord(anchor.end)
        }.compactMap(\.id) == [], "\(name): notes landing mid-word")
        #expect(result.scriptNotes.filter { $0.anchor.map { $0.start == $0.end } ?? false }.count == notes - onWords)
    }

    @Test("Ranges land on the words Final Draft measured them on, two units for each embedded block before them")
    func anchors() {
        let result = Self.finalDraftWritten("finaldraft-sample02.fdx")
        let elements = result.script.elements
        func at(_ id: String) -> Fdx.ScriptNote.Anchor? { result.scriptNotes.first { $0.id == id }?.anchor }
        func span(_ element: Int, _ start: Int, _ endElement: Int, _ end: Int) -> Fdx.ScriptNote.Anchor {
            .init(start: .init(element: element, offset: start), end: .init(element: endElement, offset: end))
        }
        // Before any block: the shot it is about, whole.
        #expect(at("107") == span(6, 0, 6, 20))
        #expect(elements[6].type == .shot && elements[6].text.utf16.count == 20)
        // After five dual dialogues: exactly one action line.
        #expect(at("109") == span(310, 0, 310, 41))
        #expect(elements[310].type == .action && elements[310].text.utf16.count == 41)
        /* Exactly one line of dialogue. Past the omitted scene, every element
           index is eight further on than it was before the omitted body was
           read into the script (§7.3) — the Range values in the file, and
           every offset here, are untouched: only the model grew. */
        #expect(at("110") == span(556, 0, 556, 6))
        #expect(elements[556].type == .dialogue && elements[556].text.utf16.count == 6)
        // After the omitted scene too: from a cue to the start of the next line.
        #expect(at("111") == span(601, 0, 603, 0))
        // Zero-length, at the end of the script's last line.
        #expect(at("112") == span(787, 13, 787, 13))
        /* 780 before the omitted scene's eight paragraphs were read. */
        #expect(elements.count == 788)
    }

    @Test("a body keeps its paragraphs, blank ones included")
    func bodies() {
        let long = Self.notes["112"]?.text.split(separator: "\n", omittingEmptySubsequences: false) ?? []
        #expect(long.count == 9)
        #expect(long.filter(\.isEmpty).count == 4)
        let scene = Self.notes["137"]?.text.split(separator: "\n", omittingEmptySubsequences: false) ?? []
        #expect(scene.count == 8)
    }

    @Test("what the file leaves empty is absent")
    func absentFields() {
        #expect(Self.notes["143"]?.color == nil)          // #000000000000
        #expect(Self.notes["107"]?.color == "#6363A7A7EFEF")
        #expect(Self.notes["152"]?.title == nil)          // Name=""
        #expect(Self.notes["143"]?.title == "Re: Re: Xxxx Xxx")
        #expect(Self.notes["137"]?.category == "Alt Scenes")
    }

    /// The <ScriptNotes> block, as bytes.
    private static func scriptNotesBlock(_ xml: String) -> [UInt8]? {
        guard let start = xml.range(of: "<ScriptNotes>"),
              let end = xml.range(of: "</ScriptNotes>") else { return nil }
        return Array(xml[start.lowerBound..<end.upperBound].utf8)
    }

    @Test("a save with no edit keeps the ScriptNotes block byte for byte")
    func noEditKeepsNotes() {
        let document = Fdx.open(Self.sample)
        let saved = document.rewrite(document.script)
        #expect(Self.scriptNotesBlock(saved) != nil)
        #expect(Self.scriptNotesBlock(saved) == Self.scriptNotesBlock(Self.sample))
    }

    @Test("editing an annotated line keeps every byte of the ScriptNotes block but the Ranges that follow their words")
    func editKeepsNotes() {
        let document = Fdx.open(Self.sample)
        var script = document.script
        script.elements[536].text = "XXXXXX (V.O.)"
        let saved = document.rewrite(script)
        #expect(saved.contains("XXXXXX (V.O.)"))
        #expect(Self.scriptNotesBlock(ScriptNoteRanges.emptied(saved)) == Self.scriptNotesBlock(ScriptNoteRanges.emptied(Self.sample)))
    }

    /* IL-0033: a save keeps every ScriptNote on its words. Final Draft counts a
       Range over the script as it stands; copied unchanged, one word typed near
       the start moved ten of the eleven notes in sample02 off their words
       (TypeScript: the same proofs). */

    /// The words a note covers, as the import reads them.
    private static func covered(_ script: Screenplay, _ anchor: Fdx.ScriptNote.Anchor?) -> String? {
        guard let anchor else { return nil }
        var texts = script.elements[anchor.start.element...anchor.end.element].map { Array($0.text.utf16) }
        if texts.count == 1 {
            return String(decoding: texts[0][anchor.start.offset..<anchor.end.offset], as: UTF16.self)
        }
        texts[0] = Array(texts[0][anchor.start.offset...])
        texts[texts.count - 1] = Array(texts[texts.count - 1][..<anchor.end.offset])
        return texts.map { String(decoding: $0, as: UTF16.self) }.joined(separator: "\n")
    }

    @Test("After any edit, every note the edit did not touch covers the same words",
          arguments: ["finaldraft-sample02.fdx", "finaldraft-sample01.fdx"])
    func notesKeepTheirWords(_ name: String) throws {
        let xml = try String(contentsOf: FixtureStore.directory.appendingPathComponent(name), encoding: .utf8)
        let before = Fdx.parse(xml)
        let reading = try FountainReading.of(xml)
        var noted = Set<Int>()
        for note in before.scriptNotes {
            if let anchor = note.anchor { noted.formUnion(anchor.start.element...anchor.end.element) }
        }
        // Lines the reading holds at the import's own index, with no note on them.
        let free = reading.elements.indices.filter { index in
            let element = reading.elements[index]
            return index < before.script.elements.count && element.text == before.script.elements[index].text
                && element.text.contains(" ") && !noted.contains(index) && element.type == .action
        }
        let spread = (0..<6).map { free[((($0 + 1) * free.count) / 8)] }
        let dual = try #require(reading.elements.firstIndex { $0.dual == true })
        var edits: [(String, (inout [ScreenplayElement]) -> Void)] = []
        for at in spread {
            edits.append(("a word typed in line \(at)", { elements in
                if let space = elements[at].text.firstIndex(of: " ") {
                    elements[at].text.replaceSubrange(space...space, with: " QZQZ ")
                }
            }))
        }
        for at in spread.prefix(3) {
            edits.append(("a word deleted in line \(at)", { elements in
                elements[at].text = elements[at].text.replacingOccurrences(of: #" \S+"#, with: "", options: .regularExpression, range: elements[at].text.range(of: #" \S+"#, options: .regularExpression))
            }))
        }
        edits.append(("a line added", { elements in elements.insert(ScreenplayElement(type: .action, text: "A new line."), at: free[1]) }))
        edits.append(("a line deleted", { elements in elements.remove(at: free[1]) }))
        edits.append(("a dual dialogue line edited", { elements in elements[dual + 1].text = "Q" + elements[dual + 1].text }))
        edits.append(("a dual dialogue dissolved", { elements in elements[dual].dual = nil }))
        #expect(edits.count >= 12)

        for (label, change) in edits {
            var edited = reading
            change(&edited.elements)
            let saved = Fdx.open(xml).rewrite(edited, unedited: reading)
            let after = Fdx.parse(saved)
            let off = zip(before.scriptNotes, after.scriptNotes).filter { original, now in
                Self.covered(before.script, original.anchor) != Self.covered(after.script, now.anchor)
            }.compactMap { $0.0.id }
            #expect(off.isEmpty, "\(name), \(label): notes off their words \(off)")
            #expect(Self.scriptNotesBlock(ScriptNoteRanges.emptied(saved)) == Self.scriptNotesBlock(ScriptNoteRanges.emptied(xml)),
                    "\(name), \(label): more than Range values changed")
        }
    }

    @Test("An edit inside a note's words stays inside the note; a note whose words are all deleted closes where they stood")
    func notesFollowTheirWords() throws {
        let xml = try String(contentsOf: FixtureStore.directory.appendingPathComponent("finaldraft-sample02.fdx"), encoding: .utf8)
        let reading = try FountainReading.of(xml)

        var inside = reading
        if let space = inside.elements[310].text.firstIndex(of: " ") {
            inside.elements[310].text.replaceSubrange(space...space, with: " INSIDE ")
        }
        let edited = Fdx.parse(Fdx.open(xml).rewrite(inside, unedited: reading))
        #expect(edited.script.elements[310].text.contains("INSIDE"))
        #expect(Self.covered(edited.script, edited.scriptNotes.first { $0.id == "109" }?.anchor) == edited.script.elements[310].text)

        var gone = reading
        gone.elements.removeSubrange(52...53)   // note 108's line of dialogue, and its cue
        let deleted = Fdx.parse(Fdx.open(xml).rewrite(gone, unedited: reading)).scriptNotes.first { $0.id == "108" }
        #expect(deleted?.range == .init(start: 2177, end: 2177))
        #expect(deleted?.anchor == .init(start: .init(element: 52, offset: 0), end: .init(element: 52, offset: 0)))
    }

    @Test("A note keeps its edges: typed at an edge stays out, typed inside joins, written end first stays so, stale stays stale")
    func noteEdges() {
        func lab(_ lines: [String], _ ranges: [String]) -> String {
            "<FinalDraft><Content>\n" + lines.map { "<Paragraph Type=\"Action\"><Text>\($0)</Text></Paragraph>" }.joined(separator: "\n")
                + "\n</Content><ScriptNotes>"
                + ranges.enumerated().map { "<ScriptNote Id=\"\($0.offset + 1)\" Range=\"\($0.element)\"><Paragraph><Text>n</Text></Paragraph></ScriptNote>" }.joined()
                + "</ScriptNotes></FinalDraft>"
        }
        // Paragraphs start at 0, 9 and 21; the script ends at 30.
        let xml = lab(["One two.", "Three four.", "Five six."], ["0,3", "9,14", "19,15", "30,30", "99,120"])
        let document = Fdx.open(xml)
        func edited(_ texts: [String]) -> Screenplay {
            Screenplay(titlePage: [], elements: texts.map { ScreenplayElement(type: .action, text: $0) })
        }
        #expect(document.rewrite(edited(["One and two.", "Thrxee four.", "Five six."]))
                == lab(["One and two.", "Thrxee four.", "Five six."], ["0,3", "13,19", "24,20", "35,35", "99,120"]))
        #expect(document.rewrite(edited(["One two.", "Five six."]))
                == lab(["One two.", "Five six."], ["0,3", "9,9", "9,9", "18,18", "99,120"]))
    }
}

/// Which notes are eDraft's: a ScriptNote titled `[eDraft]`
/// (RFC-NOTES-SYSTEM §4.3, IL-0043). Mirrors the TypeScript engine's
/// fdx.test.ts.
@Suite("FDX notes eDraft wrote")
struct FdxOwnedNoteTests {

    private static func file(_ title: String, writerName: String = "Sam Okafor", type: String = "Director") -> String {
        """
        <FinalDraft><Content>
        <Paragraph Type="Action"><Text>Hum.</Text></Paragraph>
        </Content><ScriptNotes><ScriptNote Id="1" Name="\(title)" Range="0,4" Type="\(type)" WriterName="\(writerName)"><Paragraph><Text>Words.</Text></Paragraph></ScriptNote></ScriptNotes></FinalDraft>
        """
    }

    static let owned: [(String, String, String)] = [
        ("Sam Okafor", "Director", "Sam Okafor (Director): Words."),
        ("Sam Okafor", "", "Sam Okafor: Words."),
        ("", "", "Words."),
        // After an edit in Final Draft: the title kept, the author re-stamped.
        ("x", "Director", "x (Director): Words.")
    ]

    @Test("a note titled [eDraft] comes back as the writer's own", arguments: owned.indices)
    func ownedNote(_ index: Int) {
        let (writerName, type, text) = Self.owned[index]
        let read = Fdx.parse(Self.file("[eDraft]", writerName: writerName, type: type))
        #expect(read.scriptNotes.isEmpty)
        #expect(read.script.elements == [
            ScreenplayElement(type: .note, text: text),
            ScreenplayElement(type: .action, text: "Hum.")
        ])
    }

    static let theirs: [(String, String)] = [
        ("Tighter?", "Sam Okafor"),
        ("", "Sam Okafor"),
        ("", "[eDraft] Sam Okafor"),
        ("eDraft", "Sam Okafor")
    ]

    @Test("a note stays Final Draft's when retitled, untitled, marked the IL-0042 way, or titled without brackets",
          arguments: theirs.indices)
    func finalDraftsNote(_ index: Int) {
        let (title, writerName) = Self.theirs[index]
        let read = Fdx.parse(Self.file(title, writerName: writerName))
        #expect(read.scriptNotes.count == 1)
        #expect(read.script.elements == [ScreenplayElement(type: .action, text: "Hum.")])
    }

    @Test("a whole new file writes a note as a ScriptNote, never a line of the script")
    func wholeFile() {
        let script = Screenplay(elements: [
            ScreenplayElement(type: .action, text: "Visible."),
            ScreenplayElement(type: .note, text: "Check this against the schedule.")
        ])
        let result = Fdx.write(script, options: Fdx.ExportOptions(notes: NoteWritingSpec.pinned.writing()))
        #expect(!result.xml.contains("Type=\"Note\""))
        #expect(!result.xml.contains("[eDraft thread"))
        #expect(result.xml.contains(
            ##"<ScriptNote Color="#000000000000" DateModified="20260918T120000" DateTime="20260918T120000" Id="1" Name="[eDraft]" Range="0,8" RefId="00000000-0000-4000-8000-000000000001" Type="Director" WriterID="00000000-0000-4000-8000-000000000001" WriterName="Dana Reyes">"##
        ))
        #expect(result.xml.contains(#">Check this against the schedule.</Text>"#))
        #expect(result.diagnostics.isEmpty)
        // Read back, it is the writer's own note, signed. A note after the last
        // line is anchored to the last paragraph, so it comes back in front of it.
        #expect(Fdx.parse(result.xml).script.elements == [
            ScreenplayElement(type: .note, text: "Dana Reyes (Director): Check this against the schedule."),
            ScreenplayElement(type: .action, text: "Visible.")
        ])
    }
}
