import CoreGraphics
import XCTest
@testable import EDraftCore

/// How large the page is drawn.
///
/// The numbers here are the ones that made this necessary: a Letter page is
/// 612 points wide, the canvas keeps 36 points either side of it, and a 13.6"
/// laptop runs 1710 points across.
final class PageZoomTests: XCTestCase {

    private let page: CGFloat = 612
    private let padding: CGFloat = 36

    // MARK: - Fitting

    /// A maximised window on the 13.6" laptop this was measured on: 1710
    /// points across, less a 240-point Navigator. The page would happily grow
    /// to 2.15x there, so this is the case the cap exists for — and 2x is
    /// already past life size, which needs about 2.08.
    func testAMaximisedWindowReachesTheCap() {
        let zoom = PageZoom.fitting(canvasWidth: 1470, pageWidth: page, padding: padding)

        XCTAssertEqual(zoom, PageZoom.maximum, accuracy: 0.001)
        XCTAssertGreaterThan(1470 / (page + padding * 2), PageZoom.maximum,
                             "if this fails the cap is no longer doing anything here")
    }

    func testTheDefaultWindowIsLeftAboutWhereItWas() {
        // The 900-point default window, less the Navigator.
        let zoom = PageZoom.fitting(canvasWidth: 660, pageWidth: page, padding: padding)

        XCTAssertEqual(zoom, 1, accuracy: 0.001, "660 is narrower than 612 plus its margins")
    }

    func testAWindowNarrowerThanThePageDoesNotShrinkIt() {
        let zoom = PageZoom.fitting(canvasWidth: 400, pageWidth: page, padding: padding)

        XCTAssertEqual(
            zoom, 1, accuracy: 0.001,
            "a page smaller than its own metrics helps nobody; it scrolls instead"
        )
    }

    func testItNeverExceedsTwiceActualSize() {
        let zoom = PageZoom.fitting(canvasWidth: 4000, pageWidth: page, padding: padding)

        XCTAssertEqual(zoom, PageZoom.maximum, accuracy: 0.001)
    }

    func testAZeroWidthCanvasIsNotADivision() {
        XCTAssertEqual(PageZoom.fitting(canvasWidth: 0, pageWidth: page, padding: padding), 1)
        XCTAssertEqual(PageZoom.fitting(canvasWidth: 660, pageWidth: 0, padding: 0), 1)
    }

    // MARK: - Stepping

    /// From a fitted, unround magnification, ⌘+ and ⌘− land on round numbers
    /// rather than multiplying what was there.
    func testSteppingFromAFittedSizeLandsOnAStop() {
        XCTAssertEqual(PageZoom.stepped(from: 1.83, .zoomIn), 2, accuracy: 0.001)
        XCTAssertEqual(PageZoom.stepped(from: 1.83, .zoomOut), 1.75, accuracy: 0.001)
    }

    func testSteppingWalksTheStops() {
        var zoom = PageZoom.actualSize
        var walked: [CGFloat] = [zoom]
        for _ in 0..<8 {
            zoom = PageZoom.stepped(from: zoom, .zoomIn)
            walked.append(zoom)
        }
        XCTAssertEqual(walked.suffix(4), [2, 2, 2, 2], "zooming in stops at the cap")
        XCTAssertEqual(Array(walked.prefix(6)), PageZoom.stops)
    }

    func testSteppingStopsAtActualSizeGoingDown() {
        XCTAssertEqual(PageZoom.stepped(from: 1, .zoomOut), 1, accuracy: 0.001)
        XCTAssertEqual(PageZoom.stepped(from: 1.1, .zoomOut), 1, accuracy: 0.001)
    }

    func testActualSizeIsExactlyOne() {
        XCTAssertEqual(PageZoom.stepped(from: 1.83, .actualSize), 1, accuracy: 0.001)
    }

    // MARK: - Where a pinch comes to rest

    /// The behaviour the writer meets: 102% drifts down to a hundred,
    /// 103% on to a five.
    func testAPinchSettlesToTheNearestFivePoints() {
        XCTAssertEqual(PageZoom.settled(1.02), 1, accuracy: 0.001)
        XCTAssertEqual(PageZoom.settled(1.03), 1.05, accuracy: 0.001)
        XCTAssertEqual(PageZoom.settled(1.62), 1.6, accuracy: 0.001)
        XCTAssertEqual(PageZoom.settled(1.63), 1.65, accuracy: 0.001)
    }

    /// A size already on the grid is left alone, so the settle never
    /// moves a page the writer is already happy with.
    func testAPinchThatLandsOnTheGridStaysPut() {
        XCTAssertEqual(PageZoom.settled(1.5), 1.5, accuracy: 0.001)
        XCTAssertEqual(PageZoom.settled(1), 1, accuracy: 0.001)
        XCTAssertEqual(PageZoom.settled(2), 2, accuracy: 0.001)
    }

