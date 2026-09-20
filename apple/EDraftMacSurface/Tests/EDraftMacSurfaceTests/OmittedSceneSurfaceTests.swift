import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// A scene the production cut, on the page — RFC-DRAFT-PRODUCTION §7.3.
///
/// Final Draft hides the body behind its OMITTED card. eDraft shows it,
/// struck and in muted ink, because a writer who cannot see what was cut
/// cannot tell a cut scene from one that was never written. Shown is not
/// editable: the body belongs to the file, which keeps it byte for byte on
/// save (IL-0071), so the caret does not land in it and no keystroke
/// reaches it.
@MainActor
final class OmittedSceneSurfaceTests: XCTestCase {

    /// A file with one omitted scene: the card that prints, and the two
    /// paragraphs nested inside it.
    private func opened() throws -> (EditorState, ScriptSurface) {
        let fdx = """
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        <Paragraph Type="Scene Heading"><Text>INT. LAB - DAY</Text></Paragraph>
        <Paragraph Type="Action"><Text>She waits.</Text></Paragraph>
        <Paragraph Number="21" Type="Scene Heading">
        <Text>OMITTED</Text>
        <OmittedScene>
        <Paragraph Type="Scene Heading"><Text>EXT. THE YARD - DUSK</Text></Paragraph>
        <Paragraph Type="Action"><Text>Mara waits.</Text></Paragraph>
        </OmittedScene>
        </Paragraph>
        <Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>
        </Content>
        </FinalDraft>
        """
        let file = try ScreenplayFile.open(Data(fdx.utf8), as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        return (editor, surface)
    }

    private func range(_ surface: ScriptSurface, _ editor: EditorState, _ text: String) throws -> NSRange {
        let id = try XCTUnwrap(editor.screenplay.elements.first { $0.text == text }?.id)
        return try XCTUnwrap(surface.ranges.first { $0.id == id }?.range)
    }

    // MARK: - Muted, struck, and still there

    func testTheOmittedBodyIsStruckInMutedInkAndTheLiveLinesAreNot() throws {
        let (editor, surface) = try opened()
        let storage = surface.textView.textStorage
        let omitted = try range(surface, editor, "Mara waits.")
        let live = try range(surface, editor, "The kettle screams.")

        var effective = NSRange()
        let strike = storage?.attribute(.strikethroughStyle, at: omitted.location, effectiveRange: &effective) as? Int
        XCTAssertEqual(strike, NSUnderlineStyle.single.rawValue, "the omitted line is struck")
        let ink = storage?.attribute(.foregroundColor, at: omitted.location, effectiveRange: &effective) as? NSColor
        XCTAssertEqual(ink, ScriptLayout.omittedInk, "the omitted line is muted")

        XCTAssertNil(
            storage?.attribute(.strikethroughStyle, at: live.location, effectiveRange: &effective),
            "a live line is untouched"
        )
    }

    func testTheCardItselfIsNotStruck() throws {
        let (editor, surface) = try opened()
        let card = try range(surface, editor, "OMITTED")
        var effective = NSRange()
        XCTAssertNil(
            surface.textView.textStorage?
                .attribute(.strikethroughStyle, at: card.location, effectiveRange: &effective),
            "the card prints; it is what the omission looks like"
        )
    }

    func testTheBodyIsOnThePageAndCopyable() throws {
        let (editor, surface) = try opened()
        let omitted = try range(surface, editor, "EXT. THE YARD - DUSK")
        let text = surface.textView.textStorage?.string as NSString?
        XCTAssertEqual(text?.substring(with: omitted), "EXT. THE YARD - DUSK", "muted, never hidden")
    }

    // MARK: - Closed to the caret and the keyboard

    func testTheCaretDoesNotLandInsideTheSpan() throws {
        let (editor, surface) = try opened()
        let omitted = try range(surface, editor, "Mara waits.")
        let inside = NSRange(location: omitted.location + 3, length: 0)

        // Travelling forwards: out the far side.
        let forwards = surface.textView(
            surface.textView,
            willChangeSelectionFromCharacterRange: NSRange(location: 0, length: 0),
            toCharacterRange: inside
        )
        XCTAssertEqual(forwards, NSRange(location: omitted.location + omitted.length, length: 0))

        // Travelling backwards: out the near side.
        let backwards = surface.textView(
            surface.textView,
            willChangeSelectionFromCharacterRange: NSRange(location: omitted.location + omitted.length + 2, length: 0),
            toCharacterRange: inside
        )
        XCTAssertEqual(backwards, NSRange(location: omitted.location, length: 0))
    }

    func testASelectionAcrossTheSpanIsLeftAlone() throws {
        let (editor, surface) = try opened()
        let omitted = try range(surface, editor, "Mara waits.")
        let sweep = NSRange(location: 0, length: omitted.location + omitted.length)
        XCTAssertEqual(
            surface.textView(
                surface.textView,
                willChangeSelectionFromCharacterRange: NSRange(location: 0, length: 0),
                toCharacterRange: sweep
            ),
            sweep,
            "a writer may still sweep over a cut scene and copy it"
        )
    }

    func testTypingInsideTheSpanIsRefused() throws {
        let (editor, surface) = try opened()
        let omitted = try range(surface, editor, "Mara waits.")
        XCTAssertFalse(
            surface.textView(
                surface.textView,
                shouldChangeTextIn: NSRange(location: omitted.location + 2, length: 0),
                replacementString: "x"
            ),
            "no keystroke reaches a cut scene"
        )
    }

    func testTypingOutsideTheSpanIsUntouched() throws {
        let (editor, surface) = try opened()
        let live = try range(surface, editor, "The kettle screams.")
        XCTAssertTrue(
            surface.textView(
                surface.textView,
                shouldChangeTextIn: NSRange(location: live.location + 2, length: 0),
                replacementString: "x"
            ),
            "every line outside the span behaves exactly as before"
        )
    }

    func testADocumentWithNoOmissionHasNoOmittedRanges() throws {
        let editor = EditorState(source: "INT. LAB - DAY\n\nShe waits.\n")
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        XCTAssertTrue(surface.omittedTextRanges.isEmpty)
        XCTAssertFalse(surface.touchesOmitted(NSRange(location: 2, length: 0)))
    }
}
