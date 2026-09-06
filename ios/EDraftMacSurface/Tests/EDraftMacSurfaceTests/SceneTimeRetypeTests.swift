import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// Rewriting the time on a scene heading.
///
/// Reported from the running Mac app: type a heading with a location and a
/// time, double-click the time to select it, delete it, and start typing the
/// time again — and the engine stops offering anything. Predictions only run
/// when the caret is at the end of the element (`refreshPredictions` guards on
/// `selectionOffset == text.utf16.count`), so a selection-deletion that leaves
/// the model's idea of the caret behind switches them off for good.
@MainActor
final class SceneTimeRetypeTests: XCTestCase {

    /// A script the engine has seen DAY in, so there is something to offer.
    private func surface() -> (EditorState, ScriptSurface, ScriptElement) {
        let heading = ScriptElement(type: .scene, text: "INT. KITCHEN - DAY")
        let elements = [
            ScriptElement(type: .scene, text: "INT. HALLWAY - DAY"),
            ScriptElement(type: .action, text: "She waits."),
            heading
        ]
        let (editor, surface) = ScriptSurfaceHarness.bound(elements, active: 2)
        ScriptSurfaceHarness.placeCaret(editor, surface, on: heading)
        return (editor, surface, heading)
    }

    /// The range of the trailing word, the way a double-click selects it.
    private func timeRange(_ editor: EditorState, _ surface: ScriptSurface,
                           _ element: ScriptElement) -> NSRange {
        let mapped = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
            .first { $0.id == element.id }!
        let text = editor.screenplay.elements.last!.text as NSString
        let word = text.range(of: "DAY", options: .backwards)
        return NSRange(location: mapped.range.location + word.location, length: word.length)
    }

    /// What a double-click actually does: select the word — which posts a
    /// selection change the surface listens to — and only then delete it.
    private func doubleClickAndDelete(
        _ editor: EditorState, _ surface: ScriptSurface, _ element: ScriptElement
    ) {
        let range = timeRange(editor, surface, element)
        surface.textView.setSelectedRange(range)
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: surface.textView)
        )
        ScriptSurfaceHarness.type("", into: surface, at: range)
    }

    func testDeletingTheTimeLeavesTheCaretWhereTheModelThinksItIs() {
        let (editor, surface, heading) = surface()

        doubleClickAndDelete(editor, surface, heading)

        let text = editor.screenplay.elements[2].text
        XCTAssertEqual(text, "INT. KITCHEN - ")
        XCTAssertEqual(
            editor.selectionOffset, (text as NSString).length,
            "the model's caret is not at the end of what is left, so "
                + "refreshPredictions will refuse to run"
        )
    }

    func testTheEngineStillPredictsWhenTheTimeIsTypedAgain() {
        let (editor, surface, heading) = surface()
        doubleClickAndDelete(editor, surface, heading)

        ScriptSurfaceHarness.type("D", into: surface)

        XCTAssertTrue(
            ScriptSurfaceHarness.wait { editor.currentSuggestionSuffix?.isEmpty == false },
            "the engine offered nothing after the time was deleted and retyped"
        )
    }

    // MARK: - The whole flow, typed rather than assembled

    /// The tests above start from a heading that already exists. This one
    /// types it, so promotion and the separator both run first — which is what
    /// the writer actually did.
    func testTypingAHeadingThenRewritingItsTimeStillPredicts() {
        let known = ScriptElement(type: .scene, text: "INT. HALLWAY - DAY")
        let blank = ScriptElement(type: .action, text: "")
        let (editor, surface) = ScriptSurfaceHarness.bound([known, blank], active: 1)
        ScriptSurfaceHarness.placeCaret(editor, surface, on: blank)

        for character in "int. kitchen - day" {
            ScriptSurfaceHarness.type(String(character), into: surface)
        }
        XCTAssertEqual(editor.screenplay.elements[1].text, "INT. KITCHEN - DAY")

        // Double-click the time, then delete it.
        let mapped = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
            .first { $0.id == editor.screenplay.elements[1].id }!
        let text = editor.screenplay.elements[1].text as NSString
        let word = text.range(of: "DAY", options: .backwards)
        let range = NSRange(location: mapped.range.location + word.location, length: word.length)
        surface.textView.setSelectedRange(range)
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: surface.textView)
        )
        ScriptSurfaceHarness.type("", into: surface, at: range)

        XCTAssertEqual(editor.screenplay.elements[1].text, "INT. KITCHEN - ")
        XCTAssertEqual(
            editor.selectionOffset, 15,
            "the model's caret must sit at the end for refreshPredictions to run"
        )

        // Lowercase, because that is the key the writer presses. It goes
        // through the input-boundary shouting and re-enters the delegate,
        // which is a different path from typing a capital.
        ScriptSurfaceHarness.type("d", into: surface)

        XCTAssertEqual(editor.screenplay.elements[1].text, "INT. KITCHEN - D")
        XCTAssertTrue(
            ScriptSurfaceHarness.wait { editor.currentSuggestionSuffix?.isEmpty == false },
            "the engine offered nothing after the time was deleted and retyped"
        )
        XCTAssertTrue(
            ScriptSurfaceHarness.waitForGhost(editor, surface),
            "the engine had a suggestion but the page never drew it"
        )
    }

    /// The same, but the writer deletes with the selection still standing and
    /// types straight over it — no separate delete keystroke at all.
    func testTypingStraightOverTheSelectedTimeStillPredicts() {
        let known = ScriptElement(type: .scene, text: "INT. HALLWAY - NIGHT")
        let blank = ScriptElement(type: .action, text: "")
        let (editor, surface) = ScriptSurfaceHarness.bound([known, blank], active: 1)
        ScriptSurfaceHarness.placeCaret(editor, surface, on: blank)
        for character in "int. kitchen - day" {
            ScriptSurfaceHarness.type(String(character), into: surface)
        }

        let mapped = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
            .first { $0.id == editor.screenplay.elements[1].id }!
        let text = editor.screenplay.elements[1].text as NSString
        let word = text.range(of: "DAY", options: .backwards)
        let range = NSRange(location: mapped.range.location + word.location, length: word.length)
        surface.textView.setSelectedRange(range)
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: surface.textView)
        )

        ScriptSurfaceHarness.type("n", into: surface, at: range)

        XCTAssertEqual(editor.screenplay.elements[1].text, "INT. KITCHEN - N")
        XCTAssertTrue(
            ScriptSurfaceHarness.wait { editor.currentSuggestionSuffix?.isEmpty == false },
            "typing over the selected time offered nothing"
        )
    }
}

