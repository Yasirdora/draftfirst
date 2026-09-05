import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// The ghost on the Mac page, driven without a window.
///
/// This is the first real net the ghost has ever had — the phone only covers
/// it through the `EDITOR_PREVIEW` demo. Each test names the behaviour.
/// Predictions are async (65ms plus the engine); the harness waits.
@MainActor
final class ScriptSurfaceGhostTests: XCTestCase {

    /// A script that already knows MARA, so typing `MA` on a new cue has
    /// a completion the engine, not the surface, computed.
    private func scriptWithMara(typedCue: String = "MA") -> [ScriptElement] {
        [
            ScriptElement(type: .scene, text: "INT. ROOM - DAY"),
            ScriptElement(type: .character, text: "MARA"),
            ScriptElement(type: .dialogue, text: "Keep moving."),
            ScriptElement(type: .action, text: "She waits."),
            ScriptElement(type: .character, text: typedCue)
        ]
    }

    private func cueSurface(typedCue: String = "MA")
    -> (EditorState, ScriptSurface, ScriptElement) {
        let elements = scriptWithMara(typedCue: typedCue)
        let cue = elements[4]
        let (editor, surface) = ScriptSurfaceHarness.bound(elements, active: 4)
        ScriptSurfaceHarness.placeCaret(editor, surface, on: cue)
        return (editor, surface, cue)
    }

    // MARK: - It draws, and it is not in the document

    func testAGhostAppearsForAKnownCueAndTheSuffixIsTheEngines() {
        let (editor, surface, _) = cueSurface()

        XCTAssertTrue(
            ScriptSurfaceHarness.waitForGhost(editor, surface),
            "a known cue prefix produced no ghost"
        )
        let suffix = try! XCTUnwrap(editor.currentSuggestionSuffix)
        XCTAssertFalse(suffix.isEmpty)
        XCTAssertEqual(
            surface.presentedGhostSuffix, suffix,
            "the overlay drew a suffix the engine did not offer"
        )
        XCTAssertEqual(suffix, "RA", "MARA minus the typed MA")
    }

    func testTheDocumentDoesNotContainTheGhost() throws {
        let (editor, surface, cue) = cueSurface()
        XCTAssertTrue(ScriptSurfaceHarness.waitForGhost(editor, surface))

        let index = try XCTUnwrap(editor.screenplay.elements.firstIndex(where: { $0.id == cue.id }))
        XCTAssertEqual(
            editor.screenplay.elements[index].text, "MA",
            "the model absorbed the ghost"
        )

        let mapped = try XCTUnwrap(
            ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
                .first { $0.id == cue.id }
        )
        let stored = try XCTUnwrap(surface.textView.textStorage)
            .attributedSubstring(from: mapped.range).string
        XCTAssertEqual(stored, "MA", "the text storage absorbed the ghost")
        XCTAssertEqual(surface.presentedGhostSuffix, "RA")
    }

    func testTheOverlaySitsOnTheHostLineNotTheDocument() {
        let (editor, surface, _) = cueSurface()
        XCTAssertTrue(
            ScriptSurfaceHarness.waitForGhost(editor, surface),
            "suffix=\(editor.currentSuggestionSuffix ?? "nil") hidden=\(surface.presentedGhostSuffix ?? "nil")"
        )

        let frame = surface.ghostFrame
        let line = surface.ghostHostLineRect
        XCTAssertGreaterThan(frame.width, 0, "the overlay has no width — nothing drew")
        XCTAssertGreaterThan(frame.height, 0, "the overlay has no height — nothing drew")
        XCTAssertLessThan(
            frame.height, 80,
            "the overlay is as tall as the document; hostLineRect was ignored"
        )
        XCTAssertFalse(line.isNull)
        XCTAssertEqual(
            frame.midY, line.midY, accuracy: 12,
            "the overlay is not on the host line — isFlipped or hostLineRect is wrong"
        )
        XCTAssertTrue(
            frame.intersects(line),
            "the overlay missed the host line entirely"
        )
    }

    // MARK: - Guards

    func testNoGhostWhenTheCaretIsMidElement() {
        let (editor, surface, cue) = cueSurface()
        XCTAssertTrue(ScriptSurfaceHarness.waitForGhost(editor, surface))

        ScriptSurfaceHarness.placeCaret(editor, surface, on: cue, atEnd: false)

        XCTAssertFalse(
            surface.isShowingGhost,
            "a caret in the middle of the cue still showed a ghost"
        )
    }

    func testNoGhostForATransition() {
        let transition = ScriptElement(type: .transition, text: "CUT")
        let (editor, surface) = ScriptSurfaceHarness.bound([transition])
        ScriptSurfaceHarness.placeCaret(editor, surface, on: transition)

        _ = ScriptSurfaceHarness.waitForSuffix(editor)
        ScriptSurfaceHarness.wait(timeout: 0.4) { false }
        surface.updateGhost()

        XCTAssertFalse(
            surface.isShowingGhost,
            "a transition showed a ghost — the kind is excluded"
        )
    }

    func testAHintDrawsDimmerAndRefusesSpaceAndAccept() {
        let heading = ScriptElement(type: .scene, text: "INT.")
        let (editor, surface) = ScriptSurfaceHarness.bound([heading])
        ScriptSurfaceHarness.placeCaret(editor, surface, on: heading)

        XCTAssertTrue(
            ScriptSurfaceHarness.wait(timeout: 2) {
                editor.currentPrediction?.hint == true && surface.isShowingGhost
            },
            "INT. did not produce a hint ghost"
        )
        XCTAssertEqual(
            surface.ghostForegroundColor, NSColor.tertiaryLabelColor,
            "a hint must draw as tertiary label, not a hard-coded grey"
        )

        let allowed = ScriptSurfaceHarness.type(" ", into: surface)
        XCTAssertTrue(
            allowed,
            "Space accepted a hint — hints are advisory and must insert literally"
        )
        editor.acceptPrediction()
        XCTAssertEqual(
            editor.screenplay.elements[0].text, "INT. ",
            "⌘→ / acceptPrediction committed a hint"
        )
    }

