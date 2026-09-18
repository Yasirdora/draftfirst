import Foundation
import Testing
import EDraftEngine

/// Conformance of `Fountain.parse` against `Fixtures/parse.json`: eleven
/// scripts (sample, edge headings, edge dialogue, structural, title page,
/// empty, whitespace chaos, torture, 871-element feature, note brackets,
/// asides in dialogue) parsed by the TypeScript engine, compared
/// element-for-element.
@Suite("Fountain parse conformance")
struct FountainParseConformanceTests {

    private static let corpus: [ParseCorpus.Case] = {
        do { return try FixtureStore.load("parse.json") }
        catch {
            Issue.record("Failed to load parse.json: \(error)")
            return []
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.count == 11)
    }

    @Test("parse", arguments: Self.corpus)
    func parse(_ case_: ParseCorpus.Case) throws {
        let parsed = try Fountain.parse(case_.source)
        #expect(parsed == case_.expected,
                "\(case_.name): parsed screenplay differs from the TypeScript engine")
    }
}

/// Conformance of `Fountain.serialise` against `Fixtures/serialise.json`.
@Suite("Fountain serialise conformance")
struct FountainSerialiseConformanceTests {

    private static let corpus: [SerialiseCorpus.Case] = {
        do { return try FixtureStore.load("serialise.json") }
        catch {
            Issue.record("Failed to load serialise.json: \(error)")
            return []
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.count == 11)
    }

    @Test("serialise", arguments: Self.corpus)
    func serialise(_ case_: SerialiseCorpus.Case) {
        #expect(Fountain.serialise(case_.screenplay) == case_.expected,
                "\(case_.name): serialised Fountain differs from the TypeScript engine")
    }

    /// Semantic round-trip: parsing each serialised corpus output must
    /// reproduce an equal screenplay (the TS engine's stability guarantee).
    @Test("round-trip stability", arguments: Self.corpus)
    func roundTrip(_ case_: SerialiseCorpus.Case) throws {
        let reparsed = try Fountain.parse(case_.expected)
        #expect(reparsed == case_.screenplay,
                "\(case_.name): serialise → parse round-trip is not stable")
    }
}

/// Notes that end in `]` or hold `]]` (IL-0038). The writer used to write
/// `[[` + text + `]]`: a note ending in `]` went to disk as `]]]`, the reader
/// closed at the first `]]`, and the next open cut the note short and printed
/// a stray `]` into the script. Mirrors the TypeScript engine's parse.test.ts.
@Suite("Fountain notes that end in ] or hold ]]")
struct FountainNoteBracketTests {

    private static func around(_ note: String) -> String {
        "INT. KITCHEN - NIGHT\n\n\(note)\n\nThe kettle screams.\n"
    }

    private static func scene(_ text: String) -> Screenplay {
        Screenplay(elements: [
            ScreenplayElement(type: .scene, text: "INT. KITCHEN - NIGHT"),
            ScreenplayElement(type: .note, text: text),
            ScreenplayElement(type: .action, text: "The kettle screams.")
        ])
    }

    private static func written(_ text: String) -> String {
        Fountain.serialise(Screenplay(elements: [ScreenplayElement(type: .note, text: text)]))
    }

    @Test("reads a note the old writer ended in `]]]` whole, and prints nothing")
    func oldWriterNoteEndingInBracket() throws {
        let parsed = try Fountain.parse(Self.around("[[Dana: see [scene 4]]]"))
        #expect(parsed.elements == Self.scene("Dana: see [scene 4]").elements)
    }

    @Test("reads a header-only note whole")
    func headerOnly() throws {
        let parsed = try Fountain.parse(Self.around("[[[eDraft thread:t4k9qz status:open]]]"))
        #expect(parsed.elements == Self.scene("[eDraft thread:t4k9qz status:open]").elements)
    }

    @Test("closes a note at the end of a run of `]`: the rest are its text")
    func runOfBrackets() throws {
        let parsed = try Fountain.parse(Self.around("[[x]]]]"))
        #expect(parsed.elements == Self.scene("x]]").elements)
    }

