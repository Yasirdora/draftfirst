import EDraftCore
import Foundation
import UIKit
import XCTest
@testable import EDraftUIKitSurface

/// Where the caret goes *during* a keystroke, not only where it lands.
///
/// A caret that ends in the right place can still have visibly travelled
/// somewhere else on the way — UIKit animates the insertion point between
/// positions, so a selection that is reset and restored inside one runloop turn
/// is still drawn as a trip. This records every value the surface assigns.
@MainActor
final class CaretTransitTests: XCTestCase {

    /// A mark on the first character. A full rebuild of the text storage
    /// throws every attribute away, so if this is gone afterwards the surface
    /// replaced the whole document to service one keystroke — and UITextView
    /// resets the insertion point to the start when that happens, which is the
    /// trip the writer sees.
    private static let sentinel = NSAttributedString.Key("qa.sentinel")

    private func mark(_ textView: ScreenplayTextView) {
        textView.textStorage.addAttribute(
            Self.sentinel, value: true, range: NSRange(location: 0, length: 1)
        )
    }

    private func sentinelSurvives(_ textView: ScreenplayTextView) -> Bool {
        textView.textStorage.attribute(
            Self.sentinel, at: 0, effectiveRange: nil
        ) as? Bool == true
    }

    private func surface(_ elements: [ScriptElement], active: Int)
    -> (EditorState, ScreenplayTextView, ScriptTextView.Coordinator) {
        let editor = EditorState(source: "An opening image.")
        for _ in 0..<4 { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        editor.screenplay = Screenplay(titlePage: [], elements: elements)
        editor.activeElementID = elements[active].id

        let textView = ScreenplayTextView(usingTextLayoutManager: false)
        textView.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        let coordinator = ScriptTextView.Coordinator(editor: editor)
        coordinator.attach(to: textView)
        coordinator.renderModel(selecting: elements[active].id, offset: 0)
        textView.layoutIfNeeded()
        return (editor, textView, coordinator)
    }

    /// A script whose last line is the empty one a writer is standing on.
    private func script() -> [ScriptElement] {
        [
            ScriptElement(type: .scene, text: "INT. WASHROOM - DAY"),
            ScriptElement(type: .action, text: "Tangle is obsessed with the treasure."),
            ScriptElement(type: .character, text: "IAN"),
            ScriptElement(type: .dialogue, text: "And what is the key for?"),
            ScriptElement(type: .action, text: "")
        ]
    }

    func testTheCaretDoesNotVisitTheTopWhenTheFirstCharacterIsTyped() {
        let elements = script()
        let (_, textView, coordinator) = surface(elements, active: 4)
        withExtendedLifetime(coordinator) {}
        let caret = textView.textStorage.length
        textView.selectedRange = NSRange(location: caret, length: 0)
        mark(textView)

        let range = NSRange(location: caret, length: 0)
        if coordinator.textView(textView, shouldChangeTextIn: range, replacementText: "H") {
            textView.textStorage.replaceCharacters(in: range, with: "H")
            textView.selectedRange = NSRange(location: caret + 1, length: 0)
            coordinator.textViewDidChange(textView)
        }

        XCTAssertTrue(
            sentinelSurvives(textView),
            "typing one character rebuilt the whole document, which resets the "
            + "insertion point to the start before it is put back — that is the "
            + "trip the writer sees"
        )
    }

    func testTheCaretDoesNotVisitTheTopOnBackspace() {
        var elements = script()
        elements[4] = ScriptElement(type: .action, text: "H")
        let (_, textView, coordinator) = surface(elements, active: 4)
        withExtendedLifetime(coordinator) {}
        let end = textView.textStorage.length
        textView.selectedRange = NSRange(location: end, length: 0)
        mark(textView)

        let range = NSRange(location: end - 1, length: 1)
        if coordinator.textView(textView, shouldChangeTextIn: range, replacementText: "") {
            textView.textStorage.replaceCharacters(in: range, with: "")
            textView.selectedRange = NSRange(location: end - 1, length: 0)
            coordinator.textViewDidChange(textView)
        }

        XCTAssertTrue(
            sentinelSurvives(textView),
            "backspace rebuilt the whole document, which resets the insertion "
            + "point to the start before it is put back"
        )
    }

    /// The kinds that wear caps are the suspicious ones: the model rewrites
    /// what was typed, so the surface has to put the corrected text back.
    private func typingFirstCharacterRebuildsDocument(into kind: ScreenplayKind) -> Bool {
        var elements = script()
        elements[4] = ScriptElement(type: kind, text: "")
        let (_, textView, coordinator) = surface(elements, active: 4)
        defer { withExtendedLifetime(coordinator) {} }
        let caret = textView.textStorage.length
        textView.selectedRange = NSRange(location: caret, length: 0)
        mark(textView)

        let range = NSRange(location: caret, length: 0)
        if coordinator.textView(textView, shouldChangeTextIn: range, replacementText: "h") {
            textView.textStorage.replaceCharacters(in: range, with: "h")
            textView.selectedRange = NSRange(location: caret + 1, length: 0)
            coordinator.textViewDidChange(textView)
        }
        return !sentinelSurvives(textView)
    }

    func testWhichKindsRebuildTheWholeDocumentOnTheFirstCharacter() {
        var rebuilt: [String] = []
        for kind in [ScreenplayKind.action, .character, .dialogue, .scene, .transition, .shot] {
            if typingFirstCharacterRebuildsDocument(into: kind) { rebuilt.append(kind.rawValue) }
        }
        XCTAssertTrue(
            rebuilt.isEmpty,
            "typing one character rebuilds the whole document for: \(rebuilt.joined(separator: ", "))"
        )
    }

    /// The mechanism, isolated: what does replacing the whole text storage do
    /// to the insertion point? Everything above depends on this answer.
    func testReplacingTheStorageMovesTheCaretToTheStart() {
        let (_, textView, coordinator) = surface(script(), active: 4)
        withExtendedLifetime(coordinator) {}
        let end = textView.textStorage.length
        textView.selectedRange = NSRange(location: end, length: 0)
        XCTAssertEqual(textView.selectedRange.location, end)

        let same = NSAttributedString(attributedString: textView.textStorage)
        textView.textStorage.setAttributedString(same)

        XCTAssertEqual(
            textView.selectedRange.location, end,
            "replacing the storage moved the insertion point to \(textView.selectedRange.location)"
        )
    }
}
