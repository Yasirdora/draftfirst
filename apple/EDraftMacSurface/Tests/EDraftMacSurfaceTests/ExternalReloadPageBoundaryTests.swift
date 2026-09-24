import AppKit
import EDraftCore
import EDraftEngine
import XCTest
@testable import EDraftMacSurface

/// The external-reload tear of 2026-09-23.
///
/// The owner saved a script in Final Draft while it was open here. AppKit
/// reloaded it — `ScreenplayDocument.read` → `applyExternalSource`, then
/// `attachImportedNotes` — and the page showed a dark gap band cutting
/// through a line of text: the page geometry and the laid text disagreed.
///
/// The oracle is independent of every cache the surface keeps. It asks
/// three things of the page after the reload:
/// 1. the text on screen is the model's text, laid as the model says;
/// 2. a fresh, full pagination of that text (no incremental pass, no
///    cached placement) says where each page begins;
/// 3. every gap band, every paper and every sheet boundary sits exactly
///    there — the band directly above the line that begins a page, one
///    paper per page, and no laid line drawn off its paper.
///
/// The bands alone could not have caught it. They sat on the right lines:
/// the reload had put the file's notes, sections and synopses on the page
/// (`ExternalSourceAsidesTests`), which the text lays and the paginator —
/// rightly — never counts, so a page held more than its paper. The papers
/// and the lines on them are what fail.
///
/// The same oracle is run over every other way the page is re-laid — a
/// resize, a cut opened and closed, an omit and its undo, a model edit, an
/// arrangement switch, typing — as guards: all of them held before the fix.
@MainActor
final class ExternalReloadPageBoundaryTests: XCTestCase {

    // MARK: - Documents

    private func sample02() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EDraftMacSurfaceTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // EDraftMacSurface/
            .deletingLastPathComponent()   // apple/
            .appendingPathComponent("eDraftEngine/Fixtures/finaldraft-sample02.fdx")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The first action paragraph of sample02, before the cut scene.
    private let firstAction = "<Text>Xxxxxxxx, xxxxx xxxxxxxx xxx xx.</Text>"

    /// Final Draft's save of the same file with the first action run five
    /// lines longer: the same elements, the same types — every page
    /// boundary after page one moves.
    private func lengthened(_ fdx: String) throws -> String {
        XCTAssertTrue(fdx.contains(firstAction))
        let longer = "<Text>Xxxxxxxx, xxxxx xxxxxxxx xxx xx. "
            + String(repeating: "Xxxx xxxx xxxxx xxx xxxx. ", count: 12) + "</Text>"
        return fdx.replacingOccurrences(of: firstAction, with: longer)
    }

    /// Final Draft's save with one action paragraph added after the first.
    private func inserted(_ fdx: String) throws -> String {
        let anchor = firstAction + "\n    </Paragraph>"
        XCTAssertTrue(fdx.contains(anchor))
        let added = anchor + """

            <Paragraph Type="Action" id="0b1f7a52-3c1e-4d6b-9a57-6f0c2b8e4d11">
              <Text>Xxxx xxx xxxxx xxxx xxx xxxxxx, xxx xxxx xxxx xxx xxxxx.</Text>
            </Paragraph>
        """
        return fdx.replacingOccurrences(of: anchor, with: added)
    }

    /// A long plain script with no Final Draft origin and no cut scene —
    /// the reload with nothing but the text changing.
    private func fountain(extra: String = "") -> String {
        var out = ["INT. KITCHEN - NIGHT", "", "The kettle screams." + extra, ""]
        for scene in 1...40 {
            out += ["INT. ROOM \(scene) - DAY", ""]
            out += ["Mara crosses to the window and looks down at the empty street below.", ""]
            out += ["MARA", "Nobody is coming. Nobody was ever coming, and you knew it.", ""]
            out += ["JONAS", "(quietly)", "Then why are we still here?", ""]
        }
        return out.joined(separator: "\n")
    }

    // MARK: - Driving the page

