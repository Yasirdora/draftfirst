import AppKit
import EDraftCore
import EDraftEngine
import XCTest
@testable import EDraftMacSurface

/// What a keystroke costs on the two-page page sheets — IL-0091.
///
/// Measured 2026-09-23 before this lock: 102 ms a keystroke on a 115-page
/// script (the legacy fold: 6.4), 14.5 ms on `finaldraft-sample02.fdx`
/// (3.3). Every keystroke laid out every sheet — `ensureLayout` on each
/// container, then each sheet's ink measured — and moved every later
/// page's boundary as a geometry change, which threw away TextKit's layout
/// of the rest of the script. Now a keystroke lays out the sheet it is on
/// and the sheets in view, and the boundaries move with the text.
@MainActor
final class TwoPageSheetCostTests: XCTestCase {

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

    /// Hold on to the editor: the surface keeps it weakly, and a keystroke
    /// with no editor behind it never reaches the model or the layout.
    private func spread(_ elements: [ScriptElement], sheets: Bool = true) -> (EditorState, ScriptSurface, NSWindow) {
        let editor = EditorState(source: "An opening image.")
        editor.screenplay = Screenplay(elements: elements)
        let (surface, window) = spread(editor, sheets: sheets)
        return (editor, surface, window)
    }

    private func spread(_ editor: EditorState, sheets: Bool) -> (ScriptSurface, NSWindow) {
        let surface = ScriptSurface(multiContainerSpreadEnabled: sheets)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1500, height: 1100)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        surface.setArrangement(.spread)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1500, height: 1100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = surface.scrollView
        surface.scrollView.layoutSubtreeIfNeeded()
        return (surface, window)
    }

    private func markers(_ count: Int) -> [ScriptElement] {
        (1...count).map { ScriptElement(type: .action, text: "Marker \($0) reads normal.") }
    }

    private func caret(at marker: Int, in surface: ScriptSurface, _ window: NSWindow) -> (NSTextView, Int) {
        let location = (surface.textStorage.string as NSString).range(of: "Marker \(marker) ").location + 3
        let view = surface.textView(atCharacter: location)
        XCTAssertTrue(window.makeFirstResponder(view))
        view.setSelectedRange(NSRange(location: location, length: 0))
        return (view, location)
    }

    /// A keystroke keeps the layout of the pages below it: their boundaries
    /// move with the text rather than as a change of container geometry,
    /// which would throw that layout away.
    func testAKeystrokeKeepsTheLayoutOfThePagesBelowIt() throws {
        let (editor, surface, window) = spread(markers(600))
        defer { window.close() }
        let manager = surface.layoutManager
        manager.ensureLayout(forCharacterRange: NSRange(location: 0, length: surface.textStorage.length))
        let (view, location) = caret(at: 5, in: surface, window)

        view.insertText("x", replacementRange: NSRange(location: location, length: 0))

        XCTAssertEqual(editor.screenplay.elements[4].text, "Marxker 5 reads normal.", "the keystroke reached the script")
        XCTAssertEqual(manager.firstUnlaidCharacterIndex(), surface.textStorage.length)
    }

    /// With the layout thrown away (a zoom, a change of format), a keystroke
    /// near the top of a long script lays out the sheet it is on and the
    /// sheets in view — not the pages far below them, which lay out when
    /// they are drawn. Before this lock every keystroke laid out every sheet.
    func testAKeystrokeLaysOutOnlyTheSheetsInView() throws {
        let (editor, surface, window) = spread(markers(600))
        defer { window.close() }
        XCTAssertGreaterThan(surface.sheets.count, 12)
        let manager = surface.layoutManager
        let (view, location) = caret(at: 5, in: surface, window)
        manager.invalidateLayout(forCharacterRange: NSRange(location: 0, length: surface.textStorage.length),
                                 actualCharacterRange: nil)

        view.insertText("x", replacementRange: NSRange(location: location, length: 0))

        XCTAssertEqual(editor.screenplay.elements[4].text, "Marxker 5 reads normal.", "the keystroke reached the script")
        XCTAssertLessThan(manager.firstUnlaidCharacterIndex(), surface.sheets[8].startLocation,
                          "pages well below the viewport are not laid out by a keystroke")
    }

    /// A sheet scrolled into view is measured then, and sits on its paper.
    func testASheetScrolledIntoViewIsMeasuredThere() throws {
        let (_, surface, window) = spread(markers(600))
        defer { window.close() }
        let last = try XCTUnwrap(surface.sheets.last)
        let clip = surface.scrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: max(0, surface.canvas.frame.height - clip.bounds.height)))
        surface.scrollView.reflectScrolledClipView(clip)
        NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: clip)
        let manager = surface.layoutManager
        let glyphs = manager.glyphRange(for: last.textContainer)
        XCTAssertGreaterThan(glyphs.length, 0, "the last page is laid out once it is in view")
        let paper = try XCTUnwrap(surface.canvas.pageViews.last)
        XCTAssertTrue(paper.frame.insetBy(dx: -1, dy: -1).contains(last.textView.frame.insetBy(dx: 0, dy: 1)))
    }

    /// A boundary moves with the text: unmoved before an edit, shifted after
    /// it, and at the end of the new text when the edit swallowed it.
    func testABoundaryFollowsAnEdit() {
        XCTAssertEqual(PageSheet.follow(100, 40, 0, 5), 105, "insert before")
        XCTAssertEqual(PageSheet.follow(100, 120, 0, 5), 100, "insert after")
        XCTAssertEqual(PageSheet.follow(100, 100, 0, 5), 100, "insert at the boundary goes to the page it opens")
        XCTAssertEqual(PageSheet.follow(100, 40, 10, 0), 90, "delete before")
        XCTAssertEqual(PageSheet.follow(100, 95, 10, 0), 95, "a deletion that swallows it")
        XCTAssertEqual(PageSheet.follow(100, 95, 10, 3), 98, "a replacement that swallows it")
        XCTAssertEqual(PageSheet.follow(.max, 10, 0, 5), .max, "the last page runs to the end")
    }

    // MARK: - Measured (opt-in: EDRAFT_BENCHMARKS=1)

    private func synthetic() -> Data {
        var parts: [String] = []
        for n in 1...230 {
            var scene = ["<Paragraph Type=\"Scene Heading\"><Text>INT. ROOM \(n) - DAY</Text></Paragraph>"]
            for a in 1...3 {
                scene.append("<Paragraph Type=\"Action\"><Text>Scene \(n), beat \(a): she crosses the room, stops at the window and looks down at the street below for a long moment.</Text></Paragraph>")
            }
            for d in 1...3 {
                scene.append("<Paragraph Type=\"Character\"><Text>\(d % 2 == 0 ? "TOM" : "MARA")</Text></Paragraph>")
                scene.append("<Paragraph Type=\"Dialogue\"><Text>Line \(d) of scene \(n), and it runs on a little so that it wraps onto a second line of dialogue.</Text></Paragraph>")
            }
            parts.append(scene.joined(separator: "\n"))
        }
        return Data("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\" ?>\n<FinalDraft DocumentType=\"Script\" Version=\"6\"><Content>\n\(parts.joined(separator: "\n"))\n</Content></FinalDraft>".utf8)
    }

    private func sample02() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("eDraftEngine/Fixtures/finaldraft-sample02.fdx"))
    }

    /// Median keystroke over 20 after 5 of warm-up, typed ~60% into the
    /// script through the caret's own view — IL-0089's method.
    private func keystroke(_ data: Data, sheets: Bool) throws -> Double {
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let (surface, window) = spread(editor, sheets: sheets)
        defer { window.close() }
        return try measure(editor, surface, window)
    }

    private func measure(_ editor: EditorState, _ surface: ScriptSurface, _ window: NSWindow) throws -> Double {
        let elements = editor.screenplay.elements
        let index = try XCTUnwrap(elements.indices.first { $0 > elements.count * 6 / 10 && elements[$0].type == .action })
        var location = surface.ranges[index].range.location + 3
        var times: [Double] = []
        for i in 0..<25 {
            let view = surface.usesPageSheets ? surface.textView(atCharacter: location) : surface.textView
            _ = window.makeFirstResponder(view)
            view.setSelectedRange(NSRange(location: location, length: 0))
            let start = DispatchTime.now().uptimeNanoseconds
            view.insertText("x", replacementRange: NSRange(location: location, length: 0))
            let end = DispatchTime.now().uptimeNanoseconds
            location += 1
            if i >= 5 { times.append(Double(end - start) / 1e6) }
        }
        return times.sorted()[times.count / 2]
    }

    func testAKeystrokeOnSheetsCostsWhatTheLegacyFoldCosts() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["EDRAFT_BENCHMARKS"] == "1",
                          "benchmark — set EDRAFT_BENCHMARKS=1")
        for (name, data) in [("115-page synthetic", synthetic()), ("sample02", try sample02())] {
            let legacy = try keystroke(data, sheets: false)
            let sheets = try keystroke(data, sheets: true)
            print(String(format: "BENCH %@: legacy fold %.2f ms · page sheets %.2f ms a keystroke (median of 20)", name, legacy, sheets))
            XCTAssertLessThan(sheets, legacy * 1.25 + 1, "\(name): page sheets within noise of the legacy fold")
        }
    }
}
