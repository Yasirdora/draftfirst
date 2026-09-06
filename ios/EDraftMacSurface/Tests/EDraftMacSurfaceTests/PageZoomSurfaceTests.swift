import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// How large the page is drawn. The arithmetic is `PageZoomTests` in the core;
/// this is the behaviour a writer meets.
///
/// A document opens at `PageZoom.opening` — a notch above its own metrics,
/// where word processors have settled, because 612 points drawn as 612 is
/// under half life size on a laptop. The percentage button in the corner of
/// the canvas toggles to the truth and back, and pressing it twice must give
/// back the size the writer was working at.
@MainActor
final class PageZoomSurfaceTests: XCTestCase {

    private func windowed(_ width: CGFloat) -> (EditorState, ScriptSurface) {
        let (editor, surface) = ScriptSurfaceHarness.bound([
            ScriptElement(type: .scene, text: "INT. KITCHEN - DAY"),
            ScriptElement(type: .action, text: "She waits.")
        ])
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: width, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.remeasure(to: width, elements: editor.screenplay.elements)
        return (editor, surface)
    }

    // MARK: - What a document opens at

    func testADocumentOpensAtTheOpeningSize() {
        let (editor, surface) = windowed(1470)

        XCTAssertEqual(
            surface.scrollView.magnification, PageZoom.opening, accuracy: 0.01,
            "a wide window must not decide the writer's size for them, and "
                + "neither should the page's own metrics"
        )
        XCTAssertEqual(editor.zoom, PageZoom.opening, accuracy: 0.01)
    }

    /// The opening size is a starting point, not a fit: a narrow window gets
    /// the same 125% and scrolls, rather than shrinking to suit itself.
    func testANarrowWindowStillOpensAtTheOpeningSize() {
        let (_, surface) = windowed(500)

        XCTAssertEqual(surface.scrollView.magnification, PageZoom.opening, accuracy: 0.01)
    }

    /// Magnification is a lens, not a re-layout: the page keeps its own
    /// measurements, which is what keeps it a page.
    func testThePageKeepsItsMetricsWhateverTheMagnification() {
        let (_, surface) = windowed(1470)
        surface.applyZoom(.fit)

        XCTAssertEqual(
            surface.pageFrame.width, PageFormat.letter.pageRect.width, accuracy: 0.5,
            "the page was resized rather than magnified"
        )
    }

    // MARK: - The percentage button

    func testTheButtonShowsActualSizeAndGivesTheOpeningSizeBack() {
        let (_, surface) = windowed(1470)

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01,
                       "the first press should show the page at its true size")

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.opening, accuracy: 0.01,
                       "the second press should give back the size being worked at")
    }

    /// "If a user already selected a zoom, it will be that zoom percentage and
    /// then 100%."
    func testTheButtonRemembersASizeTheWriterChose() {
        let (_, surface) = windowed(1470)
        surface.applyZoom(.zoomIn)
        let chosen = surface.scrollView.magnification
        XCTAssertEqual(chosen, 1.75, accuracy: 0.01, "one step up from the opening 1.5")

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01)

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(
            surface.scrollView.magnification, chosen, accuracy: 0.01,
            "the writer's own size was lost behind the percentage button"
        )
    }

    /// ⌘0 and the button are the same gesture reached two ways, so the button
    /// must still know where to go back to afterwards.
    func testActualSizeFromTheMenuLeavesTheWayBackIntact() {
        let (_, surface) = windowed(1470)
        surface.applyZoom(.zoomIn)
        let chosen = surface.scrollView.magnification

        surface.applyZoom(.actualSize)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01)

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(surface.scrollView.magnification, chosen, accuracy: 0.01)
    }

    // MARK: - Fitting

    func testFittingFillsAWideWindowUpToTheCap() {
        let (_, surface) = windowed(1470)
        surface.applyZoom(.fit)

        XCTAssertEqual(surface.scrollView.magnification, PageZoom.maximum, accuracy: 0.01)
    }

    func testFittingANarrowWindowLeavesThePageAtItsOwnSize() {
        let (_, surface) = windowed(500)
        surface.applyZoom(.fit)

        XCTAssertEqual(surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01,
                       "a page smaller than its own metrics helps nobody")
    }

    func testAResizeFollowsTheWindowOnlyWhileFitting() {
        let (editor, surface) = windowed(1470)
        surface.applyZoom(.fit)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.maximum, accuracy: 0.01)

        // These widths are the canvas, not the window: the harness has no
        // Navigator beside it. 600 points is less than a page and its margins,
        // so the fit bottoms out at actual size.
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 600, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.remeasure(to: 600, elements: editor.screenplay.elements)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01,
                       "while fitting, a narrower window means a smaller fit")

        surface.applyZoom(.zoomIn)
        let chosen = surface.scrollView.magnification
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1470, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.remeasure(to: 1470, elements: editor.screenplay.elements)
        XCTAssertEqual(
            surface.scrollView.magnification, chosen, accuracy: 0.01,
            "resizing the window overrode a size the writer had chosen"
        )
    }

    // MARK: - Typing must not cost the writer their size

    /// Reported as "when I type then the page become 100%".
    func testTypingDoesNotDropTheZoom() {
        let (editor, surface) = windowed(1470)
        surface.applyZoom(.fit)
        let before = surface.scrollView.magnification

        ScriptSurfaceHarness.placeCaret(editor, surface, on: editor.screenplay.elements[1])
        ScriptSurfaceHarness.type("X", into: surface)

        XCTAssertEqual(
            surface.scrollView.magnification, before, accuracy: 0.01,
            "the page snapped back to its own metrics on a keystroke"
        )
    }

    func testARerenderDoesNotDropTheZoom() {
        let (editor, surface) = windowed(1470)
        surface.applyZoom(.fit)
        let before = surface.scrollView.magnification

        surface.renderIfNeeded(editor)
        surface.remeasure(to: 1470, elements: editor.screenplay.elements)

        XCTAssertEqual(surface.scrollView.magnification, before, accuracy: 0.01)
    }
}

