import EDraftEngine
import UniformTypeIdentifiers
import XCTest
@testable import EDraftCore

/// Final Draft's act breaks through the app's own road — IL-0096.
///
/// `ScreenplayFile.open` carries an .fdx into the Fountain source of truth,
/// and Fountain has no act spelling: every `New Act` came back a centred
/// line. The model then had no acts — no Navigator acts, no renumber, no
/// page an act starts — and every road that writes from the model said so in
/// the file: Export wrote the cards as centred General paragraphs, and a
/// save after the writer touched a card rewrote Final Draft's `New Act` as
/// `<Paragraph Type="General" Alignment="Center">`. The Fountain boundary
/// now reads a centred act card (`Acts.isActCard`) as the break it was.
///
/// The file is one Final Draft 13 wrote (`finaldraft-acts.fdx`, anonymised;
/// its header says how), with four New Act elements added in Final Draft. A
/// custom card — `ACT THREE: THE TURN` — keeps the named degradation
/// (RFC-ACT-BREAK §3) and is pinned as such.
///
/// Final Draft writes each New Act as a PAIR sharing one id: an empty
/// self-closing paragraph, then the paragraph with the card. Both engines'
/// FDX readers take the empty one for an act break of its own, and the
/// editor opens it as a blank centred line. That is a KNOWN GAP, stated by the
/// two `testKnownGap…` tests below exactly as it reads today; the lock that
/// follows IL-0096 flips them. Every other test here asserts on the cards.
@MainActor
final class ActBreakRoundTripTests: XCTestCase {

