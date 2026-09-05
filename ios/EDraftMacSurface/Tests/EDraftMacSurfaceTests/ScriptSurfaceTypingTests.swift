import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// Typing on the Mac page, driven without a window.
///
/// The phone learned these lessons in public; they are written down here so
/// the Mac never has to. Each test names the behaviour rather than the
/// mechanism. The caret is placed by setting the selection directly — never
/// via `reveal`, which also jumps the model and would let Tab / ⌘1–9 pass
/// even if selection-to-model sync were missing.
@MainActor
final class ScriptSurfaceTypingTests: XCTestCase {

    /// A mark on the first character. Replacing the whole storage throws
    /// every attribute away, so if this is gone afterwards the surface
    /// rebuilt the document to service one keystroke — and NSTextView
    /// resets the insertion point to the start when that happens, which is
    /// the trip the writer sees.
    private static let sentinel = NSAttributedString.Key("qa.sentinel")

    private func mark(_ textView: NSTextView) {
        textView.textStorage?.addAttribute(
            Self.sentinel, value: true, range: NSRange(location: 0, length: 1)
        )
    }

    private func sentinelSurvives(_ textView: NSTextView) -> Bool {
        textView.textStorage?.attribute(
            Self.sentinel, at: 0, effectiveRange: nil
        ) as? Bool == true
    }

    private func bound(
        _ elements: [ScriptElement], active: Int = 0
    ) -> (EditorState, ScriptSurface) {
        let editor = EditorState(source: "An opening image.")
        editor.screenplay = Screenplay(titlePage: [], elements: elements)
        editor.activeElementID = elements[active].id
        editor.selectionOffset = 0

        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        return (editor, surface)
    }

    /// Types the way a keyboard does: the delegate first, then the storage
    /// only when that returns true, then the change the surface listens to.
    @discardableResult
    private func type(
        _ replacement: String,
        into surface: ScriptSurface,
        at range: NSRange? = nil
    ) -> Bool {
        let textView = surface.textView
        let range = range ?? textView.selectedRange()
        let allowed = surface.textView(
            textView, shouldChangeTextIn: range, replacementString: replacement
        )
        if allowed {
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.setSelectedRange(
                NSRange(
                    location: range.location + (replacement as NSString).length,
                    length: 0
                )
            )
            surface.textDidChange(
                Notification(name: NSText.didChangeNotification, object: textView)
            )
            surface.textViewDidChangeSelection(
                Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
            )
        }
        return allowed
    }

