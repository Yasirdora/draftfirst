import AppKit
import EDraftCore
import EDraftEngine
import XCTest
@testable import EDraftMacSurface

/// Editing below a collapsed cut scene — IL-0095.
///
/// A collapsed cut's lines are in the model and not in the text view, so a
/// character position in the view is not a position in the model. The edit
/// planner and the native-text sync were handed every element and a range
/// in the view's text: below a cut, Return split the hidden scene heading, a
/// paste landed inside it, Backspace ate its last letter, and a dead-key
/// accent — any composed character — deleted the cut scene outright. A
/// keystroke at the card's end overwrote the hidden heading.
///
/// The oracle is the same file with the cut opened. Open, every line is on
/// the page and positions agree, so whatever an edit does there is what it
/// must do when the cut is closed — and the cut must still stand behind its
/// card. Every test runs on Single pages and on Two Pages' page sheets.
@MainActor
final class CollapsedCutEditTests: XCTestCase {

    /// A cut scene between two live lines above and two below.
    private func fdx() -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        <Paragraph Type="Scene Heading"><Text>INT. LAB - DAY</Text></Paragraph>
        <Paragraph Type="Action"><Text>She waits.</Text></Paragraph>
        <Paragraph Number="21" Type="Scene Heading">
        <Text>OMITTED</Text>
        <OmittedScene>
        <Paragraph Type="Scene Heading"><Text>EXT. THE YARD - DUSK</Text></Paragraph>
        <Paragraph Type="Action"><Text>Mara waits.</Text></Paragraph>
        </OmittedScene>
        </Paragraph>
        <Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>
        <Paragraph Type="Action"><Text>It boils over.</Text></Paragraph>
        </Content>
        </FinalDraft>
        """.utf8)
    }

    /// Hold the editor: the surface keeps it weakly. The window makes the
    /// dead key real — marked text needs a first responder.
    private struct Opened {
        let editor: EditorState
        let surface: ScriptSurface
        let window: NSWindow
    }

    /// Runs `body` with the page arrangement put back afterwards: the tests
    /// share one defaults domain, and `setArrangement` stores the choice.
    private func keepingArrangement(_ body: () throws -> Void) rethrows {
        let arrangement = PageArrangement.stored
        let mode = PageLayoutMode.stored
        defer {
            PageArrangement.store(arrangement)
            PageLayoutMode.store(mode)
        }
        try body()
    }

    private func opened(sheets: Bool, cutOpen: Bool) throws -> Opened {
        let file = try ScreenplayFile.open(fdx(), as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        surface.setLayoutMode(.pages)
        surface.setArrangement(sheets ? .spread : .single)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface.scrollView
        XCTAssertEqual(surface.usesPageSheets, sheets)
        let key = try XCTUnwrap(editor.omittedScenes.scenes.first?.key)
        if cutOpen { surface.toggleOmission(key) }
        XCTAssertEqual(laid(surface).contains("Mara waits."), cutOpen)
        return Opened(editor: editor, surface: surface, window: window)
    }

    private func laid(_ surface: ScriptSurface) -> String { surface.textStorage.string }

    private func location(of needle: String, _ surface: ScriptSurface) throws -> Int {
        let at = (laid(surface) as NSString).range(of: needle).location
        XCTAssertNotEqual(at, NSNotFound, needle)
        return at
    }

    /// The keyboard's road: the delegate, then the storage only when it
    /// agrees, then the change — through the view that holds the text.
    private func type(_ text: String, replacing range: NSRange, in surface: ScriptSurface) {
        let view = surface.textView(atCharacter: range.location)
        view.setSelectedRange(range)
        guard surface.textView(view, shouldChangeTextIn: range, replacementString: text) else { return }
        view.textStorage?.replaceCharacters(in: range, with: text)
        view.setSelectedRange(NSRange(location: range.location + (text as NSString).length, length: 0))
        surface.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
    }

    /// A dead key: ⌥E, then e — marked text, then its commit, which is the
    /// road every composed character takes (IME included).
    private func deadKeyAccent(at location: Int, in opened: Opened) {
        let view = opened.surface.textView(atCharacter: location)
        XCTAssertTrue(opened.window.makeFirstResponder(view))
        view.setSelectedRange(NSRange(location: location, length: 0))
        view.setMarkedText("´", selectedRange: NSRange(location: 1, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        view.insertText("é", replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// Where the caret stands, as the writer sees it: the line it is on and
    /// its column there. Not a character number — a closed cut shifts those.
    private func caretPlace(_ surface: ScriptSurface) -> String {
        let text = laid(surface) as NSString
        let caret = min(surface.selectionTextView.selectedRange().location, text.length)
        let line = text.lineRange(for: NSRange(location: caret, length: 0))
        let words = text.substring(with: line).trimmingCharacters(in: .newlines)
        return "\"\(words)\" @\(caret - line.location)"
    }

    private func lines(_ editor: EditorState) -> [String] {
        editor.screenplay.elements.map { "\($0.type): \($0.text)" }
    }

    /// The cut scene, whole and behind its card — the shape the save keeps.
    private func assertTheCutStands(
        _ editor: EditorState, _ step: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let elements = editor.screenplay.elements
        let cardID = editor.omittedScenes.scenes.first?.card
        guard let card = elements.firstIndex(where: { $0.draftID != nil && $0.draftID == cardID }),
              card + 2 < elements.count else {
            return XCTFail("\(step): no card — \(lines(editor))", file: file, line: line)
        }
        XCTAssertEqual(elements[card + 1].text, "EXT. THE YARD - DUSK", "\(step): \(lines(editor))", file: file, line: line)
        XCTAssertEqual(elements[card + 2].text, "Mara waits.", "\(step): \(lines(editor))", file: file, line: line)
        XCTAssertEqual(Omissions.spans(of: editor.omittedScenes, in: elements).count, 1,
                       "\(step): the save would write the cut live", file: file, line: line)
    }

    /// Makes `edit` with the cut closed and with it open, and holds the
    /// closed result to the open one: the same lines, and the cut intact.
    private func assertSameEditOpenAndClosed(
        _ step: String, sheets: Bool, file: StaticString = #filePath, line: UInt = #line,
        _ edit: (Opened) throws -> Void
    ) throws {
        try keepingArrangement {
            let closed = try opened(sheets: sheets, cutOpen: false)
            defer { closed.window.close() }
            let open = try opened(sheets: sheets, cutOpen: true)
            defer { open.window.close() }
            try edit(closed)
            try edit(open)
            let path = sheets ? "Two Pages" : "Single pages"
            XCTAssertEqual(lines(closed.editor), lines(open.editor),
                           "\(step) (\(path)): the closed cut changed what the edit did", file: file, line: line)
            XCTAssertEqual(caretPlace(closed.surface), caretPlace(open.surface),
                           "\(step) (\(path)): the caret landed somewhere else", file: file, line: line)
            assertTheCutStands(closed.editor, "\(step) (\(path))", file: file, line: line)
            XCTAssertEqual(ScreenplayEditPlanner.flattenedText(closed.surface.laidElements(closed.editor.screenplay.elements)),
                           laid(closed.surface), "\(step) (\(path)): the page and the model disagree", file: file, line: line)
        }
    }

    // MARK: - The four roads the brief names

    func testReturnBelowAClosedCutSplitsTheLineTheCaretIsOn() throws {
        for sheets in [false, true] {
            try assertSameEditOpenAndClosed("Return", sheets: sheets) { opened in
                let at = try location(of: "The kettle", opened.surface) + 3
                type("\n", replacing: NSRange(location: at, length: 0), in: opened.surface)
            }
        }
    }

    func testBackspaceAtAnElementStartBelowAClosedCutJoinsThoseTwoLines() throws {
        for sheets in [false, true] {
            try assertSameEditOpenAndClosed("Backspace", sheets: sheets) { opened in
                let start = try location(of: "It boils", opened.surface)
                opened.surface.textView(atCharacter: start).setSelectedRange(NSRange(location: start, length: 0))
                type("", replacing: NSRange(location: start - 1, length: 1), in: opened.surface)
            }
        }
    }

    func testAPasteBelowAClosedCutLandsWhereTheCaretIs() throws {
        for sheets in [false, true] {
            try assertSameEditOpenAndClosed("Paste", sheets: sheets) { opened in
                let at = try location(of: "It boils", opened.surface)
                type("A door slams.\nNobody moves.", replacing: NSRange(location: at, length: 0), in: opened.surface)
            }
        }
    }

    func testADeadKeyBelowAClosedCutKeepsTheCut() throws {
        for sheets in [false, true] {
            try assertSameEditOpenAndClosed("Dead key", sheets: sheets) { opened in
                let end = try location(of: "The kettle screams.", opened.surface) + 19
                deadKeyAccent(at: end, in: opened)
            }
        }
    }

    // MARK: - The same cause, found while scoping

    /// The hidden lines' empty ranges sit at the card's end, and a lookup by
    /// location answered the first of them: a keystroke there overwrote the
    /// cut heading. The card is the line the caret is on.
    func testTypingAtTheCardsEndWritesOnTheCard() throws {
        for sheets in [false, true] {
            try assertSameEditOpenAndClosed("Card end", sheets: sheets) { opened in
                let end = try location(of: "OMITTED", opened.surface) + 7
                type("x", replacing: NSRange(location: end, length: 0), in: opened.surface)
            }
        }
    }

    // MARK: - Where the caret lands after an inserted line

    private func setCaretLine(_ text: String, in opened: Opened) throws {
        let line = try XCTUnwrap(opened.editor.screenplay.elements.first { $0.text == text }, text)
        opened.editor.activeElementID = line.id
    }

    func testInsertActBreakBelowAClosedCutPutsTheCaretOnTheNewLine() throws {
        for sheets in [false, true] {
            try assertSameEditOpenAndClosed("Act break", sheets: sheets) { opened in
                try setCaretLine("The kettle screams.", in: opened)
                opened.editor.onInsertActBreak?()
            }
        }
    }

    func testInsertedLinesBelowAClosedCutTakeTheCaretToTheLastOne() throws {
        for sheets in [false, true] {
            try assertSameEditOpenAndClosed("Insert", sheets: sheets) { opened in
                try setCaretLine("The kettle screams.", in: opened)
                opened.editor.onInsertElements?([ScriptElement(type: .action, text: "The lid rattles.")])
            }
        }
    }

    /// The renumber rule re-places the caret itself: deleting ACT ONE below
    /// a closed cut renumbers ACT TWO, and the caret must stay on its line.
    /// The breaks are the app's own — Final Draft's New Act reads back
    /// through Fountain as a centred line, not a break.
    func testTheActRenumberBelowAClosedCutKeepsTheCaretOnItsLine() throws {
        for sheets in [false, true] {
            try assertSameEditOpenAndClosed("Renumber", sheets: sheets) { opened in
                try setCaretLine("The kettle screams.", in: opened)
                opened.editor.onInsertActBreak?()
                opened.editor.onInsertActBreak?()
                XCTAssertEqual(opened.editor.screenplay.elements.filter { $0.type == .actbreak }.map(\.text),
                               ["ACT ONE", "ACT TWO"], "two breaks to renumber: \(lines(opened.editor))")
                let actOne = try location(of: "ACT ONE", opened.surface)
                type("", replacing: NSRange(location: actOne - 1, length: 8), in: opened.surface)
                XCTAssertEqual(opened.editor.screenplay.elements.filter { $0.type == .actbreak }.map(\.text),
                               ["ACT ONE"], "renumbered: \(lines(opened.editor))")
            }
        }
    }

    /// With the caret on the card, an inserted line goes after the scene the
    /// card stands for — open or closed — never between the card and its
    /// lines, where the save could no longer find the cut and would write
    /// it live.
    func testAnActBreakInsertedOnTheCardGoesAfterTheCutScene() throws {
        for sheets in [false, true] {
            for cutOpen in [false, true] {
                try keepingArrangement {
                    let opened = try opened(sheets: sheets, cutOpen: cutOpen)
                    defer { opened.window.close() }
                    let card = try XCTUnwrap(opened.editor.screenplay.elements.first { $0.text == "OMITTED" })
                    opened.editor.activeElementID = card.id
                    opened.editor.onInsertActBreak?()
                    assertTheCutStands(opened.editor, "Act break on the card (sheets: \(sheets), open: \(cutOpen))")
                }
            }
        }
    }

    // MARK: - Undo

    func testUndoingAnEditBelowAClosedCutPutsEveryLineBack() throws {
        for sheets in [false, true] {
            try keepingArrangement {
                let opened = try opened(sheets: sheets, cutOpen: false)
                defer { opened.window.close() }
                let before = lines(opened.editor)
                let at = try location(of: "The kettle", opened.surface) + 3
                type("\n", replacing: NSRange(location: at, length: 0), in: opened.surface)
                XCTAssertNotEqual(lines(opened.editor), before)
                try XCTUnwrap(opened.surface.undoManager(for: opened.surface.textView)).undo()
                XCTAssertEqual(lines(opened.editor), before, "sheets: \(sheets)")
                assertTheCutStands(opened.editor, "Undo (sheets: \(sheets))")
            }
        }
    }

    // MARK: - The restore rule, on its own

    func testHiddenLinesGoBackBehindTheLineTheyFollowed() {
        let a = ScriptElement(type: .scene, text: "OMITTED")
        let h1 = ScriptElement(type: .scene, text: "EXT. THE YARD - DUSK")
        let h2 = ScriptElement(type: .action, text: "Mara waits.")
        let b = ScriptElement(type: .action, text: "The kettle screams.")
        let before = ScriptElement(type: .action, text: "She waits.")
        let all = [before, a, h1, h2, b]
        let laid = [before, a, b]
        let fresh = ScriptElement(type: .action, text: "New.")

        // An edit after the card: the run stays behind the card.
        XCTAssertEqual(ScriptSurface.restoringHidden([before, a, fresh, b], from: all, laid: laid).map(\.id),
                       [before, a, h1, h2, fresh, b].map(\.id))
        // The card taken by the edit: behind the nearest line still there.
        XCTAssertEqual(ScriptSurface.restoringHidden([before, fresh, b], from: all, laid: laid).map(\.id),
                       [before, h1, h2, fresh, b].map(\.id))
        // Nothing before it survives: at the top, never dropped.
        XCTAssertEqual(ScriptSurface.restoringHidden([fresh], from: all, laid: laid).map(\.id),
                       [h1, h2, fresh].map(\.id))
        // Nothing hidden: the edit as planned.
        XCTAssertEqual(ScriptSurface.restoringHidden([fresh], from: laid, laid: laid).map(\.id), [fresh.id])
    }
}
