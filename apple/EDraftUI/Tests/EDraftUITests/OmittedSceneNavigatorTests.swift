import EDraftCore
import XCTest
@testable import EDraftUI

/// A cut scene in the Navigator — RFC-DRAFT-PRODUCTION §7.3.
///
/// An omission keeps the scene's number and its place in the list: that is
/// what an omission is, and a schedule that cites scene 21 still has to find
/// it. What changes is how the row reads — struck, inked back, and said out
/// loud, because a strike through type is not spoken.
@MainActor
final class OmittedSceneNavigatorTests: XCTestCase {

    private func row(_ title: String, number: String? = nil, omitted: Bool = false) -> SceneRow {
        SceneRow(
            id: UUID(), number: 21, page: 17, sceneNumber: number,
            title: title, elementIndex: 0, omitted: omitted
        )
    }

    // MARK: - How the row is drawn

    func testACutSceneIsStruckAndInkedBack() {
        let style = SceneRowStyle.of(row("OMITTED", number: "21", omitted: true), isSelected: false)
        XCTAssertTrue(style.struckThrough)
        XCTAssertEqual(style.ink, .omitted)
    }

    func testALiveSceneIsUntouched() {
        let style = SceneRowStyle.of(row("INT. KITCHEN - NIGHT"), isSelected: false)
        XCTAssertFalse(style.struckThrough)
        XCTAssertEqual(style.ink, .primary)
    }

    /// Selection still wins the colour — a row the writer is standing on
    /// reads as selected first — but a cut scene is still struck under it.
    func testSelectionWinsTheInkAndTheStrikeStays() {
        let style = SceneRowStyle.of(row("OMITTED", number: "21", omitted: true), isSelected: true)
        XCTAssertEqual(style.ink, .accent)
        XCTAssertTrue(style.struckThrough)
    }

    func testASecondarySlugIsStillASecondarySlug() {
        let style = SceneRowStyle.of(row("LATER"), isSelected: false)
        XCTAssertEqual(style.ink, .secondary, "a slug with no intro token")
        XCTAssertFalse(style.struckThrough)
    }

    // MARK: - And said out loud

    func testVoiceOverSaysAnOmittedSceneIsOmitted() {
        let label = SceneRowLabel(scene: row("OMITTED", number: "21", omitted: true))
        XCTAssertTrue(
            label.spokenLabel.contains("omitted"),
            "a strike is not spoken: \(label.spokenLabel)"
        )
        XCTAssertTrue(label.spokenLabel.contains("Scene 21"), "it keeps its number")
    }

    func testVoiceOverDoesNotCallALiveSceneOmitted() {
        let label = SceneRowLabel(scene: row("INT. KITCHEN - NIGHT"))
        XCTAssertFalse(label.spokenLabel.contains("omitted"))
    }
}