    /// The rubber-band can leave the magnification past a limit when the
    /// fingers lift; where it comes to rest is still inside the bounds.
    func testASettleNeverLeavesTheBounds() {
        XCTAssertEqual(PageZoom.settled(2.04), PageZoom.maximum, accuracy: 0.001)
        XCTAssertEqual(PageZoom.settled(0.97), PageZoom.actualSize, accuracy: 0.001)
    }

    // MARK: - The drift itself

    /// The ease: both ends exact, the middle halfway, never past the
    /// target, and still at the ends — a glide, not a bounce.
    func testTheDriftGlideHoldsItsPromises() {
        XCTAssertEqual(PageZoom.eased(from: 1.2, to: 1.5, progress: 0), 1.2, accuracy: 0.0001)
        XCTAssertEqual(PageZoom.eased(from: 1.2, to: 1.5, progress: 1), 1.5, accuracy: 0.0001)
        XCTAssertEqual(PageZoom.eased(from: 1.2, to: 1.5, progress: 0.5), 1.35, accuracy: 0.0001,
                       "smootherstep is halfway through at the halfway instant")

        // Monotonic, and never past either end.
        var previous = -CGFloat.infinity
        for step in 0...100 {
            let value = PageZoom.eased(from: 1.2, to: 1.5, progress: CGFloat(step) / 100)
            XCTAssertGreaterThanOrEqual(value, previous)
            XCTAssert((1.2...1.5).contains(value))
            previous = value
        }

        // Zero velocity at the ends: the first and last hundredths barely move.
        let start = PageZoom.eased(from: 1.2, to: 1.5, progress: 0.01) - 1.2
        let end = 1.5 - PageZoom.eased(from: 1.2, to: 1.5, progress: 0.99)
        XCTAssertLessThan(start, 0.001, "the glide does not leap off the mark")
        XCTAssertLessThan(end, 0.001, "the glide does not snap onto the stop")
    }

    /// Time reversed reads the same: the second half is the first half
    /// mirrored, so a drift decelerates exactly the way it accelerated.
    func testTheDriftReadsTheSameBackwards() {
        for step in 0...20 {
            let t = CGFloat(step) / 20
            XCTAssertEqual(
                PageZoom.eased(from: 0, to: 1, progress: t)
                    + PageZoom.eased(from: 0, to: 1, progress: 1 - t),
                1, accuracy: 0.0001
            )
        }
    }

    /// Longer jumps take longer, but sublinearly: ten times the distance is
    /// far from ten times the time, and nothing exceeds half a second.
    func testTheDriftPace() {
        let nudge = PageZoom.driftDuration(for: 0.005)
        let settle = PageZoom.driftDuration(for: 0.025)
        let lend = PageZoom.driftDuration(for: 0.25)
        let wholeRange = PageZoom.driftDuration(for: 1)

        XCTAssertGreaterThan(settle, nudge)
        XCTAssertGreaterThan(lend, settle)
        XCTAssertLessThan(lend / settle, 2, "the pace is sublinear — far jumps never drag")
        XCTAssertLessThanOrEqual(wholeRange, 0.5)
        XCTAssertGreaterThan(nudge, 0.1, "even a nudge gets a breath")
    }

    // MARK: - What the menu can say

    func testAMenuCanTellTheWriterWhenNothingWouldHappen() {
        XCTAssertFalse(PageZoom.isAvailable(.zoomIn, at: PageZoom.maximum))
        XCTAssertTrue(PageZoom.isAvailable(.zoomIn, at: 1.5))
        XCTAssertFalse(PageZoom.isAvailable(.zoomOut, at: PageZoom.actualSize))
        XCTAssertTrue(PageZoom.isAvailable(.zoomOut, at: 1.1))
        XCTAssertFalse(PageZoom.isAvailable(.actualSize, at: 1))
        XCTAssertTrue(PageZoom.isAvailable(.actualSize, at: 1.25))
        XCTAssertTrue(PageZoom.isAvailable(.fit, at: 1), "fitting is always something to ask for")
    }

    /// Near actual size the percentage stops toggling and offers the stops
    /// instead: at the truth, "show me the truth" has nowhere to go.
    func testThePercentageOffersAMenuNearActualSize() {
        XCTAssertTrue(PageZoom.percentageShowsMenu(at: 1))
        XCTAssertTrue(PageZoom.percentageShowsMenu(at: 1.05))
        XCTAssertFalse(PageZoom.percentageShowsMenu(at: 1.1))
        XCTAssertFalse(PageZoom.percentageShowsMenu(at: 2))
    }
}
