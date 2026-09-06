import XCTest
@testable import EDraftCore

/// Grouping scene headings by where they play.
///
/// The point of every case here is that a writer's spelling should not decide
/// whether their scene shows up in a filter.
final class SceneSettingTests: XCTestCase {

    func testInteriorInEverySpelling() {
        for heading in ["INT. KITCHEN - DAY", "int. kitchen - day", "INT KITCHEN - DAY"] {
            XCTAssertEqual(SceneSetting(heading: heading), .interior, heading)
        }
    }

    func testExteriorInEverySpelling() {
        for heading in ["EXT. STREET - NIGHT", "ext. street", "EXT STREET - NIGHT"] {
            XCTAssertEqual(SceneSetting(heading: heading), .exterior, heading)
        }
    }

    /// The one the report named, and the one with the most spellings.
    func testTheCrossingCaseInEverySpelling() {
        for heading in [
            "I/E. CAR - DAY", "I/E CAR - DAY", "i/e car - day",
            "INT/EXT. CAR - DAY", "INT/EXT CAR - DAY",
            "INT./EXT. CAR - DAY", "INT./EXT CAR - DAY",
            "int./ext. car - day"
        ] {
            XCTAssertEqual(SceneSetting(heading: heading), .both, heading)
        }
    }

    /// An establishing shot is a shot of the outside of somewhere.
    func testEstablishingCountsAsExterior() {
        XCTAssertEqual(SceneSetting(heading: "EST. THE HOUSE - DAY"), .exterior)
    }

    /// A line with no intro token is not classified, rather than guessed at.
    func testAHeadingWithNoIntroTokenHasNoSetting() {
        XCTAssertNil(SceneSetting(heading: "LATER THAT NIGHT"))
        XCTAssertNil(SceneSetting(heading: ""))
        XCTAssertNil(SceneSetting(heading: "INTERIOR DECORATOR'S OFFICE"))
    }

    /// The word "interior" starting a line must not be read as INT.
    func testAWordBeginningWithIntIsNotAnInterior() {
        XCTAssertNil(SceneSetting(heading: "INTO THE WOODS"))
    }
}