    @Test("reads an inline note ending in `]` whole, leaving the line without a stray `]`")
    func inlineNote() throws {
        let parsed = try Fountain.parse("Mara waits [[see [4]]] by the door.\n")
        #expect(parsed.elements == [
            ScreenplayElement(type: .note, text: "see [4]"),
            ScreenplayElement(type: .action, text: "Mara waits  by the door.")
        ])
    }

    @Test("a note survives save and reopen", arguments: [
        "Dana: see [scene 4]",
        "[eDraft thread:t4k9qz status:open]",
        "x]]",
        "]",
        "see [[4]] later",
        "a]]]b",
        "Dana (Director): one\nSam (Writer): see [4]"
    ])
    func roundTrip(_ text: String) throws {
        let reopened = try Fountain.parse(Fountain.serialise(Self.scene(text)))
        #expect(reopened.elements == Self.scene(text).elements, "\(text)")
    }

    @Test("the only `]]` the writer writes in a note is its close, so an older reader reads it whole",
          arguments: ["Dana: see [scene 4]", "[eDraft thread:t4k9qz status:open]", "x]]", "]",
                      "see [[4]] later", "a]]]b"])
    func onlyCloseIsDoubleBracket(_ text: String) {
        let note = Self.written(text)
        #expect(note.hasPrefix("[["))
        let firstClose = note.range(of: "]]", range: note.index(note.startIndex, offsetBy: 2)..<note.endIndex)
        #expect(firstClose?.lowerBound == note.index(note.endIndex, offsetBy: -2), "\(note)")
    }

    @Test("writes a note with no `]` at its end and no `]]` inside exactly as before")
    func unchangedNotes() {
        for text in ["rewrite this beat", "a [bracket] inside", "Dir: [beat]. Then go."] {
            #expect(Self.written(text) == "[[\(text)]]")
        }
    }

    @Test("the chosen asymmetry (RFC §13): a note typed `a] ]b` returns as `a]]b`")
    func chosenAsymmetry() throws {
        #expect(Self.written("a] ]b") == "[[a] ]b]]")
        let reopened = try Fountain.parse(Self.around(Self.written("a] ]b")))
        #expect(reopened.elements == Self.scene("a]]b").elements)
    }
}

/// Asides inside a dialogue block (IL-0040). The editor puts a note in front
/// of the line it is about; inside a dialogue block it was written as its own
/// paragraph between blank lines, which ended the block, and the next open
/// read the cue and the speech as Action. Mirrors the TypeScript engine's
/// parse.test.ts.
@Suite("Fountain asides inside a dialogue block")
struct FountainDialogueAsideTests {

    private static func reopened(_ elements: [ScreenplayElement]) throws -> [ScreenplayElement] {
        let heading = ScreenplayElement(type: .scene, text: "INT. KITCHEN - NIGHT")
        let written = Fountain.serialise(Screenplay(elements: [heading] + elements))
        return Array(try Fountain.parse(written, emphasis: .runs).elements.dropFirst())
    }

    private static func cue(_ text: String, dual: Bool = false) -> ScreenplayElement {
        dual ? ScreenplayElement(type: .character, text: text, dual: true)
            : ScreenplayElement(type: .character, text: text)
    }
    private static func speech(_ text: String) -> ScreenplayElement { ScreenplayElement(type: .dialogue, text: text) }
    private static func paren(_ text: String) -> ScreenplayElement { ScreenplayElement(type: .parenthetical, text: text) }
    private static func note(_ text: String) -> ScreenplayElement { ScreenplayElement(type: .note, text: text) }

