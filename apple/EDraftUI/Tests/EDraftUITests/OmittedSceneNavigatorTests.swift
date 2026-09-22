import EDraftCore
import XCTest
#if os(macOS)
import AppKit
#else
import UIKit
#endif
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

    // MARK: - The row's hover actions (IL-0087)

    /// The pointer on a row shows what the scene allows — and gives the
    /// trailing column up to it, rather than crowding the title.
    func testHoveringARowShowsItsActionsWhereThePageNumberWas() {
        let chrome = SceneRowChrome.of(actions: [.omit], hovering: true)
        XCTAssertTrue(chrome.showsActions)
        XCTAssertTrue(chrome.hidesTrailing)
    }

    func testAtRestTheRowIsJustTheRow() {
        let chrome = SceneRowChrome.of(actions: [.omit], hovering: false)
        XCTAssertFalse(chrome.showsActions)
        XCTAssertFalse(chrome.hidesTrailing, "the page number stays put")
    }

    /// No greyed placeholders: a row with nothing to offer — a Fountain
    /// document, a card typed by hand — shows nothing, hovered or not.
    func testARowWithNoActionsNeverShowsAnyChrome() {
        let chrome = SceneRowChrome.of(actions: [], hovering: true)
        XCTAssertFalse(chrome.showsActions)
        XCTAssertFalse(chrome.hidesTrailing)
    }

    /// A live scene offers Omit, a cut one Restore — the same names the
    /// menus and the Edit menu's Undo use, and marks from SF Symbols.
    func testTheActionsSpeakTheMenusNames() {
        XCTAssertEqual(SceneAction.omit.title, "Omit Scene")
        XCTAssertEqual(SceneAction.restore.title, "Restore Scene")
        #if os(macOS)
        XCTAssertNotNil(NSImage(systemSymbolName: SceneAction.omit.symbol, accessibilityDescription: nil))
        XCTAssertNotNil(NSImage(systemSymbolName: SceneAction.restore.symbol, accessibilityDescription: nil))
        #else
        XCTAssertNotNil(UIImage(systemName: SceneAction.omit.symbol))
        XCTAssertNotNil(UIImage(systemName: SceneAction.restore.symbol))
        #endif
    }

    /// Hiding the length to make room for the action is for the eye only:
    /// VoiceOver still hears how much was cut.
    func testTheCutLengthIsStillSpokenWhileTheActionShows() {
        let cut = row("OMITTED", number: "21", omitted: true, cut: "0.3 pgs CUT")
        let label = SceneRowLabel(scene: cut, hidesTrailing: true).spokenLabel
        XCTAssertTrue(label.contains("0.3 pages cut"), label)
    }
}