    private func fixture() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EDraftCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // EDraftCore/
            .deletingLastPathComponent()   // apple/
            .appendingPathComponent("eDraftEngine/Fixtures/finaldraft-acts.fdx")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Opened the way the app opens a document: the file to Fountain, the
    /// Fountain to the editor, the original kept for the save.
    private func opened(_ fdx: String) throws -> (EditorState, origin: String) {
        let file = try ScreenplayFile.open(Data(fdx.utf8), as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        return (editor, try XCTUnwrap(file.origin))
    }

    /// Saved the way the app saves: the editor's published source, spliced
    /// into the original.
    private func saved(_ editor: EditorState, origin: String) throws -> String {
        let source = try XCTUnwrap(editor.lastKnownSource)
        let data = try ScreenplayFile.encode(
            source, as: .finalDraftScreenplay, origin: origin, omissions: editor.publishedOmissions
        )
        return String(decoding: data, as: UTF8.self)
    }

    /// Every act break the engine reads straight from a file, empty twins
    /// included — the known gap.
    private func fileActBreaks(_ fdx: String) -> [String] {
        Fdx.parse(fdx).script.elements.filter { $0.type == .actbreak }.map(\.text)
    }

    /// The cards the engine reads from a file — the act breaks with words on
    /// them. The empty twins are the known gap's, not these tests'.
    private func fileActs(_ fdx: String) -> [String] {
        fileActBreaks(fdx).filter { !$0.isEmpty }
    }

    private func editorActs(_ editor: EditorState) -> [String] {
        editor.screenplay.elements.filter { $0.type == .actbreak }.map(\.text)
    }

    private static let canonical = ["TEASER", "ACT ONE", "ACT TWO"]

    /// Final Draft's own shape: four cards, each written as a pair — an empty
    /// self-closing New Act, then the card, with one id between them.
    func testTheFixtureIsAFinalDraftFileWithActs() throws {
        let fdx = try fixture()
        XCTAssertEqual(fileActs(fdx), Self.canonical + ["ACT THREE: THE TURN"])
        let content = try XCTUnwrap(fdx.components(separatedBy: "<Content>").dropFirst().first)
        let empty = content.matches(of: #/<Paragraph Type="New Act" id="([0-9a-f-]+)"/>/#).map { String($0.1) }
        let full = content.matches(of: #/<Paragraph Type="New Act" id="([0-9a-f-]+)">/#).map { String($0.1) }
        XCTAssertEqual(empty.count, 4, "an empty twin before each card")
        XCTAssertEqual(empty, full, "each twin shares its card's id")
    }

    // MARK: - Known gap: Final Draft's empty twin (flipped by the next lock)

    /// KNOWN GAP. The engine reads each empty twin as an act break of its
    /// own: eight act breaks for four cards. The next lock reads the pair as
    /// one act break and flips this to the four cards.
    func testKnownGapTheEngineReadsEachEmptyTwinAsAnActBreak() throws {
        XCTAssertEqual(fileActBreaks(try fixture()),
                       ["", "TEASER", "", "ACT ONE", "", "ACT TWO", "", "ACT THREE: THE TURN"])
    }

    /// KNOWN GAP. Through the Fountain boundary each empty twin opens as a
    /// blank centred line in front of its card. The next lock flips this: no
    /// line in front of any card.
    func testKnownGapEachEmptyTwinOpensAsABlankCentredLine() throws {
        let (editor, _) = try opened(try fixture())
        let elements = editor.screenplay.elements
        for card in Self.canonical + ["ACT THREE: THE TURN"] {
            let at = try XCTUnwrap(elements.firstIndex { $0.text == card }, card)
            XCTAssertEqual(elements[at - 1].type, .centered, card)
            XCTAssertEqual(elements[at - 1].text, " ", card)
        }
    }

    // MARK: - Open

    func testOpeningAFinalDraftFileKeepsItsActBreaks() throws {
        let (editor, _) = try opened(try fixture())
        XCTAssertEqual(editorActs(editor), Self.canonical, "every act card opens as an act break")
        XCTAssertEqual(editor.acts.count, Self.canonical.count, "the Navigator's acts")
    }

    /// Named, not fixed: Fountain has no act spelling, and a custom card is
    /// the writer's text (RFC-ACT-BREAK §3).
    func testACustomCardOpensCentredAsTheRFCSays() throws {
        let (editor, _) = try opened(try fixture())
        let custom = try XCTUnwrap(editor.screenplay.elements.first { $0.text == "ACT THREE: THE TURN" })
        XCTAssertEqual(custom.type, .centered)
    }

    // MARK: - Save, and open again

    /// The brief's fail-before: open, save, open the save — the act breaks
    /// are still act breaks, in the file and in the editor.
    func testOpenSaveReopenKeepsEveryActBreak() throws {
        let (editor, origin) = try opened(try fixture())
        var elements = editor.screenplay.elements
        let last = try XCTUnwrap(elements.lastIndex { $0.type == .action })
        elements[last].text += " Then silence."
        XCTAssertTrue(editor.replaceAllElements(elements, activeID: elements[last].id, offset: 0, structural: true))
        let file = try saved(editor, origin: origin)
        XCTAssertEqual(fileActs(file), Self.canonical + ["ACT THREE: THE TURN"])
        let (reopened, _) = try opened(file)
        XCTAssertEqual(editorActs(reopened), Self.canonical)
    }

    /// Retypes the card, with a new line in front of it — the edit the save
    /// cannot pair with Final Draft's paragraph, so it writes the card from
    /// the model. That is where the type was lost.
    private func restructure(_ editor: EditorState, card: String, to text: String) throws {
        var elements = editor.screenplay.elements
        let at = try XCTUnwrap(elements.firstIndex { $0.text == card }, card)
        elements[at].text = text
        elements.insert(ScriptElement(type: .action, text: "A new line."), at: at)
        XCTAssertTrue(editor.replaceAllElements(elements, activeID: elements[at + 1].id, offset: 0, structural: true))
    }

    /// Written from the model, a canonical card is a New Act — not centred
    /// General text, which is what the save used to write.
    func testACardTheSaveWritesFromTheModelIsANewAct() throws {
        let (editor, origin) = try opened(try fixture())
        try restructure(editor, card: "ACT TWO", to: "ACT 2")
        let file = try saved(editor, origin: origin)
        XCTAssertEqual(fileActs(file), ["TEASER", "ACT ONE", "ACT 2", "ACT THREE: THE TURN"])
        XCTAssertFalse(file.contains("Alignment=\"Center\"><Text>ACT 2"), "the card was written as centred General text")
    }

    /// The degradation, pinned where it bites (RFC-ACT-BREAK §3): a custom
    /// card the save writes from the model is centred General text. Its
    /// words survive; its type does not.
    func testACustomCardTheSaveWritesFromTheModelIsCentredAsTheRFCSays() throws {
        let (editor, origin) = try opened(try fixture())
        try restructure(editor, card: "ACT THREE: THE TURN", to: "ACT THREE: THE LONG TURN")
        let file = try saved(editor, origin: origin)
        XCTAssertEqual(fileActs(file), Self.canonical)
        XCTAssertTrue(file.contains("ACT THREE: THE LONG TURN"), "the words survive")
    }

    /// And where it does not: a custom card the save can pair with Final
    /// Draft's paragraph keeps that paragraph's type.
    func testACustomCardRetypedInPlaceKeepsItsNewAct() throws {
        let (editor, origin) = try opened(try fixture())
        var elements = editor.screenplay.elements
        let custom = try XCTUnwrap(elements.firstIndex { $0.text == "ACT THREE: THE TURN" })
        elements[custom].text = "ACT THREE: THE LONG TURN"
        XCTAssertTrue(editor.replaceAllElements(elements, activeID: elements[custom].id, offset: 0, structural: true))
        XCTAssertEqual(fileActs(try saved(editor, origin: origin)), Self.canonical + ["ACT THREE: THE LONG TURN"])
    }

    func testANoEditSaveIsTheFileByteForByte() throws {
        let fdx = try fixture()
        let file = try ScreenplayFile.open(Data(fdx.utf8), as: .finalDraftScreenplay)
        let data = try ScreenplayFile.encode(file.source, as: .finalDraftScreenplay, origin: file.origin)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), fdx)
    }

    // MARK: - Export, and the Fountain road

    /// Export writes from the model, not the file: it had no acts to write.
    func testExportingToFinalDraftWritesNewActs() throws {
        let (editor, _) = try opened(try fixture())
        let exported = ScreenplayExporter.fdxSource(editor.screenplay)
        XCTAssertEqual(fileActs(exported), Self.canonical)
    }

    func testAFountainFileKeepsItsActCardsAndItsBytes() throws {
        let source = "INT. LAB - DAY\n\nShe waits.\n\n> ACT ONE <\n\nEXT. YARD - DUSK\n\nMara waits.\n\n> ACT TWO: THE TURN <\n"
        let editor = EditorState(source: source)
        XCTAssertEqual(editorActs(editor), ["ACT ONE"])
        let custom = try XCTUnwrap(editor.screenplay.elements.first { $0.text == "ACT TWO: THE TURN" })
        XCTAssertEqual(custom.type, .centered)
        let written = try ScreenplayFile.encode(source, as: .plainText)
        XCTAssertEqual(String(decoding: written, as: UTF8.self), source)
    }
}
