import Foundation
import UIKit
import XCTest
@testable import DraftFirst

/// Pressing Return must leave the caret on the line it made, wherever in the
/// script it is pressed. A plan that cannot be made, or that names an element
/// the plan does not contain, hands the text surface a selection it cannot
/// restore — and a text view with no selection to restore puts the caret at
/// the top of the document, or the end of it.
final class ReturnKeyStabilityTests: XCTestCase {

    /// The shape an imported script has and a fresh one does not: runs of
    /// empty paragraphs, forced scene numbers written as text, an omitted
    /// scene, a centred general line.
    private let imported = [
        "ACT ONE", "Meet Tangle", "", "", "", "", ". #1#", "", "",
        "YOUNG GIRL (pRE-LAP)", "And what is the key for?",
        ". #2#", "", "OMITTED", "EXT. ON THE GRAVEL ROAD - DUSK",
        "Tangle shivers.", "> Cut to:", "> The end <", ""
    ].joined(separator: "\n")

    @MainActor
    func testReturnAnywhereKeepsACaretTheSurfaceCanRestore() throws {
        let editor = EditorState(source: imported)
        let elements = editor.screenplay.elements
        XCTAssertGreaterThan(elements.count, 5, "the fixture must survive parsing")

        for range in ScreenplayEditPlanner.ranges(for: elements) {
            for caret in [range.range.location, NSMaxRange(range.range)] {
                let plan = ScreenplayEditPlanner.plan(
                    elements: elements,
                    replacing: NSRange(location: caret, length: 0),
                    with: "\n",
                    intent: .returnKey,
                    kindForNewElement: { previous, _ in
                        previous?.type == .character ? .dialogue : .action
                    }
                )
                let made = try XCTUnwrap(plan, "Return at \(caret) produced no plan")
                XCTAssertTrue(
                    made.elements.contains { $0.id == made.activeElementID },
                    "Return at \(caret) left the caret on an element the script does not contain"
                )
            }
        }
    }
}
