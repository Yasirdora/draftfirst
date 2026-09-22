import AppKit
import EDraftCore
import EDraftEngine
import XCTest
@testable import EDraftMacSurface

/// Omitting and restoring a scene on the page — RFC-DRAFT-PRODUCTION §7.3,
/// IL-0087.
///
/// Three doors, one room: the Navigator row, the page's context menu and
/// Format ▸ Omit Scene all land on `performSceneAction`, which collapses
/// the scene to its card through the display path IL-0076 built, names its
/// undo, holds the page still and tells VoiceOver what happened.
@MainActor
final class OmitSceneCommandSurfaceTests: XCTestCase {

    /// Three numbered scenes, all live, in a Final Draft file.
    private func fdx(before: Int = 0, after: Int = 0) -> Data {
        let above = (0..<before).map { "<Paragraph Type=\"Action\"><Text>Before line \($0 + 1).</Text></Paragraph>" }
        let below = (0..<after).map { "<Paragraph Type=\"Action\"><Text>After line \($0 + 1).</Text></Paragraph>" }
        return Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        <Paragraph Number="20" Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
        <Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>
        \(above.joined(separator: "\n"))
        <Paragraph Number="21" Type="Scene Heading"><Text>EXT. THE YARD - DUSK</Text></Paragraph>
        <Paragraph Type="Action"><Text>Mara waits.</Text></Paragraph>
        <Paragraph Type="Character"><Text>MARA</Text></Paragraph>
        <Paragraph Type="Dialogue"><Text>Not yet.</Text></Paragraph>
        <Paragraph Number="22" Type="Scene Heading"><Text>INT. THE HALL - DAY</Text></Paragraph>
        <Paragraph Type="Action"><Text>She waits.</Text></Paragraph>
        \(below.joined(separator: "\n"))
        </Content>
        </FinalDraft>
        """.utf8)
    }

    private func opened(_ data: Data, width: CGFloat = 500, height: CGFloat = 400) throws -> (EditorState, ScriptSurface) {
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        return (editor, surface)
    }

    private func laid(_ surface: ScriptSurface) -> String {
        surface.textStorage.string
    }

    private func element(_ editor: EditorState, _ text: String) throws -> ScriptElement {
        try XCTUnwrap(editor.screenplay.elements.first { $0.text == text })
    }

    private func card(_ editor: EditorState) throws -> ScriptElement {
        try XCTUnwrap(editor.screenplay.elements.first { editor.omittedScenes.isCard($0) })
    }

    private func undo(_ surface: ScriptSurface) throws -> UndoManager {
        try XCTUnwrap(surface.undoManager(for: surface.textView))
    }

    private func contextMenu(_ surface: ScriptSurface, on text: String, atItsEnd: Bool = false) throws -> NSMenu? {
        let found = (laid(surface) as NSString).range(of: text)
        XCTAssertNotEqual(found.location, NSNotFound, "\(text) is not on the page")
        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        let at = atItsEnd ? NSMaxRange(found) : found.location + 1
        return surface.textView(surface.textView, menu: NSMenu(), for: event, at: at)
    }

    // MARK: - Omit, through the command

    func testOmitCollapsesTheSceneToItsCard() throws {
        let (editor, surface) = try opened(fdx())
        let yard = try element(editor, "EXT. THE YARD - DUSK")
        surface.performSceneAction(.omit, on: yard.id)

        XCTAssertTrue(laid(surface).contains("OMITTED"), "the card is on the page")
        for line in ["EXT. THE YARD - DUSK", "Mara waits.", "Not yet."] {
            XCTAssertFalse(laid(surface).contains(line), "\(line) is cut out of the flow")
        }
        XCTAssertTrue(laid(surface).contains("INT. THE HALL - DAY"))
        XCTAssertEqual(editor.omittedScenes.scenes.count, 1, "model state, not a view")
        let key = try XCTUnwrap(editor.omittedScenes.scenes.first?.key)
        XCTAssertFalse(surface.isOmissionExpanded(key), "put away, not open")
        XCTAssertEqual(surface.regionViews[key]?.collapsed, true, "the chevron's chrome is on the card")
    }

    func testRestoreGivesBackThePageExactly() throws {
        let (editor, surface) = try opened(fdx())
        let before = laid(surface)
        let elements = editor.screenplay.elements
        surface.performSceneAction(.omit, on: try element(editor, "EXT. THE YARD - DUSK").id)
        surface.performSceneAction(.restore, on: try card(editor).id)
        XCTAssertEqual(laid(surface), before, "byte for byte")
        XCTAssertEqual(editor.screenplay.elements, elements)
        XCTAssertTrue(editor.omittedScenes.isEmpty)
        XCTAssertTrue(surface.regionViews.isEmpty, "no chrome left behind")
    }

    // MARK: - Undo

    func testUndoIsNamedAndReversesAnOmit() throws {
        let (editor, surface) = try opened(fdx())
        let before = laid(surface)
        let elements = editor.screenplay.elements
        surface.performSceneAction(.omit, on: try element(editor, "EXT. THE YARD - DUSK").id)
        let omitted = laid(surface)
        let undo = try undo(surface)
        XCTAssertEqual(undo.undoActionName, "Omit Scene", "the Edit menu reads Undo Omit Scene")

        undo.undo()
        XCTAssertEqual(laid(surface), before)
        XCTAssertEqual(editor.screenplay.elements, elements)
        XCTAssertTrue(editor.omittedScenes.isEmpty, "the omission goes with the card")
        XCTAssertEqual(undo.redoActionName, "Omit Scene")

        undo.redo()
        XCTAssertEqual(laid(surface), omitted)
        XCTAssertEqual(editor.omittedScenes.scenes.count, 1)
    }

    func testUndoIsNamedAndReversesARestore() throws {
        let (editor, surface) = try opened(fdx())
        let undo = try undo(surface)
        /* Each command is its own event in the app; no run-loop event is
           delivered between these synchronous calls, so give each its group. */
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        surface.performSceneAction(.omit, on: try element(editor, "EXT. THE YARD - DUSK").id)
        undo.endUndoGrouping()
        let omitted = laid(surface)
        let omissions = editor.omittedScenes
        undo.beginUndoGrouping()
        surface.performSceneAction(.restore, on: try card(editor).id)
        undo.endUndoGrouping()
        XCTAssertEqual(undo.undoActionName, "Restore Scene")
        undo.undo()
        XCTAssertEqual(laid(surface), omitted)
        XCTAssertEqual(editor.omittedScenes, omissions)
    }

    // MARK: - The context menu

    func testRightClickingAHeadingOffersOmitAndACardOffersRestore() throws {
        let (editor, surface) = try opened(fdx())
        let onHeading = try contextMenu(surface, on: "EXT. THE YARD - DUSK")
        XCTAssertEqual(onHeading?.item(at: 1)?.title, "Omit Scene")
        XCTAssertEqual(onHeading?.item(at: 0)?.title, "Add Note", "added to the menu, not replacing it")

        let onDialogue = try contextMenu(surface, on: "Not yet.")
        XCTAssertNil(onDialogue?.items.first { $0.title == "Omit Scene" }, "the command is on the heading")

        surface.performSceneAction(.omit, on: try element(editor, "EXT. THE YARD - DUSK").id)
        let onCard = try contextMenu(surface, on: "OMITTED")
        XCTAssertEqual(onCard?.item(at: 1)?.title, "Restore Scene")
        XCTAssertNil(onCard?.items.first { $0.title == "Omit Scene" })

        /* Past the word, where the hidden lines' empty ranges sit: still the
           card's line, still its menu. */
        let pastTheWord = try contextMenu(surface, on: "OMITTED", atItsEnd: true)
        let restore = try XCTUnwrap(pastTheWord?.items.first { $0.title == "Restore Scene" })
        _ = (restore.target as? NSObject)?.perform(restore.action, with: restore)
        XCTAssertTrue(editor.omittedScenes.isEmpty, "restored from the card's line")
    }

    func testTheContextMenuItemCarriesTheCommandOut() throws {
        let (editor, surface) = try opened(fdx())
        let menu = try XCTUnwrap(try contextMenu(surface, on: "EXT. THE YARD - DUSK"))
        let item = try XCTUnwrap(menu.items.first { $0.title == "Omit Scene" })
        _ = (item.target as? NSObject)?.perform(item.action, with: item)
        XCTAssertEqual(editor.omittedScenes.scenes.count, 1)
    }

    func testAFountainDocumentOffersNoOmitOnThePage() throws {
        let editor = EditorState(source: "INT. KITCHEN - NIGHT\n\nThe kettle screams.\n\nEXT. THE YARD - DUSK\n\nMara waits.\n")
        editor.attachImportedNotes(from: nil)
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        let menu = try contextMenu(surface, on: "EXT. THE YARD - DUSK")
        XCTAssertNil(menu?.items.first { $0.title == "Omit Scene" },
                     "a context menu shows only what applies; Format ▸ Omit Scene says why")
        let yard = try element(editor, "EXT. THE YARD - DUSK")
        surface.performSceneAction(.omit, on: yard.id)
        XCTAssertTrue(editor.omittedScenes.isEmpty, "and no door omits here")
    }

    // MARK: - The menu bar

    func testTheMenuBarItemFollowsTheCaret() throws {
        let file = try ScreenplayFile.open(fdx(), as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let controller = ScriptWindowController(editor: editor)
        try withExtendedLifetime(controller) {
            let item = ScriptMenus.omitSceneItem()
            editor.jump(to: try element(editor, "Not yet.").id)
            XCTAssertTrue(controller.validateMenuItem(item))
            XCTAssertEqual(item.title, "Omit Scene")

            controller.toggleSceneOmission(item)
            XCTAssertEqual(editor.omittedScenes.scenes.count, 1, "the menu bar omits the caret's scene")
            XCTAssertTrue(controller.validateMenuItem(item))
            XCTAssertEqual(item.title, "Restore Scene", "on the card the same item restores")

            controller.toggleSceneOmission(item)
            XCTAssertTrue(editor.omittedScenes.isEmpty, "and restores it from the card")
        }
    }

    func testTheMenuBarItemIsDimmedWithItsReasonInAFountainDocument() {
        let editor = EditorState(source: "INT. KITCHEN - NIGHT\n\nThe kettle screams.\n")
        editor.attachImportedNotes(from: nil)
        let controller = ScriptWindowController(editor: editor)
        withExtendedLifetime(controller) {
            let item = ScriptMenus.omitSceneItem()
            editor.jump(to: editor.screenplay.elements[1].id)
            XCTAssertFalse(controller.validateMenuItem(item))
            XCTAssertEqual(item.title, "Omit Scene")
            XCTAssertEqual(item.toolTip, "Omissions are kept in Final Draft (.fdx) files.")
        }
    }

    // MARK: - The caret and the page

    func testTheCaretLandsOnTheCardAndBackOnTheHeading() throws {
        let (editor, surface) = try opened(fdx())
        let yard = try element(editor, "EXT. THE YARD - DUSK")
        surface.performSceneAction(.omit, on: yard.id)
        let card = try card(editor)
        XCTAssertEqual(editor.activeElementID, card.id)
        let cardAt = (laid(surface) as NSString).range(of: "OMITTED")
        XCTAssertEqual(surface.selectionTextView.selectedRange().location, cardAt.location,
                       "the caret sits on the card — never at its end, where the cut lines are")

        surface.performSceneAction(.restore, on: card.id)
        XCTAssertEqual(editor.activeElementID, yard.id)
        let headingAt = (laid(surface) as NSString).range(of: "EXT. THE YARD - DUSK").location
        XCTAssertEqual(surface.selectionTextView.selectedRange().location, headingAt)
    }

    func testThePageDoesNotMoveWhenASceneBelowTheTopIsCut() throws {
        let (editor, surface) = try opened(fdx(before: 30, after: 30), height: 300)
        let clip = surface.scrollView.contentView
        let before = (laid(surface) as NSString).range(of: "Before line 20.").location
        let rect = try XCTUnwrap(ScriptLayout.boundingRect(of: NSRange(location: before, length: 1), in: surface.textView))
        clip.scroll(to: NSPoint(x: 0, y: surface.canvas.convert(rect, from: surface.textView).minY))
        surface.scrollView.reflectScrolledClipView(clip)
        let held = clip.bounds.origin.y

        surface.performSceneAction(.omit, on: try element(editor, "EXT. THE YARD - DUSK").id)
        XCTAssertEqual(clip.bounds.origin.y, held, accuracy: 1, "the line at the top of the glass stays put")
        surface.performSceneAction(.restore, on: try card(editor).id)
        XCTAssertEqual(clip.bounds.origin.y, held, accuracy: 1)
    }

    func testOmitOnPageSheets() throws {
        let arrangement = PageArrangement.stored
        let mode = PageLayoutMode.stored
        PageArrangement.store(.single)
        PageLayoutMode.store(.pages)
        defer {
            PageArrangement.store(arrangement)
            PageLayoutMode.store(mode)
        }
        let file = try ScreenplayFile.open(fdx(before: 30, after: 30), as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let surface = ScriptSurface(multiContainerSpreadEnabled: true)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1500, height: 1100)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        surface.setArrangement(.spread)
        surface.scrollView.layoutSubtreeIfNeeded()
        XCTAssertTrue(surface.usesPageSheets)

        let before = laid(surface)
        surface.performSceneAction(.omit, on: try element(editor, "EXT. THE YARD - DUSK").id)
        XCTAssertFalse(laid(surface).contains("Mara waits."))
        let key = try XCTUnwrap(editor.omittedScenes.scenes.first?.key)
        XCTAssertNotNil(surface.regionViews[key], "the card's chrome is placed on its sheet")
        surface.performSceneAction(.restore, on: try card(editor).id)
        XCTAssertEqual(laid(surface), before)
    }

    // MARK: - VoiceOver

    func testVoiceOverHearsWhatHappened() throws {
        let (editor, surface) = try opened(fdx())
        surface.performSceneAction(.omit, on: try element(editor, "EXT. THE YARD - DUSK").id)
        let omitted = try XCTUnwrap(surface.lastAnnouncement)
        XCTAssertTrue(omitted.hasPrefix("Scene 21 omitted, "), omitted)
        XCTAssertTrue(omitted.hasSuffix(" pages cut"), omitted)
        surface.performSceneAction(.restore, on: try card(editor).id)
        XCTAssertEqual(surface.lastAnnouncement, "Scene 21 restored")
    }

    func testTheCardOffersRestoreToVoiceOver() throws {
        let (editor, surface) = try opened(fdx())
        surface.performSceneAction(.omit, on: try element(editor, "EXT. THE YARD - DUSK").id)
        let key = try XCTUnwrap(editor.omittedScenes.scenes.first?.key)
        let region = try XCTUnwrap(surface.regionViews[key])
        let action = try XCTUnwrap(region.accessibilityCustomActions()?.first)
        XCTAssertEqual(action.name, "Restore Scene")
        XCTAssertTrue(action.handler?() ?? false)
        XCTAssertTrue(editor.omittedScenes.isEmpty, "restored from the card itself")
    }
}