/// A trackpad pinch is a way of choosing a size, and everything has to hear it.
///
/// `NSScrollView` handles the gesture itself and changes its own magnification.
/// Nothing was watching, so the control in the corner went on reading the last
/// number the app had set — the page said one thing and the readout another —
/// and because the *preference* had not heard either, the next window resize
/// took the writer's size away again.
@MainActor
final class PinchToZoomTests: XCTestCase {

    private func windowed(_ width: CGFloat) -> (EditorState, ScriptSurface) {
        let (editor, surface) = ScriptSurfaceHarness.bound([
            ScriptElement(type: .scene, text: "INT. KITCHEN - DAY")
        ])
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: width, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.remeasure(to: width, elements: editor.screenplay.elements)
        return (editor, surface)
    }

    /// What the gesture does: it sets the scroll view's magnification directly.
    private func pinch(_ surface: ScriptSurface, to value: CGFloat) {
        surface.scrollView.magnification = value
    }

    func testTheReadoutFollowsAPinch() {
        let (editor, surface) = windowed(1200)
        XCTAssertEqual(editor.zoom, PageZoom.opening, accuracy: 0.01)

        pinch(surface, to: 1.75)

        XCTAssertEqual(
            editor.zoom, 1.75, accuracy: 0.01,
            "the page was magnified but the control still reads the old number"
        )
    }

    /// And the size the writer pinched to is theirs to keep.
    func testAPinchedSizeSurvivesAResize() {
        let (editor, surface) = windowed(1200)
        pinch(surface, to: 1.75)

        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.remeasure(to: 700, elements: editor.screenplay.elements)

        XCTAssertEqual(
            surface.scrollView.magnification, 1.75, accuracy: 0.01,
            "resizing the window undid a size the writer pinched to"
        )
    }

    /// The percentage button still knows where to go back to afterwards.
    func testTheButtonReturnsToAPinchedSize() {
        let (_, surface) = windowed(1200)
        pinch(surface, to: 1.6)

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01)

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(surface.scrollView.magnification, 1.6, accuracy: 0.01)
    }
}

extension PinchToZoomTests {

    /// Zooming out with the trackpad left the page against the left edge.
    ///
    /// The canvas is measured in document coordinates, so a pinch changes how
    /// wide it is: zooming out widens the viewport and the card must be
    /// re-centred in it. The menu and the corner buttons lay out after they
    /// change the size; the gesture went straight to the scroll view and did
    /// not, so the card kept its old x.
    func testZoomingOutWithAPinchLeavesThePageCentred() {
        let (editor, surface) = windowed(1200)
        surface.applyZoom(.zoomIn)

        surface.scrollView.magnification = PageZoom.actualSize
        // The re-measure happens on the next turn of the run loop, because the
        // clip view's bounds are not the new magnification's until AppKit's own
        // change unwinds.
        _ = ScriptSurfaceHarness.wait {
            abs(surface.pageFrame.midX - surface.scrollView.contentView.bounds.midX) < 2
        }

        // Against the *viewport's* centre, not the canvas's: the card is always
        // centred in the canvas, and the bug is that the canvas itself goes
        // stale — narrower than the widened viewport, so it is pinned left and
        // takes the page with it.
        let viewportCentre = surface.scrollView.contentView.bounds.midX
        XCTAssertEqual(
            surface.pageFrame.midX, viewportCentre, accuracy: 2,
            "the page sat at \(surface.pageFrame.midX) in a viewport centred on "
                + "\(viewportCentre) — the canvas was never re-measured after the pinch"
        )
        withExtendedLifetime(editor) {}
    }
}
