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

    func testTheDeskIsDarkInBothAppearances() {
        // Not an oversight: on the phone this is a frame around a launch card,
        // and a ground the colour of paper would say nothing at all.
        for scheme in [ColorScheme.light, .dark] {
            XCTAssertLessThan(
                LaunchIdentity.desk.resolved(scheme).luminance,
                0.2,
                "the ground is a desk, not a page (\(scheme))"
            )
        }
    }

    /// The test that should have existed the first time. Asserting two colours
    /// are *different* passes for black on black; asserting one can be read on
    /// the other does not.
    func testTheLetteringCanBeReadOnTheDeskInBothAppearances() {
        for scheme in [ColorScheme.light, .dark] {
            let ground = LaunchIdentity.desk.resolved(scheme).luminance
            let lettering = LaunchIdentity.deskInk.luminance
            XCTAssertGreaterThan(
                lettering - ground,
                0.5,
                "unreadable in \(scheme): lettering \(lettering) on ground \(ground)"
            )
        }
    }

    func testTheMarginRuleIsVisibleAgainstTheDeskWithoutShouting() {
        for scheme in [ColorScheme.light, .dark] {
            let ground = LaunchIdentity.desk.resolved(scheme).luminance
            let rule = LaunchIdentity.rule.resolved(scheme).luminance
            XCTAssertGreaterThan(rule, ground, "the rule must be lighter than the desk")
            XCTAssertLessThan(
                rule - ground,
                0.25,
                "a weight you notice only if you look for it, not a stripe"
            )
        }
    }
}
