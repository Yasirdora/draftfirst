import Foundation
import Testing
import DraftFirstEngine

/// Transcription is checked by parsing what it writes with the engine's own
/// parser and asserting the elements that come back. Comparing Fountain source
/// against an expected string would only prove the transcriber agrees with
/// itself; the question that matters is whether eDraft reads a scanned page as
/// the screenplay it was, so the parser is the judge.
@Suite("Screenplay transcription")
struct ScreenplayTranscriptionTests {

    /// A screenplay page is 55 lines of 12pt type on 8.5" paper. Positions are
    /// given in inches from the paper's edge — the units the margins are
    /// actually specified in — and converted the way the scanner does.
    private static let pitch = 0.016

    private func at(_ inches: Double, _ row: Int, _ text: String, page: Int = 0) -> ScannedTextLine {
        let top = 0.08 + Double(row) * Self.pitch
        return ScannedTextLine(
            text: text,
            page: page,
            left: inches / 8.5,
            top: top,
            bottom: top + Self.pitch * 0.6
        )
    }

    private func parse(_ lines: [ScannedTextLine]) throws -> Screenplay {
        try Fountain.parse(ScreenplayTranscription.fountain(from: lines))
    }

    @Test("A printed page reads back as the screenplay it was")
    func printedPage() throws {
        let screenplay = try parse([
            at(1.5, 0, "FADE IN:"),
            at(1.5, 2, "INT. COFFEE SHOP - DAY"),
            at(1.5, 4, "A cramped room. Rain runs down the window and"),
            at(1.5, 5, "pools on the sill."),
            at(3.7, 7, "ELENA"),
            at(3.0, 8, "(quietly)"),
            at(2.5, 9, "You came back."),
            at(3.7, 11, "DAVID"),
            at(2.5, 12, "I did. I said I would and I meant"),
            at(2.5, 13, "every word of it."),
            at(6.0, 15, "CUT TO:"),
            at(1.5, 17, "EXT. RIDGE - NIGHT")
        ])

        #expect(screenplay.elements.map(\.type) == [
            .transition, .scene, .action, .character, .parenthetical,
            .dialogue, .character, .dialogue, .transition, .scene
        ])
    }

    @Test("Wrapped lines rejoin into one paragraph")
    func wrappedLinesRejoin() throws {
        let screenplay = try parse([
            at(1.5, 0, "INT. COFFEE SHOP - DAY"),
            at(1.5, 2, "A cramped room. Rain runs down the window and"),
            at(1.5, 3, "pools on the sill."),
            at(3.7, 5, "ELENA"),
            at(2.5, 6, "I did. I said I would and I meant"),
            at(2.5, 7, "every word of it.")
        ])

        #expect(screenplay.elements[1].text
            == "A cramped room. Rain runs down the window and pools on the sill.")
        #expect(screenplay.elements[3].text
            == "I did. I said I would and I meant every word of it.")
    }

    @Test("A blank line between paragraphs keeps them apart")
    func paragraphsStayApart() throws {
        let screenplay = try parse([
            at(1.5, 0, "This agreement is made between the parties"),
            at(1.5, 1, "on the date written below."),
            at(1.5, 3, "Each party agrees to the terms set out"),
            at(1.5, 4, "in the schedule attached.")
        ])

        // Paper that is not a screenplay still arrives as readable prose
        // rather than one run-on block.
        #expect(screenplay.elements.map(\.type) == [.action, .action])
    }

    @Test("Page numbers and continuation marks are not part of the script")
    func pageFurnitureIsDropped() throws {
        let screenplay = try parse([
            ScannedTextLine(text: "2.", page: 1, left: 7.0 / 8.5, top: 0.03, bottom: 0.045),
            at(1.5, 4, "INT. KITCHEN - NIGHT", page: 1),
            at(1.5, 6, "She sets the kettle down.", page: 1),
            ScannedTextLine(text: "(CONTINUED)", page: 1, left: 6.0 / 8.5, top: 0.95, bottom: 0.965)
        ])

        #expect(screenplay.elements.map(\.type) == [.scene, .action])
    }

    @Test("A cue carrying lowercase is still a cue")
    func mixedCaseCueSurvives() throws {
        let screenplay = try parse([
            at(1.5, 0, "INT. BAR - NIGHT"),
            at(3.7, 2, "McCREADY"),
            at(2.5, 3, "Nobody leaves.")
        ])

        #expect(screenplay.elements.map(\.type) == [.scene, .character, .dialogue])
        #expect(screenplay.elements[1].text == "McCREADY")
    }

    @Test("A cue with nothing spoken under it is not a cue")
    func orphanedCueBecomesAction() throws {
        let screenplay = try parse([
            at(1.5, 0, "INT. HALL - DAY"),
            at(3.7, 2, "ELENA"),
            at(1.5, 4, "The door closes.")
        ])

        #expect(screenplay.elements.map(\.type) == [.scene, .action, .action])
    }

    @Test("A script with no margins is still read as a script")
    func flatLayoutIsReadByContent() throws {
        // A screenplay shown in an app, or a PDF exported without indents:
        // every line starts at the same place, so only the words say what
        // each one is.
        let screenplay = try parse([
            at(1.5, 0, "INT. COFFEE SHOP - DAY"),
            at(1.5, 2, "A busy, cozy coffee shop. Soft jazz plays."),
            at(1.5, 4, "JAKE"),
            at(1.5, 5, "(softly)"),
            at(1.5, 6, "Emma, we need to talk."),
            at(1.5, 8, "EMMA"),
            at(1.5, 9, "(avoiding eye contact)"),
            at(1.5, 10, "I know. I've been feeling it too.")
        ])

        #expect(screenplay.elements.map(\.type) == [
            .scene, .action, .character, .parenthetical, .dialogue,
            .character, .parenthetical, .dialogue
        ])
        #expect(screenplay.elements[4].text == "Emma, we need to talk.")
    }

    @Test("Action set in capitals is not a cast member")
    func capitalActionIsNotACue() throws {
        // Plenty of scripts set their action in capitals, and a page read
        // without usable margins has only the words to go on. Length alone
        // called these names: the cast list filled with sentences, and the
        // prose beneath each one became its first speech.
        let screenplay = try parse([
            at(1.5, 0, "INT. HARBOUR - NIGHT"),
            at(1.5, 2, "BOTH OF THEM FREEZE."),
            at(1.5, 4, "Below, waves gnaw at the rocks."),
            at(1.5, 6, "TOM"),
            at(1.5, 7, "I don't know what you mean.")
        ])

        #expect(screenplay.elements.map(\.type) == [
            .scene, .action, .action, .character, .dialogue
        ])
        #expect(screenplay.elements[3].text == "TOM")
    }

    @Test("A cue keeps its extension, its honorific and its second name")
    func namesThatMustSurvive() throws {
        // The rule that rejects sentences must not reject the names a cast
        // list is actually made of.
        let screenplay = try parse([
            at(1.5, 0, "INT. STUDY - NIGHT"),
            at(1.5, 2, "MRS. HUDSON"),
            at(1.5, 3, "There is someone at the door."),
            at(1.5, 5, "MRS. HUDSON (CONT'D)"),
            at(1.5, 6, "At this hour."),
            at(1.5, 8, "POLICE OFFICER #2 (V.O.)"),
            at(1.5, 9, "Open up.")
        ])

        #expect(screenplay.elements.map(\.type) == [
            .scene, .character, .dialogue, .character, .dialogue, .character, .dialogue
        ])
    }

    @Test("Margins that are really there are not thrown away for the words")
    func indentedPageIsNotRereadByContent() throws {
        // Nobody speaks here — a montage, an opening, a chase — but the page
        // is properly printed: the transition sits out at its own margin, so
        // the indents plainly carry meaning. Finding no cue used to be taken
        // as proof that they did not, and the page was read again by its
        // words alone, which turned the line of capitals into a cast member
        // and handed it the sentence below as speech.
        //
        // The capitals run straight into that sentence, at one margin and
        // single spacing, which on paper is one paragraph.
        let screenplay = try parse([
            at(1.5, 0, "EXT. RIDGE - NIGHT"),
            at(1.5, 2, "THE STORM ARRIVES"),
            at(1.5, 3, "Wind takes the ridge, and nothing else moves."),
            at(6.0, 5, "CUT TO:")
        ])

        #expect(screenplay.elements.map(\.type) == [.scene, .action, .transition])
        #expect(screenplay.elements[1].text.hasPrefix("THE STORM ARRIVES"))
    }

    @Test("A page with nothing on it transcribes to nothing")
    func emptyInput() {
        #expect(ScreenplayTranscription.fountain(from: []).isEmpty)
    }

    @Test("Text that opens with a Fountain marker stays action")
    func markerLeadingActionIsForced() throws {
        // A line beginning "." or ">" would otherwise force a scene heading or
        // a transition out of ordinary prose.
        let screenplay = try parse([
            at(1.5, 0, "INT. LAB - DAY"),
            at(1.5, 2, ">>> the console reads."),
            at(1.5, 4, "Mara steps back.")
        ])

        #expect(screenplay.elements.map(\.type) == [.scene, .action, .action])
        #expect(screenplay.elements[1].text == ">>> the console reads.")
    }
}