    private func withPages(_ body: () throws -> Void) rethrows {
        let storedArrangement = PageArrangement.stored
        let storedMode = PageLayoutMode.stored
        PageArrangement.store(.single)
        PageLayoutMode.store(.pages)
        defer {
            PageArrangement.store(storedArrangement)
            PageLayoutMode.store(storedMode)
        }
        try body()
    }

    private func surface(for editor: EditorState, sheets: Bool) -> ScriptSurface {
        let surface = ScriptSurface()
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1500, height: 1100)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        if sheets { surface.setArrangement(.spread) }
        surface.scrollView.layoutSubtreeIfNeeded()
        XCTAssertEqual(surface.usesPageSheets, sheets)
        return surface
    }

    private func openedFdx(_ fdx: String, sheets: Bool) throws -> (EditorState, ScriptSurface) {
        let file = try ScreenplayFile.open(Data(fdx.utf8), as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        return (editor, surface(for: editor, sheets: sheets))
    }

    /// What `ScreenplayDocument.read(from:ofType:)` does when a window is
    /// open, then what SwiftUI's update pass does (`ScriptPageView`).
    private func reloadFdx(_ fdx: String, into editor: EditorState, _ surface: ScriptSurface) throws {
        let file = try ScreenplayFile.open(Data(fdx.utf8), as: .finalDraftScreenplay)
        editor.applyExternalSource(file.source, announcing: true)
        editor.attachImportedNotes(from: file.origin)
        update(editor, surface)
    }

    private func reloadFountain(_ source: String, into editor: EditorState, _ surface: ScriptSurface) {
        editor.applyExternalSource(source, announcing: true)
        editor.attachImportedNotes(from: nil)
        update(editor, surface)
    }

    private func update(_ editor: EditorState, _ surface: ScriptSurface) {
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        surface.applyZoomForCurrentSize()
        surface.scrollView.layoutSubtreeIfNeeded()
    }

    // MARK: - The oracle

    private struct Fragment { let rect: CGRect; let chars: NSRange; let text: String }

    private func fragments(_ view: NSTextView, _ storage: NSString) -> [Fragment] {
        guard let manager = view.layoutManager, let container = view.textContainer else { return [] }
        manager.ensureLayout(for: container)
        var out: [Fragment] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { rect, _, _, glyphs, _ in
            let chars = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let text = storage.substring(with: chars).trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(Fragment(rect: rect, chars: chars, text: text))
        }
        return out
    }

    private func assertEveryBoundaryIsAPageBoundary(
        _ step: String, _ editor: EditorState, _ surface: ScriptSurface,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let path = surface.usesPageSheets ? "page sheets" : "single container"
        let storage = surface.textStorage.string as NSString

        // 1. The screen holds the model's text.
        let expected = ScriptLayout.attributedScript(
            editor.screenplay.elements, measure: surface.textView.frame.width,
            omitted: editor.omittedScenes, expanded: surface.expandedOmissions
        ).text.string
        XCTAssertTrue(storage as String == expected,
                      "\(step) (\(path)): the page holds a different text from the model",
                      file: file, line: line)

        // 2. Where the pages of that text begin, asked afresh.
        let laid = surface.laidElements(editor.screenplay.elements)
        let pages = ScreenplayExporter.paginate(Screenplay(elements: laid)) ?? []
        let starts = pages.count > 1
            ? ScreenplayPageLayout.pageStartLocations(elements: laid, pages: pages)
            : [0]
        let boundaries = Array(starts.dropFirst())

        // 3a. One paper per page, and every laid line on one.
        let papers = surface.canvas.pageViews.map { $0.frame.insetBy(dx: -1, dy: -1) }
        XCTAssertEqual(papers.count, max(pages.count, 1),
                       "\(step) (\(path)): one paper per page of the text on screen",
                       file: file, line: line)
        let hosts: [NSTextView] = surface.usesPageSheets ? surface.sheets.map(\.textView) : [surface.textView]
        var offPaper: [String] = []
        for view in hosts {
            for fragment in fragments(view, storage) where !fragment.text.isEmpty {
                let ink = fragment.rect.offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
                let onCanvas = surface.canvas.convert(ink, from: view)
                if !papers.contains(where: { $0.contains(onCanvas) }) { offPaper.append(fragment.text) }
            }
        }
        XCTAssertEqual(offPaper, [], "\(step) (\(path)): lines drawn off the paper", file: file, line: line)

        // 3b. Every boundary the page draws is a page boundary of that text.
        if surface.usesPageSheets {
            XCTAssertEqual(surface.sheets.dropFirst().map(\.startLocation), boundaries,
                           "\(step) (\(path)): a sheet begins somewhere no page does",
                           file: file, line: line)
        } else {
            guard let container = surface.textView.textContainer as? PageGapContainer else {
                return XCTFail("\(step): the single column has no gap container", file: file, line: line)
            }
            let laidLines = fragments(surface.textView, storage)
            /* The line each band pushed down: the first one resting on its
               lower edge. */
            let pushed: [Int] = container.gapBands.map { band in
                laidLines.first { $0.rect.minY >= band.maxY - 0.5 }?.chars.location ?? -1
            }
            /* The line each page begins on. */
            let opening: [Int] = boundaries.map { location in
                laidLines.first { NSLocationInRange(location, $0.chars) }?.chars.location ?? -2
            }
            XCTAssertEqual(pushed, opening,
                           "\(step) (\(path)): a gap band sits somewhere no page begins",
                           file: file, line: line)
        }
    }

    // MARK: - Final Draft saves the file while it is open here

    private func finalDraftSaves(_ change: (String) throws -> String, sheets: Bool) throws {
        try withPages {
            let fdx = try sample02()
            let (editor, surface) = try openedFdx(fdx, sheets: sheets)
            assertEveryBoundaryIsAPageBoundary("opened", editor, surface)
            try reloadFdx(change(fdx), into: editor, surface)
            assertEveryBoundaryIsAPageBoundary("reloaded", editor, surface)
        }
    }

    func testALongerLineFromFinalDraftInTheSingleContainer() throws {
        try finalDraftSaves(lengthened, sheets: false)
    }

    func testALongerLineFromFinalDraftOnPageSheets() throws {
        try finalDraftSaves(lengthened, sheets: true)
    }

    func testAnAddedLineFromFinalDraftInTheSingleContainer() throws {
        try finalDraftSaves(inserted, sheets: false)
    }

    func testAnAddedLineFromFinalDraftOnPageSheets() throws {
        try finalDraftSaves(inserted, sheets: true)
    }

    func testAnUnchangedSaveFromFinalDraftInTheSingleContainer() throws {
        try finalDraftSaves({ $0 }, sheets: false)
    }

    func testAnUnchangedSaveFromFinalDraftOnPageSheets() throws {
        try finalDraftSaves({ $0 }, sheets: true)
    }

    // MARK: - No Final Draft, no cut scene: only the text changes

    private func plainReload(sheets: Bool) {
        withPages {
            let editor = EditorState(source: fountain())
            let surface = surface(for: editor, sheets: sheets)
            assertEveryBoundaryIsAPageBoundary("opened", editor, surface)
            reloadFountain(fountain(extra: String(repeating: " The lid rattles.", count: 20)), into: editor, surface)
            assertEveryBoundaryIsAPageBoundary("reloaded", editor, surface)
        }
    }

    func testAPlainReloadInTheSingleContainer() {
        plainReload(sheets: false)
    }

    func testAPlainReloadOnPageSheets() {
        plainReload(sheets: true)
    }

    // MARK: - Guards: every other way the page is re-laid

    /// Held before the fix; here so the next entry path that re-lays the
    /// page meets the same oracle.
    private func everyOtherEntryPath(sheets: Bool) throws {
        try withPages {
            let fdx = try sample02()
            let (editor, surface) = try openedFdx(fdx, sheets: sheets)
            assertEveryBoundaryIsAPageBoundary("opened", editor, surface)

            // A resize.
            surface.remeasure(to: 1100, elements: editor.screenplay.elements)
            assertEveryBoundaryIsAPageBoundary("resized narrower", editor, surface)
            surface.remeasure(to: 1500, elements: editor.screenplay.elements)
            assertEveryBoundaryIsAPageBoundary("resized back", editor, surface)

            // The file's own cut opened, resized, closed.
            let key = try XCTUnwrap(editor.omittedScenes.scenes.first?.key)
            surface.toggleOmission(key)
            assertEveryBoundaryIsAPageBoundary("cut opened", editor, surface)
            surface.remeasure(to: 1200, elements: editor.screenplay.elements)
            assertEveryBoundaryIsAPageBoundary("cut opened, resized", editor, surface)
            surface.toggleOmission(key)
            assertEveryBoundaryIsAPageBoundary("cut closed", editor, surface)

            // Omit Scene, and its undo.
            let scene = try XCTUnwrap(editor.scenes.last { editor.sceneActions(for: $0) == [.omit] && $0.elementIndex > 100 })
            surface.performSceneAction(.omit, on: scene.id)
            assertEveryBoundaryIsAPageBoundary("omit", editor, surface)
            try XCTUnwrap(surface.undoManager(for: surface.textView)).undo()
            assertEveryBoundaryIsAPageBoundary("undo omit", editor, surface)

            // A model edit — what a structural edit or a paste commits.
            var elements = editor.screenplay.elements
            let first = try XCTUnwrap(elements.firstIndex { $0.type == .action })
            elements[first].text += String(repeating: " The lid rattles.", count: 20)
            editor.replaceAllElements(elements, activeID: elements[first].id, offset: 0, structural: true)
            surface.renderIfNeeded(editor)
            assertEveryBoundaryIsAPageBoundary("model edit", editor, surface)

            // Single to Two Pages and back.
            surface.setArrangement(sheets ? .single : .spread)
            assertEveryBoundaryIsAPageBoundary("arrangement switched", editor, surface)
            surface.setArrangement(sheets ? .spread : .single)
            assertEveryBoundaryIsAPageBoundary("arrangement back", editor, surface)
        }
    }

    func testEveryOtherEntryPathInTheSingleContainer() throws {
        try everyOtherEntryPath(sheets: false)
    }

    func testEveryOtherEntryPathOnPageSheets() throws {
        try everyOtherEntryPath(sheets: true)
    }

    /// Two hundred keystrokes, the way a keyboard delivers them: the
    /// delegate, the storage, then the change the surface listens to.
    private func typing(sheets: Bool) throws {
        try withPages {
            let editor = EditorState(source: fountain())
            let surface = surface(for: editor, sheets: sheets)
            let host: NSTextView = sheets ? surface.sheets[0].textView : surface.textView
            let target = try XCTUnwrap(editor.screenplay.elements.first { $0.type == .action })
            let range = try XCTUnwrap(surface.ranges.first { $0.id == target.id }).range
            let end = NSRange(location: NSMaxRange(range), length: 0)
            host.setSelectedRange(end)
            surface.textViewDidChangeSelection(Notification(name: NSTextView.didChangeSelectionNotification, object: host))
            for _ in 0..<200 {
                let at = host.selectedRange()
                guard surface.textView(host, shouldChangeTextIn: at, replacementString: "x") else {
                    return XCTFail("the surface refused a keystroke")
                }
                host.textStorage?.replaceCharacters(in: at, with: "x")
                host.setSelectedRange(NSRange(location: at.location + 1, length: 0))
                surface.textDidChange(Notification(name: NSText.didChangeNotification, object: host))
            }
            /* The editor is held by name, and the edit is proven to have
               reached it: a dropped editor turns keystrokes into no-ops. */
            XCTAssertTrue(editor.screenplay.elements.first { $0.id == target.id }?.text.hasSuffix("xxxx") == true,
                          "the typing reached the model")
            assertEveryBoundaryIsAPageBoundary("typed", editor, surface)
        }
    }

    func testTypingInTheSingleContainer() throws {
        try typing(sheets: false)
    }

    func testTypingOnPageSheets() throws {
        try typing(sheets: true)
    }
}
