import CoreGraphics
import Foundation
import XCTest
@testable import EDraftCore

/// The scroll arithmetic, pinned.
///
/// Every case here is one that actually went wrong on the phone, written down
/// so that the Mac starts where the phone finished rather than relearning it.
final class PageScrollTests: XCTestCase {

    // A phone-shaped page: the content begins under a translucent bar, so the
    // top of the scrollable range is not zero. Assuming it was is the single
    // mistake behind most of the bugs these tests exist for.
    private let bar: CGFloat = 116
    private let home: CGFloat = 34

    private func longPage() -> ClosedRange<CGFloat> {
        PageScroll.range(
            contentHeight: 4776, viewportHeight: 852, topInset: bar, bottomInset: home
        )
    }

    // MARK: - Where the page may rest

    func testTheTopIsTheBarsClearanceNotZero() {
        XCTAssertEqual(longPage().lowerBound, -bar)
    }

    func testAShortPageHasExactlyOneRestingPlace() {
        let range = PageScroll.range(
            contentHeight: 300, viewportHeight: 852, topInset: bar, bottomInset: home
        )
        XCTAssertEqual(range.lowerBound, range.upperBound)
        XCTAssertFalse(PageScroll.canScroll(range), "a page that fits has nowhere to go")
    }

    /// A script that fits on screen was being forced to offset zero, which put
    /// its first lines behind the navigation bar. The range is what prevents it.
    func testAShortPageIsNeverPinnedUnderTheBar() {
        let range = PageScroll.range(
            contentHeight: 300, viewportHeight: 852, topInset: bar, bottomInset: home
        )
        XCTAssertEqual(range.lowerBound, -bar)
        XCTAssertNotEqual(range.lowerBound, 0)
    }

    // MARK: - Going somewhere

    func testASceneInTheMiddleComesToTheTop() {
        let range = longPage()
        let offset = PageScroll.offset(bringingContentY: 2000, toTopOf: range)
        XCTAssertEqual(offset, 2000 - bar, accuracy: 0.001)
    }

    /// The reported bug behind the reveal mark: a target within a window's
    /// height of the end cannot reach the top, so the page goes as far as it
    /// can and stops — which looks like nothing happened.
    func testATargetNearTheEndGoesAsFarAsItCan() {
        let range = longPage()
        let offset = PageScroll.offset(bringingContentY: 4700, toTopOf: range)
        XCTAssertEqual(offset, range.upperBound)
        XCTAssertLessThan(offset, 4700 - bar, "it genuinely cannot reach the top")
    }

    func testTheFirstSceneRestsAtTheTopRatherThanAboveIt() {
        XCTAssertEqual(PageScroll.offset(bringingContentY: 0, toTopOf: longPage()), -bar)
    }

    // MARK: - Keeping the caret in sight

    func testACaretUnderTheKeyboardIsBroughtUpTheLeastPossible() throws {
        let range = longPage()
        // The visible band, in content space, with the keyboard eating the foot.
        let visible: ClosedRange<CGFloat> = 1000...1400
        let caret: ClosedRange<CGFloat> = 1390...1412
        let corrected = try XCTUnwrap(
            PageScroll.correction(
                revealing: caret, within: visible, margin: 8, from: 1000, in: range
            )
        )
        XCTAssertEqual(corrected, 1020, accuracy: 0.001, "moved by exactly what was hidden")
    }

    func testACaretAboveTheBarIsBroughtDown() throws {
        let range = longPage()
        let corrected = try XCTUnwrap(
            PageScroll.correction(
                revealing: 990...1012, within: 1000...1400, margin: 8, from: 1000, in: range
            )
        )
        XCTAssertEqual(corrected, 982, accuracy: 0.001)
    }

    /// Doing this when nothing is hidden is how the page lurched on every
    /// keystroke.
    func testACaretAlreadyInViewIsLeftAlone() {
        XCTAssertNil(
            PageScroll.correction(
                revealing: 1100...1122, within: 1000...1400, margin: 8, from: 1000, in: longPage()
            )
        )
    }

    func testACorrectionSmallerThanHalfAPointIsNotWorthMaking() {
        XCTAssertNil(
            PageScroll.correction(
                revealing: 1007.7...1030, within: 1000...1400, margin: 8, from: 1000,
                in: longPage()
            )
        )
    }

    // MARK: - Holding still while the text is rebuilt

    /// A line inserted above the caret moves every line below it down; the
    /// writer's eye should not have to follow.
    func testThePageFollowsTheCaretAcrossARebuild() {
        let settled = PageScroll.settled(
            caretWas: 400, caretIs: 430, preserved: 1000, offset: 1000, in: longPage()
        )
        XCTAssertEqual(settled, 1030, accuracy: 0.001)
    }

    /// Reading mode has no caret at all. The page must simply stay put — this
    /// is the case that, done wrong, made a short script appear blank.
    func testWithNoCaretThePageStaysWhereItWas() {
        let settled = PageScroll.settled(
            caretWas: nil, caretIs: nil, preserved: 1234, offset: 1234, in: longPage()
        )
        XCTAssertEqual(settled, 1234, accuracy: 0.001)
    }

    func testASettledOffsetIsNeverOutsideTheRange() {
        let range = PageScroll.range(
            contentHeight: 300, viewportHeight: 852, topInset: bar, bottomInset: home
        )
        // A remembered offset of zero, on a page whose only resting place is
        // -116: restoring it unclamped is what hid a short script's first page.
        let settled = PageScroll.settled(
            caretWas: nil, caretIs: nil, preserved: 0, offset: -bar, in: range
        )
        XCTAssertEqual(settled, -bar)
    }
}
