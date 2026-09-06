import EDraftCore
import Foundation
import UIKit
import XCTest
@testable import EDraftUIKitSurface

/// Going to a place in the script from the Navigator.
///
/// A row in the Navigator names a place — a scene, or a line somebody speaks —
/// and tapping it has one job: put that place on screen. These pin the two
/// halves of that job, because both have been reported broken and neither was
/// covered: the page must actually move, and it must still be there a moment
/// later, once every deferred layout pass the surface schedules has run.
@MainActor
final class NavigatorJumpTests: XCTestCase {

    /// Long enough that a late scene is far off screen, so a jump that does
    /// nothing is unmistakable.
    private func script() -> String {
        var lines: [String] = []
        for beat in 1...12 {
            lines.append("INT. ROOM \(beat) - DAY")
            lines.append("")
            lines.append("Action for beat \(beat). The road holds its breath.")
            lines.append("")
            lines.append("TANGLE")
            lines.append("Line \(beat) spoken plainly and without hurry.")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func surface() -> (EditorState, ScreenplayTextView, ScriptTextView.Coordinator) {
        let editor = EditorState(source: script())
        // Let any parsing the editor kicked off finish before the surface
        // renders, so the two agree on which elements exist.
        for _ in 0..<4 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        let textView = ScreenplayTextView(usingTextLayoutManager: false)
        textView.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        let coordinator = ScriptTextView.Coordinator(editor: editor)
        coordinator.attach(to: textView)
        coordinator.renderModel(selecting: nil, offset: nil)
        // A detached view never lays out on its own, and an unlaid text view
        // reports no content to scroll through — which would make every jump
        // look like a no-op for reasons the app never has.
        textView.layoutIfNeeded()
        return (editor, textView, coordinator)
    }

    /// Lets every deferred pass the surface scheduled actually run — the
    /// re-pins and settles that follow a render by one or more runloop turns.
    private func settle() {
        for _ in 0..<4 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
    }

    // MARK: - The page moves

    func testJumpingToALateSceneScrollsToIt() throws {
        let (editor, textView, coordinator) = surface()
        withExtendedLifetime(coordinator) {}
        let scene = try XCTUnwrap(editor.scenes.last)
        let before = textView.contentOffset.y

        editor.jump(to: scene.id)

        XCTAssertGreaterThan(
            textView.contentOffset.y, before,
            "the page did not move towards the scene the row named"
        )
        XCTAssertEqual(editor.activeElementID, scene.id)
    }

    func testJumpingToASpokenLineScrollsToIt() throws {
        let (editor, textView, coordinator) = surface()
        withExtendedLifetime(coordinator) {}
        let appearances = editor.appearances(of: "TANGLE")
        let line = try XCTUnwrap(appearances.last?.lines.last)
        let before = textView.contentOffset.y

        editor.jump(to: line.id)

        XCTAssertGreaterThan(
            textView.contentOffset.y, before,
            "the page did not move towards the line the row named"
        )
        XCTAssertEqual(editor.activeElementID, line.id)
    }

    // MARK: - And stays there

    /// The reported bug: a jump lands, and a beat later the page is back where
    /// it was. Every render schedules a deferred correction that puts the page
    /// back around the caret it remembered; a jump that arrives in between is
    /// undone by it.
    func testAJumpSurvivesTheDeferredPassesThatFollowIt() throws {
        let (editor, textView, coordinator) = surface()
        withExtendedLifetime(coordinator) {}
        let scene = try XCTUnwrap(editor.scenes.last)

        editor.jump(to: scene.id)
        let landed = textView.contentOffset.y
        settle()

        XCTAssertEqual(
            textView.contentOffset.y, landed, accuracy: 1,
            "the page drifted away from the scene after the jump"
        )
    }

    /// The same, with a render immediately before the jump — the state the
    /// surface is in when the Navigator was opened after any edit at all.
    func testAJumpAfterARenderSurvivesThatRendersOwnDeferredPass() throws {
        let (editor, textView, coordinator) = surface()
        withExtendedLifetime(coordinator) {}
        let scene = try XCTUnwrap(editor.scenes.last)

        coordinator.renderModel(selecting: nil, offset: nil)
        editor.jump(to: scene.id)
        let landed = textView.contentOffset.y
        settle()

        XCTAssertEqual(
            textView.contentOffset.y, landed, accuracy: 1,
            "the render's deferred settle pulled the page back off the scene"
        )
    }

    /// Reading mode: the surface does not hold the keyboard, and a jump must
    /// still move the page. This is the one the cast list uses, and the one
    /// reported as never working.
    func testAJumpWorksWhileTheSurfaceIsNotFocused() throws {
        let (editor, textView, coordinator) = surface()
        withExtendedLifetime(coordinator) {}
        XCTAssertFalse(textView.isFirstResponder, "the surface should be unfocused here")
        let line = try XCTUnwrap(editor.appearances(of: "TANGLE").last?.lines.last)

        editor.jump(to: line.id)
        let landed = textView.contentOffset.y
        settle()

        XCTAssertGreaterThan(landed, 0, "the page did not move while unfocused")
        XCTAssertEqual(
            textView.contentOffset.y, landed, accuracy: 1,
            "the page drifted after an unfocused jump"
        )
    }

    // MARK: - And says where it landed

    /// The mark is the whole answer to "did that work?", so it must appear
    /// wherever a row can be tapped — including the places the page cannot
    /// move to, which is where the rows looked dead.
    private func mark(in textView: UITextView) -> RevealHighlightView? {
        textView.subviews.compactMap { $0 as? RevealHighlightView }.first
    }

    func testARevealMarksTheElementItLandedOn() throws {
        let (editor, textView, coordinator) = surface()
        withExtendedLifetime(coordinator) {}
        let scene = try XCTUnwrap(editor.scenes.last)

        editor.jump(to: scene.id)
        settle()

        let highlight = try XCTUnwrap(mark(in: textView), "nothing marked the landing")
        XCTAssertFalse(highlight.frame.isEmpty, "the mark has no place on the page")
    }

    /// The reported case: the last scene of a short script cannot come to the
    /// top, so the page barely moves. Without the mark this is exactly what
    /// "sometimes it doesn't work" looked like.
    func testAnElementThePageCannotScrollToIsStillMarked() throws {
        let (editor, textView, coordinator) = surface()
        withExtendedLifetime(coordinator) {}
        let scene = try XCTUnwrap(editor.scenes.last)

        // Park at the very bottom first: from here the page has nowhere left
        // to go, so scrolling alone can say nothing at all.
        textView.setContentOffset(
            CGPoint(x: 0, y: textView.contentSize.height - textView.bounds.height),
            animated: false
        )
        editor.jump(to: scene.id)
        settle()

        XCTAssertNotNil(mark(in: textView), "a target the page cannot reach was left unmarked")
    }

    /// The bug the Mac's measurements found in this surface: a line with
    /// nothing on it measures no *width*, and a rectangle counts as empty when
    /// either dimension is zero — so the mark was being discarded for exactly
    /// the lines a writer is about to type into. The blank line at the very end
    /// of a script is the worst case: it has no line fragment of its own at all.
    func testABlankLineIsStillMarked() throws {
        let editor = EditorState(source: "INT. ROOM - DAY")
        for _ in 0..<4 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        // A blank line is what Return leaves behind, not something a parse
        // produces — the writer is standing on it, about to type.
        let blank = ScriptElement(type: .action, text: "")
        editor.screenplay = Screenplay(
            titlePage: [],
            elements: [ScriptElement(type: .scene, text: "INT. ROOM - DAY"), blank]
        )
        let textView = ScreenplayTextView(usingTextLayoutManager: false)
        textView.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        let coordinator = ScriptTextView.Coordinator(editor: editor)
        coordinator.attach(to: textView)
        coordinator.renderModel(selecting: nil, offset: nil)
        textView.layoutIfNeeded()
        withExtendedLifetime(coordinator) {}

        editor.jump(to: blank.id)
        settle()

        let highlight = try XCTUnwrap(mark(in: textView), "a blank line was left unmarked")
        XCTAssertGreaterThan(highlight.frame.height, 0)
        XCTAssertGreaterThan(highlight.frame.width, 1, "marked across the line, not as a sliver")
    }

    // MARK: - One jump after another

    /// The reported bug: a scene row works, then a cast line does nothing on
    /// the first tap and works on the second — and the same in reverse. What
    /// the two have in common is not which list they came from: it is that a
    /// jump had already happened.
    func testASecondJumpMovesThePageOnTheFirstTry() throws {
        let (editor, textView, coordinator) = surface()
        withExtendedLifetime(coordinator) {}
        let scene = try XCTUnwrap(editor.scenes.last)
        let line = try XCTUnwrap(editor.appearances(of: "TANGLE").first?.lines.first)

        editor.jump(to: scene.id)
        settle()
        let afterFirst = textView.contentOffset.y

        // A line near the top: the page must come back up for it.
        editor.jump(to: line.id)
        settle()

        XCTAssertNotEqual(
            textView.contentOffset.y, afterFirst, accuracy: 1,
            "the second jump left the page where the first one put it"
        )
    }

    /// The same, with the render the sheet's dismissal provokes in between —
    /// which is what actually happens when the Navigator closes behind a tap.
    func testAJumpAfterARenderBetweenTwoJumpsStillMoves() throws {
        let (editor, textView, coordinator) = surface()
        withExtendedLifetime(coordinator) {}
        let scene = try XCTUnwrap(editor.scenes.last)
        let line = try XCTUnwrap(editor.appearances(of: "TANGLE").first?.lines.first)

        editor.jump(to: scene.id)
        settle()
        coordinator.renderModel(selecting: nil, offset: nil)
        settle()
        let afterFirst = textView.contentOffset.y

        editor.jump(to: line.id)
        settle()

        XCTAssertNotEqual(
            textView.contentOffset.y, afterFirst, accuracy: 1,
            "a jump after a re-render did nothing"
        )
    }

    /// A reveal that arrives *between* a render and the deferred pass that
    /// render scheduled.
    ///
    /// Every render schedules a correction one runloop turn later, to counter
    /// the text view re-pinning its offset. That correction was captured before
    /// the reveal existed and knows nothing about it — so if a reveal lands in
    /// the gap, the page is dragged back to where the render wanted it and the
    /// row looks dead.
    func testAJumpLandingBetweenARenderAndItsDeferredPassSurvives() throws {
        let (editor, textView, coordinator) = surface()
        withExtendedLifetime(coordinator) {}
        let scene = try XCTUnwrap(editor.scenes.last)

        // No settle here: the deferred pass is still in flight.
        coordinator.renderModel(selecting: nil, offset: nil)
        editor.jump(to: scene.id)
        let landed = textView.contentOffset.y
        settle()

        XCTAssertEqual(
            textView.contentOffset.y, landed, accuracy: 1,
            "a render's deferred pass dragged the page off the element the row named"
        )
        XCTAssertGreaterThan(landed, 0, "the reveal should have moved the page at all")
    }
}
