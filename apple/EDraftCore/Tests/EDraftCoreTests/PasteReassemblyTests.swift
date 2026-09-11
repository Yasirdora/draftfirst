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
            paragraphs,
            [
                PasteReassembly.Paragraph(
                    text: "EXT. XANADU - FAINT DAWN - 1940 (MINIATURE)", depth: 0
                ),
                PasteReassembly.Paragraph(
                    text: "Window, very small in the distance, illuminated. "
                        + "All around this is an almost totally black screen.",
                    depth: 0
                ),
                PasteReassembly.Paragraph(text: "KANE", depth: 26),
                PasteReassembly.Paragraph(text: "(a whisper)", depth: 21),
                PasteReassembly.Paragraph(text: "Rosebud... the word echoes.", depth: 14),
                PasteReassembly.Paragraph(text: "The screen stays black.", depth: 0),
                PasteReassembly.Paragraph(text: "DISSOLVE:", depth: 62),
            ]
        )
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
}
