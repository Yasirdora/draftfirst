import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// The question the whole Mac port waits on.
///
/// The iPhone's surface reads `NSLayoutManager` rectangles directly, and every
/// scroll and every reveal is built on that arithmetic. Before committing the
/// Mac to a text system, these measure whether each one can answer the only
/// question those features ask: *where is this element on the page?*
///
/// They run headless. No window is ever shown, which is the point — a demo
/// would prove it once, on one machine, to whoever was watching.
@MainActor
final class ScriptLayoutTests: XCTestCase {

    private let measure: CGFloat = 500

    /// Long enough that the last scene is far below the fold, so a text system
    /// that reports plausible-looking nonsense is caught by the distance.
    private func script() -> [ScriptElement] {
        var elements: [ScriptElement] = []
        for beat in 1...12 {
            elements.append(ScriptElement(type: .scene, text: "INT. ROOM \(beat) - DAY"))
            elements.append(ScriptElement(type: .action, text: "Action for beat \(beat). The road holds its breath."))
            elements.append(ScriptElement(type: .character, text: "TANGLE"))
            elements.append(ScriptElement(type: .dialogue, text: "Line \(beat), spoken plainly and without hurry at all."))
        }
        return elements
    }

    // MARK: - Both stacks can place an element

    func testTextKit1PlacesALateElementFarDownThePage() throws {
        try assertPlacesLateElement(using: .textKit1)
    }

    func testTextKit2PlacesALateElementFarDownThePage() throws {
        try assertPlacesLateElement(using: .textKit2)
    }

    private func assertPlacesLateElement(using stack: ScriptLayout.TextStack) throws {
        let elements = script()
        let (view, ranges) = ScriptLayout.textView(elements, measure: measure, using: stack)
        let last = try XCTUnwrap(ranges.last { element in
            elements.first { $0.id == element.id }?.type == .scene
        })

        let rect = try XCTUnwrap(
            ScriptLayout.boundingRect(of: last.range, in: view),
            "\(stack) could not say where the last scene is — the Navigator cannot be built on it"
        )
        XCTAssertGreaterThan(rect.minY, 600, "the last of twelve scenes should be far below the fold")
        XCTAssertGreaterThan(rect.height, 0)
    }

    // MARK: - The page keeps its shape

    /// Dialogue is indented and a scene heading is not: the fractions come from
    /// `ScriptTypography`, shared with the phone, and this is what proves the
    /// Mac actually applies them rather than merely importing them.
    func testDialogueIsIndentedAndAHeadingIsNot() throws {
        let elements = [
            ScriptElement(type: .scene, text: "INT. ROOM - DAY"),
            ScriptElement(type: .dialogue, text: "A line she says.")
        ]
        let (view, ranges) = ScriptLayout.textView(elements, measure: measure, using: .textKit1)

        let heading = try XCTUnwrap(ScriptLayout.boundingRect(of: ranges[0].range, in: view))
        let dialogue = try XCTUnwrap(ScriptLayout.boundingRect(of: ranges[1].range, in: view))

        let expected = measure * ScriptTypography.indents(for: .dialogue)!.head
        XCTAssertEqual(dialogue.minX, expected, accuracy: 1, "dialogue sits at the shared indent")
        XCTAssertLessThan(heading.minX, dialogue.minX, "a slug runs full measure")
    }

    func testACueSitsFurtherInThanItsDialogue() throws {
        let elements = [
            ScriptElement(type: .character, text: "TANGLE"),
            ScriptElement(type: .dialogue, text: "A line she says.")
        ]
        let (view, ranges) = ScriptLayout.textView(elements, measure: measure, using: .textKit1)
        let cue = try XCTUnwrap(ScriptLayout.boundingRect(of: ranges[0].range, in: view))
        let dialogue = try XCTUnwrap(ScriptLayout.boundingRect(of: ranges[1].range, in: view))
        XCTAssertGreaterThan(cue.minX, dialogue.minX)
    }

    // MARK: - Ranges mean the same characters as the model

    func testEveryElementOwnsItsOwnCharacters() {
        let elements = script()
        let (text, ranges) = ScriptLayout.attributedScript(elements, measure: measure)
        XCTAssertEqual(ranges.count, elements.count)
        for (element, mapped) in zip(elements, ranges) {
            XCTAssertEqual(mapped.id, element.id)
            XCTAssertEqual(
                (text.string as NSString).substring(with: mapped.range),
                element.text,
                "a range must name exactly the element's own text"
            )
        }
    }

    /// An element with nothing in it is still a place a reader can be sent —
    /// the blank line a writer is about to type into. The hard case is the one
    /// at the very end of a script, which has no line fragment of its own.
    func testAnEmptyElementStillHasALocation() throws {
        let elements = [
            ScriptElement(type: .scene, text: "INT. ROOM - DAY"),
            ScriptElement(type: .action, text: "")
        ]
        let (view, ranges) = ScriptLayout.textView(elements, measure: measure, using: .textKit1)
        XCTAssertEqual(ranges[1].range.length, 0)

        let rect = try XCTUnwrap(
            ScriptLayout.boundingRect(of: ranges[1].range, in: view),
            "the last line of a script must still be somewhere the reader can be sent"
        )
        XCTAssertGreaterThan(rect.width, 1, "a blank line is marked across the measure, not as a sliver")
        XCTAssertGreaterThan(rect.height, 0)
        let heading = try XCTUnwrap(ScriptLayout.boundingRect(of: ranges[0].range, in: view))
        XCTAssertGreaterThan(rect.minY, heading.minY, "the blank line sits below the slug")
    }

    /// The same case in the middle of a script, where the empty line does have
    /// a fragment to borrow.
    func testAnEmptyElementInTheBodyIsPlacedOnItsOwnLine() throws {
        let elements = [
            ScriptElement(type: .scene, text: "INT. ROOM - DAY"),
            ScriptElement(type: .action, text: ""),
            ScriptElement(type: .action, text: "She waits.")
        ]
        let (view, ranges) = ScriptLayout.textView(elements, measure: measure, using: .textKit1)
        let blank = try XCTUnwrap(ScriptLayout.boundingRect(of: ranges[1].range, in: view))
        let after = try XCTUnwrap(ScriptLayout.boundingRect(of: ranges[2].range, in: view))
        XCTAssertGreaterThan(blank.height, 0)
        XCTAssertLessThan(blank.minY, after.minY)
    }
}
