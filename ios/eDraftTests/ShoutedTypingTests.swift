import EDraftCore
import Foundation
import UIKit
import XCTest
@testable import EDraftUIKitSurface

/// Typing into a line the page shouts — a scene heading, a cue, a transition,
/// a shot — from somewhere other than the end of it.
///
/// The Mac had a fault here: it let the lowercase letter into the storage and
/// rewrote the whole element afterwards, and on AppKit replacing a range moves
/// the insertion point to the end of it, so `int` typed at the head of
/// `LOCATION` came out `ILOCATIONNT`. `0527f9d` fixed that by shouting at the
/// input boundary instead.
///
/// The phone reaches the same rule by a different road: `updateTypingTraits`
/// asks the keyboard for `.allCharacters`, so the letters usually arrive
/// already capital and the repair never runs. These tests exist to pin what
/// happens on the roads where they do not — a hardware keyboard, a paste, an
/// iPad — because that is the traffic iPadOS is about to add.
@MainActor
final class ShoutedTypingTests: XCTestCase {

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

    /// Types at wherever the caret currently is, the way UIKit does: ask the
    /// delegate, and if it says yes, apply the edit, put the caret after what
    /// was inserted, and post the change.
    private func type(
        _ text: String, into textView: ScreenplayTextView,
        _ coordinator: ScriptTextView.Coordinator
    ) {
        let range = textView.selectedRange
        if coordinator.textView(textView, shouldChangeTextIn: range, replacementText: text) {
            textView.textStorage.replaceCharacters(in: range, with: text)
            textView.selectedRange = NSRange(
                location: range.location + (text as NSString).length, length: 0
            )
            coordinator.textViewDidChange(textView)
        }
    }

    // MARK: - What UIKit actually does

    /// The measurement the Mac's fix rested on, asked again of UIKit rather
    /// than assumed to have the same answer.
    ///
    /// On AppKit this moves the insertion point to the end of the replaced
    /// range, which is why repairing text after the fact scrambled it. If
    /// UIKit agrees, the phone has the Mac's bug on every road the keyboard
    /// does not pave. If it disagrees, that is worth knowing too, and worth
    /// pinning here so the next person does not assume parity.
    func testWhatReplacingAStorageRangeDoesToTheInsertionPoint() {
        let (_, textView, coordinator) = surface(
            [ScriptElement(type: .action, text: "abcdefgh")]
        )
        withExtendedLifetime(coordinator) {}
        textView.selectedRange = NSRange(location: 2, length: 0)

        textView.textStorage.replaceCharacters(
            in: NSRange(location: 0, length: 8), with: "ABCDEFGH"
        )

        XCTAssertEqual(
            textView.selectedRange.location, 2,
            "UIKit moved the caret on a storage replace, the way AppKit does. The "
                + "phone therefore has the Mac's scrambling fault wherever text "
                + "arrives lowercase, and this measurement is the proof."
        )
    }

    // MARK: - What the writer sees

    /// A hardware keyboard — an iPad's, or a Mac's over Sidecar — does not
    /// obey `autocapitalizationType`. Its letters arrive lowercase, and the
    /// element must still end up shouting, in order.
    func testTypingLowercaseAtTheHeadOfASceneHeadingKeepsTheLettersInOrder() {
        let heading = ScriptElement(type: .scene, text: "LOCATION")
        let (editor, textView, coordinator) = surface([heading])
        withExtendedLifetime(coordinator) {}
        textView.selectedRange = NSRange(location: 0, length: 0)

        for letter in "int" {
            type(String(letter), into: textView, coordinator)
        }

        XCTAssertEqual(
            editor.screenplay.elements[0].text, "INTLOCATION",
            "the letters were reordered; the caret is not staying where it was typed"
        )
        XCTAssertEqual(textView.text, "INTLOCATION")
    }

    func testTheCaretStaysWhereItWasTypedInAShoutedLine() {
        let cue = ScriptElement(type: .character, text: "MARA")
        let (_, textView, coordinator) = surface([cue])
        withExtendedLifetime(coordinator) {}
        textView.selectedRange = NSRange(location: 0, length: 0)

        type("u", into: textView, coordinator)

        XCTAssertEqual(
            textView.selectedRange.location, 1,
            "one letter typed at the head should leave the caret after it, not at the end"
        )
    }

    /// A kind that does not shout has never had this problem, and must not
    /// acquire one from the fix.
    func testTypingIntoTheMiddleOfActionIsUnaffected() {
        let action = ScriptElement(type: .action, text: "she waits")
        let (editor, textView, coordinator) = surface([action])
        withExtendedLifetime(coordinator) {}
        textView.selectedRange = NSRange(location: 4, length: 0)

        type("X", into: textView, coordinator)

        XCTAssertEqual(editor.screenplay.elements[0].text, "she Xwaits")
        XCTAssertEqual(textView.selectedRange.location, 5)
    }

    // MARK: - The page and the file must say the same thing

    /// `ß` uppercases to `SS` — one UTF-16 unit becoming two.
    ///
    /// Both the model and the surface used to decline that, so the letter
    /// stayed lowercase in a line that shouts. The Mac, capitalising at the
    /// input boundary since 0527f9d, did not decline it — so the same
    /// keystroke produced `SS` at a desk and `ß` on a phone, which is the
    /// one thing this architecture exists to make impossible.
    ///
    /// The rule now lives in one place and says one thing. What the surface
    /// keeps is the consequence: when the model's answer is not the length of
    /// what was typed, the page is redrawn from it.
    func testASharpSLooksOnThePageTheWayItIsStoredInTheFile() {
        let cue = ScriptElement(type: .character, text: "")
        let (editor, textView, coordinator) = surface([cue])
        withExtendedLifetime(coordinator) {}
        textView.selectedRange = NSRange(location: 0, length: 0)

        type("ß", into: textView, coordinator)

        XCTAssertEqual(
            editor.screenplay.elements[0].text, "SS",
            "a cue shouts, and ß shouts as SS"
        )
        XCTAssertEqual(
            textView.text, editor.screenplay.elements[0].text,
            "the page and the file disagree about what the writer just typed"
        )
    }

    /// The expansion happening in the *middle* of a line, which is where the
    /// caret arithmetic has to be right rather than merely lucky.
    ///
    /// The offset is measured on the shouted prefix — capitalise what is before
    /// the caret and take its length — so two letters arriving where one was
    /// typed carries the caret past both. The Mac asserts the same three values
    /// in `EDraftMacSurfaceTests`, by a different road: it capitalises the
    /// replacement before insertion, where the phone lets the model answer and
    /// redraws. Different roads, one destination, is the whole claim.
    func testASharpSInTheMiddleOfACueShoutsWithoutScramblingTheLine() {
        let cue = ScriptElement(type: .character, text: "MARA")
        let (editor, textView, coordinator) = surface([cue])
        withExtendedLifetime(coordinator) {}
        textView.selectedRange = NSRange(location: 2, length: 0)

        type("ß", into: textView, coordinator)

        XCTAssertEqual(editor.screenplay.elements[0].text, "MASSRA")
        XCTAssertEqual(textView.text, "MASSRA")
        XCTAssertEqual(
            textView.selectedRange.location, 4,
            "two letters were inserted where one was typed; the caret must clear both"
        )
    }
}
