import SwiftUI
import XCTest
@testable import EDraftUI

/// The launch ground, checked against the craft rather than against itself.
///
/// Asserting that a colour is the colour we wrote down proves nothing. These
/// ask the questions a screenwriter would: is the rule where a screenplay's
/// text actually begins, is the revision run the sequence a production really
/// reprints in, and can the page be read in both appearances.
final class LaunchIdentityTests: XCTestCase {

    func testTheMarginRuleSitsWhereAScreenplaysTextBegins() {
        // An 8.5 inch page, and the text block starts at 1.5 inches.
        XCTAssertEqual(
            LaunchIdentity.marginRuleFraction * 8.5,
            1.5,
            accuracy: 0.0001,
            "the rule is the margin, not a line near it"
        )
    }

    func testTheRevisionRunIsTheWholeProductionSequence() {
        // White, blue, pink, yellow, green, goldenrod, salmon, cherry, buff —
        // the order a script reprints in. A short run would be a gradient.
        XCTAssertEqual(LaunchIdentity.revisionRun.count, 9)
    }

    func testTheGroundAnswersToBothAppearances() {
        XCTAssertNotEqual(
            LaunchIdentity.paper.resolved(.light),
            LaunchIdentity.paper.resolved(.dark),
            "a ground that ignores the appearance has no edge in one of them"
        )
        XCTAssertNotEqual(
            LaunchIdentity.ink.resolved(.light),
            LaunchIdentity.ink.resolved(.dark)
        )
    }

    func testInkAndPaperAreNotTheSameColourInEitherAppearance() {
        for scheme in [ColorScheme.light, .dark] {
            XCTAssertNotEqual(
                LaunchIdentity.ink.resolved(scheme),
                LaunchIdentity.paper.resolved(scheme),
                "unreadable in \(scheme)"
            )
        }
    }
}
