import EDraftEngine
import XCTest
import EDraftCore
@testable import EDraftMacSurface

/// A keystroke that moves no page boundary must not rebuild the gap bands.
///
/// The bands live in the text container, so tearing them down invalidates
/// the whole layout — twice, once clearing and once assigning — and a
/// feature-length draft paid two full-document layouts for every letter
/// typed. Measured on a 6,652-element paste: 170–460ms a keystroke, which
/// is the "super laggy, sometimes not responding" report. The fixpoint is
/// the geometry staying put; these two tests drive both sides of it.
@MainActor
final class BreaksFixpointTests: XCTestCase {

    /// A few pages of screenplay: scenes with action, an exchange each.
    private func script(scenes: Int = 16) -> [ScriptElement] {
        var elements: [ScriptElement] = []
        for beat in 1...scenes {
            elements.append(ScriptElement(type: .scene, text: "INT. ROOM \(beat) - DAY"))
            elements.append(ScriptElement(
                type: .action,
                text: "Action for beat \(beat). The road holds its breath for a full line of the page."
            ))
            elements.append(ScriptElement(type: .character, text: "MARA"))
            elements.append(ScriptElement(
                type: .dialogue,
                text: "Line \(beat), spoken plainly and without hurry at all."
            ))
        }
        return elements
    }

    func testAKeystrokeThatMovesNoBoundaryRebuildsNoBands() {
        let (editor, surface) = ScriptSurfaceHarness.bound(script())
        let placed = surface.breakRecomputeCount
        XCTAssertGreaterThan(placed, 0, "the first render placed the bands")

        // One letter at the end of an early action line: the text changes,
        // the geometry does not.
        ScriptSurfaceHarness.placeCaret(editor, surface, on: editor.screenplay.elements[1])
        ScriptSurfaceHarness.type("x", into: surface)

        XCTAssertEqual(
            surface.breakRecomputeCount, placed,
            "a layout-neutral keystroke tore the bands down and rebuilt them"
        )
    }

    func testAnEditThatMovesABoundaryRebuildsTheBands() {
        let (editor, surface) = ScriptSurfaceHarness.bound(script())
        let placed = surface.breakRecomputeCount

        // Return is a structural edit: a new element, new boundaries below.
        ScriptSurfaceHarness.placeCaret(editor, surface, on: editor.screenplay.elements[1])
        ScriptSurfaceHarness.type("\n", into: surface)

        XCTAssertGreaterThan(
            surface.breakRecomputeCount, placed,
            "a boundary-moving edit must rebuild — the fixpoint may not skip it"
        )
    }
}
