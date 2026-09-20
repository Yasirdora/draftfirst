import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

@MainActor
final class PageSheetTests: XCTestCase {
    override func setUp() {
        super.setUp()
        let mode = PageLayoutMode.stored
        let arrangement = PageArrangement.stored
        addTeardownBlock {
            PageLayoutMode.store(mode)
            PageArrangement.store(arrangement)
        }
    }

    private func script(_ count: Int) -> [ScriptElement] {
        (0..<count).flatMap { index in
            [ScriptElement(type: .scene, text: "INT. ROOM \(index) - DAY"),
             ScriptElement(type: .action, text: "The road holds its breath. A light shines at the end of the hall."),
             ScriptElement(type: .character, text: "MARA"),
             ScriptElement(type: .dialogue, text: "A line spoken plainly and without hurry.")]
        }
    }

    private func surface(_ elements: [ScriptElement], enabled: Bool = true) -> ScriptSurface {
        let surface = ScriptSurface(multiContainerSpreadEnabled: enabled)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 900, height: 650)
        surface.setArrangement(.spread)
        surface.render(elements)
        return surface
    }

    private func assertEngineRanges(_ surface: ScriptSurface, _ elements: [ScriptElement],
                                    file: StaticString = #filePath, line: UInt = #line) throws {
        let pages = try XCTUnwrap(ScreenplayExporter.paginate(Screenplay(elements: elements)))
        let locations = ScreenplayPageLayout.pageStartLocations(elements: elements, pages: pages)
        let starts = locations.isEmpty ? [0] : locations
        XCTAssertEqual(surface.sheets.count, starts.count, file: file, line: line)
        var covered = 0
        for (index, sheet) in surface.sheets.enumerated() {
            surface.layoutManager.ensureLayout(for: sheet.textContainer)
            let range = surface.layoutManager.characterRange(
                forGlyphRange: surface.layoutManager.glyphRange(for: sheet.textContainer), actualGlyphRange: nil
            )
            XCTAssertEqual(sheet.startLocation, starts[index], file: file, line: line)
            if surface.textStorage.length > 0 {
                XCTAssertEqual(range.location, starts[index], file: file, line: line)
            }
            let end = index + 1 < starts.count ? starts[index + 1] : surface.textStorage.length
            XCTAssertEqual(NSMaxRange(range), end, file: file, line: line)
            covered += range.length
        }
        XCTAssertEqual(covered, surface.textStorage.length, file: file, line: line)
    }

    func testOneStorageOneLayoutManagerAndOneContainerAndViewPerEnginePage() throws {
        let elements = script(30)
        let surface = surface(elements)
        try assertEngineRanges(surface, elements)
        XCTAssertGreaterThan(surface.sheets.count, 2)
        XCTAssertEqual(surface.textStorage.layoutManagers.count, 1)
        XCTAssertTrue(surface.textStorage.layoutManagers[0] === surface.layoutManager)
        XCTAssertEqual(surface.layoutManager.textContainers.count, surface.sheets.count)
        XCTAssertNil(surface.textView.layoutManager, "the legacy column must not take any characters")
        for (index, sheet) in surface.sheets.enumerated() {
            XCTAssertTrue(surface.layoutManager.textContainers[index] === sheet.textContainer)
            XCTAssertTrue(sheet.textContainer.textView === sheet.textView)
            XCTAssertTrue(sheet.textView.textStorage === surface.textStorage)
            XCTAssertTrue(sheet.textView.superview === surface.canvas)
            XCTAssertTrue(sheet.textView.isEditable)
            XCTAssertTrue(sheet.textView.isSelectable)
        }
    }

    func testDisabledFlagKeepsTheLegacySpread() {
        let surface = surface(script(25), enabled: false)
        XCTAssertTrue(surface.sheets.isEmpty)
        XCTAssertTrue(surface.textView.textStorage === surface.textStorage)
        XCTAssertTrue(surface.textView.textContainer is PageGapContainer)
        XCTAssertEqual(surface.layoutManager.textContainers.count, 1)
        XCTAssertNotNil(surface.canvas.spreadFold)
        XCTAssertFalse(surface.textView.isHidden)
    }

    func testFlagDoesNotAffectSingleGridOrContinuous() {
        let elements = script(25)
        let enabled = ScriptSurface(multiContainerSpreadEnabled: true)
        let disabled = ScriptSurface(multiContainerSpreadEnabled: false)
        for surface in [enabled, disabled] {
            surface.scrollView.frame = NSRect(x: 0, y: 0, width: 900, height: 650)
            surface.render(elements)
        }
        for arrangement in [PageArrangement.single, .grid, .single] {
            for surface in [enabled, disabled] { surface.setArrangement(arrangement) }
            XCTAssertTrue(enabled.sheets.isEmpty)
            XCTAssertEqual(enabled.pageFrames, disabled.pageFrames)
            XCTAssertEqual(enabled.textView.frame, disabled.textView.frame)
            XCTAssertEqual(enabled.textView.isHidden, disabled.textView.isHidden)
            XCTAssertEqual(enabled.textView.isEditable, disabled.textView.isEditable)
        }
        for surface in [enabled, disabled] { surface.setLayoutMode(.continuous) }
        XCTAssertTrue(enabled.sheets.isEmpty)
        XCTAssertEqual(enabled.pageFrames, disabled.pageFrames)
        XCTAssertEqual(enabled.textView.frame, disabled.textView.frame)
    }

    func testMovingABreakAfterLayoutInvalidatesContainerGeometry() {
        let storage = NSTextStorage(string: (0..<90).map { "Line \($0)\n" }.joined(),
                                    attributes: ScriptLayout.attributes(for: .action, measure: 400, spacingAfter: 0))
        let manager = NSLayoutManager()
        storage.addLayoutManager(manager)
        let first = PageSheet(startLocation: 0, endLocation: Int.max, measure: 400, layoutManager: manager)
        let second = PageSheet(startLocation: 0, endLocation: Int.max, measure: 400, layoutManager: manager)
        manager.ensureLayout(for: first.textContainer)
        let source = storage.string as NSString
        for marker in ["Line 30\n", "Line 12\n", "Line 55\n"] {
            let start = source.range(of: marker).location
            first.update(startLocation: 0, endLocation: start, measure: 400)
            second.update(startLocation: start, endLocation: Int.max, measure: 400)
            manager.ensureLayout(for: second.textContainer)
            let firstRange = manager.characterRange(forGlyphRange: manager.glyphRange(for: first.textContainer), actualGlyphRange: nil)
            let secondRange = manager.characterRange(forGlyphRange: manager.glyphRange(for: second.textContainer), actualGlyphRange: nil)
            XCTAssertEqual(NSMaxRange(firstRange), start)
            XCTAssertEqual(secondRange.location, start)
            XCTAssertEqual(NSMaxRange(secondRange), storage.length)
        }
    }

    func testRenderingChangedTextReusesSheetsAndMovesTheirBreaks() throws {
        let original = script(25)
        let surface = surface(original)
        let sheets = surface.sheets
        let starts = sheets.map(\.startLocation)
        var changed = original
        changed[1].text = "A different first action."
        surface.render(changed)
        try assertEngineRanges(surface, changed)
        XCTAssertNotEqual(surface.sheets.map(\.startLocation), starts)
        for (old, new) in zip(sheets, surface.sheets) { XCTAssertTrue(old === new) }
    }

    func testPageCountGrowthAndShrinkRemoveOnlyTheTail() throws {
        let small = script(5)
        let large = script(40)
        let surface = surface(small)
        let first = try XCTUnwrap(surface.sheets.first)
        surface.render(large)
        try assertEngineRanges(surface, large)
        XCTAssertTrue(surface.sheets[0] === first)
        let removed = surface.sheets.last!
        surface.render(small)
        try assertEngineRanges(surface, small)
        XCTAssertTrue(surface.sheets[0] === first)
        XCTAssertNil(removed.textView.superview)
        XCTAssertNil(removed.textContainer.layoutManager)
        XCTAssertEqual(surface.layoutManager.textContainers.count, surface.sheets.count)
    }

    func testEmptyScriptAndTrailingEmptyElementHaveASheet() throws {
        for elements in [[], [ScriptElement(type: .action, text: "")],
                         script(20) + [ScriptElement(type: .action, text: "")]] {
            let surface = surface(elements)
            try assertEngineRanges(surface, elements)
            XCTAssertFalse(surface.sheets.isEmpty)
            XCTAssertTrue(surface.sheets.allSatisfy { $0.textView.frame.height > 0 })
        }
    }

    func testReturningToLegacyAfterPreviewUsesCurrentTextAndBreaks() throws {
        let surface = ScriptSurface(multiContainerSpreadEnabled: true)
        surface.render(script(20))
        let storage = surface.textStorage
        let manager = surface.layoutManager
        let legacyContainer = surface.textView.textContainer
        surface.textView.setSelectedRange(NSRange(location: 20, length: 4))
        for mode in [PageArrangement.single, .grid, .single] {
            surface.setArrangement(.spread)
            let oldSheets = surface.sheets
            let elements = script(30)
            surface.render(elements)
            surface.setArrangement(mode)
            XCTAssertTrue(surface.sheets.isEmpty)
            XCTAssertTrue(surface.textStorage === storage)
            XCTAssertTrue(surface.layoutManager === manager)
            XCTAssertTrue(surface.textView.textContainer === legacyContainer)
            XCTAssertTrue(surface.textView.textStorage === storage)
            XCTAssertEqual(manager.textContainers.count, 1)
            XCTAssertEqual(surface.textView.string, ScreenplayEditPlanner.flattenedText(elements))
            XCTAssertTrue(oldSheets.allSatisfy { $0.textView.superview == nil && $0.textContainer.layoutManager == nil })
        }
        XCTAssertEqual(surface.textView.selectedRange(), NSRange(location: 20, length: 4))
    }

    func testResizeChangesFramesWithoutRecreatingViewsOrMovingPageStarts() throws {
        let elements = script(25)
        let surface = surface(elements)
        let sheets = surface.sheets
        let frame = sheets[1].textView.frame
        surface.scrollView.frame.size = CGSize(width: 650, height: 400)
        surface.remeasure(to: 650, elements: elements)
        try assertEngineRanges(surface, elements)
        XCTAssertNotEqual(frame, surface.sheets[1].textView.frame)
        for (before, after) in zip(sheets, surface.sheets) { XCTAssertTrue(before === after) }
    }

    func testDefaultSurfaceUsesLegacyUnlessDebugEnvironmentExplicitlyOptsIn() {
        let surface = ScriptSurface()
        surface.setArrangement(.spread)
        surface.render(script(10))
        #if DEBUG
        let enabled = ProcessInfo.processInfo.environment["EDRAFT_MULTI_CONTAINER_SPREAD"] == "1"
        #else
        let enabled = false
        #endif
        XCTAssertEqual(surface.usesPageSheets, enabled)
        XCTAssertEqual(surface.textView.layoutManager == nil, enabled)
    }

    func testLeavingPreviewForContinuousRestoresTheSameLegacyGeometry() {
        let elements = script(30)
        let preview = surface(script(5))
        preview.render(elements)
        preview.setLayoutMode(.continuous)
        let legacy = surface(elements, enabled: false)
        legacy.setLayoutMode(.continuous)
        XCTAssertTrue(preview.sheets.isEmpty)
        XCTAssertEqual(preview.pageFrames, legacy.pageFrames)
        XCTAssertEqual(preview.textView.frame, legacy.textView.frame)
        for range in ScreenplayEditPlanner.ranges(for: elements) {
            XCTAssertEqual(ScriptLayout.boundingRect(of: range.range, in: preview.textView),
                           ScriptLayout.boundingRect(of: range.range, in: legacy.textView))
        }
    }

    /// PageSheet ownership ends at the surface/array, including after a
    /// switch back to the legacy container. AppKit's internal text-system
    /// caches have a separate lifetime on both architectures.
    func testRetiredSheetsAndSurfaceAreReleased() {
        for enabled in [false, true] {
            weak var owner: ScriptSurface?
            weak var retired: PageSheet?
            autoreleasepool {
                let surface = surface(script(20), enabled: enabled)
                owner = surface
                retired = surface.sheets.last
                surface.setArrangement(.single)
                XCTAssertNil(retired)
            }
            XCTAssertNil(owner)
        }
    }


    func testBoundPreviewPreservesTheModelAndResumesLegacyEditing() {
        PageArrangement.store(.single)
        PageLayoutMode.store(.pages)
        let elements = script(20)
        let editor = EditorState(source: "An opening image.")
        editor.screenplay = Screenplay(titlePage: [], elements: elements)
        editor.activeElementID = elements[41].id
        editor.selectionOffset = 3
        let surface = ScriptSurface(multiContainerSpreadEnabled: true)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        let selection = surface.textView.selectedRange()
        let revision = editor.revision
        surface.setArrangement(.spread)
        XCTAssertEqual(editor.activeElementID, elements[41].id)
        XCTAssertEqual(editor.selectionOffset, 3)
        XCTAssertEqual(editor.revision, revision)
        XCTAssertEqual(surface.textStorage.string, ScreenplayEditPlanner.flattenedText(elements))
        surface.setArrangement(.single)
        XCTAssertEqual(surface.textView.selectedRange(), selection)
        XCTAssertTrue(ScriptSurfaceHarness.type("X", into: surface))
        XCTAssertEqual(surface.textStorage.string, ScreenplayEditPlanner.flattenedText(editor.screenplay.elements))
        XCTAssertEqual(editor.screenplay.elements[41].text, "TheX road holds its breath. A light shines at the end of the hall.")
    }

}
