import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// The Mac page, driven without a window.
///
/// The phone learned every one of these lessons the hard way and in public;
/// they are written down here so the Mac never has to. Each test names the
/// behaviour rather than the mechanism, because the mechanism is allowed to
/// change and the behaviour is not.
@MainActor
final class ScriptSurfaceTests: XCTestCase {

    private func script(scenes: Int = 12) -> [ScriptElement] {
        var elements: [ScriptElement] = []
        for beat in 1...scenes {
            elements.append(ScriptElement(type: .scene, text: "INT. ROOM \(beat) - DAY"))
            elements.append(ScriptElement(type: .action, text: "Action for beat \(beat). The road holds its breath."))
            elements.append(ScriptElement(type: .character, text: "MARA"))
            elements.append(ScriptElement(type: .dialogue, text: "Line \(beat), spoken plainly and without hurry at all."))
        }
        return elements
    }

    /// A surface with a real viewport, laid out, as a window would leave it.
    private func surface(_ elements: [ScriptElement]) -> ScriptSurface {
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        // Deliberately no sizeToFit or layout pass here: bringing its own
        // geometry up to date is the surface's job, and a harness that does it
        // for the code hides exactly the bug the phone shipped.
        surface.render(elements)
        return surface
    }

    // MARK: - Going somewhere

    func testAJumpToALateSceneMovesThePage() throws {
        let elements = script()
        let surface = surface(elements)
        let last = try XCTUnwrap(elements.last { $0.type == .scene })
        let before = surface.scrollView.contentView.bounds.origin.y

        XCTAssertTrue(surface.reveal(last.id))

        XCTAssertGreaterThan(
            surface.scrollView.contentView.bounds.origin.y, before,
            "the page did not move towards the scene the row named"
        )
    }

    func testAJumpPutsTheCaretOnTheElement() throws {
        let elements = script()
        let surface = surface(elements)
        let target = try XCTUnwrap(elements.last { $0.type == .character })

        XCTAssertTrue(surface.reveal(target.id))

        let selected = surface.textView.selectedRange()
        XCTAssertEqual(surface.element(at: selected.location), target.id)
    }

    /// The reported bug, in its Mac form: a target the page cannot bring to the
    /// top must still be marked, or the row looks dead.
    func testAnElementThePageCannotReachIsStillMarked() throws {
        let elements = script(scenes: 2)
        let surface = surface(elements)
        let last = try XCTUnwrap(elements.last)

        XCTAssertTrue(surface.reveal(last.id))
        XCTAssertTrue(surface.isMarking, "a target the page cannot reach was left unmarked")
    }

    /// A script that fits in the window has nowhere to scroll. The reveal must
    /// still answer — with the mark, which is the whole reason it exists.
    func testAScriptThatFitsIsStillAnswered() throws {
        let elements = [
            ScriptElement(type: .scene, text: "INT. ROOM - DAY"),
            ScriptElement(type: .action, text: "She waits.")
        ]
        let surface = surface(elements)
        XCTAssertFalse(
            PageScroll.canScroll(surface.scrollableRange),
            "this script is meant to fit in the window"
        )
        XCTAssertTrue(surface.reveal(elements[1].id))
        XCTAssertTrue(surface.isMarking)
    }

    /// The blank line a writer is about to type into — the case that was
    /// silently broken on the phone until the Mac's measurements found it.
    func testABlankLineIsRevealable() throws {
        let elements = [
            ScriptElement(type: .scene, text: "INT. ROOM - DAY"),
            ScriptElement(type: .action, text: "")
        ]
        let surface = surface(elements)
        XCTAssertTrue(surface.reveal(elements[1].id), "a blank line is still a place")
        XCTAssertTrue(surface.isMarking)
    }

    func testAnElementTheScriptNoLongerHasIsRefusedRatherThanGuessed() {
        let surface = surface(script())
        XCTAssertFalse(surface.reveal(UUID()))
    }

    // MARK: - The page keeps its shape

    /// Asking the page which element a character belongs to has to give the
    /// same answer the model would — that mapping is what every reveal, every
    /// selection report and every conversion is built on.
    func testEveryElementOwnsItsOwnCharacters() {
        let elements = script(scenes: 3)
        let surface = surface(elements)
        var location = 0
        for element in elements {
            XCTAssertEqual(
                surface.element(at: location), element.id,
                "the character at \(location) should belong to “\(element.text)”"
            )
            location += (element.text as NSString).length + 1   // the joining newline
        }
    }

    /// A resized window is a re-measured script, because every indent is a
    /// fraction of the measure rather than a fixed inch.
    func testResizingRemeasuresTheScript() throws {
        let elements = [
            ScriptElement(type: .dialogue, text: "A line she says.")
        ]
        let surface = surface(elements)
        let narrow = try XCTUnwrap(
            ScriptLayout.boundingRect(of: NSRange(location: 0, length: 16), in: surface.textView)
        )

        surface.remeasure(to: 900, elements: elements)
        let wide = try XCTUnwrap(
            ScriptLayout.boundingRect(of: NSRange(location: 0, length: 16), in: surface.textView)
        )

        XCTAssertGreaterThan(
            wide.minX, narrow.minX,
            "dialogue's indent is a fraction of the measure, so a wider page indents further"
        )
    }

    /// The phone's bug, in its Mac form: a reveal that arrives in the same turn
    /// as a render must still move the page. A text view's height is a result
    /// of laying out, so measuring before the layout catches up says the page
    /// is one screen tall and cannot move — and the row does nothing.
    func testARevealInTheSameTurnAsARenderStillMovesThePage() throws {
        let elements = script()
        let surface = surface(elements)
        let last = try XCTUnwrap(elements.last { $0.type == .scene })
        let before = surface.scrollView.contentView.bounds.origin.y

        surface.render(elements)          // no layout pass in between
        XCTAssertTrue(surface.reveal(last.id))

        XCTAssertGreaterThan(
            surface.scrollView.contentView.bounds.origin.y, before,
            "a reveal in the same turn as a render measured a page that did not exist yet"
        )
    }
}
