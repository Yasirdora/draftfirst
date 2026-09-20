import EDraftEngine
import UniformTypeIdentifiers
import XCTest
@testable import EDraftCore

/// A scene the production has cut — RFC-DRAFT-PRODUCTION §7.3.
///
/// The engine reads the `<OmittedScene>` block into the script and records
/// the span (IL-0071). These are the document's side of it: the span placed
/// on the editor's own lines by `DraftElementID`, the Navigator told once
/// instead of twice, and the page count that Final Draft would give.
@MainActor
final class OmittedSceneTests: XCTestCase {

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EDraftCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // EDraftCore/
            .deletingLastPathComponent()   // apple/
            .appendingPathComponent("eDraftEngine/Fixtures/\(name)"))
    }

    private func opened(_ data: Data) throws -> EditorState {
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: try XCTUnwrap(file.origin))
        return editor
    }

    /// A Final Draft file with one omitted scene: the card that prints, and
    /// the body nested inside it.
    private func omittedFixture() -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        <Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
        <Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>
        <Paragraph Number="21" Type="Scene Heading">
        <Text>OMITTED</Text>
        <OmittedScene>
        <Paragraph Type="Scene Heading"><Text>EXT. THE YARD - DUSK</Text></Paragraph>
        <Paragraph Type="Action"><Text>Mara waits.</Text></Paragraph>
        </OmittedScene>
        </Paragraph>
        <Paragraph Type="Scene Heading"><Text>INT. THE HALL - DAY</Text></Paragraph>
        <Paragraph Type="Action"><Text>She waits.</Text></Paragraph>
        </Content>
        </FinalDraft>
        """.utf8)
    }

    // MARK: - The span, placed on the document

    func testTheOmittedBodyIsMarkedAndTheCardIsNot() throws {
        let editor = try opened(omittedFixture())
        let elements = editor.screenplay.elements
        let named = elements.map { "\(editor.isOmitted($0) ? "omitted" : "live") \($0.text)" }
        XCTAssertEqual(named, [
            "live INT. KITCHEN - NIGHT",
            "live The kettle screams.",
            "live OMITTED",
            "omitted EXT. THE YARD - DUSK",
            "omitted Mara waits.",
            "live INT. THE HALL - DAY",
            "live She waits."
        ])
        let card = try XCTUnwrap(elements.first { $0.text == "OMITTED" })
        XCTAssertTrue(editor.omittedScenes.isCard(card), "the card carries the omission")
    }

    /// The span is held by identity, not by position — the whole reason it is
    /// converted at open. Type a line above it and the same scene is still
    /// the omitted one.
    func testAnEditAboveTheSpanLeavesTheRightSceneMarked() throws {
        let editor = try opened(omittedFixture())
        let before = editor.screenplay.elements.filter { editor.isOmitted($0) }.map(\.text)
        XCTAssertEqual(before, ["EXT. THE YARD - DUSK", "Mara waits."])

        var script = editor.screenplay
        script.elements.insert(
            ScriptElement(type: .action, text: "A line the writer just typed."), at: 1
        )
        editor.screenplay = script

        let after = editor.screenplay.elements.filter { editor.isOmitted($0) }.map(\.text)
        XCTAssertEqual(after, before, "the omission followed its elements, not their indices")
    }

    func testADocumentWithNoOriginCarriesNoOmission() throws {
        let editor = EditorState(source: "INT. KITCHEN - NIGHT\n\nThe kettle screams.\n")
        editor.attachImportedNotes(from: nil)
        XCTAssertTrue(editor.omittedScenes.isEmpty)
        XCTAssertFalse(editor.screenplay.elements.contains { editor.isOmitted($0) })
    }

    /// A reading that does not line up with the document is dropped rather
    /// than placed somewhere plausible: a mis-placed span greys out a scene
    /// the writer is working in.
    func testASpanThatCannotBePlacedIsDropped() {
        let document = [ScriptElement(type: .scene, text: "INT. KITCHEN - NIGHT", draftID: DraftElementID(rawValue: "1"))]
        let placed = Omissions.resolve(
            [EDraftEngine.Omission(start: 1, end: 3)],
            imported: [],
            document: document
        )
        XCTAssertTrue(placed.isEmpty)
    }

    // MARK: - The Navigator

    func testTheNavigatorShowsOneRowForAnOmittedScene() throws {
        let editor = try opened(omittedFixture())
        let rows = editor.scenes
        XCTAssertEqual(rows.map(\.title), [
            "INT. KITCHEN - NIGHT", "OMITTED", "INT. THE HALL - DAY"
        ], "the scene behind the card is not a row of its own")
        XCTAssertEqual(rows.map(\.omitted), [false, true, false])
        XCTAssertEqual(rows[1].sceneNumber, "21", "an omitted scene keeps its number")
    }

    /// The bug this stage exists to fix: a real Final Draft file showed its
    /// one omitted scene as two rows, both reading as scene 21.
    func testTheRealFileShowsScene21Once() throws {
        let editor = try opened(try fixture("finaldraft-sample02.fdx"))
        XCTAssertFalse(editor.omittedScenes.isEmpty, "sample02 has an omitted scene")
        let twentyOnes = editor.scenes.filter { $0.sceneNumber == "21" }
        XCTAssertEqual(twentyOnes.count, 1, "scene 21 appears once")
        XCTAssertTrue(try XCTUnwrap(twentyOnes.first).omitted)
        XCTAssertFalse(
            editor.scenes.contains { $0.title == "Ext. Xx xxx xxxxxx xxxx - dusk" },
            "the scene behind the card is not a row"
        )
    }

    // MARK: - Pagination

    /// *Measured on the fixture Final Draft 13.4 wrote:* the OMITTED card
    /// records `Length="0" Page="17"`, and the scene inside the block records
    /// `Page="1"` against a script whose 35 live scenes run 1 to 25. Final
    /// Draft does not count an omitted scene toward page numbers.
    func testTheOmittedBodyIsNotPaginated() throws {
        let editor = try opened(omittedFixture())
        let model = editor.screenplay.engineModel
        let paginable = Omissions.paginable(
            model, document: editor.screenplay.elements, omitted: editor.omittedScenes
        )
        XCTAssertEqual(paginable.model.elements.map(\.text), [
            "INT. KITCHEN - NIGHT", "The kettle screams.", "OMITTED",
            "INT. THE HALL - DAY", "She waits."
        ])
        XCTAssertEqual(paginable.kept, [0, 1, 2, 5, 6], "the card keeps its place")
    }

    /// Page numbers come back keyed by the script's own indices, so the
    /// Navigator's page column still points at the right lines.
    func testPageNumbersAreKeyedBackToTheScript() {
        let restored = Omissions.restored([0: 1, 1: 1, 2: 1, 3: 2, 4: 2], through: [0, 1, 2, 5, 6])
        XCTAssertEqual(restored, [0: 1, 1: 1, 2: 1, 5: 2, 6: 2])
        XCTAssertNil(restored[3], "an omitted element is on no page")
        XCTAssertNil(restored[4])
    }

    func testWithoutAnOmissionThePaginatorSeesTheWholeScript() throws {
        let editor = EditorState(source: "INT. KITCHEN - NIGHT\n\nThe kettle screams.\n")
        let model = editor.screenplay.engineModel
        let paginable = Omissions.paginable(
            model, document: editor.screenplay.elements, omitted: OmittedScenes()
        )
        XCTAssertEqual(paginable.model.elements.count, model.elements.count)
        XCTAssertEqual(paginable.kept, Array(model.elements.indices))
    }
}
