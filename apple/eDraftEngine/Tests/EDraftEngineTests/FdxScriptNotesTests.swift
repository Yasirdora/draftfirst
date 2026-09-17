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
        #expect(Self.corpus.scriptNoteCases.count == 7)
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

    @Test("Ranges land on the text they were measured on")
    func anchors() {
        let elements = Fdx.parse(Self.sample).script.elements
        // Exactly one whole character cue.
        #expect(Self.notes["110"]?.anchor == .init(
            start: .init(element: 536, offset: 0), end: .init(element: 536, offset: 6)
        ))
        #expect(elements[536].type == .character)
        #expect(elements[536].text.utf16.count == 6)
        // The shot it is about, from its first character.
        #expect(Self.notes["107"]?.anchor?.start == .init(element: 6, offset: 0))
        #expect(elements[6].type == .shot)
        // Zero-length, inside the absorbed End of Act: the next element.
        #expect(Self.notes["112"]?.range == .init(start: 25736, end: 25736))
        #expect(Self.notes["112"]?.anchor?.start == .init(element: 766, offset: 0))
        // Across elements.
        #expect(Self.notes["137"]?.anchor?.start.element == 17)
        #expect(Self.notes["137"]?.anchor?.end.element == 27)
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