    /// Puts the caret in an element by setting the selection, then telling
    /// the surface — the same two calls a click in the page produces. Does
    /// not go through `reveal`, so a test of Tab or a kind change cannot
    /// accidentally inherit the model's jump.
    private func placeCaret(
        _ editor: EditorState,
        _ surface: ScriptSurface,
        on element: ScriptElement,
        atEnd: Bool = true
    ) {
        let mapped = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
            .first { $0.id == element.id }
        let location: Int
        if let mapped {
            location = atEnd ? NSMaxRange(mapped.range) : mapped.range.location
        } else {
            location = 0
        }
        surface.textView.setSelectedRange(NSRange(location: location, length: 0))
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: surface.textView)
        )
    }

    // MARK: - The caret does not visit the top

    func testTheCaretDoesNotVisitTheTopWhenTheFirstCharacterIsTyped() {
        let elements = [
            ScriptElement(type: .scene, text: "INT. ROOM - DAY"),
            ScriptElement(type: .action, text: "")
        ]
        let (editor, surface) = bound(elements, active: 1)
        placeCaret(editor, surface, on: elements[1])
        mark(surface.textView)

        XCTAssertTrue(type("H", into: surface))

        XCTAssertTrue(
            sentinelSurvives(surface.textView),
            "typing one character rebuilt the whole document, which resets the "
                + "insertion point to the start before it is put back — that is the "
                + "trip the writer sees"
        )
        XCTAssertEqual(editor.screenplay.elements[1].text, "H")
    }

    func testTheCaretDoesNotVisitTheTopOnBackspace() {
        let action = ScriptElement(type: .action, text: "H")
        let elements = [
            ScriptElement(type: .scene, text: "INT. ROOM - DAY"),
            action
        ]
        let (editor, surface) = bound(elements, active: 1)
        placeCaret(editor, surface, on: action)
        mark(surface.textView)

        let end = (surface.textView.string as NSString).length
        XCTAssertTrue(type("", into: surface, at: NSRange(location: end - 1, length: 1)))

        XCTAssertTrue(
            sentinelSurvives(surface.textView),
            "backspace rebuilt the whole document, which resets the insertion "
                + "point to the start before it is put back"
        )
        XCTAssertEqual(editor.screenplay.elements[1].text, "")
    }

    /// A SwiftUI pass after a keystroke — the subtitle reading `stats` is
    /// the usual one — must not replace the storage. `renderIfNeeded` is
    /// exactly what `updateNSView` calls.
    func testASwiftUIRefreshAfterTypingDoesNotRebuildThePage() {
        let elements = [
            ScriptElement(type: .scene, text: "INT. ROOM - DAY"),
            ScriptElement(type: .action, text: "")
        ]
        let (editor, surface) = bound(elements, active: 1)
        placeCaret(editor, surface, on: elements[1])
        mark(surface.textView)

        XCTAssertTrue(type("H", into: surface))
        surface.renderIfNeeded(editor)

        XCTAssertTrue(
            sentinelSurvives(surface.textView),
            "a SwiftUI refresh after a keystroke rebuilt the page"
        )
        XCTAssertNotEqual(
            surface.textView.selectedRange().location, 0,
            "the caret visited the top of the document after the refresh"
        )
    }

    // MARK: - Return

    func testReturnOnAnEmptyCueEscapesToAction() {
        let cue = ScriptElement(type: .character, text: "")
        let (editor, surface) = bound([cue])
        placeCaret(editor, surface, on: cue)

        XCTAssertFalse(type("\n", into: surface), "Return on an empty cue is not a native insert")
        XCTAssertEqual(editor.screenplay.elements.count, 1)
        XCTAssertEqual(editor.screenplay.elements[0].id, cue.id)
        XCTAssertEqual(editor.screenplay.elements[0].type, .action)
        XCTAssertEqual(editor.screenplay.elements[0].text, "")
    }

    func testReturnInsideActionInsertsANewActionBelow() {
        let action = ScriptElement(type: .action, text: "She waits.")
        let (editor, surface) = bound([action])
        placeCaret(editor, surface, on: action)

        XCTAssertFalse(type("\n", into: surface))
        XCTAssertEqual(editor.screenplay.elements.count, 2)
        XCTAssertEqual(editor.screenplay.elements[0].id, action.id)
        XCTAssertEqual(editor.screenplay.elements[0].text, "She waits.")
        XCTAssertEqual(editor.screenplay.elements[1].type, .action)
        XCTAssertEqual(editor.screenplay.elements[1].text, "")
        XCTAssertEqual(editor.activeElementID, editor.screenplay.elements[1].id)
    }

    // MARK: - Scene promotion and casing

    func testTypingASlugTurnsAnActionLineIntoASceneHeading() {
        let action = ScriptElement(type: .action, text: "")
        let (editor, surface) = bound([action])
        placeCaret(editor, surface, on: action)

        XCTAssertTrue(type("INT. KITCHEN", into: surface))

        XCTAssertEqual(
            editor.screenplay.elements[0].type, .scene,
            "Fountain calls this line a scene heading; the editor must agree as it is typed"
        )
    }

    func testThePromotedLineIsShouted() {
        let action = ScriptElement(type: .action, text: "")
        let (editor, surface) = bound([action])
        placeCaret(editor, surface, on: action)

        XCTAssertTrue(type("int. kitchen", into: surface))

        XCTAssertEqual(editor.screenplay.elements[0].type, .scene)
        XCTAssertEqual(editor.screenplay.elements[0].text, "INT. KITCHEN")
    }

    func testAnOrdinaryActionLineIsLeftAlone() {
        let action = ScriptElement(type: .action, text: "")
        let (editor, surface) = bound([action])
        placeCaret(editor, surface, on: action)

        XCTAssertTrue(type("INTO the room she goes.", into: surface))

        XCTAssertEqual(editor.screenplay.elements[0].type, .action)
        XCTAssertEqual(editor.screenplay.elements[0].text, "INTO the room she goes.")
    }

    func testACueIsNotPromotedHoweverItReads() {
        let cue = ScriptElement(type: .character, text: "")
        let (editor, surface) = bound([cue])
        placeCaret(editor, surface, on: cue)

        _ = type("INT. KITCHEN", into: surface)

        XCTAssertEqual(editor.screenplay.elements[0].type, .character)
    }

    func testACueOnThePageMatchesTheCueInTheDocument() {
        let cue = ScriptElement(type: .character, text: "")
        let (editor, surface) = bound([cue])
        placeCaret(editor, surface, on: cue)

        for character in "uncle" {
            XCTAssertTrue(type(String(character), into: surface))
        }

        XCTAssertEqual(editor.screenplay.elements[0].text, "UNCLE", "the document")
        XCTAssertEqual(
            surface.textView.string, "UNCLE",
            "the page shows something the document does not say — a writer reads "
                + "one thing and the file holds another"
        )
    }

    // MARK: - Scene heading dash

    func testADashInAHeadingWritesTheSpacedSeparator() {
        let heading = ScriptElement(type: .scene, text: "INT. BASEMENT")
        let (editor, surface) = bound([heading])
        placeCaret(editor, surface, on: heading)

        XCTAssertFalse(type("-", into: surface))
        XCTAssertEqual(editor.screenplay.elements[0].text, "INT. BASEMENT - ")
    }

    func testDeleteAgainstAJustWrittenSeparatorCollapsesToAHyphen() {
        let heading = ScriptElement(type: .scene, text: "INT. DRIVE")
        let (editor, surface) = bound([heading])
        placeCaret(editor, surface, on: heading)

        XCTAssertFalse(type("-", into: surface))
        XCTAssertEqual(editor.screenplay.elements[0].text, "INT. DRIVE - ")

        let caret = surface.textView.selectedRange().location
        XCTAssertFalse(type("", into: surface, at: NSRange(location: caret - 1, length: 1)))
        XCTAssertEqual(editor.screenplay.elements[0].text, "INT. DRIVE-")
    }

    // MARK: - Tab and kind change act on the caret's element

    func testTabCyclesTheElementTheCaretIsInNotTheOneLastJumpedTo() {
        let scene = ScriptElement(type: .scene, text: "INT. ROOM - DAY")
        let action = ScriptElement(type: .action, text: "She waits.")
        let (editor, surface) = bound([scene, action], active: 0)
        XCTAssertEqual(editor.activeElementID, scene.id, "the fixture starts on the scene")

        placeCaret(editor, surface, on: action, atEnd: false)
        XCTAssertEqual(
            editor.activeElementID, action.id,
            "placing the caret must tell the model — Tab reads activeElementID"
        )

        XCTAssertTrue(
            surface.textView(surface.textView, doCommandBy: #selector(NSResponder.insertTab(_:)))
        )

        XCTAssertEqual(editor.screenplay.elements[0].type, .scene, "the scene must not have moved")
        XCTAssertEqual(
            editor.screenplay.elements[1].type, .character,
            "Tab after a scene heading cycles action toward a cue"
        )
        XCTAssertFalse(
            surface.textView.string.contains("\t"),
            "Tab must not insert a tab character into the screenplay"
        )
    }

    func testChangingKindRestylesTheParagraphTheCaretIsIn() throws {
        let scene = ScriptElement(type: .scene, text: "INT. ROOM - DAY")
        let cue = ScriptElement(type: .character, text: "MARA")
        let (editor, surface) = bound([scene, cue], active: 0)
        placeCaret(editor, surface, on: cue, atEnd: false)

        let before = try XCTUnwrap(
            ScriptLayout.boundingRect(
                of: NSRange(location: (scene.text as NSString).length + 1, length: 4),
                in: surface.textView
            )
        )

        editor.onChangeElementKind?(.dialogue)

        let after = try XCTUnwrap(
            ScriptLayout.boundingRect(
                of: NSRange(location: (scene.text as NSString).length + 1, length: 4),
                in: surface.textView
            )
        )
        XCTAssertEqual(editor.screenplay.elements[0].type, .scene)
        XCTAssertEqual(editor.screenplay.elements[1].type, .dialogue)
        XCTAssertLessThan(
            after.minX, before.minX,
            "dialogue sits closer to the left edge than a cue; the page must "
                + "show the conversion, not only the model"
        )
    }

    /// `isRichText = false` is why this is here: assigning `typingAttributes`
    /// on a plain-text view can restyle the whole document. A letter typed
    /// into action must not steal the indent off the cue above it.
    func testTypingDoesNotRestyleADifferentElement() throws {
        let cue = ScriptElement(type: .character, text: "MARA")
        let action = ScriptElement(type: .action, text: "")
        let (editor, surface) = bound([cue, action], active: 1)
        let cueRange = NSRange(location: 0, length: 4)
        let indentBefore = try XCTUnwrap(
            ScriptLayout.boundingRect(of: cueRange, in: surface.textView)
        ).minX

        placeCaret(editor, surface, on: action)
        XCTAssertTrue(type("H", into: surface))

        let indentAfter = try XCTUnwrap(
            ScriptLayout.boundingRect(of: cueRange, in: surface.textView)
        ).minX
        XCTAssertEqual(
            indentAfter, indentBefore, accuracy: 0.5,
            "typing into action restyled the cue — isRichText/typingAttributes "
                + "leaked across elements"
        )
    }
}
