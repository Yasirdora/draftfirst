import AppKit
import EDraftCore
import EDraftEngine
import XCTest
@testable import EDraftMacSurface

/// The two-page page sheets, proven for the flip — IL-0091.
///
/// Stage 3 left five things unverified: a drag across sheets, focus and the
/// key-view loop, IME, editing churn at a sheet boundary, and cost. Each is
/// here as a test on the page-sheet path, driven through the native input
/// paths — AppKit's own mouse tracking, `insertText`, `setMarkedText`,
/// `deleteBackward`, undo. Run against the legacy fold on 2026-09-23, the
/// drag selected the wrong text and the page jumped 432 and 342 points on
/// the two churn cases; the sheets hold. Cost is `TwoPageSheetCostTests`.
@MainActor
final class TwoPageSheetProofTests: XCTestCase {

    override func setUp() {
        super.setUp()
        let arrangement = PageArrangement.stored, mode = PageLayoutMode.stored
        PageArrangement.store(.single)
        PageLayoutMode.store(.pages)
        addTeardownBlock {
            PageArrangement.store(arrangement)
            PageLayoutMode.store(mode)
        }
    }

    private func bound() -> (EditorState, ScriptSurface) {
        let editor = EditorState(source: "An opening image.")
        editor.screenplay = Screenplay(elements: (1...120).map {
            ScriptElement(type: .action, text: "Marker \($0) reads normal.")
        })
        let surface = ScriptSurface()
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1500, height: 1100)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        surface.setArrangement(.spread)
        XCTAssertTrue(surface.usesPageSheets)
        return (editor, surface)
    }

    private func window(for surface: ScriptSurface) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1500, height: 1100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface.scrollView
        surface.scrollView.layoutSubtreeIfNeeded()
        return window
    }

    /// Where the engine starts each page in the laid text.
    private func pageStarts(_ editor: EditorState, _ surface: ScriptSurface) -> [Int] {
        let laid = surface.laidElements(editor.screenplay.elements)
        let pages = ScreenplayExporter.paginate(Screenplay(elements: laid)) ?? []
        return ScreenplayPageLayout.pageStartLocations(elements: laid, pages: pages)
    }

    /// The sheet that draws `location`, and its glyph in canvas coordinates.
    private func drawn(_ location: Int, _ surface: ScriptSurface) throws -> (view: NSTextView, rect: CGRect) {
        let view = surface.textView(atCharacter: location)
        let rect = try XCTUnwrap(ScriptLayout.sheetBoundingRect(of: NSRange(location: location, length: 1), in: view))
        return (view, surface.canvas.convert(rect, from: view))
    }

    private func find(_ text: String, after: Int, in surface: ScriptSurface) -> NSRange {
        let source = surface.textStorage.string as NSString
        return source.range(of: text, options: [], range: NSRange(location: after, length: source.length - after))
    }

    private func inSync(_ editor: EditorState, _ surface: ScriptSurface) -> Bool {
        surface.textStorage.string == ScreenplayEditPlanner.flattenedText(editor.screenplay.elements)
    }

    // MARK: - 1. A drag across the spread, and Copy

    func testADragFromTheLeftSheetToTheRightSelectsThatTextAndCopiesIt() throws {
        let (editor, surface) = bound()
        let window = window(for: surface)
        defer { window.close() }
        let starts = pageStarts(editor, surface)
        let from = find("Marker 10 ", after: 0, in: surface).location + 1
        let to = find("normal", after: starts[1] + 40, in: surface).location + 3
        let a = try drawn(from, surface), b = try drawn(to, surface)
        XCTAssertFalse(a.view === b.view, "the drag must start and end on different sheets")
        let p0 = surface.canvas.convert(CGPoint(x: a.rect.minX + 1, y: a.rect.midY), to: nil)
        let p1 = surface.canvas.convert(CGPoint(x: b.rect.minX + 1, y: b.rect.midY), to: nil)
        let clock = ProcessInfo.processInfo.systemUptime
        func event(_ type: NSEvent.EventType, _ point: CGPoint, _ after: Double) throws -> NSEvent {
            try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: clock + after,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1,
                pressure: type == .leftMouseUp ? 0 : 1
            ))
        }
        // The drag and the release wait in the queue for the text view's own tracking loop.
        for step in 1...8 {
            let f = CGFloat(step) / 8
            let point = CGPoint(x: p0.x + (p1.x - p0.x) * f, y: p0.y + (p1.y - p0.y) * f)
            NSApplication.shared.postEvent(try event(.leftMouseDragged, point, 0.01 * Double(step)), atStart: false)
        }
        NSApplication.shared.postEvent(try event(.leftMouseUp, p1, 0.2), atStart: false)
        XCTAssertTrue(window.makeFirstResponder(a.view))
        a.view.mouseDown(with: try event(.leftMouseDown, p0, 0))
        while NSApplication.shared.nextEvent(
            matching: [.leftMouseDragged, .leftMouseUp], until: Date(), inMode: .default, dequeue: true
        ) != nil {}

        let selection = surface.selectionTextView.selectedRange()
        XCTAssertEqual(selection.location, from, accuracy: 1)
        XCTAssertEqual(NSMaxRange(selection), to, accuracy: 1)
        XCTAssertLessThan(selection.location, starts[1])
        XCTAssertGreaterThan(NSMaxRange(selection), starts[1], "the selection crosses onto the right page")

        /* Copy writes the view's own writable types — to a private pasteboard,
           never the writer's clipboard. */
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("eDraft-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        let view = surface.selectionTextView
        XCTAssertTrue(view.writeSelection(to: pasteboard, types: view.writablePasteboardTypes))
        XCTAssertEqual(pasteboard.string(forType: .string),
                       (surface.textStorage.string as NSString).substring(with: selection))
    }

    // MARK: - 2. Focus

    func testEnteringTwoPagesFocusesTheSheetThatHoldsTheCaret() throws {
        let editor = EditorState(source: "An opening image.")
        editor.screenplay = Screenplay(elements: (1...120).map {
            ScriptElement(type: .action, text: "Marker \($0) reads normal.")
        })
        let surface = ScriptSurface()
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1500, height: 1100)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        let window = window(for: surface)
        defer { window.close() }
        XCTAssertTrue(window.makeFirstResponder(surface.textView))
        let caret = find("Marker 70 ", after: 0, in: surface).location + 3
        surface.textView.setSelectedRange(NSRange(location: caret, length: 0))

        surface.setArrangement(.spread)
        surface.scrollView.layoutSubtreeIfNeeded()
        XCTAssertTrue(window.firstResponder === surface.textView(atCharacter: caret))
        XCTAssertEqual(surface.selectionTextView.selectedRange(), NSRange(location: caret, length: 0))
    }

    func testThePageIsOneStopInTheKeyViewLoop() throws {
        let (editor, surface) = bound()
        let window = window(for: surface)
        defer { window.close() }
        let caret = find("Marker 40 ", after: pageStarts(editor, surface)[1], in: surface).location
        let holder = surface.textView(atCharacter: caret)
        XCTAssertTrue(window.makeFirstResponder(holder))
        holder.setSelectedRange(NSRange(location: caret, length: 0))

        let stops = surface.sheets.filter { $0.textView.canBecomeKeyView }
        XCTAssertEqual(stops.count, 1, "one script, one stop — not one per page")
        XCTAssertTrue(stops.first?.textView === holder, "the stop is the sheet holding the caret")

        window.recalculateKeyViewLoop()
        window.selectNextKeyView(nil)
        let next = window.firstResponder
        XCTAssertFalse(surface.sheets.contains { $0.textView !== holder && $0.textView === next },
                       "Tab does not walk from page to page")
    }

    // MARK: - 3. IME

    func testComposedTextOnTheRightSheetLandsOnceWhereTheCaretIs() throws {
        let (editor, surface) = bound()
        let window = window(for: surface)
        defer { window.close() }
        let word = find("normal", after: pageStarts(editor, surface)[1] + 80, in: surface)
        let caret = word.location + 3
        let view = surface.textView(atCharacter: caret)
        XCTAssertTrue(window.makeFirstResponder(view))
        view.setSelectedRange(NSRange(location: caret, length: 0))
        let before = NSString(string: String(surface.textStorage.string))
        let glyph = try drawn(caret, surface).rect

        view.setMarkedText("k", selectedRange: NSRange(location: 1, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        view.setMarkedText("かな", selectedRange: NSRange(location: 2, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        /* The candidate window goes where the composition is drawn, on this sheet. */
        let candidate = view.firstRect(forCharacterRange: view.markedRange(), actualRange: nil)
        let expected = window.convertToScreen(surface.canvas.convert(glyph, to: nil))
        XCTAssertEqual(candidate.minX, expected.minX, accuracy: 2)
        XCTAssertEqual(candidate.midY, expected.midY, accuracy: 12)

        view.insertText("仮名", replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(surface.textStorage.string,
                       before.replacingCharacters(in: NSRange(location: caret, length: 0), with: "仮名"),
                       "committed once, where the caret was")
        XCTAssertEqual(surface.selectionTextView.selectedRange(), NSRange(location: caret + 2, length: 0))
        XCTAssertTrue(inSync(editor, surface))
    }

    // MARK: - 4. Editing churn

    func testTypingAcrossTheSheetBoundaryKeepsTheCaretTheFocusAndThePage() throws {
        let (editor, surface) = bound()
        let window = window(for: surface)
        defer { window.close() }
        let undo = try XCTUnwrap(surface.undoManager(for: surface.textView))
        undo.groupsByEvent = false
        let clip = surface.scrollView.contentView
        let original = surface.textStorage.string
        let lastLeftEnd = pageStarts(editor, surface)[1] - 1
        let view = surface.textView(atCharacter: lastLeftEnd - 1)
        XCTAssertTrue(window.makeFirstResponder(view))
        view.setSelectedRange(NSRange(location: lastLeftEnd, length: 0))
        let top = clip.bounds.origin.y

        let typed = String(repeating: "and on ", count: 14)
        undo.beginUndoGrouping()
        view.insertText(typed, replacementRange: view.selectedRange())
        undo.endUndoGrouping()
        let caret = surface.selectionTextView.selectedRange().location
        XCTAssertEqual(caret, lastLeftEnd + typed.utf16.count)
        XCTAssertTrue(window.firstResponder === surface.textView(atCharacter: max(0, caret - 1)),
                      "focus follows the caret onto the sheet that now holds it")
        XCTAssertEqual(clip.bounds.origin.y, top, accuracy: 2, "the page holds still")
        XCTAssertTrue(inSync(editor, surface))
        XCTAssertEqual(surface.sheets.map(\.startLocation), pageStarts(editor, surface),
                       "the sheets begin where the engine's pages begin")

        let typingView = try XCTUnwrap(window.firstResponder as? NSTextView)
        undo.beginUndoGrouping()
        for _ in 0..<typed.utf16.count { typingView.deleteBackward(nil) }
        undo.endUndoGrouping()
        XCTAssertEqual(surface.textStorage.string, original)
        XCTAssertEqual(surface.sheets.map(\.startLocation), pageStarts(editor, surface))

        undo.undo()
        XCTAssertEqual(surface.textStorage.string.utf16.count, original.utf16.count + typed.utf16.count)
        undo.undo()
        XCTAssertEqual(surface.textStorage.string, original)
        XCTAssertTrue(inSync(editor, surface))
        XCTAssertEqual(surface.sheets.map(\.startLocation), pageStarts(editor, surface))
    }

    func testReturnAtAPageBreakKeepsTheCaretOnItsLineAndThePageStill() throws {
        let (editor, surface) = bound()
        let window = window(for: surface)
        defer { window.close() }
        let undo = try XCTUnwrap(surface.undoManager(for: surface.textView))
        undo.groupsByEvent = false
        let clip = surface.scrollView.contentView
        let original = surface.textStorage.string
        let pageTwo = pageStarts(editor, surface)[1]
        let view = surface.textView(atCharacter: pageTwo)
        XCTAssertTrue(window.makeFirstResponder(view))
        view.setSelectedRange(NSRange(location: pageTwo, length: 0))
        let top = clip.bounds.origin.y

        undo.beginUndoGrouping()
        view.insertText("\n", replacementRange: view.selectedRange())
        undo.endUndoGrouping()
        let caret = surface.selectionTextView.selectedRange().location
        let line = (surface.textStorage.string as NSString).substring(
            with: NSRange(location: caret, length: min(6, surface.textStorage.length - caret)))
        XCTAssertEqual(line, "Marker", "the caret stays at the head of its own line")
        XCTAssertEqual(clip.bounds.origin.y, top, accuracy: 2, "the page holds still")
        XCTAssertTrue(window.firstResponder === surface.textView(atCharacter: caret))
        XCTAssertTrue(inSync(editor, surface))
        XCTAssertEqual(surface.sheets.map(\.startLocation), pageStarts(editor, surface))

        undo.undo()
        XCTAssertEqual(surface.textStorage.string, original)
        XCTAssertTrue(inSync(editor, surface))
    }

    func testADeletionAcrossTheBoundaryLeavesTheSheetsOnTheEnginePages() throws {
        let (editor, surface) = bound()
        let window = window(for: surface)
        defer { window.close() }
        let boundary = pageStarts(editor, surface)[1]
        let view = surface.textView(atCharacter: boundary - 40)
        XCTAssertTrue(window.makeFirstResponder(view))
        view.setSelectedRange(NSRange(location: boundary - 40, length: 80))
        view.deleteBackward(nil)
        XCTAssertTrue(inSync(editor, surface))
        XCTAssertEqual(surface.sheets.map(\.startLocation), pageStarts(editor, surface))
    }

    // MARK: - Parity: zoom and the notes wash on page sheets

    func testZoomOnPageSheetsKeepsEveryLineOnItsSheetAndUnderThePointer() throws {
        let (editor, surface) = bound()
        let window = window(for: surface)
        defer { window.close() }
        let caret = find("Marker 60 ", after: 0, in: surface).location + 2
        surface.textView(atCharacter: caret).setSelectedRange(NSRange(location: caret, length: 0))
        let before = surface.scrollView.magnification

        surface.applyZoom(.zoomIn)
        surface.scrollView.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(surface.scrollView.magnification, before)
        XCTAssertEqual(surface.sheets.map(\.startLocation), pageStarts(editor, surface))
        for (sheet, paper) in zip(surface.sheets, surface.canvas.pageViews) {
            XCTAssertTrue(paper.frame.insetBy(dx: -1, dy: -1).contains(sheet.textView.frame.insetBy(dx: 0, dy: 1)),
                          "a sheet sits on its own paper")
        }
        let glyph = try drawn(caret, surface)
        let point = glyph.view.convert(surface.canvas.convert(CGPoint(x: glyph.rect.minX + 1, y: glyph.rect.midY), to: nil), from: nil)
        XCTAssertEqual(glyph.view.characterIndexForInsertion(at: point), caret, "the pointer still lands on the word")
        XCTAssertEqual(surface.selectionTextView.selectedRange(), NSRange(location: caret, length: 0))
    }

    func testANoteOnTheRightSheetWashesItsOwnLine() throws {
        let (editor, surface) = bound()
        let starts = pageStarts(editor, surface)
        let ranges = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
        let noted = try XCTUnwrap(ranges.first { $0.range.location > starts[1] + 100 })
        let neighbour = try XCTUnwrap(ranges.first { $0.range.location > NSMaxRange(noted.range) })
        editor.activeElementID = noted.id
        editor.addNote("About this line.")
        surface.renderIfNeeded(editor)

        let manager = surface.layoutManager
        XCTAssertNotNil(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: noted.range.location, effectiveRange: nil),
                        "the noted line is washed")
        XCTAssertNil(manager.temporaryAttribute(.backgroundColor, atCharacterIndex: neighbour.range.location, effectiveRange: nil))
        let glyph = manager.glyphIndexForCharacter(at: noted.range.location)
        XCTAssertTrue(manager.textContainer(forGlyphAt: glyph, effectiveRange: nil)?.textView === surface.sheets[1].textView,
                      "and it is drawn by the right-hand sheet")
    }
}
