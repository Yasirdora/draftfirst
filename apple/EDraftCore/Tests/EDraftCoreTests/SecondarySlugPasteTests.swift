import XCTest
@testable import EDraftCore
@testable import EDraftEngine

/// The secondary slug, the title-page block, and the closing card on the
/// paste routes (RFC-SECONDARY-SLUG) — mirrored from the TypeScript engine's
/// classify.ts arms 2¾ and 5½ and its `frontMatterIndexes`, with the corpus's
/// witnesses: no-country's time-ending cards sat in the cast panel, every
/// pasted title page made the film's name a speaker, and `THE END` fused
/// into the final scene's words.
@MainActor
final class SecondarySlugPasteTests: XCTestCase {

    /// The route the surfaces take: a paste's signal-less line falls back to
    /// prose (a paste is not typing).
    private func paste(_ source: String) -> [ScriptElement] {
        ScreenplayEditPlanner.plan(
            elements: [ScriptElement(type: .action, text: "")],
            replacing: NSRange(location: 0, length: 0),
            with: source,
            intent: .multilinePaste,
            kindForNewElement: { previous, text, depth, attached in
                EditorState(source: "").kindForInsertedElement(
                    after: previous, text: text, pasteDepth: depth,
                    attached: attached, fallback: .action
                )
            }
        )?.elements ?? []
    }

    // MARK: - The secondary slug (§2)

    func testTheCorpussTimeEndingSecondarySlugsTypeAsScenes() {
        // Every line here is a corpus witness: corpus-1, godfather-2, heat,
        // no-country ×5.
        let witnesses = [
            "COURTYARD - 1612 HAVENHURST - DAY",
            "THE NEW YORK HARBOR - DAY",
            "MARCIAN0'S OFFICE - MARCIANO - DAY",
            "BASIN - DAY",
            "2ND HOTEL EAGLE ROOM - NIGHT",
            "OFFICE HALLWAY - DAY",
            "SHERIFF BELL'S OFFICE - DAY",
            "COFFEE SHOP - EL PASO - NIGHT"
        ]
        for witness in witnesses {
            let elements = paste("""
                INT. SOMEWHERE - DAY
                Action under the master heading.

                \(witness)

                More action follows here.
                """)
            XCTAssertEqual(
                elements.map(\.type),
                [.scene, .action, .scene, .action],
                "\(witness) is the secondary slug, never a speaker"
            )
        }
    }

    func testTheQuantityLaterCardsTypeAsScenes() {
        for witness in ["MINUTES LATER", "A MINUTE LATER", "FOUR YEARS LATER"] {
            let elements = paste("""
                INT. SOMEWHERE - DAY
                Action.

                \(witness)

                More action.
                """)
            XCTAssertEqual(elements.map(\.type), [.scene, .action, .scene, .action], witness)
        }
    }

    func testTheAnotherPartInsertTypesAsScene() {
        let elements = paste("""
            INT. CASINO - NIGHT
            Action.

            ANOTHER PART OF THE CASINO

            More action.
            """)
        XCTAssertEqual(elements.map(\.type), [.scene, .action, .scene, .action])
    }

    func testTheGrammarRefusesTheShapesNamedAsResidue() {
        // X - NAME collides with real speakers (HAGEN'S SON); the possessive
        // insert, the tailed LATER card, and the unit-less LATER lines are
        // named residue (§2).
        for text in ["BEDROOM - JUSTINE", "NEIL'S HAND",
                     "SEVEN YEARS LATER -- THE PRESENT", "LATER THAT NIGHT",
                     "SEE YOU LATER", "ANOTHER COUNTER"] {
            XCTAssertFalse(PasteHeuristics.isSecondarySlug(text), text)
        }
    }

    func testASecondarySlugUnderACueEndsTheCuesCandidacy() {
        // The slug answers before speech position: under a cue it is the
        // slug, not the speech — and the cue was no speaker.
        let elements = paste("""
            MOSS
            It's a mess.
            BASIN - DAY
            The two lawmen are dismounting.
            """)
        XCTAssertEqual(elements.map(\.type), [.character, .dialogue, .scene, .action])
    }

    // MARK: - The closing card (§4)

    func testTheClosingCardTypesCenteredAndKeepsOutOfTheLastSpeech() {
        let elements = paste("""
            EXT. ROOF - NIGHT
            MARA
            Goodnight.

            THE END
            """)
        XCTAssertEqual(elements.map(\.type), [.scene, .character, .dialogue, .centered])
        XCTAssertEqual(elements.last?.text, "THE END")
    }

