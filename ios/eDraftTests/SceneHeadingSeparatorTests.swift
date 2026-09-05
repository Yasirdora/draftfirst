import Foundation
import XCTest
@testable import eDraft

/// The dash key in a scene heading writes a separator, and the engine only
/// reads a separator that is spaced on both sides. These pin the one shape it
/// reads — against every spacing a keyboard can deliver — and the single
/// delete that takes it back for a heading that meant a hyphen.
final class SceneHeadingSeparatorTests: XCTestCase {

    private func spacing(_ text: String, replacing range: NSRange) -> (text: String, caret: Int)? {
        SceneHeadingSeparator.spaced(in: text as NSString, replacing: range)
    }

    /// Typed straight after the location, which is the common case and the
    /// one a keyboard leaves as "BASEMENT-".
    func testADashAfterTheLocationBecomesASpacedSeparator() throws {
        let edit = try XCTUnwrap(spacing("INT. BASEMENT", replacing: NSRange(location: 13, length: 0)))
        XCTAssertEqual(edit.text, "INT. BASEMENT - ")
        XCTAssertEqual(edit.caret, 16, "the caret waits where the time is typed")
    }

    /// The writer's own space is not doubled.
    func testASpaceAlreadyTypedIsNotRepeated() throws {
        let edit = try XCTUnwrap(spacing("INT. BASEMENT ", replacing: NSRange(location: 14, length: 0)))
        XCTAssertEqual(edit.text, "INT. BASEMENT - ")
    }

    /// What the keyboard actually does: it deletes the space it inserted and
    /// puts the dash in its place. The separator survives it.
    func testTheKeyboardEatingTheSpaceStillLeavesASeparator() throws {
        let edit = try XCTUnwrap(spacing("INT. BASEMENT ", replacing: NSRange(location: 13, length: 1)))
        XCTAssertEqual(edit.text, "INT. BASEMENT - ")
    }

    func testRunsOfSpacesCollapseToOne() throws {
        let edit = try XCTUnwrap(spacing("INT. BASEMENT   ", replacing: NSRange(location: 16, length: 0)))
        XCTAssertEqual(edit.text, "INT. BASEMENT - ")
    }

    /// A time already stands, so this dash opens the modifier — CONTINUOUS,
    /// ESTABLISHING — and is spaced exactly the same way.
    func testASecondDashSeparatesTheModifier() throws {
        let edit = try XCTUnwrap(spacing("INT. LAB - MORNING", replacing: NSRange(location: 18, length: 0)))
        XCTAssertEqual(edit.text, "INT. LAB - MORNING - ")
    }

    func testTextAfterTheCaretKeepsItsSingleSpace() throws {
        let edit = try XCTUnwrap(spacing("INT. BASEMENT MORNING", replacing: NSRange(location: 13, length: 1)))
        XCTAssertEqual(edit.text, "INT. BASEMENT - MORNING")
        XCTAssertEqual(edit.caret, 16)
    }

    /// Nothing to divide: the dash is just a dash.
    func testADashOpeningAHeadingIsLeftAlone() {
        XCTAssertNil(spacing("", replacing: NSRange(location: 0, length: 0)))
        XCTAssertNil(spacing("   ", replacing: NSRange(location: 3, length: 0)))
    }

    /// A writer reaching for something else — "--" — is not writing a second
    /// separator, and should not be given one.
    func testADashAfterADashIsLeftAlone() {
        XCTAssertNil(spacing("INT. LAB -", replacing: NSRange(location: 10, length: 0)))
        XCTAssertNil(spacing("INT. LAB - ", replacing: NSRange(location: 11, length: 0)))
    }

    func testAnOutOfBoundsRangeIsRefused() {
        XCTAssertNil(spacing("INT. LAB", replacing: NSRange(location: 40, length: 0)))
        XCTAssertNil(spacing("INT. LAB", replacing: NSRange(location: 7, length: 9)))
    }

    // MARK: - Taking it back

    /// One delete against the separator, and the heading has the hyphen it
    /// wanted: INT. DRIVE-IN THEATER.
    func testOneDeleteCollapsesTheSeparatorToAHyphen() throws {
        let edit = try XCTUnwrap(
            SceneHeadingSeparator.collapsed(in: "INT. DRIVE - " as NSString, endingAt: 13)
        )
        XCTAssertEqual(edit.text, "INT. DRIVE-")
        XCTAssertEqual(edit.caret, 11, "the caret stays against the hyphen, ready for IN")
    }

    func testCollapsingKeepsWhateverFollowsTheCaret() throws {
        let edit = try XCTUnwrap(
            SceneHeadingSeparator.collapsed(in: "INT. DRIVE - THEATER" as NSString, endingAt: 13)
        )
        XCTAssertEqual(edit.text, "INT. DRIVE-THEATER")
    }

    /// Everywhere else, delete behaves as it always has.
    func testACaretNotAgainstASeparatorIsLeftAlone() {
        XCTAssertNil(SceneHeadingSeparator.collapsed(in: "INT. DRIVE - " as NSString, endingAt: 12))
        XCTAssertNil(SceneHeadingSeparator.collapsed(in: "INT. LAB" as NSString, endingAt: 8))
        XCTAssertNil(SceneHeadingSeparator.collapsed(in: "INT. LAB" as NSString, endingAt: 2))
        XCTAssertNil(SceneHeadingSeparator.collapsed(in: "INT. LAB" as NSString, endingAt: 40))
    }

    /// The two are exact inverses, which is what makes the escape hatch safe
    /// to offer: nothing is lost by taking the separator back.
    func testSpacingAndCollapsingAreInverses() throws {
        let spaced = try XCTUnwrap(spacing("INT. DRIVE", replacing: NSRange(location: 10, length: 0)))
        let collapsed = try XCTUnwrap(
            SceneHeadingSeparator.collapsed(in: spaced.text as NSString, endingAt: spaced.caret)
        )
        XCTAssertEqual(collapsed.text, "INT. DRIVE-")
    }
}
