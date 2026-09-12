import XCTest
@testable import EDraftCore
@testable import EDraftEngine

/// The paste route learns the act card (RFC-ACT-BREAK §5): a pasted
/// TEASER or ACT ONE is a boundary, never a speaker, and the closing
/// card — END TEASER, END OF ACT ONE — is dropped, because an act ends
/// where the next one begins. The witnesses are Breaking Bad's own
/// cards, the one script in the corpus that carries them.
@MainActor
final class ActBreakPasteTests: XCTestCase {

    private func paste(_ source: String) -> ScreenplayEditPlanner.Plan? {
        ScreenplayEditPlanner.plan(
            elements: [ScriptElement(type: .action, text: "")],
            replacing: NSRange(location: 0, length: 0),
            with: source,
            intent: .multilinePaste,
            kindForNewElement: { previous, text, depth in
                EditorState(source: "").kindForInsertedElement(
                    after: previous, text: text, pasteDepth: depth
                )
            }
        )
    }

    /// Breaking Bad's own opening, verbatim in shape: the teaser's card,
    /// its closing card, the first act. Unindented and blank-separated,
    /// so the planner takes the raw line-per-element path.
    func testActCardsAreBoundariesAndEndCardsAreDropped() {
        let plan = paste([
            "TEASER",
            "",
            "EXT. COW PASTURE - DAY",
            "",
            "Deep blue sky overhead. Fat, scuddy clouds.",
            "",
            "END TEASER",
            "",
            "ACT ONE",
            "",
            "EXT. WHITE HOUSE - NIGHT"
        ].joined(separator: "\n"))

        XCTAssertEqual(
            plan?.elements.map(\.type),
            [.actbreak, .scene, .action, .actbreak, .scene]
        )
        XCTAssertEqual(plan?.elements.first?.text, "TEASER")
        XCTAssertEqual(
            plan?.elements.filter { $0.type == .character }.count, 0,
            "no card is adopted as a speaker"
        )
        XCTAssertNil(
            plan?.elements.first { $0.text.contains("END") },
            "the closing card is furniture — dropped, never stored"
        )
    }

    /// Speech position must not swallow the boundary: an act card after a
    /// cue is still the act, not something the character says.
    func testAnActCardInsideASpeechRunIsStillTheBoundary() {
        let plan = paste([
            "WALTER",
            "",
            "I am the one who knocks.",
            "",
            "END OF ACT ONE",
            "",
            "ACT TWO",
            "",
            "EXT. DESERT - DAY"
        ].joined(separator: "\n"))

        XCTAssertEqual(
            plan?.elements.map(\.type),
            [.character, .dialogue, .actbreak, .scene]
        )
    }

    /// The hard-wrapped path reads its tells from the words: the card is
    /// structural there too, and the end card ends the paragraph under
    /// way — nothing joins across it.
    func testAHardWrappedPasteDropsTheEndCardBetweenParagraphs() {
        let plan = paste([
            "WALTER",
            "I am the one who knocks, and this speech runs long enough to wrap",
            "under the courier's right edge.",
            "END OF ACT ONE",
            "ACT TWO",
            "The desert lies quiet and wide under a hard midday sun, heat rising",
            "off the blacktop in sheets. Nothing moves out there but the wind,",
            "and nothing has moved for a hundred years."
        ].joined(separator: "\n"))

        let types = plan?.elements.map(\.type)
        XCTAssertEqual(types, [.character, .dialogue, .actbreak, .action])
        XCTAssertEqual(
            plan?.elements[1].text,
            "I am the one who knocks, and this speech runs long enough to wrap "
                + "under the courier's right edge.",
            "the speech ends at the boundary — nothing joins across it"
        )
        XCTAssertEqual(
            plan?.elements.last?.text,
            "The desert lies quiet and wide under a hard midday sun, heat rising "
                + "off the blacktop in sheets. Nothing moves out there but the wind, "
                + "and nothing has moved for a hundred years.",
            "and prose after the card is its own paragraph, not the card's"
        )
    }

    /// A customised card is the writer's text, not a boundary the paste
    /// route claims; a lowercase one is prose until the writer shouts it.
    func testCustomisedAndLowercaseCardsAreNotClaimed() {
        XCTAssertNotEqual(
            EditorState(source: "").kindForInsertedElement(after: nil, text: "ACT TWO: THE TURN"),
            .actbreak
        )
        XCTAssertNotEqual(
            EditorState(source: "").kindForInsertedElement(after: nil, text: "Act One"),
            .actbreak
        )
        XCTAssertNotEqual(
            EditorState(source: "").kindForInsertedElement(after: nil, text: "teaser"),
            .actbreak
        )
    }

    /// The classifier's arm, named directly: the cards the corpus carries
    /// are act breaks wherever they land.
    func testTheClassifierTypesEveryWitnessedCard() {
        let editor = EditorState(source: "")
        for card in ["TEASER", "COLD OPEN", "ACT ONE", "ACT 4"] {
            XCTAssertEqual(
                editor.kindForInsertedElement(after: nil, text: card), .actbreak, card
            )
        }
    }
}
