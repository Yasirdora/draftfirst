import XCTest
@testable import EDraftCore

/// The reassembly a hard-wrapped paste gets — margins off, paragraphs
/// joined, depths kept — and the plain pastes it must never touch.
final class PasteReassemblyTests: XCTestCase {

    private func line(_ column: Int, _ text: String) -> String {
        String(repeating: " ", count: column) + text
    }

    /// Kane-shaped: an action margin at ten, speeches at twenty-four,
    /// parentheticals at thirty-one, cues at thirty-six, transitions far
    /// right; paragraphs hard-wrapped, cues and speeches sharing no blank.
    private lazy var wrapped = [
        line(10, "EXT. XANADU - FAINT DAWN -"),
        line(10, "1940 (MINIATURE)"),
        "",
        line(10, "Window, very small in the distance,"),
        line(10, "illuminated. All around this is an"),
        line(10, "almost totally black screen."),
        "",
        line(36, "KANE"),
        line(31, "(a whisper)"),
        line(24, "Rosebud... the word echoes."),
        "",
        line(10, "The screen stays black."),
        line(72, "DISSOLVE:"),
    ].joined(separator: "\n")

    /// One screenplay paragraph arrived as three source lines; the courier's
    /// margin is not text. A cue and its speech share no blank line — the
    /// column change is what parts them.
    func testAHardWrappedPasteIsReassembledIntoParagraphs() {
        let paragraphs = PasteReassembly.paragraphs(from: wrapped)

        XCTAssertEqual(
            paragraphs?.map { "\($0.depth)|\($0.kind?.rawValue ?? "-")|\($0.text)" },
            [
                "0|-|EXT. XANADU - FAINT DAWN - 1940 (MINIATURE)",
                "0|-|Window, very small in the distance, illuminated. "
                    + "All around this is an almost totally black screen.",
                "26|-|KANE",
                "21|-|(a whisper)",
                "14|-|Rosebud... the word echoes.",
                "0|-|The screen stays black.",
                "62|-|DISSOLVE:",
            ]
        )
    }

    /// The paragraph keeps the lines it joined — the wrap evidence cue
    /// confirmation measures a speech's width and sentence shape from.
    func testAParagraphCarriesTheSourceLinesItJoined() {
        let paragraphs = PasteReassembly.paragraphs(from: wrapped)

        XCTAssertEqual(
            paragraphs?[1].sourceLines,
            ["Window, very small in the distance,", "illuminated. All around this is an", "almost totally black screen."]
        )
        XCTAssertEqual(paragraphs?[2].sourceLines, ["KANE"])
    }

    /// A one-column drift between a line and its continuation is the
    /// copier's noise, not the writer's structure.
    func testAColumnOfDriftDoesNotSplitAParagraph() {
        let drifted = "          First line of action here\n           and its continuation a space off\n\n          Next paragraph."
        let paragraphs = PasteReassembly.paragraphs(from: drifted)

        XCTAssertEqual(paragraphs?.count, 2)
        XCTAssertEqual(
            paragraphs?.first?.text,
            "First line of action here and its continuation a space off"
        )
    }

    /// Fountain text and unindented copies carry no scheme: they keep the
    /// planner's line-per-element reading, markers and all.
    func testAPasteWithoutASchemeIsLeftAlone() {
        XCTAssertNil(PasteReassembly.paragraphs(from: "INT. LAB - DAY\n\nDust hangs."))
        XCTAssertNil(PasteReassembly.paragraphs(from: "A\nB"))
        XCTAssertNil(PasteReassembly.paragraphs(from: "  two lines only\n  is not a scheme"))
        XCTAssertNil(
            PasteReassembly.paragraphs(from: "**bold** and _plain_\nthe way fountain reads it\nno margins here")
        )
    }

