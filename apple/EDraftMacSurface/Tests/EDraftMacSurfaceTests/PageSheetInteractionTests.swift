import AppKit
import EDraftCore
import EDraftEngine
import XCTest
@testable import EDraftMacSurface

@MainActor
final class PageSheetInteractionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        let arrangement = PageArrangement.stored
        let mode = PageLayoutMode.stored
        PageArrangement.store(.single)
        PageLayoutMode.store(.pages)
        addTeardownBlock {
            PageArrangement.store(arrangement)
            PageLayoutMode.store(mode)
        }
    }

    private func bound(_ elements: [ScriptElement]? = nil) -> (EditorState, ScriptSurface) {
        let editor = EditorState(source: "An opening image.")
        editor.screenplay = Screenplay(elements: elements ?? (1...100).map {
            ScriptElement(type: .action, text: "Marker \($0) reads normal.")
        })
        let surface = ScriptSurface(multiContainerSpreadEnabled: true)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1500, height: 1100)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        surface.setArrangement(.spread)
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

    private func rightWord(_ surface: ScriptSurface) throws -> NSRange {
        XCTAssertGreaterThan(surface.sheets.count, 1)
        let start = surface.sheets[1].startLocation
        let source = surface.textStorage.string as NSString
        let word = source.range(of: "normal", options: [], range: NSRange(location: start, length: source.length - start))
        XCTAssertNotEqual(word.location, NSNotFound)
        XCTAssertTrue(surface.textView(atCharacter: word.location) === surface.sheets[1].textView)
        return word
    }

    /// Exercise AppKit's mouse tracking, not a simulated selectedRange write.
    private func click(_ range: NSRange, count: Int, surface: ScriptSurface, window: NSWindow) throws {
        let view = surface.textView(atCharacter: range.location)
        let rect = try XCTUnwrap(ScriptLayout.sheetBoundingRect(of: range, in: view))
        let local = NSPoint(x: rect.midX, y: rect.midY)
        let canvasPoint = surface.canvas.convert(local, from: view)
        let hit = surface.canvas.hitTest(canvasPoint)
        XCTAssertTrue(hit === view, "the pointer must actually land on the right sheet")
        let point = view.convert(local, to: nil)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: point,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: count, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: point,
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + 0.01, windowNumber: window.windowNumber,
            context: nil, eventNumber: 2, clickCount: count, pressure: 0))
        NSApplication.shared.postEvent(down, atStart: true)
        let queued = try XCTUnwrap(NSApplication.shared.nextEvent(matching: .leftMouseDown,
            until: Date().addingTimeInterval(1), inMode: .default, dequeue: true))
        NSApplication.shared.postEvent(up, atStart: true)
        // The package test host cannot become a key application. Focus the
        // hit view as window activation would, then exercise native mouse
        // tracking; never set a character range to simulate the click.
        XCTAssertTrue(window.makeFirstResponder(view))
        view.mouseDown(with: queued)
    }

    func testRightSheetClickAndTypingMutateTheRightWordsAndModel() throws {
        let (editor, surface) = bound()
        let window = window(for: surface)
        defer { window.close() }
        let word = try rightWord(surface)
        let before = surface.textStorage.string as NSString
        try click(NSRange(location: word.location + 2, length: 1), count: 1, surface: surface, window: window)
        let view = surface.sheets[1].textView
        let insertion = view.selectedRange()
        XCTAssertEqual(insertion.length, 0)
        XCTAssertTrue(NSLocationInRange(insertion.location, word), "insertion=\(insertion), word=\(word), key=\(window.isKeyWindow), responder=\(String(describing: window.firstResponder))")
        XCTAssertTrue(window.firstResponder === view, "responder=\(String(describing: window.firstResponder)), sheet=\(view)")
        let expected = before.replacingCharacters(in: insertion, with: "XYZ")
        view.insertText("XYZ", replacementRange: insertion)
        XCTAssertEqual(surface.textStorage.string, expected)
        XCTAssertEqual(surface.textStorage.string, ScreenplayEditPlanner.flattenedText(editor.screenplay.elements))
        XCTAssertEqual(surface.selectionTextView.selectedRange().location, insertion.location + 3)
    }

    func testDoubleClickSelectsTheWordUnderThePointerOnTheRightSheet() throws {
        let (_, surface) = bound()
        let window = window(for: surface)
        defer { window.close() }
        let word = try rightWord(surface)
        try click(word, count: 2, surface: surface, window: window)
        XCTAssertEqual(surface.selectionTextView.selectedRange(), word)
        XCTAssertEqual(surface.textStorage.attributedSubstring(from: surface.selectionTextView.selectedRange()).string, "normal")
    }

    func testCrossPageSelectionIsSharedAndResolvesBothEndpointViews() throws {
        let (_, surface) = bound()
        let boundary = surface.sheets[1].startLocation
        let selection = NSRange(location: boundary - 5, length: 12)
        surface.sheets[0].textView.setSelectedRange(selection)
        for sheet in surface.sheets { XCTAssertEqual(sheet.textView.selectedRange(), selection) }
        XCTAssertTrue(surface.layoutManager.textViewForBeginningOfSelection === surface.sheets[0].textView)
        let glyph = surface.layoutManager.glyphIndexForCharacter(at: NSMaxRange(selection) - 1)
        XCTAssertTrue(surface.layoutManager.textContainer(forGlyphAt: glyph, effectiveRange: nil)?.textView === surface.sheets[1].textView)
    }

    func testFormatBarOnRightSheetStaysInsideVisibleCanvas() throws {
        let (_, surface) = bound()
        let window = window(for: surface)
        defer { window.close() }
        let word = try rightWord(surface)
        surface.sheets[1].textView.setSelectedRange(word)
        surface.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: surface.sheets[1].textView))
        let frame = try XCTUnwrap(surface.formatBarFrame)
        let onCanvas = surface.canvas.convert(frame, from: surface.scrollView)
        XCTAssertTrue(surface.scrollView.contentView.bounds.insetBy(dx: -1, dy: -1).contains(onCanvas))
        let wordRect = try XCTUnwrap(ScriptLayout.sheetBoundingRect(of: word, in: surface.sheets[1].textView))
        XCTAssertGreaterThan(surface.canvas.convert(wordRect, from: surface.sheets[1].textView).midX, surface.sheets[0].textView.frame.maxX)
    }

    func testFinderReportsTheRightContentViewRangeAndLocalRectangles() throws {
        let (_, surface) = bound()
        let word = try rightWord(surface)
        let client = PageSheetFindBarClient(surface: surface)
        var owned = NSRange()
        let view = client.contentView(at: word.location, effectiveCharacterRange: &owned)
        XCTAssertTrue(view === surface.sheets[1].textView)
        XCTAssertEqual(owned.location, surface.sheets[1].startLocation)
        XCTAssertTrue(NSLocationInRange(word.location, owned))
        let rect = try XCTUnwrap(client.rects(forCharacterRange: word)?.first?.rectValue)
        XCTAssertEqual(rect, ScriptLayout.sheetBoundingRect(of: word, in: surface.sheets[1].textView))
        client.selectedRanges = [NSValue(range: word)]
        XCTAssertEqual(surface.selectionTextView.selectedRange(), word)
        XCTAssertFalse(client.isEditable, "finder replacement must not bypass the planner")
    }

    func testRevealAndScreenOffsetUseTheRightSheet() throws {
        let (editor, surface) = bound()
        let word = try rightWord(surface)
        let mapped = try XCTUnwrap(ScreenplayEditPlanner.ranges(for: editor.screenplay.elements).first { NSLocationInRange(word.location, $0.range) })
        XCTAssertTrue(surface.reveal(mapped.id, reduceMotion: true))
        let view = surface.sheets[1].textView
        XCTAssertTrue(surface.highlight.superview === view)
        let rect = try XCTUnwrap(ScriptLayout.sheetBoundingRect(of: mapped.range, in: view))
        XCTAssertEqual(surface.highlight.frame.midY, rect.midY, accuracy: 1)
        let character = try XCTUnwrap(ScriptLayout.sheetBoundingRect(of: NSRange(location: word.location, length: 0), in: view))
        XCTAssertEqual(try XCTUnwrap(surface.screenOffsetForTesting(atCharacter: word.location)), surface.canvas.convert(character, from: view).minY - surface.scrollView.contentView.bounds.minY, accuracy: 0.5)
    }

    func testPredictionOnLaterSheetUsesItsHostLine() throws {
        var elements = [ScriptElement(type: .character, text: "MARA"), ScriptElement(type: .dialogue, text: "Keep moving.")]
        elements += (1...45).map { ScriptElement(type: .action, text: "Marker \($0) reads normal.") }
        let cue = ScriptElement(type: .character, text: "MA")
        elements.append(cue)
        let (editor, surface) = bound(elements)
        let end = surface.textStorage.length
        let view = surface.textView(atCharacter: end)
        XCTAssertFalse(view === surface.sheets[0].textView)
        view.setSelectedRange(NSRange(location: end, length: 0))
        surface.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: view))
        XCTAssertTrue(ScriptSurfaceHarness.waitForGhost(editor, surface))
        XCTAssertEqual(surface.presentedGhostSuffix, "RA")
        let line = try XCTUnwrap(ScriptLayout.sheetBoundingRect(of: NSRange(location: end - 1, length: 1), in: view))
        XCTAssertEqual(surface.ghostHostLineRect.midY, line.midY, accuracy: 2)
        XCTAssertEqual(surface.textStorage.string, ScreenplayEditPlanner.flattenedText(editor.screenplay.elements))
    }

    func testEditingAcrossPageCountChangesPreservesStorageSelectionAndResponder() throws {
        let (editor, surface) = bound()
        let window = window(for: surface)
        defer { window.close() }
        let original = surface.sheets
        let view = surface.sheets[1].textView
        let location = surface.sheets[1].startLocation + 3
        view.setSelectedRange(NSRange(location: location, length: 0))
        window.makeFirstResponder(view)
        view.insertText(String(repeating: "More words fill the page. ", count: 200), replacementRange: view.selectedRange())
        XCTAssertGreaterThan(surface.sheets.count, original.count)
        XCTAssertEqual(surface.textStorage.string, ScreenplayEditPlanner.flattenedText(editor.screenplay.elements))
        let caret = surface.selectionTextView.selectedRange()
        XCTAssertTrue(window.firstResponder === surface.textView(atCharacter: caret.location))
        let owner = surface.textView(atCharacter: location)
        owner.setSelectedRange(NSRange(location: location, length: caret.location - location))
        window.makeFirstResponder(owner)
        owner.insertText("", replacementRange: owner.selectedRange())
        XCTAssertEqual(surface.sheets.count, original.count)
        XCTAssertEqual(surface.selectionTextView.selectedRange(), NSRange(location: location, length: 0))
        XCTAssertEqual(surface.textStorage.string, ScreenplayEditPlanner.flattenedText(editor.screenplay.elements))
    }
    func testFormatBarUsesVisibleEndWhenSelectionBeginsAboveViewport() throws {
        let (_, surface) = bound()
        let window = window(for: surface)
        defer { window.close() }
        let sheet = try XCTUnwrap(surface.sheets.last)
        let end = sheet.startLocation + 10
        sheet.textView.scrollRangeToVisible(NSRange(location: end, length: 1))
        let selection = NSRange(location: 0, length: end)
        surface.sheets[0].textView.setSelectedRange(selection)
        surface.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: sheet.textView))
        let frame = try XCTUnwrap(surface.formatBarFrame)
        let canvasFrame = surface.canvas.convert(frame, from: surface.scrollView)
        XCTAssertTrue(surface.scrollView.contentView.bounds.insetBy(dx: -1, dy: -1).contains(canvasFrame))
    }

    func testRightSheetFormattingUpdatesOnlyTheSelectedModelRunAndUndoes() throws {
        let (editor, surface) = bound()
        let word = try rightWord(surface)
        let mapped = try XCTUnwrap(ScreenplayEditPlanner.ranges(for: editor.screenplay.elements).first { NSLocationInRange(word.location, $0.range) })
        surface.sheets[1].textView.setSelectedRange(word)
        surface.applyMark(.bold)
        let element = try XCTUnwrap(editor.screenplay.elements.first { $0.id == mapped.id })
        XCTAssertEqual(element.runs, [StyleRun(start: word.location - mapped.range.location,
                                             end: NSMaxRange(word) - mapped.range.location, styles: .bold)])
        XCTAssertNil(editor.screenplay.elements[0].runs)
        XCTAssertEqual(surface.selectionTextView.selectedRange(), word)
        editor.undo()
        XCTAssertNil(editor.screenplay.elements.first { $0.id == mapped.id }?.runs)
    }

    func testReturnOnRightSheetUsesPlannerAndPreservesResponderThroughUndo() throws {
        let (editor, surface) = bound()
        let window = window(for: surface)
        defer { window.close() }
        let word = try rightWord(surface)
        let view = surface.sheets[1].textView
        let before = ScreenplayEditPlanner.flattenedText(editor.screenplay.elements)
        let count = editor.screenplay.elements.count
        let insertion = NSRange(location: word.location + 2, length: 0)
        view.setSelectedRange(insertion)
        window.makeFirstResponder(view)
        view.insertText("\n", replacementRange: insertion)
        XCTAssertEqual(editor.screenplay.elements.count, count + 1)
        XCTAssertEqual(surface.textStorage.string, ScreenplayEditPlanner.flattenedText(editor.screenplay.elements))
        XCTAssertTrue(window.firstResponder === surface.textView(atCharacter: surface.selectionTextView.selectedRange().location))
        editor.undo()
        XCTAssertEqual(surface.textStorage.string, before)
    }

    func testNotesAtTheSameHeightOnDifferentSheetsStaySeparate() throws {
        let (editor, surface) = bound()
        let rightStart = surface.sheets[1].startLocation
        let mapped = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
        let rightID = try XCTUnwrap(mapped.first { NSLocationInRange(rightStart, $0.range) }?.id)
        editor.addNote("Left note", to: editor.screenplay.elements[0].id)
        editor.addNote("Right note", to: rightID)
        surface.render(editor.screenplay.elements)
        let markers = surface.canvas.subviews.compactMap { $0 as? NoteMarker }
        XCTAssertEqual(markers.count, 2)
        let frames = markers.map(\.frame).sorted { $0.minX < $1.minX }
        XCTAssertGreaterThan(frames[1].minX, surface.sheets[1].textView.frame.maxX)
        XCTAssertLessThan(frames[0].maxX, surface.sheets[1].textView.frame.minX)
    }

    func testArrowAcrossPageBoundaryKeepsTheCaretInTheOwningSheet() throws {
        let (_, surface) = bound()
        let window = window(for: surface)
        defer { window.close() }
        let boundary = surface.sheets[1].startLocation
        let left = surface.sheets[0].textView
        left.setSelectedRange(NSRange(location: boundary - 1, length: 0))
        window.makeFirstResponder(left)
        left.moveRight(nil)
        XCTAssertEqual(surface.selectionTextView.selectedRange(), NSRange(location: boundary, length: 0))
        XCTAssertTrue(surface.selectionTextView === surface.sheets[1].textView)
    }

}
