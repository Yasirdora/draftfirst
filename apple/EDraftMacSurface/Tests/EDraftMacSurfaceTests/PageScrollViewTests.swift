import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// The pinch, routed by hand.
///
/// `PageScrollView` never lets AppKit's own magnify handling run — that path
/// scales around the cursor off the bounds path, which is the sideways pull
/// this class exists to remove. These tests pin the routing itself: the
/// bookend notifications the surface's gesture machine listens for, the
/// spring past the ends, and the unphased nudge. Where an anchored frame
/// lands is the clip view's story, pinned in `CentringClipViewTests`.
@MainActor
final class PageScrollViewTests: XCTestCase {

    private func scrollView() -> PageScrollView {
        let scrollView = PageScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 684, height: 2000))
        scrollView.magnification = 1.0
        return scrollView
    }

    /// The surface's gesture machine runs on AppKit's bookends; routing the
    /// gesture by hand must feed it the same sequence — start, then end —
    /// or the live readout, the settle and the drift lose their clock.
    func testAGesturePostsTheBookendsInOrder() {
        let scrollView = scrollView()
        var names: [Notification.Name] = []
        let centre = NotificationCenter.default
        let observers = [
            NSScrollView.willStartLiveMagnifyNotification,
            NSScrollView.didEndLiveMagnifyNotification,
        ].map { name in
            centre.addObserver(forName: name, object: scrollView, queue: nil) { _ in
                names.append(name)
            }
        }
        defer { observers.forEach(centre.removeObserver) }

        scrollView.handleMagnify(delta: 0, phase: [.began], at: .zero)
        scrollView.handleMagnify(delta: 0.25, phase: [.changed], at: .zero)
        scrollView.handleMagnify(delta: 0.25, phase: [.changed], at: .zero)
        scrollView.handleMagnify(delta: 0, phase: [.ended], at: .zero)

        XCTAssertEqual(names, [
            NSScrollView.willStartLiveMagnifyNotification,
            NSScrollView.didEndLiveMagnifyNotification,
        ])
    }

    /// Inside the range a pull is answered in full: a half-spread from
    /// actual size is a 150% page.
    func testAPullInsideTheRangeIsAnsweredInFull() {
        let scrollView = scrollView()

        scrollView.handleMagnify(delta: 0.5, phase: [.changed], at: .zero)

        XCTAssertEqual(scrollView.magnification, 1.5, accuracy: 0.001)
    }

    /// At the ceiling the page still answers the fingers, at the spring's
    /// third-strength, and never past the band the settle will walk back.
    func testAPullPastTheCeilingMeetsTheSpring() {
        let scrollView = scrollView()
        scrollView.magnification = PageZoom.maximum

        scrollView.handleMagnify(delta: 1.0, phase: [.changed], at: .zero)

        XCTAssertGreaterThan(scrollView.magnification, PageZoom.maximum,
                             "a hard wall at 200% reads as a broken gesture")
        XCTAssertEqual(scrollView.magnification, PageZoom.bandMaximum, accuracy: 0.001,
                       "a pull twice the range deep is capped at 8%")
    }

    /// A mouse driver's pinch carries no phase: one event is the whole
    /// gesture — applied, and the settle booked, in a single call.
    func testAnUnphasedNudgeIsSelfContained() {
        let scrollView = scrollView()
        var ended = false
        let observer = NotificationCenter.default.addObserver(
            forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: nil
        ) { _ in ended = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        scrollView.handleMagnify(delta: 0.25, phase: [], at: .zero)

        XCTAssertEqual(scrollView.magnification, 1.25, accuracy: 0.001)
        XCTAssertTrue(ended, "an unphased nudge never booked its settle")
    }
}