    func testTheClosingCardNeverFusesIntoTheParagraphUnderWay() {
        // Hard-wrapped (eight dense lines): before the arm, the card joined
        // the trailing action paragraph's words.
        let elements = paste("""
            EXT. ROOF - NIGHT
            Mara watches the city below her, the lights
            blinking out one by one as the hour runs
            toward morning and the streets empty slow.
            She lights a cigarette and does not look
            back at the door behind her even once more.
            The wind carries the last of the music
            away over the water and out to sea now.
            THE END
            """)
        XCTAssertEqual(elements.map(\.type), [.scene, .action, .centered])
        XCTAssertFalse(elements[1].text.contains("THE END"))
    }

    func testTheClosingCardKeepsItsPeriodAndRefusesTheSentence() {
        XCTAssertTrue(PasteHeuristics.isEndCard("THE END."))
        XCTAssertTrue(PasteHeuristics.isEndCard("The End"))
        XCTAssertFalse(PasteHeuristics.isEndCard("THE END OF A THIRTY FOOT METAL POLE-"))
    }

    // MARK: - The ON-insert (§8)

    func testTheOnInsertTypesAsShot() {
        // heat ×5: the camera frames a surface.
        let elements = paste("""
            INT. SOMEWHERE - DAY
            Action.
            ON AMBULANCE
            It screams through traffic.
            """)
        XCTAssertEqual(elements.map(\.type), [.scene, .action, .shot, .action])
    }

    // MARK: - The title-page block (§3)

    func testAPastedTitlePageCentersAndTheStoryIsUntouched() {
        // manchester's opening, verbatim.
        let elements = paste("""
            MANCHESTER BY THE SEA
            Written & Directed
            by
            Kenneth Lonergan
            EXT. MANCHESTER HARBOR -- SEA. DAY.
            A small commercial fishing boat heads out of Manchester.
            """)
        XCTAssertEqual(
            elements.map(\.type),
            [.centered, .centered, .centered, .centered, .scene, .action]
        )
    }

    func testTheBlockCentersThroughTheDottedLeaderCastTable() {
        // episode-101's opening shapes. Eight dense lines, no blanks: the
        // hard-wrapped route reads this one.
        let elements = paste("""
            Episode 101
            "PILOT"
            Written by
            Vince Gilligan
            WALTER WHITE..............Bryan Cranston
            JESSE PINKMAN..............Aaron Paul
            TEASER
            EXT. COW PASTURE - DAY
            """)
        XCTAssertEqual(
            elements.map(\.type),
            [.centered, .centered, .centered, .centered, .centered, .centered, .actbreak, .scene]
        )
    }

    func testTheBlockEngagesOnTheCreditWordsHoweverLongTheCreditRuns() {
        // emilia-perez: 49 characters of credit — the line that killed the
        // length rule.
        let elements = paste("""
            EMILIA PÉREZ
            A musical written and directed by Jacques Audiard
            EXT. MEXICO CITY - NIGHT
            Top shot and perpendicular zoom: Mexico City.
            """)
        XCTAssertEqual(elements.map(\.type), [.centered, .centered, .scene, .action])
    }

    func testTheBlockClosesAtAnExtensionCue() {
        // gone-girl's opening: the OCR twin "(V.0.)" closes the block, and
        // the speech that follows stays speech.
        let elements = paste("""
            GONE GIRL
            GONE GIRL
            by Gillian Flynn
            NICK (V.0.)
            When I think of my wife, I picture cracking her lovely skull.
            """)
        XCTAssertEqual(
            elements.map(\.type),
            [.centered, .centered, .centered, .character, .dialogue]
        )
    }

    func testTheBlockNeverEngagesWithoutACreditLine() {
        // The Social Network opening, and the fragment that opens at a cue:
        // the walk stops, no credit ever appears, and every line classifies
        // exactly as it always did.
        let elements = paste("""
            FROM THE BLACK WE HEAR--
            MARK (V.O.)
            When I was a kid, I wanted to be a Marine.
            """)
        XCTAssertEqual(elements.map(\.type), [.character, .dialogue, .dialogue])
    }

    func testTheBlockNeverEngagesPastAFortyCharacterLine() {
        let elements = paste("""
            A line of opening prose that runs well past forty characters, the way a story does.
            Written by
            SOMEBODY
            """)
        XCTAssertNotEqual(elements.first?.type, .centered)
    }

    func testTheIndentedRouteCentersTheBlockWhateverColumnItSatAt() {
        // The courier's margins carry the scheme; the block's lines print
        // centered anyway, and the story's first wrap still joins.
        let elements = paste("""
                  MANCHESTER BY THE SEA
                  Written & Directed
                  by
                  Kenneth Lonergan

                  EXT. MANCHESTER HARBOR -- SEA. DAY.

                  A small commercial fishing boat heads out of
                  Manchester, Massachusetts, toward the open sea.
            """)
        XCTAssertEqual(
            elements.map(\.type),
            [.centered, .centered, .centered, .centered, .scene, .action]
        )
        XCTAssertEqual(
            elements.last?.text,
            "A small commercial fishing boat heads out of Manchester, Massachusetts, toward the open sea."
        )
    }
}