/// The reported sequence, exactly: two scene headings, then rewrite the time
/// on the *first* one.
///
/// Every test above edits the last element in the document. This one edits an
/// element with a heading after it, which is a different path — the ranges of
/// everything below shift, and the caret is no longer at the end of the
/// storage even though it is at the end of its own element.
@MainActor
final class RewritingAnEarlierHeadingTests: XCTestCase {

    private func twoHeadings() -> (EditorState, ScriptSurface) {
        let blank = ScriptElement(type: .action, text: "")
        let (editor, surface) = ScriptSurfaceHarness.bound([blank], active: 0)
        ScriptSurfaceHarness.placeCaret(editor, surface, on: blank)

        for character in "int. kitchen - day" {
            ScriptSurfaceHarness.type(String(character), into: surface)
        }
        ScriptSurfaceHarness.type("\n", into: surface)
        for character in "int. hallway - night" {
            ScriptSurfaceHarness.type(String(character), into: surface)
        }
        return (editor, surface)
    }

    func testTheDocumentIsTwoHeadings() {
        let (editor, _) = twoHeadings()
        XCTAssertEqual(editor.screenplay.elements.map(\.text),
                       ["INT. KITCHEN - DAY", "INT. HALLWAY - NIGHT"])
        XCTAssertEqual(editor.screenplay.elements.map(\.type), [.scene, .scene])
    }

