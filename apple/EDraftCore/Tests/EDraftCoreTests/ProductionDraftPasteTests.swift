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
            kindForNewElement: { previous, text, depth, attached in
                EditorState(source: "").kindForInsertedElement(
                    after: previous, text: text, pasteDepth: depth,
                    attached: attached, fallback: fallback
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

    /// The production page's footer — draft colour, date, page number —
    /// is furniture too: 650 witnesses across seven corpus files.
    func testTheRawPathDropsDraftStampFooters() {
        let plan = paste([
            "Pink (9/10/2013) 2", "",
            "10/29/14 / 2.", "",
            "Revision 2.", "",
            "GG- Yellow Revisions 9/27/13 4.", "",
            "The Irishman D1-5 SZ 9.15.09 2.", "",
            "FINAL SHOOTING SCRIPT Pink 7.25.06", "",
            "GREEN REVISIONS 12/14/19", "",
            "INT. CAFE - DAY"
        ].joined(separator: "\n"))

        XCTAssertEqual(plan?.elements.map(\.type), [.scene])
        XCTAssertEqual(plan?.elements.map(\.text), ["INT. CAFE - DAY"])
    }

    /// The bare date is not a stamp — it belongs to the title page the
    /// paste route does not model yet — and the sentence is prose whatever
    /// it mentions.
    func testTheRawPathKeepsTheDatesThatAreNotStamps() {
        let plan = paste([
            "1/5/1999", "",
            "5/27/05", "",
            "28/29/30 OUT", "",
            "He delivered the FINAL DRAFT on 9/10/2013, late.", "",
            "INT. CAFE - DAY"
        ].joined(separator: "\n"))

        XCTAssertEqual(
            plan?.elements.map(\.text),
            ["1/5/1999", "5/27/05", "28/29/30 OUT",
             "He delivered the FINAL DRAFT on 9/10/2013, late.", "INT. CAFE - DAY"]
        )
    }

    /// The scene number set loose from its heading is furniture: corpus-6's
    /// "4A", lalaland's "A1" (×42), the page's twin numbers "1 1"
    /// (whiplash ×134) and "1A 1A" (foryourcon) — a pair counts only when
    /// both numbers are equal. "APARTMENT 4A" is a place, not furniture;
    /// "1 2" is not a twin.
    func testTheRawPathDropsLooseSceneNumbers() {
        let plan = paste([
            "4A", "", "A1", "", "1 1", "", "1A 1A", "", "23A.", "",
            "INT. CAFE - DAY", "", "APARTMENT 4A", "", "1 2"
        ].joined(separator: "\n"))

        XCTAssertEqual(
            plan?.elements.map(\.text),
            ["INT. CAFE - DAY", "APARTMENT 4A", "1 2"]
        )
    }

    /// gone-girl ×1,426, whiplash ×21 ("TRUMPETER #2 **"), corpus-6 ×189:
    /// the revision asterisk riding a line's tail is furniture, and the
    /// content keeps its own ending.
    func testTheRawPathStripsTheRevisionAsterisk() {
        let plan = paste([
            "INT. CAFE - DAY", "",
            "AMY wakes, turns, gives a look of alarm.*", "",
            "TRUMPETER #2 **"
        ].joined(separator: "\n"))

        XCTAssertEqual(
            plan?.elements.map(\.text),
            ["INT. CAFE - DAY", "AMY wakes, turns, gives a look of alarm.", "TRUMPETER #2"]
        )
    }

    /// corpus-6 ×115: the bare margin mark sits alone on its line inside a
    /// wrapped paragraph — it drops the way (MORE) does, and the thought
    /// under way continues across it: attachment survives the furniture,
    /// so the raw route keeps the continuation speech.
    func testTheBareMarginMarkDropsAndTheThoughtContinuesAcrossIt() {
        let plan = paste([
            "MARA",
            "The first part of the speech",
            "*",
            "and the rest of it."
        ].joined(separator: "\n"))

        XCTAssertEqual(plan?.elements.map(\.type), [.character, .dialogue, .dialogue])
        XCTAssertEqual(
            plan?.elements.map(\.text),
            ["MARA", "The first part of the speech", "and the rest of it."]
        )
    }

    /// The cue-shaped interruption: an uppercase line inside an attached
    /// run is a new speaker, not a shouted continuation — the TypeScript
    /// engine's arm 7, whose shouts keep their terminal punctuation.
    func testAnAttachedCueInterruptsTheSpeech() {
        let plan = paste([
            "MARA",
            "The first part of the speech",
            "runs on under the courier's right edge.",
            "SKYLER",
            "Sit down."
        ].joined(separator: "\n"))

        XCTAssertEqual(
            plan?.elements.map(\.type),
            [.character, .dialogue, .dialogue, .character, .dialogue]
        )
    }

    /// The protection clause: a body holding a star keeps its ending, so
    /// the emphasis marker's tail is never eaten — "**MARK**" stays a
    /// bolded cue, and the sentence keeps the asterisk its own text
    /// carries.
    func testTheStripNeverEatsTheEmphasisMarkersTail() {
        let plan = paste(["**MARK**", "", "He said **exactly** that.*"].joined(separator: "\n"))

        XCTAssertEqual(plan?.elements.map(\.type), [.character, .dialogue])
        XCTAssertEqual(plan?.elements.map(\.text), ["MARK", "He said exactly that.*"])
        XCTAssertEqual(plan?.elements[0].runs, [StyleRun(start: 0, end: 4, styles: .bold)])
        XCTAssertEqual(plan?.elements[1].runs, [StyleRun(start: 8, end: 15, styles: .bold)])
    }

    /// pasted-26 ×199: a stray NUL is a UTF-16 paste leak, never text.
    func testTheRawPathStripsNULBytes() {
        let plan = paste("\0\0INT. CAFE - DAY\0")

        XCTAssertEqual(plan?.elements.map(\.type), [.scene])
        XCTAssertEqual(plan?.elements.map(\.text), ["INT. CAFE - DAY"])
    }

    /// corpus-6 ×9: the lettered number a scene added after distribution
    /// carries — led or flanked, the printed page's asterisk on its tail.
    func testALetteredSceneNumberHomesToo() {
        let plan = paste([
            "128A EXT./INT. P~~BW MANSION - DUSK. 128A*", "",
            "12A INT. APARTMENT - DAY"
        ].joined(separator: "\n"))

        XCTAssertEqual(plan?.elements.map(\.type), [.scene, .scene])
        XCTAssertEqual(plan?.elements[0].text, "EXT./INT. P~~BW MANSION - DUSK.")
        XCTAssertEqual(plan?.elements[0].sceneNumber, "128A")
        XCTAssertEqual(plan?.elements[1].text, "INT. APARTMENT - DAY")
        XCTAssertEqual(plan?.elements[1].sceneNumber, "12A")
    }

    /// The compound intro the corpus witnesses — 19 lines across six
    /// files, none of them a speaker.
    func testTheCompoundIntroIsAScene() {
        let editor = EditorState(source: "")
        XCTAssertEqual(
            editor.kindForInsertedElement(after: nil, text: "EXT./INT. NEWS VAN - MOVING"), .scene
        )
        XCTAssertEqual(
            editor.kindForInsertedElement(after: nil, text: "EXT/INT. CAR - NIGHT"), .scene
        )
    }

    /// gone-girl's dash-heading retires a scene and prints its number over
    /// the heading it replaces — 27 witnesses, every one adopted by the cue
    /// check before this arm existed.
    func testTheOmitDashHeadingIsTheSceneItRetires() {
        let plan = paste([
            "139 OMIT- INT. DUNNE BEDROOM- NIGHT 139*",
            "",
            "Nick drives."
        ].joined(separator: "\n"))

        XCTAssertEqual(plan?.elements.map(\.type), [.scene, .action])
        XCTAssertEqual(plan?.elements[0].text, "OMITTED")
        XCTAssertEqual(plan?.elements[0].sceneNumber, "139")
    }

    /// The marked card, gone-girl @1211: the marker opens the card, the
    /// date prints centered, one all-caps message closes it — and the
    /// speech that follows with no blank line keeps its cue.
    func testAMarkedTitleCardCentersItsContentAndKeepsTheCue() {
        let plan = paste([
            "Nick walks to the door.",
            "TITLE CARD:",
            "July 6, 2012",
            "ONE DAY GONE",
            "NICK",
            "I should shower."
        ].joined(separator: "\n"))

        XCTAssertEqual(
            plan?.elements.map(\.type),
            [.action, .centered, .centered, .character, .dialogue]
        )
        XCTAssertEqual(plan?.elements[1].text, "July 6, 2012")
        XCTAssertEqual(plan?.elements[2].text, "ONE DAY GONE")
        XCTAssertEqual(plan?.elements[3].text, "NICK")
    }

    /// episode-101's shape: the marker carries the whole card on its own
    /// line.
    func testAnInlineChyronMarkerIsTheWholeCard() {
        let plan = paste("INSERT CHYRON: 1994")
        XCTAssertEqual(plan?.elements.map(\.type), [.centered])
        XCTAssertEqual(plan?.elements[0].text, "1994")
    }

    /// No witnessed card follows a time-only opening with a message, so a
    /// bare time stamp shuts the message slot: the caps line under it is
    /// the next speaker (from-the-black's "9:48 PM / MARK (V.O.)"). A card
    /// that took a date still reads its message after the time line
    /// (gone-girl's "1:17 PM / TWO HOURS GONE").
    func testABareTimeStampShutsTheMessageSlot() {
        let timeOnly = paste([
            "TITLE:",
            "9:48 PM",
            "MARK (V.O.)",
            "The truth is she has a nice face."
        ].joined(separator: "\n"))
        XCTAssertEqual(timeOnly?.elements.map(\.type), [.centered, .character, .dialogue])

        let dated = paste([
            "TITLE CARD:",
            "JULY, 5, 2012",
            "1:17 PM",
            "TWO HOURS GONE"
        ].joined(separator: "\n"))
        XCTAssertEqual(dated?.elements.map(\.type), [.centered, .centered, .centered])
    }

    /// corpus-6's title sequence prints the omitted scene's card inside the
    /// card block: structural grammar outranks alignment, the way the
    /// TypeScript classifier orders it — the line is the scene, not the
    /// card's styling.
    func testACardCarryingAnOmittedSceneTypesAsTheScene() {
        let plan = paste([
            "CUT TO BLACK.",
            "TITLE CARD:",
            "128 OMITTED",
            "FADE UP:"
        ].joined(separator: "\n"))

        XCTAssertEqual(plan?.elements.map(\.type), [.action, .scene, .action])
        XCTAssertEqual(plan?.elements[1].text, "OMITTED")
        XCTAssertEqual(plan?.elements[1].sceneNumber, "128")
    }

}
