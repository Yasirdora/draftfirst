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
        #expect(Self.corpus.scriptNoteCases.count == 10)
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
        #expect(at("109") == span(295, 0, 295, 41))
        #expect(elements[295].type == .action && elements[295].text.utf16.count == 41)
        // Exactly one line of dialogue.
        #expect(at("110") == span(533, 0, 533, 6))
        #expect(elements[533].type == .dialogue && elements[533].text.utf16.count == 6)
        // After the omitted scene too: from a cue to the start of the next line.
        #expect(at("111") == span(578, 0, 580, 0))
        // Zero-length, at the end of the script's last line.
        #expect(at("112") == span(761, 13, 761, 13))
        #expect(elements.count == 762)
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

    @Test("editing an annotated line keeps the ScriptNotes block byte for byte")
    func editKeepsNotes() {
        let document = Fdx.open(Self.sample)
        var script = document.script
        script.elements[536].text = "XXXXXX (V.O.)"
        let saved = document.rewrite(script)
        #expect(saved.contains("XXXXXX (V.O.)"))
        #expect(Self.scriptNotesBlock(saved) == Self.scriptNotesBlock(Self.sample))
    }
}
