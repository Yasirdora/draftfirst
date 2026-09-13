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
        let (editor, surface) = windowed(1470)

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01,
                       "the first press should show the page at its true size")
        XCTAssertTrue(editor.holdingActualSize)
        XCTAssertFalse(
            PageZoom.percentageShowsMenu(at: editor.zoom, holdingActualSize: editor.holdingActualSize),
            "landing on 100% turned the toggle into a menu, so the way back was lost"
        )

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.opening, accuracy: 0.01,
                       "the second press should give back the size being worked at")
        XCTAssertFalse(editor.holdingActualSize)
    }

    /// At 110% or below the percentage is a menu, not a trip to 100%. Going
    /// to 100% first and *then* offering the list is how a press at 110%
    /// used to behave, and it is the wrong one.
    func testAtOneHundredAndTenThePercentageOffersTheMenuRatherThanToggling() {
        let (editor, surface) = windowed(1470)
        surface.applyChosenSize(1.1)
        XCTAssertEqual(surface.scrollView.magnification, 1.1, accuracy: 0.01)

        XCTAssertFalse(editor.holdingActualSize)
        XCTAssertTrue(
            PageZoom.percentageShowsMenu(at: editor.zoom, holdingActualSize: editor.holdingActualSize),
            "at 110% the control should offer the sizes, not step to 100% first"
        )
    }

    /// "If a user already selected a zoom, it will be that zoom percentage and
    /// then 100%."
    func testTheButtonRemembersASizeTheWriterChose() {
        let (editor, surface) = windowed(1470)
        surface.applyZoom(.zoomIn)
        let chosen = surface.scrollView.magnification
        XCTAssertEqual(chosen, 1.5, accuracy: 0.01, "one step up from the opening 1.25")

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01)
        XCTAssertTrue(editor.holdingActualSize)
        XCTAssertFalse(
            PageZoom.percentageShowsMenu(at: editor.zoom, holdingActualSize: editor.holdingActualSize),
            "a toggle from 150% became a menu at 100% instead of waiting to restore"
        )

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(
            surface.scrollView.magnification, chosen, accuracy: 0.01,
            "the writer's own size was lost behind the percentage button"
        )
        XCTAssertFalse(editor.holdingActualSize)
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

    // MARK: - The window a document opens in

    /// Two widths, one for each state of the desk: 1,026 points hugs the
    /// page at the opening size, 1,130 holds the thread beside the page at
    /// actual size — where a lent page settles, a fit never going below.
    /// The window moves between the two as the column comes and goes, which
    /// is what lets the margins stay a breath in both states; one fixed
    /// width would pad one state or clip the other.
    func testTheWindowWidthsAreDerivedFromThePageAndTheThread() {
        let pageAndDesk = PageFormat.letter.pageRect.width + 2 * PageCanvasView.deskPadding
        XCTAssertEqual(pageAndDesk, 628, accuracy: 0.01,
                       "the arithmetic the window is measured against changed")

        XCTAssertEqual(
            ScriptWindowController.openingWidth, 240 + 1 + pageAndDesk * 1.25, accuracy: 0.5,
            "the window no longer opens hugging the page at the opening size, "
                + "beside the 240-point Navigator"
        )
        XCTAssertEqual(
            ScriptWindowController.threadOpenWidth, 240 + 1 + 260 + 1 + pageAndDesk, accuracy: 0.5,
            "a thread-open window no longer holds exactly the thread beside "
                + "the page at actual size"
        )
    }

    /// Growing keeps the page's left edge still and never reaches past the
    /// screen; a window already wide enough is left alone, and one the
    /// writer resized after the grow is not narrowed out from under them.
    func testTheWindowGrowsForTheThreadAndGivesTheRoomBack() {
        let screen = NSRect(x: 0, y: 0, width: 1600, height: 1000)
        let closed = NSRect(x: 100, y: 100, width: ScriptWindowController.openingWidth, height: 860)

        guard let grow = ScriptWindowController.frameForThread(
            open: true, current: closed, screen: screen, grownFrom: nil
        ) else { return XCTFail("a window too narrow for the thread did not grow") }
        XCTAssertEqual(grow.frame.width, ScriptWindowController.threadOpenWidth, accuracy: 0.5)
        XCTAssertEqual(grow.frame.minX, closed.minX, accuracy: 0.5,
                       "growing moved the page's left edge")

        // The close gives back exactly the room the grow took.
        guard let shrink = ScriptWindowController.frameForThread(
            open: false, current: grow.frame, screen: screen, grownFrom: grow.grownFrom
        ) else { return XCTFail("a grown window did not give the room back") }
        XCTAssertEqual(shrink.frame.width, closed.width, accuracy: 0.5)
        XCTAssertNil(shrink.grownFrom)

        // A window already wide enough is left alone.
        let wide = NSRect(x: 100, y: 100,
                          width: ScriptWindowController.threadOpenWidth + 200, height: 860)
        XCTAssertNil(ScriptWindowController.frameForThread(
            open: true, current: wide, screen: screen, grownFrom: nil
        ))

        // A window the writer resized after the grow keeps their size.
        var resized = grow.frame
        resized.size.width += 40
        XCTAssertNil(ScriptWindowController.frameForThread(
            open: false, current: resized, screen: screen, grownFrom: grow.grownFrom
        ))

        // Growth never reaches past the screen's visible edge.
        let nearEdge = NSRect(x: 1550, y: 100, width: 400, height: 860)
        guard let clamped = ScriptWindowController.frameForThread(
            open: true, current: nearEdge, screen: screen, grownFrom: nil
        ) else { return XCTFail("a narrow window at the screen's edge did not grow") }
        XCTAssertLessThanOrEqual(clamped.frame.maxX, screen.maxX + 0.5)
        XCTAssertGreaterThanOrEqual(clamped.frame.minX, screen.minX - 0.5)
    }

    /// The arithmetic above only holds if the Navigator really opens at its
    /// 240-point minimum. AppKit picks an automatic width proportional to
    /// the window's, and past some window width that choice climbs over the
    /// minimum and takes the room the page was promised — so open a real
    /// window and measure.
    func testARealWindowOpensWithTheNavigatorAtItsMinimum() {
        let controller = ScriptWindowController(editor: EditorState(source: "INT. LAB - DAY"))
        withExtendedLifetime(controller) {
            guard let window = controller.window,
                  let split = window.contentViewController as? NSSplitViewController
            else { return XCTFail("the window's columns are not a split view") }
            window.makeKeyAndOrderFront(nil)
            window.displayIfNeeded()
            window.contentView?.layoutSubtreeIfNeeded()

            let navigator = split.splitViewItems[0].viewController.view.frame.width
            XCTAssertEqual(navigator, 240, accuracy: 1,
                           "the Navigator opened wider than its minimum and took "
                               + "the room the page was measured for")
        }
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
        let (editor, surface) = windowed(1200)
        pinch(surface, to: 1.6)

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01)
        XCTAssertTrue(editor.holdingActualSize)
        XCTAssertFalse(
            PageZoom.percentageShowsMenu(at: editor.zoom, holdingActualSize: editor.holdingActualSize),
            "a toggle from a pinched size became a menu at 100%"
        )

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(surface.scrollView.magnification, 1.6, accuracy: 0.01)
        XCTAssertFalse(editor.holdingActualSize)
    }

    /// A trackpad can sit on 110%. That is near enough that the percentage
    /// offers the named sizes instead of toggling to 100% — toggling first
    /// and then showing the list is the wrong shape.
    func testAPinchOntoOneHundredAndTenOffersTheMenu() {
        let (editor, surface) = windowed(1200)
        pinch(surface, to: 1.1)

        XCTAssertEqual(editor.zoom, 1.1, accuracy: 0.01)
        XCTAssertFalse(editor.holdingActualSize)
        XCTAssertTrue(
            PageZoom.percentageShowsMenu(at: editor.zoom, holdingActualSize: editor.holdingActualSize),
            "a pinched 110% should open the sizes, not step to 100%"
        )
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

extension PinchToZoomTests {

    /// Reported as "pinch-to-zoom takes several attempts to work". The pinch
    /// sets the scroll view's magnification directly, and a SwiftUI update
    /// landing mid-gesture — the readout changing is enough to cause one —
    /// used to reach `remeasure` and set the *old* preference back: the page
    /// snapped out from under the fingers and the gesture had to be retried.
    func testAnUpdateMidPinchDoesNotSetTheSizeBack() {
        let (editor, surface) = windowed(1200)

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveMagnifyNotification, object: surface.scrollView
        )
        surface.scrollView.magnification = 1.7
        // The update pass, as ScriptPageView.updateNSView would run it.
        surface.remeasure(to: 1200, elements: editor.screenplay.elements)

        XCTAssertEqual(
            surface.scrollView.magnification, 1.7, accuracy: 0.01,
            "a re-measure mid-pinch set the magnification back to the old preference"
        )

        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveMagnifyNotification, object: surface.scrollView
        )
        XCTAssertEqual(
            surface.scrollView.magnification, 1.7, accuracy: 0.01,
            "170% is on the grid: nothing left to settle"
        )
        withExtendedLifetime(editor) {}
    }

    /// The gesture lands where the fingers stop; the page comes to rest on
    /// the nearest five points. The harness has no window, so the drift
    /// lands directly rather than animating.
    func testAPinchBetweenStopsDriftsToTheGridWhenTheFingersLift() {
        let (editor, surface) = windowed(1200)

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveMagnifyNotification, object: surface.scrollView
        )
        surface.scrollView.magnification = 1.62
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveMagnifyNotification, object: surface.scrollView
        )

        XCTAssertEqual(
            surface.scrollView.magnification, 1.6, accuracy: 0.01,
            "a pinch never lands on a number; it comes to rest on the grid"
        )
        XCTAssertEqual(editor.zoom, 1.6, accuracy: 0.01)
        withExtendedLifetime(editor) {}
    }

    /// The preference the gesture leaves behind is the grid point: the
    /// percentage button's way back, and what a resize must not undo.
    func testTheSettledSizeIsTheWritersChoice() {
        let (_, surface) = windowed(1200)
        pinch(surface, to: 1.62)

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01)
        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(
            surface.scrollView.magnification, 1.6, accuracy: 0.01,
            "the button went back to the raw landing rather than the settled size"
        )
    }

    /// The readout displays whole percentage points; reporting at any finer
    /// granularity re-renders the glass capsule dozens of times a second for
    /// a change nobody can read.
    func testTheReadoutMovesAtTheGranularityItDisplays() {
        let (editor, surface) = windowed(1200)

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveMagnifyNotification, object: surface.scrollView
        )
        surface.scrollView.magnification = 1.254
        XCTAssertEqual(
            editor.zoom, PageZoom.opening, accuracy: 0.0001,
            "a change too small to display re-rendered the capsule anyway"
        )

        surface.scrollView.magnification = 1.27
        XCTAssertEqual(
            editor.zoom, 1.27, accuracy: 0.0001,
            "a change that crosses a whole point is shown"
        )

        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveMagnifyNotification, object: surface.scrollView
        )
        withExtendedLifetime(editor) {}
    }

    /// A window that goes away mid-pinch never sends didEnd. The next pinch
    /// still works — and so does everything the live flag would otherwise
    /// have refused forever.
    func testAnInterruptedGestureDoesNotDeadlockTheZoom() {
        let (_, surface) = windowed(1200)

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveMagnifyNotification, object: surface.scrollView
        )
        // The window goes away with the fingers still down.
        surface.canvas.onLeaveWindow?()

        surface.applyZoom(.zoomIn)
        XCTAssertEqual(
            surface.scrollView.magnification, 1.5, accuracy: 0.01,
            "a missed didEnd left the surface refusing to change the size"
        )
    }

    // MARK: - The thread column borrows the size

    /// Choosing a character opens the thread beside the page and takes 260
    /// points of the desk. The page lends the room — fits what is left, down
    /// to actual size and never below — without the writer asking.
    func testAnOpenThreadLendsTheRoomAndFitsWhatIsLeft() {
        let (editor, surface) = windowed(855)

        // The thread's arrival as the window reports it: the column is laid
        // out — 260 points and a divider gone from the page — and then the
        // surface is told.
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 594, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.threadColumn(opened: true)

        XCTAssertEqual(
            surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01,
            "594 points cannot hold a 684-point canvas, so the fit floors at actual size"
        )
        XCTAssertEqual(editor.zoom, PageZoom.actualSize, accuracy: 0.01,
                       "the readout shows the size the page actually has")
    }

    /// The lend is a borrow, not a takeover: closing the column hands back
    /// the size the writer had, though no one asked for it in between.
    func testAClosedThreadHandsTheWritersSizeBack() {
        let (_, surface) = windowed(855)

        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 594, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.threadColumn(opened: true)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01)

        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 855, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.threadColumn(opened: false)

        XCTAssertEqual(
            surface.scrollView.magnification, PageZoom.opening, accuracy: 0.01,
            "the writer's own 125% did not come back when the column closed"
        )
    }

    /// A size asked for while the room is lent is the writer taking the wheel
    /// back: it ends the borrow, and the column closing changes nothing.
    func testASizeChosenWhileLentStands() {
        let (_, surface) = windowed(855)

        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 594, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.threadColumn(opened: true)

        surface.applyZoom(.zoomIn)
        let chosen = surface.scrollView.magnification
        XCTAssertEqual(chosen, 1.25, accuracy: 0.01, "one stop up from the lent 100%")

        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 855, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.threadColumn(opened: false)

        XCTAssertEqual(
            surface.scrollView.magnification, chosen, accuracy: 0.01,
            "closing the column overrode a size the writer chose beside it"
        )
    }

    /// A pinch is the same choice made with the fingers.
    func testAPinchWhileLentStands() {
        let (_, surface) = windowed(855)

        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 594, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.threadColumn(opened: true)

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveMagnifyNotification, object: surface.scrollView
        )
        surface.scrollView.magnification = 1.42
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveMagnifyNotification, object: surface.scrollView
        )
        let settled = surface.scrollView.magnification
        XCTAssertEqual(settled, 1.4, accuracy: 0.01, "the gesture settles onto the 5% grid")

        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 855, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.threadColumn(opened: false)

        XCTAssertEqual(
            surface.scrollView.magnification, settled, accuracy: 0.01,
            "closing the column overrode the size the writer pinched to"
        )
    }

    /// Actual size borrows the lent size; it does not end the lend. Pressing
    /// the button twice beside an open thread returns to the fit the thread
    /// left in place — not to a size that no longer fits beside it.
    func testTheButtonBorrowsTheLentSize() {
        let (_, surface) = windowed(1470)

        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1209, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.threadColumn(opened: true)
        let lent = surface.scrollView.magnification
        XCTAssertEqual(lent, 1.925, accuracy: 0.01, "1209 points fit the canvas at about 192%")

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01)

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(
            surface.scrollView.magnification, lent, accuracy: 0.01,
            "the button returned to the writer's old size, which does not fit the room"
        )
    }

    /// While the writer is holding actual size, the thread's arrival moves
    /// nothing: the button's borrow is the more explicit one.
    func testAThreadOpeningDuringAnActualSizeHoldDoesNotMoveThePage() {
        let (_, surface) = windowed(1470)
        surface.applyZoom(.toggleActualSize)

        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1209, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.threadColumn(opened: true)

        XCTAssertEqual(
            surface.scrollView.magnification, PageZoom.actualSize, accuracy: 0.01,
            "the column's arrival moved a page the writer was holding at 100%"
        )

        surface.applyZoom(.toggleActualSize)
        XCTAssertEqual(
            surface.scrollView.magnification, 1.925, accuracy: 0.01,
            "letting go of the button should land on the lent fit"
        )
    }

    /// A lent size is a fit, and a fit follows the window: resizing beside an
    /// open thread re-fits the room that is left.
    func testALentSizeFollowsTheWindow() {
        let (editor, surface) = windowed(1470)

        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1209, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.threadColumn(opened: true)

        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.remeasure(to: 700, elements: editor.screenplay.elements)

        XCTAssertEqual(
            surface.scrollView.magnification, 1.115, accuracy: 0.01,
            "a narrower window beside the thread did not shrink the fit"
        )
    }

    /// A size chosen by name from the percentage menu is an explicit choice:
    /// it ends the thread's borrow, and a window resize must not undo it.
    func testAChosenSizeEndsTheBorrow() {
        let (editor, surface) = windowed(1209)
        surface.threadColumn(opened: true)

        surface.applyChosenSize(1.5)
        XCTAssertEqual(surface.scrollView.magnification, 1.5, accuracy: 0.01)

        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 700)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.remeasure(to: 700, elements: editor.screenplay.elements)
        XCTAssertEqual(
            surface.scrollView.magnification, 1.5, accuracy: 0.01,
            "resizing the window overrode a size the writer had chosen by name"
        )
    }

    // MARK: - A pinch stays on the page's midline

    /// A pinch anchors on the point under the cursor, and the cursor is
    /// rarely on the page's midline — so the page used to slide sideways as
    /// the fingers wandered. From willStart to didEnd the horizontal anchor
    /// is the page's own centre, and a pan the writer had going is taken
    /// back to it.
    func testAPinchKeepsThePageOnItsMidline() {
        let (_, surface) = windowed(500)
        let clip = surface.scrollView.contentView

        // A pan the writer chose — far enough that keeping the *visible*
        // centre instead of the page's would read clearly differently.
        clip.scroll(to: NSPoint(x: 200, y: 200))
        surface.scrollView.reflectScrolledClipView(clip)
        XCTAssertEqual(clip.bounds.origin.x, 200, accuracy: 0.5, "the pan did not stand")

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveMagnifyNotification, object: surface.scrollView
        )
        surface.scrollView.magnification = 1.6
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveMagnifyNotification, object: surface.scrollView
        )

        XCTAssertEqual(
            clip.bounds.origin.x,
            (PageFormat.letter.pageRect.width + 2 * PageCanvasView.deskPadding - clip.bounds.width) / 2,
            accuracy: 0.5,
            "the page followed the cursor's x instead of its own midline"
        )
    }
}

