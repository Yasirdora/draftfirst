import XCTest
@testable import EDraftCore
@testable import EDraftEngine

/// The paste route reads a production draft's printed furniture (routing
/// pack, step 1): page numbers, (MORE) and CONTINUED are dropped and never
/// stored; a numbered scene heading is a scene whose number has a home in
/// the model; and a pasted line no signal claims is prose, not the
/// choreography's next guess. The witnesses are the corpus's own:
/// gone-girl's flanked headings, corpus-6's OMITTED cards, breaking-bad's
/// "1148. So my records show I paid".
@MainActor
final class ProductionDraftPasteTests: XCTestCase {

    /// The route the surfaces take: a paste's signal-less line falls back
    /// to prose. `fallback: nil` answers as typing does, for contrast.
    private func paste(_ source: String, fallback: ScreenplayKind? = .action) -> ScreenplayEditPlanner.Plan? {
        ScreenplayEditPlanner.plan(
            elements: [ScriptElement(type: .action, text: "")],
            replacing: NSRange(location: 0, length: 0),
            with: source,
            intent: .multilinePaste,
            kindForNewElement: { previous, text, depth in
                EditorState(source: "").kindForInsertedElement(
                    after: previous, text: text, pasteDepth: depth, fallback: fallback
                )
            }
        )
    }

    /// The raw path drops the printed page's furniture: no page number,
    /// (MORE) or CONTINUED is ever stored as an element.
    func testTheRawPathDropsPaginationArtifacts() {
        let plan = paste([
            "1.",
            "",
            "INT. CAFE - DAY",
            "",
            "WALTER",
            "",
            "I am the one who knocks.",
            "",
            "(MORE)",
            "",
            "CONTINUED:",
            "",
            "17.",
            "",
            "The cafe hums."
        ].joined(separator: "\n"))

        XCTAssertEqual(
            plan?.elements.map(\.type),
            [.scene, .character, .dialogue, .action]
        )
        XCTAssertEqual(
            plan?.elements.filter {
                PasteHeuristics.isPaginationArtifact($0.text)
            }.count, 0,
            "no artifact is stored — the printed page's furniture is dropped"
        )
    }

    /// A (MORE) splits a speech, not a thought: the hard-wrapped speech
    /// under way joins straight across it.
    func testAHardWrappedSpeechJoinsAcrossMore() {
        let plan = paste([
            "WALTER",
            "I am the one who knocks, and this speech runs long enough to wrap",
            "under the courier's right edge, the way a speech does.",
            "(MORE)",
            "And the speech continues on the page that follows, long enough to",
            "keep wrapping past the courier's right edge once more.",
            "SKYLER",
            "Walter, sit down. We need to talk about what happened last night."
        ].joined(separator: "\n"))

        XCTAssertEqual(
            plan?.elements.map(\.type),
            [.character, .dialogue, .character, .dialogue]
        )
        XCTAssertEqual(
            plan?.elements[1].text,
            "I am the one who knocks, and this speech runs long enough to wrap "
                + "under the courier's right edge, the way a speech does. "
                + "And the speech continues on the page that follows, long enough to "
                + "keep wrapping past the courier's right edge once more.",
            "one speech — the (MORE) neither stored nor splitting"
        )
    }

    /// The indented scheme: a page number at the margin does not move the
    /// column, and the speech it interrupts is one paragraph.
    func testAnIndentedPageNumberDoesNotSplitTheSpeech() {
        let plan = paste([
            "INT. CAFE - DAY",
            "          WALTER",
            "                I am the one who knocks, and this speech runs",
            "17.",
            "                long enough to need a second line of dialogue."
        ].joined(separator: "\n"))

        XCTAssertEqual(
            plan?.elements.map(\.type),
            [.scene, .character, .dialogue]
        )
        XCTAssertEqual(
            plan?.elements[2].text,
            "I am the one who knocks, and this speech runs "
                + "long enough to need a second line of dialogue.",
            "the speech is one paragraph — the page number never happened"
        )
    }

