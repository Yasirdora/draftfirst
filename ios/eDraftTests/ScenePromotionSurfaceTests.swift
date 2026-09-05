import EDraftCore
import Foundation
import UIKit
import XCTest
@testable import eDraft

/// Typing a slug makes the line a slug.
///
/// The rule itself is `ScenePromotion` in the core and tested there; this
/// covers the half that only exists on the surface — that a writer typing into
/// a live text view sees the line change kind, wearing the caps a heading
/// wears, without having said anything about it.
@MainActor
final class ScenePromotionSurfaceTests: XCTestCase {

    private func surface(_ elements: [ScriptElement])
    -> (EditorState, ScreenplayTextView, ScriptTextView.Coordinator) {
        let editor = EditorState(source: "An opening image.")
        for _ in 0..<4 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        editor.screenplay = Screenplay(titlePage: [], elements: elements)
        editor.activeElementID = elements.first?.id

        let textView = ScreenplayTextView(usingTextLayoutManager: false)
        textView.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        let coordinator = ScriptTextView.Coordinator(editor: editor)
        coordinator.attach(to: textView)
        coordinator.renderModel(selecting: elements.first?.id, offset: 0)
        textView.layoutIfNeeded()
        return (editor, textView, coordinator)
    }

    /// Types `text` the way a keyboard does — through the delegate, one call,
    /// then the change notification the surface listens to.
    private func type(
        _ text: String, into textView: ScreenplayTextView,
        _ coordinator: ScriptTextView.Coordinator
    ) {
        let range = NSRange(location: textView.textStorage.length, length: 0)
        textView.selectedRange = range
        if coordinator.textView(textView, shouldChangeTextIn: range, replacementText: text) {
            textView.textStorage.replaceCharacters(in: range, with: text)
            textView.selectedRange = NSRange(location: range.location + (text as NSString).length, length: 0)
            coordinator.textViewDidChange(textView)
        }
    }

    func testTypingASlugTurnsAnActionLineIntoASceneHeading() {
        let action = ScriptElement(type: .action, text: "")
        let (editor, textView, coordinator) = surface([action])
        withExtendedLifetime(coordinator) {}

        type("INT. KITCHEN", into: textView, coordinator)

        XCTAssertEqual(
            editor.screenplay.elements[0].type, .scene,
            "Fountain calls this line a scene heading; the editor must agree as it is typed"
        )
    }

    /// The conversion goes through the same channel as every other, so the
    /// heading wears the caps a heading wears.
    func testThePromotedLineIsShouted() {
        let action = ScriptElement(type: .action, text: "")
        let (editor, textView, coordinator) = surface([action])
        withExtendedLifetime(coordinator) {}

        type("int. kitchen", into: textView, coordinator)

        XCTAssertEqual(editor.screenplay.elements[0].type, .scene)
        XCTAssertEqual(editor.screenplay.elements[0].text, "INT. KITCHEN")
    }

    /// A word that merely begins with those letters is not a heading, and an
    /// action line must never flinch mid-sentence.
    func testAnOrdinaryActionLineIsLeftAlone() {
        let action = ScriptElement(type: .action, text: "")
        let (editor, textView, coordinator) = surface([action])
        withExtendedLifetime(coordinator) {}

        type("INTO the room she goes.", into: textView, coordinator)

        XCTAssertEqual(editor.screenplay.elements[0].type, .action)
    }

    /// A writer who has said what a line is does not get argued with.
    func testACueIsNotPromotedHoweverItReads() {
        let cue = ScriptElement(type: .character, text: "")
        let (editor, textView, coordinator) = surface([cue])
        withExtendedLifetime(coordinator) {}

        type("INT. KITCHEN", into: textView, coordinator)

        XCTAssertEqual(editor.screenplay.elements[0].type, .character)
    }
}