extension PinchToZoomTests {

    /// Nothing must move under the fingers while a pinch is in progress.
    ///
    /// A pinch is dozens of magnification changes a second, and AppKit
    /// rubber-bands past its own limits and settles back. Recording a
    /// preference and re-measuring the canvas on each one fights that: the page
    /// shrinks, snaps and bounces. Reported as "it keeps shrinking… it went a
    /// bit and then smoothly bounced back".
    func testNothingIsReMeasuredWhileTheFingersAreStillDown() {
        let (editor, surface) = windowed(1200)
        let canvasBefore = surface.canvas.frame.width

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveMagnifyNotification, object: surface.scrollView
        )
        for step in stride(from: 1.5, through: 1.0, by: -0.1) {
            surface.scrollView.magnification = step
        }
        // Give any deferred re-measure a chance to run. Without the guard one
        // is scheduled on every step and the canvas moves during the pump —
        // which is the whole complaint.
        _ = ScriptSurfaceHarness.wait(timeout: 0.4) { false }

        XCTAssertEqual(
            surface.canvas.frame.width, canvasBefore, accuracy: 0.5,
            "the canvas was re-measured mid-gesture, which is what fights the pinch"
        )
        // The readout still follows, because that costs the gesture nothing.
        XCTAssertEqual(editor.zoom, 1.0, accuracy: 0.01)
    }

    /// And when they lift, it settles once.
    func testItSettlesWhenTheGestureEnds() {
        let (editor, surface) = windowed(1200)

        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveMagnifyNotification, object: surface.scrollView
        )
        surface.scrollView.magnification = 1.0
        NotificationCenter.default.post(
            name: NSScrollView.didEndLiveMagnifyNotification, object: surface.scrollView
        )

        XCTAssertTrue(ScriptSurfaceHarness.wait {
            abs(surface.pageFrame.midX - surface.scrollView.contentView.bounds.midX) < 2
        }, "the page never re-centred after the gesture ended")
        XCTAssertEqual(editor.zoom, 1.0, accuracy: 0.01)
    }
}
