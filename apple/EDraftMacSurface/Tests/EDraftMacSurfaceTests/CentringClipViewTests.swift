import AppKit
import XCTest
@testable import EDraftMacSurface

/// The page's horizontal centre is the anchor of every zoom.
///
/// A pinch otherwise anchors on the point under the cursor, and the cursor is
/// rarely on the page's midline — so the page slid sideways as the fingers
/// wandered, reported as distracting. The clip view owns the rule because
/// every bounds proposal passes through it; the surface owns the flag,
/// because the surface alone knows when a gesture is in flight.
@MainActor
final class CentringClipViewTests: XCTestCase {

    private func clipView(
        documentWidth: CGFloat = 684, viewportWidth: CGFloat = 400
    ) -> CentringClipView {
        let clip = CentringClipView(frame: NSRect(x: 0, y: 0, width: viewportWidth, height: 600))
        clip.documentView = NSView(
            frame: NSRect(x: 0, y: 0, width: documentWidth, height: 2000)
        )
        return clip
    }

    /// Between gestures the writer owns x: a pan stands.
    func testAPanIsLeftAlone() {
        let clip = clipView()
        clip.bounds = NSRect(x: 0, y: 0, width: 400, height: 600)

        let constrained = clip.constrainBoundsRect(NSRect(x: 120, y: 500, width: 400, height: 600))

        XCTAssertEqual(constrained.origin.x, 120, accuracy: 0.001,
                       "a scroll between gestures was re-centred")
        XCTAssertEqual(constrained.origin.y, 500, accuracy: 0.001)
    }

    /// Mid-gesture, every proposal is centred — AppKit applies one frame in
    /// two constrained steps, a size set and an origin set, and both must
    /// land on the midline. Vertical still follows the gesture, so the line
    /// under the fingers stays under them.
    func testDuringAGestureEveryProposalIsCentred() {
        let clip = clipView()
        clip.bounds = NSRect(x: 120, y: 500, width: 400, height: 600)
        clip.centresHorizontally = true

        let sizeStep = clip.constrainBoundsRect(
            NSRect(x: 120, y: 500, width: 400 / 1.5, height: 600 / 1.5)
        )
        XCTAssertEqual(sizeStep.origin.x, (684 - 400 / 1.5) / 2, accuracy: 0.5,
                       "the size step followed the cursor's x")

        let originStep = clip.constrainBoundsRect(
            NSRect(x: 61, y: 520, width: 400 / 1.5, height: 600 / 1.5)
        )
        XCTAssertEqual(originStep.origin.x, (684 - 400 / 1.5) / 2, accuracy: 0.5,
                       "the origin step followed the cursor's x")
        XCTAssertEqual(originStep.origin.y, 520, accuracy: 0.001,
                       "the vertical anchor was lost with the horizontal one")
    }

    /// A page smaller than the window is centred, as it always has been —
    /// gesture or no gesture.
    func testAPageSmallerThanTheWindowIsCentred() {
        let clip = clipView(viewportWidth: 900)
        clip.bounds = NSRect(x: 0, y: 0, width: 900, height: 600)

        let constrained = clip.constrainBoundsRect(NSRect(x: 30, y: 0, width: 900, height: 600))

        XCTAssertEqual(constrained.origin.x, (684 - 900) / 2, accuracy: 0.001)
    }

    /// End to end through a real scroll view: with the gesture's flag set,
    /// AppKit's own two-step application of a size change lands centred —
    /// where without it the visible centre, not the page's, is what is kept.
    func testDuringAGestureASizeChangeLandsCentred() {
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        let clip = CentringClipView(frame: scrollView.bounds)
        scrollView.contentView = clip
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 684, height: 2000))
        scrollView.magnification = 1.0
        clip.bounds = NSRect(x: 120, y: 500, width: 400, height: 600)
        clip.centresHorizontally = true

        scrollView.magnification = 1.5

        XCTAssertEqual(
            clip.bounds.origin.x, (684 - clip.bounds.width) / 2, accuracy: 0.5,
            "a mid-gesture size change left the page off the midline"
        )
    }
}
