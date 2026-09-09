import XCTest
@testable import EDraftCore

/// The writer's outline is in the document and not on the page.
///
/// Final Draft's Outline levels and its Summary are how a writer holds an act,
/// a sequence and a beat. Read as General they printed as stage directions and
/// paginated — four pages of outline counted as script on one of the two
/// production drafts this was measured on.
@MainActor
final class EditorOutlineTests: XCTestCase {

    private func editor(_ source: String) -> EditorState {
        EditorState(source: source)
    }

    private let script = """
    # Act One

    = They meet, badly.

    ## Meet Tangle

    INT. LAB - DAY

    She waits by the centrifuge.
    """

    func testTheOutlineIsLiftedOffThePage() {
        let editor = editor(script)

        XCTAssertEqual(
            editor.screenplay.elements.map(\.type), [.scene, .action],
            "the outline was left on the page"
        )
        XCTAssertEqual(editor.outline.map(\.kind), [.section, .synopsis, .section])
        XCTAssertEqual(editor.outline.map(\.text), ["Act One", "They meet, badly.", "Meet Tangle"])
    }

    /// The level is what makes an act an act and a beat a beat.
    func testEachHeadingKeepsItsLevel() {
        let editor = editor("# Act One\n\n## Meet Tangle\n\n### Set up Gold Key\n\nINT. LAB - DAY")
        XCTAssertEqual(editor.outline.compactMap(\.depth), [1, 2, 3])
    }

    /// The heading belongs to the line under it, which is how the Navigator
    /// will know where to send a reader who taps it.
    func testAHeadingIsAnchoredToTheLineBelowIt() {
        let editor = editor(script)
        let heading = try? XCTUnwrap(editor.screenplay.elements.first)
        XCTAssertEqual(editor.outline.map(\.anchor), [heading?.id, heading?.id, heading?.id])
    }

    func testTheOutlineGoesBackIntoTheSavedSource() {
        let editor = editor(script)
        var published: String?
        editor.onSourceChange = { published = $0 }
        editor.flushPendingWork()

        let saved = published ?? ""
        XCTAssertTrue(saved.contains("# Act One"), "the act heading was lost")
        XCTAssertTrue(saved.contains("## Meet Tangle"), "the sequence heading lost its level")
        XCTAssertTrue(saved.contains("= They meet, badly."), "the summary was lost")
    }

    /// The number a production schedules against. An outline that paginated
    /// made the script longer than it is.
    func testTheOutlineDoesNotLengthenTheScript() {
        let withOutline = editor(script)
        let without = editor("INT. LAB - DAY\n\nShe waits by the centrifuge.")
        XCTAssertEqual(withOutline.screenplay.elements.count, without.screenplay.elements.count)
    }

    /// Notes and the outline share one seam; both have to survive it.
    func testNotesAndOutlineComeBackTogetherInDocumentOrder() {
        let source = "# Act One\n\n[[Open colder.]]\n\n= They meet.\n\nINT. LAB - DAY\n\nShe waits."
        let editor = editor(source)
        XCTAssertEqual(editor.asides.map(\.kind), [.section, .note, .synopsis])
        XCTAssertEqual(editor.notes.map(\.text), ["Open colder."])
        XCTAssertEqual(editor.outline.map(\.text), ["Act One", "They meet."])

        var published: String?
        editor.onSourceChange = { published = $0 }
        editor.flushPendingWork()
        let saved = published ?? ""
        XCTAssertTrue(saved.contains("# Act One"))
        XCTAssertTrue(saved.contains("[[Open colder.]]"))
        XCTAssertTrue(saved.contains("= They meet."))
    }
}
