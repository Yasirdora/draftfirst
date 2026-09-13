import XCTest
@testable import EDraftCore
@testable import EDraftEngine

/// The camera grammar and the wrapped-heading tail on the paste routes —
/// mirrored from the TypeScript engine's classify.ts rule 5 (CAMERA_LINE)
/// and toScreenplay fold, with the corpus's witnesses: godfather-2's VIEW
/// idiom flooded the cast panel (69 of 179 names before the rule), heat and
/// corpus-6 carried the ANGLE/POV families, and "CORLEONE - DAY" posed as a
/// cue on a column break.
@MainActor
final class CameraLinePasteTests: XCTestCase {

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

    func testTheCameraGrammarTypesAsShotNeverSpeaker() {
        // The same witness list the TypeScript suite holds, verbatim.
        let witnesses = [
            "VIEW ON HAGEN",
            "VIEW ON THE PAVILION",
            "MOVING VIEW ON THE PRIEST",
            "VIEW ALTERS",
            "THE VIEW BEGINS",
            "VIEW THROUGH THE WINDOW",
            "MED. VIEW",
            "CLOSE VIEW",
            "CLOSE MOVING VIEW",
            "FULL VIEW",
            "HIS VIEW",
            "THEIR VIEW",
            "MICHAEL'S VIEW",
            "LONG SHOT",
            "REAR SHOT - MAN",
            "CLOSE - TWO SHOT",
            "MED. CLOSE",
            "MED. CLOSE ON CLEMENZA",
            "MED. CLOSE - THE PHONE BOOTH",
            "CLOSE ON MICHAEL",
            "CLOSER ON THE GUN",
            "CLOSEUP",
            "INSERT",
            "WIDE ON THE YARD",
            "WIDE SHOT",
            "AERIAL SHOT",
            "CRANE SHOT",
            "ESTABLISHING SHOT",
            "WHAT HE SEES",
            "VERY TIGHT ON HANNA IN 3/4 REAR SHOT",
            "ANGLE",
            "ANGLE - WAINGRO",
            "ANGLE, ELI",
            "NEW ANGLE - AN RV",
            "ANOTHER ANGLE",
            "35A ANGLE, MOMENTS LATER. 35A",
            "MOSS'S POV",
            "DANIEL'S POV,",
            "CERRITO'S POV: JAMMING",
            "POINT-OF-VIEW THROUGH WINDSHIELD",
            "TRAVELING POINT OF VIEW",
            // heat's colon family — the labelled frame
            "ECU: CHRIS' FINGERS",
            "CLOSE: ENVELOPE",
            "CLOSER: HANNA",
            "FRONTAL: GARBAGE TRUCK",
            "TIGHTER: CHRIS",
            "WIDER: NEIL",
            "HIGH + WIDE: HANNA",
            "VIDEO MONITOR: HANNA",
            "REVERSE: BLACK + WHITE",
            "SIDE ANGLE: NEIL",
            "OVER HANNA'S SHOULDER: CERRITO'S",
            // the dash twin of CLOSE ON, the verb without the noun,
            // the plural terminal
            "CLOSE - DRILL BIT",
            "CLOSER - NEIL",
            "TRACKING HANNA",
            "REAR SHOTS",
            "SHOTS",
            "A SERIES OF SHOTS"
        ]
        for witness in witnesses {
            XCTAssertTrue(
                PasteHeuristics.looksLikeCameraShot(witness),
                "\(witness) reads as a camera line"
            )
        }
    }

    func testMixedCaseViewSentencesAreNotCameraLines() {
        // The camera grammar is uppercase-only (classify.ts rule 5): these
        // are prose that happens to name the framing.
        XCTAssertFalse(PasteHeuristics.looksLikeCameraShot("VIEW ON MICHAEL, calm, thoughtful."))
        XCTAssertFalse(PasteHeuristics.looksLikeCameraShot("CLOSE VIEW ON Michael's hand.  ROCCO LAMPONE kisses his hand."))
        XCTAssertFalse(PasteHeuristics.looksLikeCameraShot("He had no hint, not in his wildest imagination"))
    }

    func testAPastedViewLineIsAShotAndItsDescriptionIsAction() {
        // The user's Godfather II paste: prose under a VIEW line sat in the
        // speech slot, and the VIEW line sat in the cast panel. A snippet
        // this small runs the raw route — typed line for line, no wrap join.
        let elements = paste("""
            VIEW ON MICHAEL
            He had no hint, not in his wildest imagination could he have
            guessed that she would do such a thing.
            """)
        XCTAssertEqual(elements.map(\.type), [.shot, .action, .action])
    }

    func testAShotUnderACueEndsTheCuesCandidacy() {
        // The camera arm fires before speech position, so the shot is the
        // structural line under the cue — and the cue was no speaker.
        let elements = paste("""
            MICHAEL
            Sit down. Francie.
            VIEW ON NERI
            quiet, and deadly.
            """)
        XCTAssertEqual(elements.map(\.type), [.character, .dialogue, .shot, .action])
    }

    func testAHeadingThatMerelyContainsACameraNounStaysAScene() {
        let elements = paste("EXT. A SICILIAN LANDSCAPE - FULL VIEW - DAY")
        XCTAssertEqual(elements.map(\.type), [.scene])
    }