    static let oneLineCases: [(String, [ScreenplayElement])] = [
        ("between the cue and the speech", [cue("BOB"), note("n1"), speech("Hello.")]),
        ("two of them there", [cue("BOB"), note("n1"), note("n2"), speech("Hello.")]),
        ("before a parenthetical", [cue("BOB"), note("n1"), paren("(beat)"), speech("Hello.")]),
        ("after a parenthetical", [cue("BOB"), paren("(beat)"), note("n1"), speech("Hello.")]),
        ("in the middle of a speech", [cue("BOB"), speech("Hello."), note("n1"), paren("(beat)"), speech("Again.")]),
        ("between two lines of one speech", [cue("BOB"), speech("Line one"), note("n1"), speech("Line two")]),
        ("inside a dual second speech", [cue("BOB"), speech("Hi."), cue("ANN", dual: true), note("n1"), speech("Ho.")]),
        ("ending in ] (IL-0038)", [cue("BOB"), note("see [scene 4]"), speech("Hello.")])
    ]

    @Test("a one-line note stays exactly where it was", arguments: oneLineCases.indices)
    func oneLineNote(_ index: Int) throws {
        let (label, elements) = Self.oneLineCases[index]
        #expect(try Self.reopened(elements) == elements, "\(label)")
    }

    @Test("a note before an emphasised speech keeps the emphasis")
    func emphasis() throws {
        let elements = [
            Self.cue("BOB"),
            Self.note("n1"),
            ScreenplayElement(
                type: .dialogue, text: "Hello there.",
                runs: [StyleRun(start: 0, end: 5, styles: [.bold])]
            )
        ]
        #expect(try Self.reopened(elements) == elements)
    }

    static let movedCases: [(String, ScreenplayElement)] = [
        ("a note of two lines", ScreenplayElement(type: .note, text: "first\nsecond")),
        ("a synopsis", ScreenplayElement(type: .synopsis, text: "The kettle wins.")),
        ("a section", ScreenplayElement(type: .section, text: "Beat", depth: 3))
    ]

    @Test("an aside that cannot go inline moves in front of the cue, and the block survives",
          arguments: movedCases.indices)
    func movedInFront(_ index: Int) throws {
        let (label, aside) = Self.movedCases[index]
        let reopened = try Self.reopened([Self.cue("BOB"), Self.paren("(beat)"), aside, Self.speech("Hello.")])
        #expect(reopened == [aside, Self.cue("BOB"), Self.paren("(beat)"), Self.speech("Hello.")], "\(label)")
    }

    @Test("a run holding anything that cannot go inline moves whole, in order")
    func runMovesWhole() throws {
        let synopsis = ScreenplayElement(type: .synopsis, text: "The kettle wins.")
        let reopened = try Self.reopened([Self.cue("BOB"), Self.note("n1"), synopsis, Self.note("n2"), Self.speech("Hello.")])
        #expect(reopened == [Self.note("n1"), synopsis, Self.note("n2"), Self.cue("BOB"), Self.speech("Hello.")])
    }

    @Test("writes a one-line note inside a block inline on the line after it")
    func writtenInline() {
        let written = Fountain.serialise(Screenplay(elements: [
            Self.cue("BOB"), Self.note("n1"), Self.note("n2"), Self.speech("Hello.")
        ]))
        #expect(written == "BOB\nHello. [[n1]] [[n2]]")
    }

    @Test("writes a note before a dual second speaker as before, and the pair survives")
    func dualCueAsBefore() throws {
        let elements = [Self.cue("BOB"), Self.speech("Hi."), Self.note("n1"), Self.cue("ANN", dual: true), Self.speech("Ho.")]
        #expect(Fountain.serialise(Screenplay(elements: elements)) == "BOB\nHi.\n\n[[n1]]\n\nANN ^\nHo.")
        #expect(try Self.reopened(elements) == elements)
    }

    @Test("writes an aside outside a dialogue block exactly as before")
    func outsideAsBefore() throws {
        let elements = [
            Self.note("before the cue"), Self.cue("BOB"), Self.speech("Hello."),
            Self.note("after the block"), ScreenplayElement(type: .action, text: "The kettle screams.")
        ]
        #expect(Fountain.serialise(Screenplay(elements: elements))
            == "[[before the cue]]\n\nBOB\nHello.\n\n[[after the block]]\n\nThe kettle screams.")
        #expect(try Self.reopened(elements) == elements)
    }
}
