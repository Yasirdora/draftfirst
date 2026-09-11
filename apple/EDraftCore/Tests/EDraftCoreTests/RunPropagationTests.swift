import EDraftEngine
import Foundation
import XCTest
@testable import EDraftCore

/// Style runs travel with the text they mark (RFC v2.1 §4). The planner
/// rebuilds paragraphs on every structural edit; these pin what happens to
/// the runs when it does: split, merge, shrink, inherit — and the two ways
/// the style is honestly let go rather than pinned to the wrong words.
@MainActor
final class RunPropagationTests: XCTestCase {

    private func plan(
        _ elements: [ScriptElement],
        replacing range: NSRange,
        with replacement: String,
        intent: ScreenplayEditPlanner.Intent
    ) -> ScreenplayEditPlanner.Plan {
        let made = ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: range,
            with: replacement,
            intent: intent,
            kindForNewElement: { previous, _, _ in
                previous?.type == .character ? .dialogue : .action
            }
        )
        guard let made else {
            XCTFail("no plan for \(elements.map(\.text)) replacing \(range)")
            return ScreenplayEditPlanner.Plan(
                elements: elements, selection: NSRange(location: 0, length: 0),
                activeElementID: elements[0].id, activeOffset: 0
            )
        }
        return made
    }

    func testReturnSplitKeepsRunsOnBothSides() {
        let element = ScriptElement(
            type: .action, text: "ab cd ef",
            runs: [StyleRun(start: 0, end: 8, styles: .bold)]
        )
        // Caret at 5: head "ab cd", tail " ef".
        let made = plan(
            [element], replacing: NSRange(location: 5, length: 0),
            with: "\n", intent: .returnKey
        )
        XCTAssertEqual(made.elements.map(\.text), ["ab cd", " ef"])
        XCTAssertEqual(made.elements[0].runs, [StyleRun(start: 0, end: 5, styles: .bold)])
        XCTAssertEqual(made.elements[1].runs, [StyleRun(start: 0, end: 3, styles: .bold)])
    }

    func testBoundaryMergeShiftsTheIncomingRuns() {
        let left = ScriptElement(
            type: .action, text: "ab",
            runs: [StyleRun(start: 0, end: 2, styles: .bold)]
        )
        let right = ScriptElement(
            type: .action, text: "cd",
            runs: [StyleRun(start: 0, end: 2, styles: .italic)]
        )
        // Backspace over the separator: "ab\ncd" → "abcd".
        let made = plan(
            [left, right], replacing: NSRange(location: 2, length: 1),
            with: "", intent: .backspaceAtElementStart
        )
        XCTAssertEqual(made.elements.map(\.text), ["abcd"])
        XCTAssertEqual(made.elements[0].runs, [
            StyleRun(start: 0, end: 2, styles: .bold),
            StyleRun(start: 2, end: 4, styles: .italic)
        ])
    }

    func testDeletionShrinksTheCoveringRun() {
        let element = ScriptElement(
            type: .action, text: "hello world",
            runs: [StyleRun(start: 0, end: 11, styles: .bold)]
        )
        // Delete "o w" (4..<7): "hellorld".
        let made = plan(
            [element], replacing: NSRange(location: 4, length: 3),
            with: "", intent: .replacement
        )
        XCTAssertEqual(made.elements.map(\.text), ["hellorld"])
        XCTAssertEqual(made.elements[0].runs, [StyleRun(start: 0, end: 8, styles: .bold)])
    }

    func testInsertionAtTheEndOfARunExtendsIt() {
        // The platform's own donor rule: typed text inherits from the
        // character before the caret — so typing at the end of a bold word
        // keeps typing bold.
        let element = ScriptElement(
            type: .action, text: "ab",
            runs: [StyleRun(start: 0, end: 2, styles: .bold)]
        )
        let made = plan(
            [element], replacing: NSRange(location: 2, length: 0),
            with: "x", intent: .replacement
        )
        XCTAssertEqual(made.elements.map(\.text), ["abx"])
        XCTAssertEqual(made.elements[0].runs, [StyleRun(start: 0, end: 3, styles: .bold)])
    }

    func testInsertionAtContentPositionZeroInheritsForward() {
        // Nothing precedes the caret, so the donor is the character after
        // the insertion point — AppKit's rule at the start of the content.
        let element = ScriptElement(
            type: .action, text: "ab",
            runs: [StyleRun(start: 0, end: 2, styles: .bold)]
        )
        let made = plan(
            [element], replacing: NSRange(location: 0, length: 0),
            with: "x", intent: .replacement
        )
        XCTAssertEqual(made.elements.map(\.text), ["xab"])
        XCTAssertEqual(made.elements[0].runs, [StyleRun(start: 0, end: 3, styles: .bold)])
    }

    func testAnUntouchedElementKeepsItsRunsVerbatim() {
        let untouched = ScriptElement(
            type: .action, text: "keep",
            runs: [StyleRun(start: 1, end: 3, styles: .underline)]
        )
        let edited = ScriptElement(type: .action, text: "change me")
        let made = plan(
            [untouched, edited], replacing: NSRange(location: 14, length: 0),
            with: "d", intent: .replacement
        )
        XCTAssertEqual(made.elements.map(\.text), ["keep", "change med"])
        XCTAssertEqual(
            made.elements[0].runs, [StyleRun(start: 1, end: 3, styles: .underline)],
            "an element the edit did not touch keeps its runs exact"
        )
    }

    func testCasingThatKeepsItsLengthKeepsTheRuns() {
        // "john" → "JOHN!" — same length, so every offset stays honest, and
        // the donor rule extends the run over the typed character.
        let element = ScriptElement(
            type: .character, text: "john",
            runs: [StyleRun(start: 0, end: 4, styles: .bold)]
        )
        let made = plan(
            [element], replacing: NSRange(location: 4, length: 0),
            with: "!", intent: .replacement
        )
        XCTAssertEqual(made.elements.map(\.text), ["JOHN!"])
        XCTAssertEqual(made.elements[0].runs, [StyleRun(start: 0, end: 5, styles: .bold)])
    }

    func testCasingThatGrowsLetsTheStyleGo() {
        // "straße" uppercases to "STRASSE" — one character longer, so no
        // offset in the old text means anything in the new. The style is let
        // go rather than pinned to the wrong letters.
        let element = ScriptElement(
            type: .character, text: "straße",
            runs: [StyleRun(start: 0, end: 6, styles: .bold)]
        )
        let made = plan(
            [element], replacing: NSRange(location: 6, length: 0),
            with: "x", intent: .replacement
        )
        XCTAssertEqual(made.elements.map(\.text), ["STRASSEX"])
        XCTAssertNil(made.elements[0].runs)
    }
}
