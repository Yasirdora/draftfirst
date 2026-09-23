import AppKit
import EDraftCore
import EDraftEngine
import XCTest
@testable import EDraftMacSurface

/// The page tear of 2026-09-22 — IL-0089.
///
/// With a cut scene collapsed, the surface counted its pages over every
/// element while the text held only the laid ones: the first layout of a
/// document always took the incremental path (the empty document primed the
/// cache at init), which paginated the unfiltered list, and the page starts
/// were then read off the filtered one. Every start after the cut landed
/// late, a page came out longer than its sheet, and its lines were drawn off
/// the paper — onto the desk below it, or across the gap into the next.
/// Keyed on every element too, opening or closing a cut scene reused pages
/// counted for the other state.
///
/// Measured here as the writer sees it, in both layout paths: every laid
/// line's ink sits on a paper, no page ends on a scene heading cut off from
/// its scene, and there is one paper for every page the engine counts in the
/// text on the page.
@MainActor
final class OmittedPageTearTests: XCTestCase {

    private func realFile() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EDraftMacSurfaceTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // EDraftMacSurface/
            .deletingLastPathComponent()   // apple/
            .appendingPathComponent("eDraftEngine/Fixtures/finaldraft-sample02.fdx"))
    }

    /// Runs `body` with the pages drawn as sheets — one column (the classic
    /// single container), or the two-page spread's page sheets.
    private func withPages(_ body: () throws -> Void) rethrows {
        let arrangement = PageArrangement.stored
        let mode = PageLayoutMode.stored
        PageArrangement.store(.single)
        PageLayoutMode.store(.pages)
        defer {
            PageArrangement.store(arrangement)
            PageLayoutMode.store(mode)
        }
        try body()
    }

    private func opened(_ data: Data, sheets: Bool) throws -> (EditorState, ScriptSurface) {
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let surface = ScriptSurface()
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1500, height: 1100)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        if sheets { surface.setArrangement(.spread) }
        surface.scrollView.layoutSubtreeIfNeeded()
        XCTAssertEqual(surface.usesPageSheets, sheets)
        return (editor, surface)
    }

    /// Every laid line: its text, where it starts in the storage, and its
    /// ink in the canvas's coordinates.
    private struct Line { let text: String; let location: Int; let rect: CGRect }

    private func lines(_ surface: ScriptSurface) -> [Line] {
        let storage = surface.textStorage.string as NSString
        let hosts: [NSTextView] = surface.usesPageSheets ? surface.sheets.map(\.textView) : [surface.textView]
        var out: [Line] = []
        for view in hosts {
            guard let manager = view.layoutManager, let container = view.textContainer else { continue }
            manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) { _, used, _, glyphs, _ in
                let chars = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
                let text = storage.substring(with: chars).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return }
                let ink = used.offsetBy(dx: view.textContainerOrigin.x, dy: view.textContainerOrigin.y)
                out.append(Line(text: text, location: chars.location, rect: surface.canvas.convert(ink, from: view)))
            }
        }
        return out
    }

    /// The writer's view of the page, checked after `step`.
    private func assertThePageHolds(
        _ step: String, _ editor: EditorState, _ surface: ScriptSurface,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let papers = surface.canvas.pageViews.map { $0.frame.insetBy(dx: -1, dy: -1) }
        let laid = lines(surface)
        let path = surface.usesPageSheets ? "page sheets" : "single container"

        let offPaper = laid.filter { line in !papers.contains { $0.contains(line.rect) } }
        XCTAssertEqual(offPaper.map(\.text), [],
                       "\(step) (\(path)): lines drawn off the paper", file: file, line: line)

        var orphans: [String] = []
        for paper in papers {
            guard let last = laid.filter({ paper.contains($0.rect) }).max(by: { $0.rect.minY < $1.rect.minY }),
                  let range = surface.ranges.firstIndex(where: { NSLocationInRange(last.location, $0.range) }),
                  editor.screenplay.elements.indices.contains(range)
            else { continue }
            /* A heading cut off from its scene's first line. An OMITTED card
               is not one: it is a whole scene of one line, with nothing
               after it to be parted from, and the engine may end a page on
               it as Final Draft does. */
            let element = editor.screenplay.elements[range]
            if element.type == .scene, !editor.omittedScenes.isCard(element) { orphans.append(last.text) }
        }
        XCTAssertEqual(orphans, [], "\(step) (\(path)): a page ends on its scene heading", file: file, line: line)

        let counted = ScreenplayExporter.paginate(
            Screenplay(elements: surface.laidElements(editor.screenplay.elements))
        )?.count ?? 1
        XCTAssertEqual(surface.canvas.pageViews.count, counted,
                       "\(step) (\(path)): one paper per page counted in the text on the page",
                       file: file, line: line)
    }

    // MARK: - The owner's hands: an in-session omit and restore

    private func omitAndRestore(sheets: Bool) throws {
        try withPages {
            let (editor, surface) = try opened(realFile(), sheets: sheets)
            assertThePageHolds("opened", editor, surface)
            let scene = try XCTUnwrap(editor.scenes.last { editor.sceneActions(for: $0) == [.omit] && $0.elementIndex > 100 })
            surface.performSceneAction(.omit, on: scene.id)
            assertThePageHolds("omit", editor, surface)
            let key = try XCTUnwrap(editor.omittedScenes.scenes.last?.key)
            surface.toggleOmission(key)
            assertThePageHolds("the new cut opened", editor, surface)
            surface.toggleOmission(key)
            assertThePageHolds("the new cut closed", editor, surface)
            let card = try XCTUnwrap(editor.screenplay.elements.first { $0.draftID == editor.omittedScenes.scenes.last?.card })
            surface.performSceneAction(.restore, on: card.id)
            assertThePageHolds("restore", editor, surface)
            try XCTUnwrap(surface.undoManager(for: surface.textView)).undo()
            assertThePageHolds("undo the restore", editor, surface)
        }
    }

    func testAnOmitAndRestoreKeepEveryLineOnItsPageInTheSingleContainer() throws {
        try omitAndRestore(sheets: false)
    }

    func testAnOmitAndRestoreKeepEveryLineOnItsPageOnPageSheets() throws {
        try omitAndRestore(sheets: true)
    }

    // MARK: - Older than the command: the file's own omission

    /// Final Draft's own cut scene, collapsed at open, then a keystroke's
    /// worth of edit and the chevron opened and closed. This tore before
    /// Omit Scene existed.
    private func filesOwnOmission(sheets: Bool) throws {
        try withPages {
            let (editor, surface) = try opened(realFile(), sheets: sheets)
            assertThePageHolds("opened with Final Draft's omission collapsed", editor, surface)
            var elements = editor.screenplay.elements
            let last = try XCTUnwrap(elements.lastIndex { $0.type == .action })
            elements[last].text += " Then silence."
            editor.replaceAllElements(elements, activeID: elements[last].id, offset: 0, structural: false)
            surface.renderIfNeeded(editor)
            assertThePageHolds("an edit below the cut", editor, surface)
            let key = try XCTUnwrap(editor.omittedScenes.scenes.first?.key)
            surface.toggleOmission(key)
            assertThePageHolds("the cut opened", editor, surface)
            surface.toggleOmission(key)
            assertThePageHolds("the cut closed", editor, surface)
        }
    }

    func testAFilesOwnOmissionKeepsEveryLineOnItsPageInTheSingleContainer() throws {
        try filesOwnOmission(sheets: false)
    }

    func testAFilesOwnOmissionKeepsEveryLineOnItsPageOnPageSheets() throws {
        try filesOwnOmission(sheets: true)
    }
}
