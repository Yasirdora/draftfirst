import EDraftCore
import Foundation
import UIKit
import XCTest
@testable import EDraftUIKitSurface

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

    /// Typing a slug straight through, the way a writer trained on any other
    /// screenwriting app types one: spaces and all.
    ///
    /// The dash key writes `" - "` and leaves the caret after it, so the space
    /// typed next lands on one that is already there. Fountain still reads the
    /// heading, and so does `splitSceneHeading`; the cost is that the double
    /// space reaches the page, the PDF and the file. Found in the Mac app by
    /// hand and checked here, because the two surfaces share the rule.
    func testTheSpaceAfterTheDashIsNotTypedTwice() {
        let action = ScriptElement(type: .action, text: "")
        let (editor, textView, coordinator) = surface([action])
        withExtendedLifetime(coordinator) {}

        for character in "int. kitchen - day" {
            type(String(character), into: textView, coordinator)
        }

        XCTAssertEqual(
            editor.screenplay.elements[0].text, "INT. KITCHEN - DAY",
            "the separator already carries its space; the writer's landed on top of it"
        )
    }

    /// The writer who does not type the space must still get the separator's.
    func testTheSeparatorStillSuppliesItsOwnSpace() {
        let action = ScriptElement(type: .action, text: "")
        let (editor, textView, coordinator) = surface([action])
        withExtendedLifetime(coordinator) {}

        for character in "int. kitchen -day" {
            type(String(character), into: textView, coordinator)
        }

        XCTAssertEqual(editor.screenplay.elements[0].text, "INT. KITCHEN - DAY")
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

/// Does the page show what the document says?
///
/// A cue is stored in capitals — the model normalises it on every keystroke.
/// The text view, on the incremental path, keeps whatever the keyboard put
/// there and is never told about the correction. If the two disagree, the
/// writer reads one thing and the file holds another.
@MainActor
final class CasingOnThePageTests: XCTestCase {

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

    /// Types one character the way a keyboard does, uncapitalised — which is
    /// what happens on the first keystroke of a new line, before the keyboard
    /// has been told this element shouts.
    private func type(
        _ text: String, into textView: ScreenplayTextView,
        _ coordinator: ScriptTextView.Coordinator
    ) {
        let range = NSRange(location: textView.textStorage.length, length: 0)
        textView.selectedRange = range
        if coordinator.textView(textView, shouldChangeTextIn: range, replacementText: text) {
            textView.textStorage.replaceCharacters(in: range, with: text)
            textView.selectedRange = NSRange(
                location: range.location + (text as NSString).length, length: 0
            )
            coordinator.textViewDidChange(textView)
        }
    }

    func testACueOnThePageMatchesTheCueInTheDocument() {
        let cue = ScriptElement(type: .character, text: "")
        let (editor, textView, coordinator) = surface([cue])
        withExtendedLifetime(coordinator) {}

        for character in "uncle" { type(String(character), into: textView, coordinator) }

        XCTAssertEqual(editor.screenplay.elements[0].text, "UNCLE", "the document")
        XCTAssertEqual(
            textView.text, "UNCLE",
            "the page shows something the document does not say — a writer reads "
            + "one thing and the file holds another"
        )
    }

    /// The reported shape exactly: a capital, then a stray lowercase, then
    /// capitals — what you get when only some keystrokes are corrected on
    /// screen.
    func testAMixedCaseCueIsCorrectedOnThePageToo() {
        let cue = ScriptElement(type: .character, text: "")
        let (editor, textView, coordinator) = surface([cue])
        withExtendedLifetime(coordinator) {}

        type("U", into: textView, coordinator)
        type("n", into: textView, coordinator)
        type("CLE", into: textView, coordinator)

        XCTAssertEqual(editor.screenplay.elements[0].text, "UNCLE")
        XCTAssertEqual(textView.text, "UNCLE")
    }

    func testATransitionOnThePageMatchesTheDocument() {
        let transition = ScriptElement(type: .transition, text: "")
        let (editor, textView, coordinator) = surface([transition])
        withExtendedLifetime(coordinator) {}

        for character in "cut to:" { type(String(character), into: textView, coordinator) }

        XCTAssertEqual(editor.screenplay.elements[0].text, "CUT TO:")
        XCTAssertEqual(textView.text, "CUT TO:")
    }
}
