import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// How large the page is actually drawn, as opposed to the arithmetic that
/// decides it — `PageZoomTests` in the core covers the numbers.
///
/// A screenplay's measurements are absolute and a screen point is not, so a
/// page at its own metrics comes out about half life size on a laptop. The
/// page follows the window by default; these check that it does, and that it
/// stops the moment the writer says otherwise.
@MainActor
final class PageZoomSurfaceTests: XCTestCase {

    private func widened(to width: CGFloat) -> (EditorState, ScriptSurface) {
        let (editor, surface) = ScriptSurfaceHarness.bound([
            ScriptElement(type: .scene, text: "INT. KITCHEN - DAY"),
            ScriptElement(type: .action, text: "She waits.")
        ])
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: width, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.remeasure(to: width, elements: editor.screenplay.elements)
        return (editor, surface)
    }

    func testAWideWindowDrawsThePageLarger() {
        let (editor, surface) = widened(to: 1470)

        XCTAssertEqual(surface.scrollView.magnification, PageZoom.maximum, accuracy: 0.01)
        XCTAssertEqual(editor.zoom, PageZoom.maximum, accuracy: 0.01,
                       "the model did not hear what the surface settled on")
    }

    /// Magnification is a lens, not a re-layout: the page keeps its own
    /// measurements, which is what makes it still a page.
    func testThePageKeepsItsMetricsWhateverTheMagnification() {
        let (_, surface) = widened(to: 1470)

        XCTAssertEqual(
            surface.pageFrame.width, PageFormat.letter.pageRect.width, accuracy: 0.5,
            "the page was resized rather than magnified"
        )
    }

    func testANarrowWindowLeavesThePageAtItsOwnSize() {
        let (_, surface) = widened(to: 500)

        XCTAssertEqual(surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01)
    }

    // MARK: - Once the writer chooses, the window stops choosing

    func testChoosingASizeStopsTheWindowOverridingIt() {
        let (editor, surface) = widened(to: 1470)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.maximum, accuracy: 0.01)

        surface.applyZoom(.actualSize)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01)

        // A resize must not undo it.
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1200, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.remeasure(to: 1200, elements: editor.screenplay.elements)

        XCTAssertEqual(
            surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01,
            "resizing the window overrode a size the writer had chosen"
        )
    }

    func testZoomToFitHandsTheWindowBackTheDecision() {
        let (editor, surface) = widened(to: 1470)
        surface.applyZoom(.actualSize)

        surface.applyZoom(.fit)

        XCTAssertEqual(surface.scrollView.magnification, PageZoom.maximum, accuracy: 0.01)

        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 500, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.remeasure(to: 500, elements: editor.screenplay.elements)

        XCTAssertEqual(
            surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01,
            "after Zoom to Fit the window should be following again"
        )
    }

    func testSteppingWalksFromWhereverTheFitLeftIt() {
        let (_, surface) = widened(to: 500)
        XCTAssertEqual(surface.scrollView.magnification, 1, accuracy: 0.01)

        surface.applyZoom(.zoomIn)
        XCTAssertEqual(surface.scrollView.magnification, 1.1, accuracy: 0.01)

        surface.applyZoom(.zoomOut)
        XCTAssertEqual(surface.scrollView.magnification, 1, accuracy: 0.01)
    }
}
