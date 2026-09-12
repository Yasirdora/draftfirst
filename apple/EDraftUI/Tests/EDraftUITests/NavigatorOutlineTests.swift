import EDraftCore
import XCTest
@testable import EDraftUI

/// The Navigator's outline merge: acts as top-level entries, scenes beneath
/// the one that owns them (RFC-ACT-BREAK §6). Pure over the two row lists,
/// so no view is drawn to pin it.
@MainActor
final class NavigatorOutlineTests: XCTestCase {

    private func act(_ title: String, _ index: Int, ordinal: Int) -> ActRow {
        ActRow(id: UUID(), ordinal: ordinal, title: title, elementIndex: index,
               firstPage: nil, lastPage: nil)
    }

    private func scene(_ title: String, _ index: Int, number: Int) -> SceneRow {
        SceneRow(id: UUID(), number: number, page: nil, sceneNumber: nil,
                 title: title, elementIndex: index)
    }

    private func kinds(_ rows: [NavigatorOutline.Row]) -> [String] {
        rows.map { row in
            switch row {
            case .act(let act): "act:\(act.title)"
            case .scene(let scene): "scene:\(scene.title)"
            }
        }
    }

    func testAScriptWithoutActsGetsTheSceneListItAlwaysHad() {
        let scenes = [scene("INT. A - DAY", 0, number: 1), scene("INT. B - DAY", 4, number: 2)]
        let rows = NavigatorOutline.rows(acts: [], scenes: scenes)
        XCTAssertEqual(rows, scenes.map(NavigatorOutline.Row.scene))
    }

    func testScenesBeforeTheFirstCardBelongToNoActAndSitAboveIt() {
        let rows = NavigatorOutline.rows(
            acts: [act("ACT ONE", 2, ordinal: 1)],
            scenes: [scene("INT. COLD - DAY", 0, number: 1), scene("INT. OPEN - DAY", 3, number: 2)]
        )
        XCTAssertEqual(kinds(rows), [
            "scene:INT. COLD - DAY", "act:ACT ONE", "scene:INT. OPEN - DAY"
        ])
    }

    func testScenesLandBeneathTheActThatOwnsThem() {
        let rows = NavigatorOutline.rows(
            acts: [act("ACT ONE", 1, ordinal: 1), act("ACT TWO", 5, ordinal: 2)],
            scenes: [
                scene("INT. A - DAY", 2, number: 1),
                scene("INT. B - DAY", 3, number: 2),
                scene("INT. C - DAY", 6, number: 3)
            ]
        )
        XCTAssertEqual(kinds(rows), [
            "act:ACT ONE", "scene:INT. A - DAY", "scene:INT. B - DAY",
            "act:ACT TWO", "scene:INT. C - DAY"
        ])
    }

    func testActsWithoutScenesStillList() {
        let rows = NavigatorOutline.rows(
            acts: [act("ACT ONE", 0, ordinal: 1), act("ACT TWO", 2, ordinal: 2)],
            scenes: []
        )
        XCTAssertEqual(kinds(rows), ["act:ACT ONE", "act:ACT TWO"])
    }

    func testAnEmptyActIsFollowedImmediatelyByTheNext() {
        let rows = NavigatorOutline.rows(
            acts: [act("ACT ONE", 0, ordinal: 1), act("ACT TWO", 1, ordinal: 2)],
            scenes: [scene("INT. A - DAY", 2, number: 1)]
        )
        XCTAssertEqual(kinds(rows), ["act:ACT ONE", "act:ACT TWO", "scene:INT. A - DAY"])
    }
}
