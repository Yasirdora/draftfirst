import XCTest
@testable import EDraftCore

/// Master scenes and the slugs inside them.
///
/// A master heading opens with INT./EXT. and is a setup: it takes a scene
/// number, it appears on a schedule, a first AD breaks the day down by it. A
/// secondary slug names somewhere inside that setup. Both are typed as
/// headings — this only decides which way the Navigator leans.
@MainActor
final class SecondarySlugTests: XCTestCase {

    private func row(_ heading: String) -> SceneRow {
        SceneRow(
            id: UUID(), number: 1, page: 1, sceneNumber: nil,
            title: heading, elementIndex: 0
        )
    }

    func testAHeadingWithASettingIsAMasterScene() {
        for heading in [
            "INT. HOME LIBRARY - DAY",
            "EXT. GRAVEL ROAD - NIGHT",
            "I/E. CAR - CONTINUOUS",
            "INT./EXT. FERRY - DUSK",
            "int. kitchen - day"
        ] {
            XCTAssertFalse(row(heading).isSecondary, "\(heading) is a master scene")
        }
    }

    /// Taken from a real Final Draft feature: 29 of its 37 headings are these.
    func testASlugWithNoSettingReadsAsSecondary() {
        for heading in [
            "LATER",
            "DAWN",
            "BACK TO SCENE",
            "DOWN THE SLOPE",
            "DEEPER IN THE WOODS - CONTINUOUS",
            "BASE OF THE SLOPE"
        ] {
            XCTAssertTrue(row(heading).isSecondary, "\(heading) is a secondary slug")
        }
    }

    /// The one that must not be over-read. `INTO THE WOODS` opens with the
    /// letters of `INT` and is not a scene set indoors; the engine's own
    /// detector requires a separator after the token, which is why this is
    /// asked of `SceneSetting` rather than of a prefix match.
    func testAHeadingThatMerelyStartsWithTheLettersIsNotInterior() {
        XCTAssertTrue(row("INTO THE WOODS").isSecondary)
        XCTAssertTrue(row("EXTERIOR FEELINGS").isSecondary)
    }
}
