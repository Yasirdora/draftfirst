import EDraftCore
import XCTest
@testable import EDraftUI

/// Narrowing the Navigator's scene list. Matching, not classification —
/// `EditorState.scenes` already decided what a scene is.
@MainActor
final class SceneListFilterTests: XCTestCase {

    private func scenes() -> [SceneRow] {
        [
            SceneRow(id: UUID(), number: 1, page: 1, sceneNumber: nil,
                     title: "INT. KITCHEN - DAY", elementIndex: 0),
            SceneRow(id: UUID(), number: 2, page: 3, sceneNumber: "12A",
                     title: "EXT. ALLEY - NIGHT", elementIndex: 4),
            SceneRow(id: UUID(), number: 3, page: 4, sceneNumber: nil,
                     title: "INT. CAR - DAY", elementIndex: 8)
        ]
    }

    func testAnEmptyQueryLeavesEveryScene() {
        XCTAssertEqual(SceneListFilter.included(scenes(), query: "").count, 3)
        XCTAssertEqual(SceneListFilter.included(scenes(), query: "   ").count, 3)
    }

    func testATitleFragmentNarrowsTheList() {
        let found = SceneListFilter.included(scenes(), query: "alley")
        XCTAssertEqual(found.map(\.title), ["EXT. ALLEY - NIGHT"])
    }

    func testAProductionNumberMatchesTheLabel() {
        let found = SceneListFilter.included(scenes(), query: "12A")
        XCTAssertEqual(found.map(\.label), ["12A"])
    }

    func testNothingMatchingIsEmptyRatherThanGuessed() {
        XCTAssertTrue(SceneListFilter.included(scenes(), query: "warehouse").isEmpty)
    }
}

/// Narrowing by where a scene plays.
///
/// The classification is `SceneSetting`'s and tested there; this covers the
/// list behaviour — that the two narrowings compose, and that a scene with no
/// setting is hidden by one rather than swept in.
@MainActor
final class SceneSettingFilterTests: XCTestCase {

    private func scenes() -> [SceneRow] {
        [
            SceneRow(id: UUID(), number: 1, page: 1, sceneNumber: nil,
                     title: "INT. KITCHEN - DAY", elementIndex: 0),
            SceneRow(id: UUID(), number: 2, page: 3, sceneNumber: nil,
                     title: "EXT. ALLEY - NIGHT", elementIndex: 4),
            SceneRow(id: UUID(), number: 3, page: 4, sceneNumber: nil,
                     title: "I/E. CAR - DAY", elementIndex: 8),
            SceneRow(id: UUID(), number: 4, page: 5, sceneNumber: nil,
                     title: "INT./EXT. TRAIN - DUSK", elementIndex: 12),
            SceneRow(id: UUID(), number: 5, page: 6, sceneNumber: nil,
                     title: "THE LONG WAY ROUND", elementIndex: 16)
        ]
    }

    func testNoSettingLeavesEveryScene() {
        XCTAssertEqual(SceneListFilter.included(scenes(), query: "").count, 5)
    }

    func testInteriorsOnly() {
        let visible = SceneListFilter.included(scenes(), query: "", setting: .interior)
        XCTAssertEqual(visible.map(\.title), ["INT. KITCHEN - DAY"])
    }

    func testExteriorsOnly() {
        let visible = SceneListFilter.included(scenes(), query: "", setting: .exterior)
        XCTAssertEqual(visible.map(\.title), ["EXT. ALLEY - NIGHT"])
    }

    /// Both spellings of the crossing case land in the same bucket, which is
    /// the whole reason this is read through the engine.
    func testTheCrossingCaseGathersItsSpellings() {
        let visible = SceneListFilter.included(scenes(), query: "", setting: .both)
        XCTAssertEqual(visible.map(\.title), ["I/E. CAR - DAY", "INT./EXT. TRAIN - DUSK"])
    }

    /// A forced slug has no intro token, so it belongs to no setting. Asking
    /// for interiors and being handed one would be a wrong answer, not a
    /// generous one.
    func testASlugWithNoIntroTokenIsHiddenByAnySetting() {
        for setting in SceneSetting.allCases {
            let visible = SceneListFilter.included(scenes(), query: "", setting: setting)
            XCTAssertFalse(visible.contains { $0.title == "THE LONG WAY ROUND" }, "\(setting)")
        }
    }

    func testTheSearchAndTheFilterCompose() {
        let visible = SceneListFilter.included(scenes(), query: "CAR", setting: .both)
        XCTAssertEqual(visible.map(\.title), ["I/E. CAR - DAY"])

        XCTAssertTrue(
            SceneListFilter.included(scenes(), query: "KITCHEN", setting: .exterior).isEmpty,
            "a search inside a filter must not escape it"
        )
    }
}

/// Narrowing and ordering the Navigator's cast list. Matching, not
/// ranking — `EditorState.cast` already counted the cues; this covers
/// search and the two ways of looking at the same rows.
@MainActor
final class CastListFilterTests: XCTestCase {

    private func cast() -> [CastRow] {
        [
            CastRow(id: "WALT", name: "WALT", cues: 5, firstCueID: UUID()),
            CastRow(id: "ANNA", name: "ANNA", cues: 3, firstCueID: UUID()),
            CastRow(id: "MIKE", name: "MIKE", cues: 3, firstCueID: UUID())
        ]
    }

    func testAnEmptyQueryLeavesEveryone() {
        XCTAssertEqual(CastListFilter.included(cast(), query: "").count, 3)
        XCTAssertEqual(CastListFilter.included(cast(), query: "   ").count, 3)
    }

    func testLeadIsMostCuesThenName() {
        let visible = CastListFilter.included(cast(), query: "", sort: .lead)
        XCTAssertEqual(visible.map(\.name), ["WALT", "ANNA", "MIKE"])
    }

    func testAlphabeticalOrdersByName() {
        let visible = CastListFilter.included(cast(), query: "", sort: .alphabetical)
        XCTAssertEqual(visible.map(\.name), ["ANNA", "MIKE", "WALT"])
    }

    func testANameFragmentNarrowsTheList() {
        let found = CastListFilter.included(cast(), query: "ann")
        XCTAssertEqual(found.map(\.name), ["ANNA"])
    }

    func testNothingMatchingIsEmptyRatherThanGuessed() {
        XCTAssertTrue(CastListFilter.included(cast(), query: "warehouse").isEmpty)
    }

    func testTheSearchAndTheSortCompose() {
        let lead = CastListFilter.included(cast(), query: "a", sort: .lead)
        XCTAssertEqual(lead.map(\.name), ["WALT", "ANNA"])
        let alpha = CastListFilter.included(cast(), query: "a", sort: .alphabetical)
        XCTAssertEqual(alpha.map(\.name), ["ANNA", "WALT"])
    }
}
