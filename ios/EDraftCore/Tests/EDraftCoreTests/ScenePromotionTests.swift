import Foundation
import XCTest
@testable import EDraftCore

/// A line becomes a scene heading because Fountain says it is one.
///
/// These pin both halves: that the editor now agrees with its own parser, and
/// that it never overrules a writer who has already said what a line is.
final class ScenePromotionTests: XCTestCase {

    func testTheFourPrefixesFountainRecognises() {
        for text in ["INT. KITCHEN - DAY", "EXT. ROOFTOP - NIGHT",
                     "EST. THE CITY - DAWN", "I/E. CAR - CONTINUOUS",
                     "INT./EXT. VAN - DAY"] {
            XCTAssertEqual(
                ScenePromotion.kind(for: text, currently: .action), .scene,
                "“\(text)” is a scene heading in Fountain"
            )
        }
    }

    /// Case is the writer's business; the format's rule is not case-sensitive,
    /// and the casing memory will shout the line once it is a heading.
    func testItRecognisesALineBeforeItHasBeenCapitalised() {
        XCTAssertEqual(ScenePromotion.kind(for: "int. kitchen", currently: .action), .scene)
    }

    /// The moment the prefix completes, not before — a writer typing "INTO the
    /// room she goes" must never watch their action line become a slug.
    func testAWordThatMerelyStartsWithThoseLettersIsNotAHeading() {
        for text in ["INTO the room she goes.", "INTERIOR feelings.", "ESTATE agents wait."] {
            XCTAssertNil(ScenePromotion.kind(for: text, currently: .action))
        }
    }

    func testAnEmptyLineIsNothingYet() {
        XCTAssertNil(ScenePromotion.kind(for: "", currently: .action))
        XCTAssertNil(ScenePromotion.kind(for: "   ", currently: .action))
    }

    // MARK: - What it must never touch

    /// The whole reason this is a promotion and not a classifier: a writer who
    /// has chosen a kind has said something, and the app does not argue.
    func testAWriterWhoHasChosenAKindIsNotOverruled() {
        for kind in [ScreenplayKind.character, .dialogue, .parenthetical,
                     .transition, .scene, .shot, .lyrics] {
            XCTAssertNil(
                ScenePromotion.kind(for: "INT. KITCHEN - DAY", currently: kind),
                "a line the writer made \(kind.rawValue) stays \(kind.rawValue)"
            )
        }
    }

    func testItPromotesOnlyAndNeverDemotes() {
        // There is no path back: taking a heading away as a writer edits it
        // would make the line flicker between kinds mid-sentence.
        XCTAssertNil(ScenePromotion.kind(for: "She waits.", currently: .scene))
    }
}
