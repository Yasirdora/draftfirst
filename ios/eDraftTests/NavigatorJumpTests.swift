import EDraftCore
import Foundation
import UIKit
import XCTest
@testable import eDraft

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
}