    // MARK: - Accept

    func testSpaceAtTheEndOfALiveGhostAcceptsIt() throws {
        let (editor, surface, cue) = cueSurface()
        XCTAssertTrue(ScriptSurfaceHarness.waitForGhost(editor, surface))
        XCTAssertEqual(surface.ghostForegroundColor, NSColor.secondaryLabelColor)

        XCTAssertFalse(
            ScriptSurfaceHarness.type(" ", into: surface),
            "Space on a live ghost should be consumed"
        )

        let index = try XCTUnwrap(editor.screenplay.elements.firstIndex(where: { $0.id == cue.id }))
        // Space-to-accept keeps the space, matching the phone: the writer
        // typed one, and a cue with a trailing space is ready for (V.O.).
        XCTAssertEqual(editor.screenplay.elements[index].text, "MARA ")
        XCTAssertEqual(editor.screenplay.elements[index].type, .character)
    }

    func testAGhostBeginningWithASpaceTakesTheSpaceLiterallyThenAccepts() throws {
        let heading = ScriptElement(type: .scene, text: "INT. KITCHEN -")
        let (editor, surface) = ScriptSurfaceHarness.bound([heading])
        ScriptSurfaceHarness.placeCaret(editor, surface, on: heading)

        XCTAssertTrue(
            ScriptSurfaceHarness.wait(timeout: 2) {
                (editor.currentSuggestionSuffix ?? "").hasPrefix(" ")
                    && surface.isShowingGhost
            },
            "INT. KITCHEN - did not produce a leading-space ghost"
        )
        let suffix = try XCTUnwrap(editor.currentSuggestionSuffix)
        XCTAssertTrue(suffix.hasPrefix(" "), "expected a leading space, got \(suffix)")

        XCTAssertTrue(
            ScriptSurfaceHarness.type(" ", into: surface),
            "the first space must insert literally so EVENING is still typeable"
        )
        XCTAssertTrue(
            editor.screenplay.elements[0].text.hasSuffix(" "),
            "the first space was swallowed as an accept"
        )

        XCTAssertTrue(ScriptSurfaceHarness.waitForGhost(editor, surface))
        XCTAssertFalse(
            ScriptSurfaceHarness.type(" ", into: surface),
            "the second space should accept"
        )
        let text = editor.screenplay.elements[0].text
        XCTAssertFalse(text.hasSuffix("- "), "accept left the separator hanging")
        XCTAssertTrue(text.contains("INT. KITCHEN"), text)
    }

    func testAcceptPredictionAcceptsWithoutATrailingSpace() throws {
        let (editor, surface, cue) = cueSurface()
        XCTAssertTrue(ScriptSurfaceHarness.waitForGhost(editor, surface))

        editor.acceptPrediction()

        let index = try XCTUnwrap(editor.screenplay.elements.firstIndex(where: { $0.id == cue.id }))
        XCTAssertEqual(editor.screenplay.elements[index].text, "MARA")
        XCTAssertFalse(editor.screenplay.elements[index].text.hasSuffix(" "))
        XCTAssertFalse(surface.isShowingGhost)
    }

    func testAcceptingIsOneUndoStep() throws {
        let (editor, surface, cue) = cueSurface()
        XCTAssertTrue(ScriptSurfaceHarness.waitForGhost(editor, surface))

        editor.acceptPrediction()
        let index = try XCTUnwrap(editor.screenplay.elements.firstIndex(where: { $0.id == cue.id }))
        XCTAssertEqual(editor.screenplay.elements[index].text, "MARA")

        XCTAssertTrue(editor.canUndo)
        editor.undo()
        XCTAssertEqual(
            editor.screenplay.elements[index].text, "MA",
            "undo did not restore the typed prefix"
        )
    }

    func testTypingACharacterThatInvalidatesTheSuggestionRemovesTheGhost() {
        let (editor, surface, _) = cueSurface()
        XCTAssertTrue(ScriptSurfaceHarness.waitForGhost(editor, surface))

        XCTAssertTrue(ScriptSurfaceHarness.type("Q", into: surface))

        XCTAssertTrue(
            ScriptSurfaceHarness.wait(timeout: 2) { !surface.isShowingGhost },
            "a letter that matches no cue left a stale ghost on the page"
        )
        XCTAssertEqual(editor.screenplay.elements.last?.text, "MAQ")
    }

    /// AppKit is stricter than UIKit about replacing the storage from inside
    /// `textDidChange`. Typing a slug goes
    /// `promoteToSceneHeadingIfTyped` → `changeKind` → `applyModelEdit` →
    /// `render` on that path. If it throws, that finding outranks the ghost.
    func testInsertingASlugThroughAppKitPromotesWithoutThrowing() {
        let action = ScriptElement(type: .action, text: "")
        let (editor, surface) = ScriptSurfaceHarness.bound([action])
        ScriptSurfaceHarness.placeCaret(editor, surface, on: action)

        surface.textView.insertText("int. kitchen", replacementRange: surface.textView.selectedRange())

        XCTAssertEqual(editor.screenplay.elements[0].type, .scene)
        XCTAssertEqual(editor.screenplay.elements[0].text, "INT. KITCHEN")
    }
}
