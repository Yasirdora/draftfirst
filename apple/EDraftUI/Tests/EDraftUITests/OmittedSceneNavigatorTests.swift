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

    private func row(
        _ title: String, number: String? = nil, omitted: Bool = false, cut: String? = nil
    ) -> SceneRow {
        SceneRow(
            id: UUID(), number: 21, page: 17, sceneNumber: number,
            title: title, elementIndex: 0, omitted: omitted, cutPages: cut
        )
    }

    // MARK: - How the row is drawn

    func testACutSceneIsInkedBackAndNotStruck() {
        let style = SceneRowStyle.of(row("OMITTED", number: "21", omitted: true), isSelected: false)
        XCTAssertEqual(style.ink, .omitted)
    }

    func testALiveSceneIsUntouched() {
        let style = SceneRowStyle.of(row("INT. KITCHEN - NIGHT"), isSelected: false)
        XCTAssertEqual(style.ink, .primary)
    }

    /// Selection still wins the colour — a row the writer is standing on
    /// reads as selected first.
    func testSelectionWinsTheInk() {
        let style = SceneRowStyle.of(row("OMITTED", number: "21", omitted: true), isSelected: true)
        XCTAssertEqual(style.ink, .accent)
    }

    func testASecondarySlugIsStillASecondarySlug() {
        let style = SceneRowStyle.of(row("LATER"), isSelected: false)
        XCTAssertEqual(style.ink, .secondary, "a slug with no intro token")
    }

    /// A cut scene has no page to turn to; the row shows what it cost.
    func testTheRowShowsTheCutLengthInsteadOfAPage() {
        let cut = row("OMITTED", number: "21", omitted: true, cut: "0.3 pgs CUT")
        XCTAssertEqual(cut.cutPages, "0.3 pgs CUT")
        XCTAssertNil(row("INT. KITCHEN - NIGHT").cutPages, "a live scene has none")
    }

    // MARK: - And said out loud

    func testVoiceOverSaysAnOmittedSceneIsOmittedAndWhatItCost() {
        let label = SceneRowLabel(scene: row("OMITTED", number: "21", omitted: true, cut: "0.3 pgs CUT"))
        /* The page stays: the card prints on 17, and that is where a reader
           turns to find it. */
        XCTAssertEqual(label.spokenLabel, "Scene 21, OMITTED, omitted, 0.3 pages cut, page 17")
    }

    func testVoiceOverDoesNotCallALiveSceneOmitted() {
        let label = SceneRowLabel(scene: row("INT. KITCHEN - NIGHT"))
        XCTAssertFalse(label.spokenLabel.contains("omitted"))
    }
}
