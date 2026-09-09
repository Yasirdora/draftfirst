import Foundation
import XCTest
@testable import EDraftCore

/// The mark that says where a Navigator row landed is the same mark on every
/// surface. These pin the parts that must not drift between them — and the one
/// part that must change when a reader has asked for less motion.
final class RevealMarkTests: XCTestCase {

    func testTheMarkWaitsForTheNavigatorToClearBeforeAppearing() {
        XCTAssertGreaterThan(
            RevealMark.wait, 0,
            "a mark that fades in behind a dismissing sheet is never seen"
        )
    }

    func testTheMarkIsHeldLongEnoughToBeFound() {
        // The eye is on the sheet when the reveal is asked for; it has to
        // travel to the page and still find the mark waiting.
        XCTAssertGreaterThanOrEqual(RevealMark.hold, 0.75)
    }

    func testReducedMotionStillMarksTheLanding() {
        let reduced = RevealMark.timing(reduceMotion: true)
        XCTAssertEqual(reduced.fadeIn, 0)
        XCTAssertEqual(reduced.fadeOut, 0)
        XCTAssertEqual(
            reduced.hold, RevealMark.hold,
            "less motion means no fade, never no answer"
        )
    }

    func testFullMotionFades() {
        let full = RevealMark.timing(reduceMotion: false)
        XCTAssertGreaterThan(full.fadeIn, 0)
        XCTAssertGreaterThan(full.fadeOut, 0)
    }
}