    /// The floor is an outlier's answer: one flush-left opener does not
    /// move the action margin the other thousand lines agree on.
    func testTheBaseColumnIgnoresAFlushLeftOutlier() {
        let lines = ["FADE IN:"]
            + (1...12).map { "          Action beat \($0), long enough to wrap\n          onto a second line here." }
        let source = lines.joined(separator: "\n\n")

        let paragraphs = PasteReassembly.paragraphs(from: source)

        XCTAssertEqual(paragraphs?.dropFirst().first?.depth, 0,
                       "action sits at the base column, whatever the opener did")
    }

    // MARK: - The unindented hard-wrap

    /// Social-Network-shaped: no margins, no blank lines, prose wrapped at
    /// a fixed right edge, speeches volleying in short lines.
    private let unindented = """
        FROM THE BLACK WE HEAR--
        MARK (V.O.)
        Did you know there are more people with
        genius IQ's living in China than there
        are people of any kind living in the
        United States?
        ERICA (V.O.)
        That can't possibly be true.
        FADE IN:
        INT. CAMPUS BAR - NIGHT
        MARK ZUCKERBERG is a sweet looking 19 year old whose lack of
        any physically intimidating attributes masks a very
        complicated and dangerous anger.
        MARK
        How do you distinguish yourself in a
        population of people who all got 1600 on
        their SAT's?
        ERICA
        I didn't know they take SAT's in China.
        MARK
        They don't. I wasn't talking about China
        anymore, I was talking about me.
        CUT TO:
        EXT. SQUARE - DAY
        The plaza holds its breath for a moment and
        then moves on.
        """

    /// A speech is one paragraph: the wrap column is not a paragraph break,
    /// and a cue is never its dialogue's continuation. The opening sound
    /// line types as a cue (it wears the cue shape — a front-matter tell is
    /// the deferred RFC's, both engines agree), and under speech position
    /// (classify.ts rule 7) the cue beneath it reads as its speech, so
    /// MARK (V.O.) opens the speech paragraph it introduces.
    func testAnUnindentedHardWrapKeepsSpeechesWhole() {
        let paragraphs = PasteReassembly.paragraphs(from: unindented)

        XCTAssertEqual(
            paragraphs?.map(\.kind),
            [.character, .dialogue, .character, .dialogue,
             .transition, .scene, .action,
             .character, .dialogue, .character, .dialogue, .character, .dialogue,
             .transition, .scene, .action]
        )
        XCTAssertEqual(
            paragraphs?[1].text,
            "MARK (V.O.) Did you know there are more people with genius IQ's living in China "
                + "than there are people of any kind living in the United States?"
        )
        XCTAssertEqual(
            paragraphs?[6].text,
            "MARK ZUCKERBERG is a sweet looking 19 year old whose lack of "
                + "any physically intimidating attributes masks a very "
                + "complicated and dangerous anger."
        )
    }

    /// The volley is the point: short lines do not keep a speech from
    /// joining, and each cue still parts from its dialogue.
    func testVolleysStayWhole() {
        let paragraphs = PasteReassembly.paragraphs(from: unindented)
        let erica = paragraphs?.firstIndex { $0.text.hasPrefix("I didn't know") }
        XCTAssertEqual(paragraphs?[erica!].kind, .dialogue)
        XCTAssertEqual(paragraphs?[erica! + 1].text, "MARK")
    }

    /// What it must not fire on: Fountain text with real blank lines, an
    /// unwrapped paragraph-per-line copy, and a two-line snippet all keep
    /// the line-per-element reading.
    func testTheUnindentedModeRefusesWhatItCannotRead() {
        XCTAssertNil(PasteReassembly.paragraphs(from: "INT. LAB - DAY\n\nDust hangs in the light."))
        let longLines = (1...10).map { "Line \($0) of a paragraph that runs very long indeed, well past any sane wrap column, because the source kept its elements whole and never hard-wrapped them at all." }
        XCTAssertNil(PasteReassembly.paragraphs(from: longLines.joined(separator: "\n")))
        XCTAssertNil(PasteReassembly.paragraphs(from: "A\nB\nC\nD\nE\nF\nG\nH"))
    }
}
