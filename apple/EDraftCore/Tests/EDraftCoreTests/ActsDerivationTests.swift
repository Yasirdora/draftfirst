import XCTest
import EDraftEngine
@testable import EDraftCore

/// The Navigator's act rows and the surface side of the renumber rule
/// (RFC-ACT-BREAK §2, §4). The rule itself is the engine's, pinned by the
/// shared corpus; what these tests pin is the bridge — page ranges from the
/// real paginator's rows, the "you are here" mark, and the delta adapter.
@MainActor
final class ActsDerivationTests: XCTestCase {

    private func element(_ type: ScreenplayKind, _ text: String) -> ScriptElement {
        ScriptElement(type: type, text: text)
    }

    private func editor(with elements: [ScriptElement]) -> EditorState {
        let editor = EditorState(source: "INT. NOWHERE - DAY\n\nPlaceholder.")
        editor.replaceAllElements(
            elements,
            activeID: elements.first?.id,
            offset: 0,
            structural: true,
            recordsUndo: false
        )
        return editor
    }

    // MARK: - The page map

    /// The act card arrives from the paginator as an element line with its
    /// index, on a page of its own — the fact the page ranges are built on.
    func testThePageMapRecordsAnActBreaksOwnPage() throws {
        let model = Screenplay(elements: [
            ScreenplayElement(type: .scene, text: "INT. ROOM - DAY"),
            ScreenplayElement(type: .action, text: "Quiet."),
            ScreenplayElement(type: .actbreak, text: "ACT ONE"),
            ScreenplayElement(type: .scene, text: "INT. KITCHEN - LATER")
        ])
        let pages = try Paginator.paginate(model, linesPerPage: PageFormat.current.linesPerPage)
        let map = EditorState.elementPages(in: pages)
        XCTAssertEqual(map[0], 1)
        XCTAssertEqual(map[2], 2, "the card opens the page the break-before rule gave it")
        XCTAssertEqual(map[3], 2)
    }

    // MARK: - The derivation

    private func makeEditor() -> EditorState {
        editor(with: [
            element(.scene, "INT. ROOM - DAY"), element(.action, "Quiet."),
            element(.actbreak, "ACT ONE"),
            element(.scene, "INT. KITCHEN - LATER"), element(.action, "Coffee."),
            element(.actbreak, "ACT TWO"),
            element(.scene, "INT. HALL - NIGHT"), element(.action, "A door."),
            element(.actbreak, "ACT THREE")
        ])
    }

    func testActsListInOrderWithTheirCards() {
        let editor = makeEditor()
        XCTAssertEqual(editor.acts.map(\.ordinal), [1, 2, 3])
        XCTAssertEqual(editor.acts.map(\.title), ["ACT ONE", "ACT TWO", "ACT THREE"])
        XCTAssertEqual(editor.acts.map(\.elementIndex), [2, 5, 8])
    }

    func testActPageRangesRunToTheNextCardOrTheDocumentsEnd() {
        let editor = makeEditor()
        // Element indices: 0 scene, 1 action, 2 ACT ONE, 3 scene, 4 action,
        // 5 ACT TWO, 6 scene, 7 action, 8 ACT THREE.
        editor.stats = ScreenplayStats(
            pages: 12, runtime: "~12 minutes", words: 30,
            elementPages: [0: 1, 1: 1, 2: 3, 3: 4, 4: 4, 5: 6, 6: 7, 7: 7, 8: 10]
        )
        let acts = editor.acts
        XCTAssertEqual(acts[0].firstPage, 3)
        XCTAssertEqual(acts[0].lastPage, 5, "act one ends the page before act two's card")
        XCTAssertEqual(acts[1].lastPage, 9)
        XCTAssertEqual(acts[2].lastPage, 12, "the last act runs to the document's end")
        XCTAssertEqual(acts[0].pageRangeLabel, "3–5")
        XCTAssertEqual(acts[2].pageRangeLabel, "10–12")
    }

    func testAnEmptyActSpansItsOwnPageAlone() {
        let editor = editor(with: [
            element(.actbreak, "ACT ONE"),
            element(.actbreak, "ACT TWO"),
            element(.action, "Content.")
        ])
        editor.stats = ScreenplayStats(
            pages: 3, runtime: "~3 minutes", words: 5,
            elementPages: [0: 1, 1: 2, 2: 3]
        )
        XCTAssertEqual(editor.acts[0].firstPage, 1)
        XCTAssertEqual(editor.acts[0].lastPage, 1)
        XCTAssertEqual(editor.acts[0].pageRangeLabel, "1", "a one-page act names its page, not a span")
    }

    func testAScriptWithoutActsListsNone() {
        let editor = EditorState(source: "INT. ROOM - DAY\n\nQuiet.")
        XCTAssertTrue(editor.acts.isEmpty)
        XCTAssertNil(editor.activeActID)
    }

    // MARK: - You are here

    func testTheCaretAboveTheFirstCardIsInNoAct() {
        let editor = makeEditor()
        editor.selectionChanged(elementID: editor.screenplay.elements[0].id, offset: 0)
        XCTAssertNil(editor.activeActID)
    }

    func testAnActOwnsEverythingDownToTheNextCard() {
        let editor = makeEditor()
        let acts = editor.acts
        editor.selectionChanged(elementID: editor.screenplay.elements[4].id, offset: 0)
        XCTAssertEqual(editor.activeActID, acts[0].id, "the coffee is act one's")
        editor.selectionChanged(elementID: editor.screenplay.elements[6].id, offset: 0)
        XCTAssertEqual(editor.activeActID, acts[1].id)
        editor.selectionChanged(elementID: editor.screenplay.elements[8].id, offset: 0)
        XCTAssertEqual(editor.activeActID, acts[2].id, "a caret on the card is in that act")
    }

    // MARK: - The renumber bridge

    func testTheDeltaNamesOnlyTheCardsThatChange() {
        let elements = [
            element(.actbreak, "ACT ONE"),
            element(.action, "Middle."),
            element(.actbreak, "ACT THREE")
        ]
        XCTAssertEqual(ScreenplayEditPlanner.renumberedActCards(in: elements), [2: "ACT TWO"])
    }

    func testTheDeltaLeavesCustomisedCardsAndOtherElementsOut() {
        let elements = [
            element(.scene, "INT. ROOM - DAY"),
            element(.actbreak, "ACT ONE"),
            element(.actbreak, "TEASER"),
            element(.actbreak, "ACT TWO")
        ]
        XCTAssertEqual(
            ScreenplayEditPlanner.renumberedActCards(in: elements), [3: "ACT THREE"],
            "TEASER is never rewritten, but its act still counts"
        )
    }

    func testASequentialScriptProducesTheEmptyDelta() {
        let elements = [element(.actbreak, "ACT ONE"), element(.actbreak, "ACT TWO")]
        XCTAssertTrue(ScreenplayEditPlanner.renumberedActCards(in: elements).isEmpty)
    }

    func testTheDefaultCardIsOnePastTheCount() {
        XCTAssertEqual(ScreenplayEditPlanner.defaultActCard(forInsertionInto: []), "ACT ONE")
        let two = [element(.actbreak, "ACT ONE"), element(.actbreak, "ACT TWO")]
        XCTAssertEqual(ScreenplayEditPlanner.defaultActCard(forInsertionInto: two), "ACT THREE")
    }
}
