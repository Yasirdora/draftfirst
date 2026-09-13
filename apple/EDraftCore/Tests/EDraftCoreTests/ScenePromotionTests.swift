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

    // MARK: - The cards (RFC-SECONDARY-SLUG §5)

    /// The writer's hand spells the card OMIT or OMITTED, one period
    /// tolerated, in any case; the line becomes the scene the navigator
    /// shows, and numbering keeps its number. The text itself is never
    /// rewritten.
    func testTheOmittedCardPromotesInTheWritersOwnSpellings() {
        for text in ["OMITTED", "OMITTED.", "Omit", "omitted", "OMIT", "omit"] {
            XCTAssertEqual(
                ScenePromotion.kind(for: text, currently: .action), .scene,
                "“\(text)” is the OMITTED card"
            )
        }
    }

    /// "Omitting" is a word in a sentence, not the card.
    func testAWordThatMerelyStartsWithOmitIsNotTheCard() {
        XCTAssertNil(ScenePromotion.kind(for: "OMITTING the obvious, she goes on.", currently: .action))
    }

    func testTheClosingCardPromotes() {
        for text in ["THE END", "THE END.", "The End", "the end"] {
            XCTAssertEqual(
                ScenePromotion.kind(for: text, currently: .action), .centered,
                "“\(text)” is the closing card"
            )
        }
    }

    func testASentenceThatMerelyEndsOnTheWordsIsNotTheClosingCard() {
        XCTAssertNil(ScenePromotion.kind(for: "THE END OF A THIRTY FOOT METAL POLE-", currently: .action))
    }

    /// The dash form keeps the uppercase gate even in the writer's own hand
    /// (D6): the convention that slugs are typed in caps is the signal.
    func testTheSecondarySlugPromotesUppercaseOnly() {
        XCTAssertEqual(ScenePromotion.kind(for: "BASIN - DAY", currently: .action), .scene)
        XCTAssertEqual(ScenePromotion.kind(for: "COURTYARD - 1612 HAVENHURST - DAY", currently: .action), .scene)
        XCTAssertNil(ScenePromotion.kind(for: "Basin - Day", currently: .action))
    }

    /// The whole-line LATER card is the writer's plain intent, read in any
    /// case (D6) — and only the quantity family: "LATER THAT NIGHT" carries
    /// no unit before LATER and stays action.
    func testTheLaterCardPromotesInAnyCase() {
        XCTAssertEqual(ScenePromotion.kind(for: "MINUTES LATER", currently: .action), .scene)
        XCTAssertEqual(ScenePromotion.kind(for: "A few minutes later", currently: .action), .scene)
        XCTAssertEqual(ScenePromotion.kind(for: "FOUR YEARS LATER", currently: .action), .scene)
        XCTAssertNil(ScenePromotion.kind(for: "LATER THAT NIGHT", currently: .action))
        XCTAssertNil(ScenePromotion.kind(for: "SEE YOU LATER", currently: .action))
    }

    /// The cards respect the writer who has chosen, the way the slug does.
    func testTheCardsNeverOverruleAChosenKind() {
        XCTAssertNil(ScenePromotion.kind(for: "THE END", currently: .dialogue))
        XCTAssertNil(ScenePromotion.kind(for: "OMITTED", currently: .character))
        XCTAssertNil(ScenePromotion.kind(for: "MINUTES LATER", currently: .transition))
    }
}
