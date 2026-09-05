import AppKit
import EDraftCore
import EDraftUI
import XCTest
@testable import EDraftMacSurface

/// Find-in-page and Find Scene, as far as a windowless surface can tell.
///
/// The system find bar itself is not honestly testable here — see
/// `TextFinderMeasurementTests`. These tests cover the model-facing half:
/// a find landing updates the active element, a filtered scene still
/// reveals, and a find session hides the ghost.
@MainActor
final class ScriptSurfaceFindTests: XCTestCase {

    private func script() -> [ScriptElement] {
        [
            ScriptElement(type: .scene, text: "INT. KITCHEN - DAY"),
            ScriptElement(type: .action, text: "She waits."),
            ScriptElement(type: .character, text: "MARA"),
            ScriptElement(type: .dialogue, text: "Keep moving."),
            ScriptElement(type: .scene, text: "EXT. ALLEY - NIGHT"),
            ScriptElement(type: .action, text: "Rain.")
        ]
    }

    func testLandingOnAFindHitUpdatesTheActiveElement() throws {
        let elements = script()
        let alley = elements[4]
        let (editor, surface) = ScriptSurfaceHarness.bound(elements, active: 0)
        XCTAssertEqual(editor.activeElementID, elements[0].id)

        let mapped = try XCTUnwrap(
            ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
                .first { $0.id == alley.id }
        )
        // A find hit is a selection on the matched characters, not a caret
        // at the start — that is what Find Next actually leaves.
        surface.textView.setSelectedRange(
            NSRange(location: mapped.range.location, length: min(3, mapped.range.length))
        )
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: surface.textView)
        )

        XCTAssertEqual(
            editor.activeElementID, alley.id,
            "a find landing did not tell the model — Tab and ⌘1–9 would hit the wrong line"
        )
    }

    func testAJumpFromAFilteredSceneRevealsAndMarks() throws {
        let elements = script()
        let alley = try XCTUnwrap(elements.last { $0.type == .scene })
        let (editor, surface) = ScriptSurfaceHarness.bound(elements, active: 0)
        editor.onJumpToElement = { id in
            _ = surface.reveal(id)
        }

        let visible = SceneListFilter.included(editor.scenes, query: "alley")
        XCTAssertEqual(visible.map(\.id), [alley.id])

        editor.jump(to: alley.id)

        XCTAssertEqual(editor.activeElementID, alley.id)
        XCTAssertTrue(surface.isMarking, "the filtered row jumped but did not mark")
        XCTAssertEqual(
            surface.element(at: surface.textView.selectedRange().location), alley.id
        )
    }

    func testTheGhostHidesWhileTheFindBarIsUp() {
        let mara = ScriptElement(type: .character, text: "MARA")
        let cue = ScriptElement(type: .character, text: "MA")
        let elements = [
            ScriptElement(type: .scene, text: "INT. ROOM - DAY"),
            mara,
            ScriptElement(type: .dialogue, text: "Keep moving."),
            ScriptElement(type: .action, text: "She waits."),
            cue
        ]
        let (editor, surface) = ScriptSurfaceHarness.bound(elements, active: 4)
        ScriptSurfaceHarness.placeCaret(editor, surface, on: cue)
        XCTAssertTrue(ScriptSurfaceHarness.waitForGhost(editor, surface))

        surface.scrollView.isFindBarVisible = true
        surface.updateGhost()

        XCTAssertFalse(
            surface.isShowingGhost,
            "a completion stayed on the page while Find was up"
        )
    }
}
