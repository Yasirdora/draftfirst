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
