import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// The editor's banners in the Mac document window — IL-0099.
///
/// `EditorState.banner` was drawn only by the iPhone's capsule, so on the Mac
/// "Updated elsewhere", "A change from elsewhere couldn't be read" and a
/// refused edit said nothing at all. The window now docks a banner the way it
/// docks the page-lock notice (IL-0090): a titlebar accessory under the
/// toolbar, there until the writer dismisses it.
@MainActor
final class EditorBannerSurfaceTests: XCTestCase {

    private func window(_ editor: EditorState = EditorState(
        source: "INT. KITCHEN - NIGHT\n\nThe kettle screams."
    )) -> (EditorState, ScriptWindowController) {
        let controller = ScriptWindowController(editor: editor)
        settle()
        return (editor, controller)
    }

    /// The window follows the model on the main actor's next turn.
    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    }

    private func docked(_ controller: ScriptWindowController) -> [WindowNoticeAccessory] {
        controller.window?.titlebarAccessoryViewControllers.compactMap { $0 as? WindowNoticeAccessory } ?? []
    }

    func testNothingIsDockedAtOpen() {
        let (_, controller) = window()
        withExtendedLifetime(controller) {
            XCTAssertTrue(docked(controller).isEmpty)
            XCTAssertNil(controller.bannerAccessory)
        }
    }

    func testABannerDocksUnderTheToolbar() throws {
        let (editor, controller) = window()
        try withExtendedLifetime(controller) {
            let window = try XCTUnwrap(controller.window)
            let content = window.contentLayoutRect.height
            editor.showBanner("Updated elsewhere")
            settle()
            let accessory = try XCTUnwrap(controller.bannerAccessory, "the Mac shows the banner")
            XCTAssertEqual(docked(controller).count, 1)
            XCTAssertEqual(accessory.layoutAttribute, .bottom, "docked under the toolbar, not floated over the page")
            XCTAssertEqual(accessory.text, "Updated elsewhere")
            XCTAssertGreaterThan(accessory.view.frame.height, 0)
            XCTAssertLessThan(window.contentLayoutRect.height, content,
                              "the page is laid out below it — its height comes out of the content area")
        }
    }

    /// The model clears `banner` after 1.6 s for the iPhone's capsule. The
    /// docked strip stays until the writer puts it away.
    func testItOutlivesTheModelsTimerAndLeavesWhenDismissed() throws {
        let (editor, controller) = window()
        withExtendedLifetime(controller) {
            editor.showBanner("Updated elsewhere")
            settle()
            editor.banner = nil
            settle()
            XCTAssertEqual(docked(controller).count, 1, "still there once the model has let go of it")
            controller.dismissBanner()
            settle()
            XCTAssertTrue(docked(controller).isEmpty)
            XCTAssertNil(controller.bannerAccessory)
        }
    }

    func testANewerBannerReplacesTheWordsInOneStrip() throws {
        let (editor, controller) = window()
        try withExtendedLifetime(controller) {
            editor.showBanner("Updated elsewhere")
            settle()
            editor.showBanner("A change from elsewhere couldn't be read")
            settle()
            XCTAssertEqual(docked(controller).count, 1, "one strip, not a stack of them")
            XCTAssertEqual(try XCTUnwrap(controller.bannerAccessory).text,
                           "A change from elsewhere couldn't be read")
        }
    }

    /// The path a reload takes on the Mac: `ScreenplayDocument.read` hands the
    /// file to `applyExternalSource`, saying whether it came from elsewhere.
    func testAnOutsideChangeSaysSoAndTheWritersOwnRevertDoesNot() throws {
        let (editor, controller) = window()
        try withExtendedLifetime(controller) {
            editor.applyExternalSource("INT. KITCHEN - NIGHT\n\nThe kettle screams. Then silence.")
            settle()
            XCTAssertEqual(try XCTUnwrap(controller.bannerAccessory).text, "Updated elsewhere")
            controller.dismissBanner()
            settle()

            editor.applyExternalSource("INT. KITCHEN - NIGHT\n\nThe kettle is quiet.", announcing: false)
            settle()
            XCTAssertTrue(docked(controller).isEmpty, "a revert is not a change from elsewhere")
            XCTAssertEqual(editor.screenplay.elements.last?.text, "The kettle is quiet.")
        }
    }

    /// Two notices, two strips: putting the banner away leaves the page-lock
    /// warning where it is.
    func testItDocksBesideThePageLockNotice() throws {
        let fdx = Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        <Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
        <Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>
        </Content>
        <LockedPages>
        <LockedPage Deleted="0" LevelIndex="0" LockLevel="0" PageNumber="1" Position="0"/>
        </LockedPages>
        </FinalDraft>
        """.utf8)
        let file = try ScreenplayFile.open(fdx, as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let (_, controller) = window(editor)
        try withExtendedLifetime(controller) {
            var elements = editor.screenplay.elements
            elements[elements.count - 1].text += " Then silence."
            editor.replaceAllElements(elements, activeID: elements[elements.count - 1].id, offset: 0, structural: true)
            editor.showBanner("Updated elsewhere")
            settle()
            XCTAssertNotNil(controller.pageLockAccessory)
            XCTAssertNotNil(controller.bannerAccessory)
            XCTAssertEqual(docked(controller).count, 2)

            controller.dismissBanner()
            settle()
            XCTAssertEqual(docked(controller).count, 1)
            XCTAssertTrue(try XCTUnwrap(docked(controller).first) === controller.pageLockAccessory)
        }
    }
}
