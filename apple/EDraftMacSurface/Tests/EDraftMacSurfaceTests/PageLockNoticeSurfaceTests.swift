import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// The Final Draft page-lock notice in the document window — IL-0090.
///
/// Docked under the toolbar, never floated over the page: a titlebar
/// accessory, whose height AppKit takes out of the content area. It arrives
/// with the writer's first edit of a locked file, goes when dismissed, and
/// does not come back in the same session.
@MainActor
final class PageLockNoticeSurfaceTests: XCTestCase {

    private func fdx(locks: Bool) -> Data {
        let block = locks ? """
        <LockedPages>
        <LockedPage Deleted="0" LevelIndex="0" LockLevel="0" PageNumber="1" Position="0"/>
        <LockedPage Deleted="0" LevelIndex="1" LockLevel="0" PageNumber="2" Position="140"/>
        </LockedPages>
        """ : ""
        return Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        <Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
        <Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>
        </Content>
        \(block)
        </FinalDraft>
        """.utf8)
    }

    private func window(locks: Bool) throws -> (EditorState, ScriptWindowController) {
        let file = try ScreenplayFile.open(fdx(locks: locks), as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let controller = ScriptWindowController(editor: editor)
        settle()
        return (editor, controller)
    }

    /// The window follows the model on the main actor's next turn.
    private func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
    }

    private func edit(_ editor: EditorState) {
        var elements = editor.screenplay.elements
        let last = elements.count - 1
        elements[last].text += " Then silence."
        editor.replaceAllElements(elements, activeID: elements[last].id, offset: 0, structural: true)
        settle()
    }

    private func docked(_ controller: ScriptWindowController) -> [PageLockNoticeAccessory] {
        controller.window?.titlebarAccessoryViewControllers.compactMap { $0 as? PageLockNoticeAccessory } ?? []
    }

    func testNothingIsDockedAtOpen() throws {
        let (_, controller) = try window(locks: true)
        withExtendedLifetime(controller) {
            XCTAssertEqual(docked(controller).count, 0)
        }
    }

    func testTheFirstEditDocksItUnderTheToolbar() throws {
        let (editor, controller) = try window(locks: true)
        try withExtendedLifetime(controller) {
            let window = try XCTUnwrap(controller.window)
            let content = window.contentLayoutRect.height
            edit(editor)
            let accessory = try XCTUnwrap(docked(controller).first)
            XCTAssertEqual(docked(controller).count, 1)
            XCTAssertEqual(accessory.layoutAttribute, .bottom, "docked under the toolbar, not floated over the desk")
            XCTAssertEqual(accessory.text, EditorState.pageLockNoticeText)
            XCTAssertGreaterThan(accessory.view.frame.height, 0)
            XCTAssertLessThan(window.contentLayoutRect.height, content,
                              "the page is laid out below it — its height comes out of the content area")
        }
    }

    func testANarrowWindowWrapsTheWordsRatherThanCuttingThem() throws {
        let (editor, controller) = try window(locks: true)
        try withExtendedLifetime(controller) {
            edit(editor)
            let accessory = try XCTUnwrap(docked(controller).first)
            accessory.fit(width: 2000)
            let wide = accessory.view.frame.height
            accessory.fit(width: 420)
            XCTAssertGreaterThan(accessory.view.frame.height, wide, "two lines where one would not fit")
        }
    }

    func testDismissedItLeavesAndDoesNotComeBack() throws {
        let (editor, controller) = try window(locks: true)
        withExtendedLifetime(controller) {
            edit(editor)
            XCTAssertEqual(docked(controller).count, 1)
            editor.dismissPageLockNotice()
            settle()
            XCTAssertEqual(docked(controller).count, 0)
            XCTAssertNil(controller.pageLockAccessory)
            edit(editor)
            XCTAssertEqual(docked(controller).count, 0, "once per document per session")
        }
    }

    func testAFileWithoutLocksNeverShowsIt() throws {
        let (editor, controller) = try window(locks: false)
        withExtendedLifetime(controller) {
            edit(editor)
            XCTAssertEqual(docked(controller).count, 0)
        }
    }
}