    func testRewritingTheFirstHeadingsTimeStillPredicts() {
        let (editor, surface) = twoHeadings()

        // Double-click DAY in the first heading, and delete it.
        let first = editor.screenplay.elements[0]
        let mapped = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
            .first { $0.id == first.id }!
        let word = (first.text as NSString).range(of: "DAY", options: .backwards)
        let range = NSRange(location: mapped.range.location + word.location, length: word.length)
        surface.textView.setSelectedRange(range)
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: surface.textView)
        )
        ScriptSurfaceHarness.type("", into: surface, at: range)

        XCTAssertEqual(editor.screenplay.elements[0].text, "INT. KITCHEN - ")
        XCTAssertEqual(
            editor.selectionOffset, 15,
            "the model's caret must sit at the end of the element it is in"
        )
        XCTAssertEqual(
            editor.activeElementID, first.id,
            "the caret is in the first heading, so that is the active element"
        )

        ScriptSurfaceHarness.type("d", into: surface)

        XCTAssertEqual(editor.screenplay.elements[0].text, "INT. KITCHEN - D")
        XCTAssertTrue(
            ScriptSurfaceHarness.wait { editor.currentSuggestionSuffix?.isEmpty == false },
            "the engine offered nothing when rewriting an earlier heading's time"
        )
        XCTAssertTrue(
            ScriptSurfaceHarness.waitForGhost(editor, surface),
            "the engine had a suggestion but the page never drew it"
        )
    }
}

/// The same sequence, with AppKit's real notification order.
///
/// `ScriptSurfaceHarness.type` posts `didChangeText` and then
/// `didChangeSelection`. AppKit moves the insertion point as part of the edit,
/// so the selection notification arrives *first* — and `updateSelection`
/// clamps its offset to `mapped.range.length`, read from `ranges`, which the
/// incremental path has not yet widened. One character short of the element's
/// end is exactly the condition `refreshPredictions` refuses to run on.
@MainActor
final class NotificationOrderTests: XCTestCase {

    /// Types the way AppKit does: selection first, then the text change.
    private func typeAsAppKitDoes(_ text: String, into surface: ScriptSurface) {
        let textView = surface.textView
        let range = textView.selectedRange()
        guard surface.textView(textView, shouldChangeTextIn: range, replacementString: text)
        else { return }
        textView.textStorage?.replaceCharacters(in: range, with: text)
        textView.setSelectedRange(
            NSRange(location: range.location + (text as NSString).length, length: 0)
        )
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
        )
        surface.textDidChange(
            Notification(name: NSText.didChangeNotification, object: textView)
        )
    }

    func testPredictionsSurviveAppKitsNotificationOrder() {
        let blank = ScriptElement(type: .action, text: "")
        let (editor, surface) = ScriptSurfaceHarness.bound([blank], active: 0)
        ScriptSurfaceHarness.placeCaret(editor, surface, on: blank)

        for character in "int. parking lot - evening" {
            typeAsAppKitDoes(String(character), into: surface)
        }
        typeAsAppKitDoes("\n", into: surface)
        for character in "int. kiosk - continuous" {
            typeAsAppKitDoes(String(character), into: surface)
        }
        XCTAssertEqual(editor.screenplay.elements.map(\.text),
                       ["INT. PARKING LOT - EVENING", "INT. KIOSK - CONTINUOUS"])

        // Double-click EVENING in the first heading and delete it.
        let first = editor.screenplay.elements[0]
        let mapped = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
            .first { $0.id == first.id }!
        let word = (first.text as NSString).range(of: "EVENING", options: .backwards)
        let range = NSRange(location: mapped.range.location + word.location, length: word.length)
        surface.textView.setSelectedRange(range)
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: surface.textView)
        )
        surface.textView.setSelectedRange(range)
        _ = surface.textView(surface.textView, shouldChangeTextIn: range, replacementString: "")
        surface.textView.textStorage?.replaceCharacters(in: range, with: "")
        surface.textView.setSelectedRange(NSRange(location: range.location, length: 0))
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: surface.textView)
        )
        surface.textDidChange(
            Notification(name: NSText.didChangeNotification, object: surface.textView)
        )

        XCTAssertEqual(editor.screenplay.elements[0].text, "INT. PARKING LOT - ")

        typeAsAppKitDoes("e", into: surface)

        XCTAssertEqual(editor.screenplay.elements[0].text, "INT. PARKING LOT - E")
        XCTAssertEqual(
            editor.selectionOffset, 20,
            "the selection notification arrived before the text change and clamped "
                + "the offset against ranges that had not been widened yet"
        )
        XCTAssertTrue(
            ScriptSurfaceHarness.wait { editor.currentSuggestionSuffix?.isEmpty == false },
            "the engine offered nothing — EVENING should complete E"
        )
    }
}