    /// gone-girl's shape: the flanking number repeats the leader, a
    /// revision asterisk on its tail, and both are furniture.
    func testANumberedHeadingHomesItsNumberAndShedsItsFlanking() {
        let plan = paste([
            "2 EXT. NORTH CARTHAGE- MORNING 2",
            "",
            "The house sits quiet at the end of the street.",
            "",
            "3 EXT. NICK DUNNE'S FRONT YARD- DAWN 3*",
            "",
            "Dew on the lawn."
        ].joined(separator: "\n"))

        XCTAssertEqual(plan?.elements.map(\.type), [.scene, .action, .scene, .action])
        XCTAssertEqual(plan?.elements[0].text, "EXT. NORTH CARTHAGE- MORNING")
        XCTAssertEqual(plan?.elements[0].sceneNumber, "2")
        XCTAssertEqual(plan?.elements[2].text, "EXT. NICK DUNNE'S FRONT YARD- DAWN")
        XCTAssertEqual(plan?.elements[2].sceneNumber, "3")
    }

    /// corpus-6's and episode-101's shape: an omitted scene keeps its
    /// number and prints the card, numbered or bare.
    func testTheOmittedCardIsAScene() {
        let plan = paste([
            "113 OMITTED.",
            "",
            "114 INT. BANKSIDE HOME - NIGHT",
            "",
            "OMITTED"
        ].joined(separator: "\n"))

        XCTAssertEqual(plan?.elements.map(\.type), [.scene, .scene, .scene])
        XCTAssertEqual(plan?.elements[0].text, "OMITTED")
        XCTAssertEqual(plan?.elements[0].sceneNumber, "113")
        XCTAssertEqual(plan?.elements[1].text, "INT. BANKSIDE HOME - NIGHT")
        XCTAssertEqual(plan?.elements[1].sceneNumber, "114")
        XCTAssertEqual(plan?.elements[2].text, "OMITTED")
        XCTAssertNil(plan?.elements[2].sceneNumber)
    }

    /// The flanking number is stripped only when it repeats the leader:
    /// "APARTMENT 4" is a place, not a coincidence.
    func testAFlankingNumberThatIsNotTheLeaderStays() {
        let plan = paste("2 INT. APARTMENT 4")
        XCTAssertEqual(plan?.elements.map(\.type), [.scene])
        XCTAssertEqual(plan?.elements[0].text, "INT. APARTMENT 4")
        XCTAssertEqual(plan?.elements[0].sceneNumber, "2")
    }

    /// The hard-wrapped path: a numbered heading mid-paste opens a scene
    /// paragraph, and the planner homes its number.
    func testAHardWrappedNumberedHeadingOpensAScene() {
        let plan = paste([
            "The night crew works the perimeter in silence, flashlights low,",
            "radios murmuring the coded nothing of a quiet shift.",
            "15 INT. HOLE.",
            "A single bulb burns over the table where the ledger lies open,",
            "its columns added and added again by hands that never shake.",
            "16 INT. CORRIDOR.",
            "Footsteps approach from the far end, unhurried, and stop short",
            "of the door."
        ].joined(separator: "\n"))

        XCTAssertEqual(
            plan?.elements.map(\.type),
            [.action, .scene, .action, .scene, .action]
        )
        XCTAssertEqual(plan?.elements[1].text, "INT. HOLE.")
        XCTAssertEqual(plan?.elements[1].sceneNumber, "15")
        XCTAssertEqual(plan?.elements[3].text, "INT. CORRIDOR.")
        XCTAssertEqual(plan?.elements[3].sceneNumber, "16")
    }

    /// breaking-bad's cast-list junk: "1148. So my records show I paid"
    /// arrived after a speech and the choreography adopted it as a cue
    /// named "1148. SO MY RECORDS SHOW I PAID". A paste is not typing —
    /// the line no signal claims is prose.
    func testASignalLessPastedLineIsProseNotTheChoreographysGuess() {
        let source = [
            "WALTER",
            "",
            "I pay my debts.",
            "",
            "1148. So my records show I paid"
        ].joined(separator: "\n")

        XCTAssertEqual(
            paste(source)?.elements.map(\.type),
            [.character, .dialogue, .action],
            "with the paste fallback the line is prose"
        )
        XCTAssertEqual(
            paste(source, fallback: nil)?.elements.map(\.type),
            [.character, .dialogue, .character],
            "without it the choreography still answers a cue — typing's contract, kept"
        )
    }

    /// The classifier's arm, named directly: the numbered heading is a
    /// scene wherever it lands.
    func testTheClassifierTypesEveryWitnessedNumberedShape() {
        let editor = EditorState(source: "")
        for heading in [
            "2 EXT. NORTH CARTHAGE- MORNING 2",
            "15 INT. HOLE.",
            "113 OMITTED.",
            "OMITTED"
        ] {
            XCTAssertEqual(
                editor.kindForInsertedElement(after: nil, text: heading), .scene, heading
            )
        }
    }
}