    func testTheRawRouteFoldsAWrappedHeadingsTailIntoTheHeading() {
        // A flat paste (no margin scheme) keeps the lines attached; the tail
        // joins the heading it completes — one scene, no cue, no drift in
        // the part-indexed bookkeeping downstream.
        let elements = paste("""
            INT. DON CORLEONE'S OLD OFFICE - CLOSE VIEW ON MICHAEL
            CORLEONE - DAY
            standing impassively, like a young Prince, recently crowned
            """)
        XCTAssertEqual(elements.map(\.type), [.scene, .action])
        XCTAssertEqual(
            elements.first?.text,
            "INT. DON CORLEONE'S OLD OFFICE - CLOSE VIEW ON MICHAEL CORLEONE - DAY"
        )
    }

    func testTheIndentedRouteFoldsTheTailAcrossTheColumnBreak() {
        // The user's paste: the heading at the action margin, its tail at the
        // column the copier gave it, enough margin around them for the
        // indented scheme to hold. The reassembly folds across the break.
        let elements = paste("""
            INT. DON CORLEONE'S OLD OFFICE - CLOSE VIEW ON MICHAEL
                                          CORLEONE - DAY
                              MICHAEL
                    Sit down. Francie.
                              KAY
                    Yes, Michael.
            """)
        XCTAssertEqual(
            elements.map(\.type),
            [.scene, .character, .dialogue, .character, .dialogue]
        )
        XCTAssertEqual(
            elements.first?.text,
            "INT. DON CORLEONE'S OLD OFFICE - CLOSE VIEW ON MICHAEL CORLEONE - DAY"
        )
    }

    func testAFinishedHeadingKeepsTheNextLineToItself() {
        // The tell needs the opening: a heading that already carries its
        // time-of-day takes no tail.
        let elements = paste("""
            INT. BOATHOUSE - DAY
            CORLEONE - DAY
            """)
        XCTAssertEqual(elements.count, 2)
        XCTAssertNotEqual(elements[1].type, .scene)
    }

    func testBackToBackHeadingsNeverMerge() {
        let elements = paste("""
            INT. BOATHOUSE
            EXT. TAHOE GATE - DAY
            """)
        XCTAssertEqual(elements.map(\.type), [.scene, .scene])
        XCTAssertEqual(elements.map(\.text), ["INT. BOATHOUSE", "EXT. TAHOE GATE - DAY"])
    }

    func testAColonLineWhoseLabelIsNoFramingWordIsNotAShot() {
        // The labelled-frame family names the camera's words only.
        XCTAssertFalse(PasteHeuristics.looksLikeCameraShot("SYNOPSIS: THE FAMILY"))
        XCTAssertFalse(PasteHeuristics.looksLikeCameraShot("CUE MUSIC -- P.J. HARVEY"))
    }

    func testTheCueShapeWearsNoneOfASpeakersMarks() {
        // classify.ts's cueShape: terminal sentence punctuation is a shout,
        // a colon makes a label, the parentheticals ride off before the
        // name is measured (42 characters, the TypeScript ceiling).
        XCTAssertFalse(PasteHeuristics.looksLikeCharacterCue(
            "DO YOU ACCEPT JESUS CHRIST AS YOUR SAVIOR?",
            uppercase: "DO YOU ACCEPT JESUS CHRIST AS YOUR SAVIOR?"
        ))
        XCTAssertFalse(PasteHeuristics.looksLikeCharacterCue(
            "HOLD! HOLD! WAIT!", uppercase: "HOLD! HOLD! WAIT!"
        ))
        XCTAssertFalse(PasteHeuristics.looksLikeCharacterCue(
            "CONTINUED: (2)", uppercase: "CONTINUED: (2)"
        ))
        XCTAssertFalse(PasteHeuristics.looksLikeCharacterCue(
            "(SHOUTING)", uppercase: "(SHOUTING)"
        ))
        XCTAssertTrue(PasteHeuristics.looksLikeCharacterCue(
            "HANNA (V.O.) (CONT'D)", uppercase: "HANNA (V.O.) (CONT'D)"
        ))
        XCTAssertTrue(PasteHeuristics.looksLikeCharacterCue(
            "ELI", uppercase: "ELI"
        ))
    }

    func testAShoutUnderACueStaysSpeech() {
        // corpus-6's revival tent: speech position (classify.ts rule 7)
        // answers before the cue shape, so a shouted question under a cue
        // is the character's line, not a new speaker.
        let elements = paste("""
            ELI
            DO YOU ACCEPT JESUS CHRIST AS YOUR SAVIOR?
            DANIEL
            I accept Him.
            """)
        XCTAssertEqual(
            elements.map(\.type),
            [.character, .dialogue, .character, .dialogue]
        )
    }

    func testAShoutInsideASpeechContinuesIt() {
        // The same shout mid-speech: the cue shape rejects its terminal
        // punctuation, so the speech runs on.
        let elements = paste("""
            ELI
            I am a false prophet.
            HOLD! HOLD! WAIT!
            Goddammit.
            """)
        XCTAssertEqual(
            elements.map(\.type),
            [.character, .dialogue, .dialogue, .dialogue]
        )
    }

    func testADotlessSceneIntroStillOpensTheScene() {
        // heat's "INT - MERCEDES - NEIL + EADY - NIGHT": the production's
        // dash spelling, SCENE_INTRO's bare prefix, never a speaker.
        let elements = paste("""
            INT - MERCEDES - NEIL + EADY - NIGHT
            Neil drives. Eady watches the road.
            """)
        XCTAssertEqual(elements.map(\.type), [.scene, .action])
    }
}
