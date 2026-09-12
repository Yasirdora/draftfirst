import XCTest
import UIKit
import EDraftEngine
import EDraftCore
@testable import EDraftUIKitSurface

/// The phone draws the attention mark: one document is one document
/// (docs/RFC-HIGHLIGHTER.md), so the file's highlight shows on the
/// phone's page as it does on the Mac's and on paper.
@MainActor
final class HighlightRenderingTests: XCTestCase {

    private func surface(_ elements: [ScriptElement])
    -> (EditorState, ScreenplayTextView, ScriptTextView.Coordinator) {
        let editor = EditorState(source: "An opening image.")
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

    func testTheMarkDrawsAsAWashOnThePaper() {
        let element = ScriptElement(
            type: .action, text: "The marked word.",
            runs: [StyleRun(start: 4, end: 10, styles: [], highlight: .yellow)]
        )
        let (_, textView, _) = surface([element])

        let range = (textView.attributedText.string as NSString).range(of: "marked")
        XCTAssertGreaterThan(range.length, 0)
        let background = textView.attributedText.attribute(
            .backgroundColor, at: range.location, effectiveRange: nil
        )
        XCTAssertNotNil(background, "the phone shows no wash where the file carries the mark")

        let plain = (textView.attributedText.string as NSString).range(of: "word.")
        XCTAssertNil(
            textView.attributedText.attribute(.backgroundColor, at: plain.location, effectiveRange: nil),
            "the wash reached words it was never placed on"
        )
    }

    func testAWordWithoutHighlightDrawsNoWash() {
        let element = ScriptElement(type: .action, text: "The marked word.")
        let (_, textView, _) = surface([element])
        let range = (textView.attributedText.string as NSString).range(of: "marked")
        XCTAssertNil(
            textView.attributedText.attribute(.backgroundColor, at: range.location, effectiveRange: nil)
        )
    }
}
