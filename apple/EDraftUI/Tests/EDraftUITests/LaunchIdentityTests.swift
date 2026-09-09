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

}
