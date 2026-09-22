import AppKit
import EDraftCore
import EDraftEngine
import XCTest
@testable import EDraftMacSurface

/// A scene the production cut, on the page — RFC-DRAFT-PRODUCTION §7.3.
///
/// Collapsed out of the flow, not struck through it: one line where the
/// scene was, the body not in the layout at all, and a disclosure that puts
/// it back. What the collapse has to protect is the surface's own
/// arithmetic — `ranges` is indexed by element index everywhere, so a
/// hidden element keeps its place in that array and holds an empty range.
@MainActor
final class OmittedSceneSurfaceTests: XCTestCase {

    /// A file with one cut scene: the card, and two paragraphs behind it.
    private func fdx(
        before: [(String, String)] = [("Scene Heading", "INT. LAB - DAY"), ("Action", "She waits.")],
        after: [(String, String)] = [("Action", "The kettle screams.")],
        number: String = "21",
        length: String? = "2/8"
    ) -> Data {
        let head = before.map { "<Paragraph Type=\"\($0.0)\"><Text>\($0.1)</Text></Paragraph>" }.joined(separator: "\n")
        let tail = after.map { "<Paragraph Type=\"\($0.0)\"><Text>\($0.1)</Text></Paragraph>" }.joined(separator: "\n")
        let properties = length.map { "<SceneProperties Length=\"\($0)\" Page=\"1\"></SceneProperties>" } ?? ""
        return Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        \(head)
        <Paragraph Number="\(number)" Type="Scene Heading">
        <Text>OMITTED</Text>
        <OmittedScene>
        <Paragraph Type="Scene Heading">\(properties)<Text>EXT. THE YARD - DUSK</Text></Paragraph>
        <Paragraph Type="Action"><Text>Mara waits.</Text></Paragraph>
        </OmittedScene>
        </Paragraph>
        \(tail)
        </Content>
        </FinalDraft>
        """.utf8)
    }

    private func opened(_ data: Data) throws -> (EditorState, ScriptSurface) {
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        return (editor, surface)
    }

    private func laid(_ surface: ScriptSurface) -> String {
        surface.textView.textStorage?.string ?? ""
    }

    private func key(_ editor: EditorState) throws -> DraftElementID {
        try XCTUnwrap(editor.omittedScenes.scenes.first?.key)
    }

    // MARK: - The toggle moves nothing the writer was looking at

    /// A file tall enough to scroll: forty live lines before and after the
    /// cut scene, so the viewport has somewhere to be — and somewhere to be
    /// thrown to, which is the defect under test.
    private func tallFdx() -> Data {
        fdx(
            before: [("Scene Heading", "INT. LAB - DAY")]
                + (1...40).map { ("Action", "Before line \($0).") },
            after: (1...40).map { ("Action", "After line \($0).") }
        )
    }

    /// Opening inserts the body *above* this caret, so the location moves by
    /// exactly the inserted length and the caret stays on its own line.
    /// Anything else — the document's end, say — is the bug.
    private func assertToggleKeepsTheCaret(
        _ editor: EditorState, _ surface: ScriptSurface,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let caretText = "After line 20."
        let caretAt = (surface.textStorage.string as NSString).range(of: caretText).location + 3
        surface.selectionTextView.setSelectedRange(NSRange(location: caretAt, length: 0))

        let key = try key(editor)
        surface.toggleOmission(key)
        let grown = surface.textStorage.length
        let reopened = (surface.textStorage.string as NSString).range(of: caretText).location + 3
        XCTAssertEqual(surface.selectionTextView.selectedRange().location, reopened,
                       "open: the caret stays on its own line", file: file, line: line)

        surface.toggleOmission(key)
        XCTAssertEqual(surface.selectionTextView.selectedRange().location, caretAt,
                       "shut: the caret comes back to the same spot", file: file, line: line)
        _ = grown
    }

    func testTogglingKeepsTheCaretInTheSingleContainer() throws {
        let (editor, surface) = try opened(tallFdx())
        XCTAssertFalse(surface.usesPageSheets)
        try assertToggleKeepsTheCaret(editor, surface)
    }

    func testTogglingKeepsTheCaretOnPageSheets() throws {
        let arrangement = PageArrangement.stored
        let mode = PageLayoutMode.stored
        PageArrangement.store(.single)
        PageLayoutMode.store(.pages)
        defer {
            PageArrangement.store(arrangement)
            PageLayoutMode.store(mode)
        }

        let file = try ScreenplayFile.open(tallFdx(), as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let surface = ScriptSurface(multiContainerSpreadEnabled: true)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1500, height: 1100)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        surface.setArrangement(.spread)
        surface.scrollView.layoutSubtreeIfNeeded()
        XCTAssertTrue(surface.usesPageSheets)

        try assertToggleKeepsTheCaret(editor, surface)

        /* The viewport, too: scrolled midway before the toggle, it must not
           chase anything — least of all the last page. */
        let clip = surface.scrollView.contentView
        let midway = NSPoint(x: 0, y: max(0, surface.canvas.frame.height / 2 - clip.bounds.height / 2))
        clip.scroll(to: midway)
        surface.scrollView.reflectScrolledClipView(clip)
        surface.toggleOmission(try key(editor))
        XCTAssertEqual(clip.bounds.origin.y, midway.y, accuracy: 60,
                       "the page the writer was reading does not move")
    }

    // MARK: - Collapsed by default

    func testTheCutBodyIsNotInTheLayoutAtAll() throws {
        let (_, surface) = try opened(fdx())
        let text = laid(surface)
        XCTAssertTrue(text.contains("OMITTED"), "the card is the line that stands in its place")
        XCTAssertFalse(text.contains("EXT. THE YARD - DUSK"), "the cut heading is out of the flow")
        XCTAssertFalse(text.contains("Mara waits."), "and so is its body")
        XCTAssertTrue(text.contains("The kettle screams."), "the live script is untouched")
    }

    /// The invariant the whole design rests on.
    func testRangesStayParallelToElementsWithHiddenOnesEmpty() throws {
        let (editor, surface) = try opened(fdx())
        XCTAssertEqual(surface.ranges.count, editor.screenplay.elements.count)
        for (index, element) in editor.screenplay.elements.enumerated() {
            XCTAssertEqual(surface.ranges[index].id, element.id, "range \(index) is its element's")
            if editor.isOmitted(element) {
                XCTAssertEqual(surface.ranges[index].range.length, 0, "a hidden element holds no text")
            }
        }
        // And every hidden element sits at its card's foot, not at zero.
        let card = try XCTUnwrap(editor.screenplay.elements.firstIndex { editor.omittedScenes.isCard($0) })
        let foot = surface.ranges[card].range.location + surface.ranges[card].range.length
        for (index, element) in editor.screenplay.elements.enumerated() where editor.isOmitted(element) {
            XCTAssertEqual(surface.ranges[index].range.location, foot)
        }
    }

    /// The layout decides what to lay out; the pagination decides what to
    /// count. They are two code paths over one predicate, and if they ever
    /// disagree the canvas and the page count drift apart again — which is
    /// the bug this design exists to end. So: the text on the page is
    /// exactly the elements `laidElements` names, in order, in both states.
    func testTheLaidTextIsExactlyWhatThePaginatorCounts() throws {
        let (editor, surface) = try opened(fdx())
        for _ in 0...1 {
            let expected = surface.laidElements(editor.screenplay.elements)
                .map(\.text)
                .joined(separator: "\n")
            XCTAssertEqual(laid(surface), expected, "the page and the page count are one script")
            surface.toggleOmission(try key(editor))
        }
    }

    func testNothingIsStruckThroughAnyMore() throws {
        let (_, surface) = try opened(fdx())
        let storage = try XCTUnwrap(surface.textView.textStorage)
        var struck = 0
        storage.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value != nil { struck += 1 }
        }
        XCTAssertEqual(struck, 0, "the struck presentation is gone, not disabled")
    }

    // MARK: - Opening it

    func testTheDisclosurePutsTheBodyBackInTheSameSepia() throws {
        let (editor, surface) = try opened(fdx())
        surface.toggleOmission(try key(editor))
        let text = laid(surface)
        XCTAssertTrue(text.contains("EXT. THE YARD - DUSK"))
        XCTAssertTrue(text.contains("Mara waits."))

        let storage = try XCTUnwrap(surface.textView.textStorage)
        let at = (text as NSString).range(of: "Mara waits.")
        var effective = NSRange()
        let ink = storage.attribute(.foregroundColor, at: at.location, effectiveRange: &effective) as? NSColor
        XCTAssertEqual(ink, NSColor.screenplayOmittedInk, "shown, and plainly not live")
        XCTAssertNil(storage.attribute(.strikethroughStyle, at: at.location, effectiveRange: &effective))
    }

    func testCollapsingPutsItAwayAgain() throws {
        let (editor, surface) = try opened(fdx())
        let scene = try key(editor)
        surface.toggleOmission(scene)
        XCTAssertTrue(surface.isOmissionExpanded(scene))
        surface.toggleOmission(scene)
        XCTAssertFalse(surface.isOmissionExpanded(scene))
        XCTAssertFalse(laid(surface).contains("Mara waits."))
    }

    /// The human's expectation, measured rather than asserted in prose: a
    /// document opened again comes back collapsed, because nothing about
    /// the expansion was written anywhere.
    func testAReopenedDocumentComesBackCollapsed() throws {
        let data = fdx()
        let (editor, surface) = try opened(data)
        surface.toggleOmission(try key(editor))
        XCTAssertTrue(laid(surface).contains("Mara waits."))

        let (reopenedEditor, reopened) = try opened(data)
        XCTAssertTrue(reopened.expandedOmissions.isEmpty, "nothing persisted")
        XCTAssertFalse(laid(reopened).contains("Mara waits."))
        XCTAssertFalse(reopened.isOmissionExpanded(try key(reopenedEditor)))
    }

    // MARK: - Closed to the caret, open or shut

    func testTypingIsRefusedInsideAnOpenedSpan() throws {
        let (editor, surface) = try opened(fdx())
        surface.toggleOmission(try key(editor))
        let at = (laid(surface) as NSString).range(of: "Mara waits.")
        XCTAssertFalse(
            surface.textView(
                surface.textView,
                shouldChangeTextIn: NSRange(location: at.location + 2, length: 0),
                replacementString: "x"
            )
        )
    }

    func testTypingOutsideTheSpanIsUntouchedInBothStates() throws {
        let (editor, surface) = try opened(fdx())
        for _ in 0...1 {
            let at = (laid(surface) as NSString).range(of: "The kettle screams.")
            XCTAssertTrue(
                surface.textView(
                    surface.textView,
                    shouldChangeTextIn: NSRange(location: at.location + 2, length: 0),
                    replacementString: "x"
                ),
                "a live line is a live line either way"
            )
            surface.toggleOmission(try key(editor))
        }
    }

    func testCollapsedThereIsNowhereInsideToPutACaret() throws {
        let (editor, surface) = try opened(fdx())
        let hidden = try XCTUnwrap(editor.screenplay.elements.firstIndex { editor.isOmitted($0) })
        let empty = surface.ranges[hidden].range
        XCTAssertEqual(empty.length, 0)
        XCTAssertFalse(surface.touchesOmitted(empty), "an empty range is not inside anything")
    }

    // MARK: - The chrome

    func testTheRegionIsMarkedCollapsedAndThenOpen() throws {
        let (editor, surface) = try opened(fdx())
        XCTAssertEqual(surface.omittedRegions.count, 1)
        XCTAssertTrue(try XCTUnwrap(surface.omittedRegions.first).collapsed)
        surface.toggleOmission(try key(editor))
        XCTAssertEqual(surface.omittedRegions.count, 1)
        XCTAssertFalse(try XCTUnwrap(surface.omittedRegions.first).collapsed)
    }

    func testTheRegionSaysItselfOutLoud() throws {
        let (editor, _) = try opened(fdx())
        let scene = try XCTUnwrap(editor.omittedScenes.scenes.first)
        XCTAssertEqual(scene.spoken(collapsed: true), "Scene 21, omitted, 0.3 pages cut, collapsed")
        XCTAssertEqual(scene.spoken(collapsed: false), "Scene 21, omitted, 0.3 pages cut, expanded")
        XCTAssertEqual(scene.pillText, "0.3 pgs CUT")
    }

    // MARK: - The overlay's frame

    /// The defect the showcase capture caught: the overlay was framed to the
    /// card's glyphs, so its trailing-aligned chrome — wider than the word
    /// OMITTED — ran leftward over the card and off the page into the
    /// gutter. The overlay belongs to the text column, and the glyph rect
    /// stays what reveals, find and the note wash rely on.
    private func assertOverlaySpansTheColumn(
        _ editor: EditorState, _ surface: ScriptSurface, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let region = try XCTUnwrap(surface.omittedRegions.first, file: file, line: line)
        let overlay = try XCTUnwrap(surface.regionViews[region.key], file: file, line: line)
        let host = try XCTUnwrap(overlay.superview as? NSTextView, file: file, line: line)
        overlay.layoutSubtreeIfNeeded()

        let glyphs = try XCTUnwrap(
            ScriptLayout.sheetBoundingRect(of: region.range, in: host), file: file, line: line
        )
        let column = try XCTUnwrap(host.textContainer, file: file, line: line).size.width

        XCTAssertEqual(overlay.frame.width, column, accuracy: 1,
                       "the overlay is the column, not the word", file: file, line: line)
        XCTAssertGreaterThan(overlay.frame.width, glyphs.width * 2,
                             "the card's glyphs are one word; the column is the page", file: file, line: line)

        let chevron = overlay.convert(overlay.chevronFrame, to: host)
        XCTAssertFalse(chevron.intersects(glyphs), "the chevron never overprints the card's words",
                       file: file, line: line)
        XCTAssertGreaterThan(chevron.minX, glyphs.maxX,
                             "the chevron sits right of the word OMITTED",
                             file: file, line: line)
        XCTAssertLessThanOrEqual(chevron.maxX, overlay.frame.maxX + 1,
                                 "and inside the overlay's frame — ordinary in-bounds chrome",
                                 file: file, line: line)
        XCTAssertEqual(chevron.midY, glyphs.midY, accuracy: 6,
                       "on the card's own line", file: file, line: line)
    }

    /// Open, the region's head is still the card: the chevron that closes
    /// the cut text sits beside the word OMITTED, above the body it shows.
    func testOpenTheChevronStillRidesTheCardsLine() throws {
        let (editor, surface) = try opened(fdx())
        surface.toggleOmission(try key(editor))
        let region = try XCTUnwrap(surface.omittedRegions.first)
        let overlay = try XCTUnwrap(surface.regionViews[region.key])
        let host = try XCTUnwrap(overlay.superview as? NSTextView)
        overlay.layoutSubtreeIfNeeded()

        let text = laid(surface) as NSString
        let cardGlyphs = try XCTUnwrap(
            ScriptLayout.sheetBoundingRect(of: text.range(of: "OMITTED"), in: host))
        let bodyGlyphs = try XCTUnwrap(
            ScriptLayout.sheetBoundingRect(of: text.range(of: "Mara waits."), in: host))
        let chevron = overlay.convert(overlay.chevronFrame, to: host)

        XCTAssertEqual(chevron.midY, cardGlyphs.midY, accuracy: 6,
                       "the way back sits beside the word OMITTED")
        XCTAssertFalse(chevron.intersects(cardGlyphs))
        XCTAssertLessThan(chevron.minY, bodyGlyphs.minY,
                          "the card's line is above the body it opens")
        XCTAssertLessThanOrEqual(overlay.frame.minY, cardGlyphs.minY + 1,
                                 "the overlay covers the card")
        XCTAssertGreaterThanOrEqual(overlay.frame.maxY, bodyGlyphs.maxY - 1,
                                    "and the open body beneath it")
    }

    func testTheOverlaySpansTheColumnInTheSingleContainer() throws {
        let (editor, surface) = try opened(fdx())
        XCTAssertFalse(surface.usesPageSheets)
        try assertOverlaySpansTheColumn(editor, surface)
    }

    func testTheOverlaySpansTheColumnOnAPageSheet() throws {
        let arrangement = PageArrangement.stored
        let mode = PageLayoutMode.stored
        PageArrangement.store(.single)
        PageLayoutMode.store(.pages)
        defer {
            PageArrangement.store(arrangement)
            PageLayoutMode.store(mode)
        }

        let file = try ScreenplayFile.open(fdx(), as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let surface = ScriptSurface(multiContainerSpreadEnabled: true)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1500, height: 1100)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        surface.setArrangement(.spread)
        surface.scrollView.layoutSubtreeIfNeeded()

        XCTAssertTrue(surface.usesPageSheets)
        try assertOverlaySpansTheColumn(editor, surface)
        let region = try XCTUnwrap(surface.omittedRegions.first)
        let host = try XCTUnwrap(surface.regionViews[region.key]?.superview as? NSTextView)
        XCTAssertTrue(surface.sheets.contains { $0.textView === host },
                      "the overlay rides the sheet that draws the card")
    }

    // MARK: - The quiet card

    /// A real enter/exit event, delivered the way the window would.
    private func hover(_ overlay: OmittedSceneRegionView, entered: Bool) {
        let event = NSEvent.enterExitEvent(
            with: entered ? .mouseEntered : .mouseExited,
            location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, trackingNumber: 0, userData: nil
        )
        entered ? overlay.mouseEntered(with: event!) : overlay.mouseExited(with: event!)
    }

    private func overlay(on surface: ScriptSurface) throws -> OmittedSceneRegionView {
        let region = try XCTUnwrap(surface.omittedRegions.first)
        return try XCTUnwrap(surface.regionViews[region.key])
    }

    /// At rest the line is the word OMITTED and nothing else — the chevron
    /// is the whole of the chrome, and it waits for the pointer.
    func testCollapsedAtRestThereIsNoChrome() throws {
        let (_, surface) = try opened(fdx())
        let view = try overlay(on: surface)
        XCTAssertEqual(view.subviews.count, 1, "one chevron is the whole of the chrome")
        XCTAssertFalse(view.chevronVisible, "at rest there is nothing but the word")
    }

    func testHoveringTheLineRevealsTheChevronAndLeavingHidesIt() throws {
        let (_, surface) = try opened(fdx())
        let view = try overlay(on: surface)
        hover(view, entered: true)
        XCTAssertTrue(view.chevronVisible, "the pointer asks, the chevron answers")
        hover(view, entered: false)
        XCTAssertFalse(view.chevronVisible, "and it goes away with the pointer")
    }

    /// An open region keeps its chevron, hovered or not — it is the way back.
    func testAnOpenRegionKeepsItsChevron() throws {
        let (editor, surface) = try opened(fdx())
        surface.toggleOmission(try key(editor))
        let view = try overlay(on: surface)
        XCTAssertTrue(view.chevronVisible)
        hover(view, entered: false)
        XCTAssertTrue(view.chevronVisible, "open is open; the way back does not hide")
    }

    /// The toggle goes through the view's own button, the way a click does.
    func testPressingTheChevronOpensAndClosesTheCutText() throws {
        let (editor, surface) = try opened(fdx())
        let view = try overlay(on: surface)
        hover(view, entered: true)
        view.accessibilityPerformPress()
        XCTAssertTrue(laid(surface).contains("Mara waits."), "the cut text opens inline")
        XCTAssertFalse(try overlay(on: surface).collapsed)
        try overlay(on: surface).accessibilityPerformPress()
        XCTAssertFalse(laid(surface).contains("Mara waits."), "and folds away again")
    }

    /// The length is production data: the tooltip and VoiceOver say it in
    /// words, and the page never carries it.
    func testTheLengthIsSpokenAndHoveredButNeverStamped() throws {
        let (editor, surface) = try opened(fdx())
        let view = try overlay(on: surface)
        XCTAssertEqual(view.toolTip, "Scene 21, omitted, 0.3 pages cut, collapsed")
        surface.toggleOmission(try key(editor))
        XCTAssertEqual(try overlay(on: surface).toolTip, "Scene 21, omitted, 0.3 pages cut, expanded")
    }

    /// The chevron is the only thing on the overlay that takes a click —
    /// the card's line stays a live line the caret can land on.
    func testOnlyTheChevronTakesAClick() throws {
        let (_, surface) = try opened(fdx())
        let view = try overlay(on: surface)
        view.frame = NSRect(x: 0, y: 0, width: 500, height: 20)
        hover(view, entered: true)
        view.layoutSubtreeIfNeeded()
        /* hitTest reads a point in the superview's coordinates. */
        let middle = view.convert(NSPoint(x: 250, y: 10), to: view.superview)
        XCTAssertNil(view.hitTest(middle), "a click mid-line belongs to the text")
        let onChevron = view.convert(
            NSPoint(x: view.chevronFrame.midX, y: view.chevronFrame.midY), to: view.superview
        )
        XCTAssertNotNil(view.hitTest(onChevron), "a click on the chevron is the chevron's")
    }

    /// The reveal and the hide are eased, not snapped — hover chrome the
    /// way macOS does it. The animation's target is set the moment the
    /// state changes; the runloop owns only the in-between frames.
    func testTheChevronFadesInAndOutWithEasing() throws {
        let (_, surface) = try opened(fdx())
        let view = try overlay(on: surface)
        let chevron = try XCTUnwrap(view.subviews.first as? NSButton)
        XCTAssertEqual(chevron.alphaValue, 0, "at rest there is nothing but the word")
        hover(view, entered: true)
        XCTAssertEqual(chevron.alphaValue, 1, "the pointer asks, the chevron fades in")
        hover(view, entered: false)
        XCTAssertEqual(chevron.alphaValue, 0, "and it fades away with the pointer")
    }

    // MARK: - The sepia, on both papers

    func testTheSepiaIsLegibleOnBothPapers() {
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            var ink: NSColor?
            var paper: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                ink = NSColor.screenplayOmittedInk.usingColorSpace(.sRGB)
                paper = NSColor.screenplayPaper.usingColorSpace(.sRGB)
            }
            let contrast = Self.contrast(try! XCTUnwrap(ink), try! XCTUnwrap(paper))
            XCTAssertGreaterThanOrEqual(
                contrast, 4.5,
                "a whole cut scene is read in this ink; \(dark ? "dark" : "light") paper was \(contrast)"
            )
        }
    }

    /// WCAG relative luminance, so "legible" is a number and not a taste.
    private static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        func luminance(_ color: NSColor) -> Double {
            func channel(_ value: CGFloat) -> Double {
                let v = Double(value)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(color.redComponent)
                + 0.7152 * channel(color.greenComponent)
                + 0.0722 * channel(color.blueComponent)
        }
        let first = luminance(a), second = luminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    // MARK: - Edge cases

    func testAnOmissionAsTheDocumentsFirstElement() throws {
        let (editor, surface) = try opened(fdx(before: []))
        XCTAssertEqual(editor.omittedScenes.scenes.count, 1)
        XCTAssertFalse(laid(surface).contains("Mara waits."))
        XCTAssertTrue(laid(surface).hasPrefix("OMITTED"), "the card opens the document")
        XCTAssertEqual(surface.ranges.count, editor.screenplay.elements.count)
    }

    func testAnOmissionAsTheDocumentsLastElement() throws {
        let (editor, surface) = try opened(fdx(after: []))
        XCTAssertEqual(editor.omittedScenes.scenes.count, 1)
        XCTAssertFalse(laid(surface).contains("Mara waits."))
        XCTAssertTrue(laid(surface).hasSuffix("OMITTED"), "the card closes the document")
        XCTAssertEqual(surface.ranges.count, editor.screenplay.elements.count)
    }

    func testTwoOmissionsSeparatedByOneLiveParagraph() throws {
        let two = Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        <Paragraph Number="21" Type="Scene Heading">
        <Text>OMITTED</Text>
        <OmittedScene>
        <Paragraph Type="Scene Heading"><SceneProperties Length="2/8"></SceneProperties><Text>EXT. THE YARD - DUSK</Text></Paragraph>
        </OmittedScene>
        </Paragraph>
        <Paragraph Type="Action"><Text>One live line between them.</Text></Paragraph>
        <Paragraph Number="22" Type="Scene Heading">
        <Text>OMITTED</Text>
        <OmittedScene>
        <Paragraph Type="Scene Heading"><SceneProperties Length="1 4/8"></SceneProperties><Text>INT. THE HALL - DAY</Text></Paragraph>
        </OmittedScene>
        </Paragraph>
        </Content>
        </FinalDraft>
        """.utf8)
        let (editor, surface) = try opened(two)
        XCTAssertEqual(editor.omittedScenes.scenes.count, 2)
        XCTAssertEqual(surface.omittedRegions.count, 2)
        XCTAssertEqual(editor.omittedScenes.scenes.map(\.sceneNumber), ["21", "22"])
        XCTAssertEqual(editor.omittedScenes.scenes.map(\.pillText), ["0.3 pgs CUT", "1.5 pgs CUT"])

        let text = laid(surface)
        XCTAssertTrue(text.contains("One live line between them."), "the live line survives between them")
        XCTAssertFalse(text.contains("EXT. THE YARD - DUSK"))
        XCTAssertFalse(text.contains("INT. THE HALL - DAY"))
        XCTAssertEqual(surface.ranges.count, editor.screenplay.elements.count)

        // Opening one leaves the other shut.
        surface.toggleOmission(editor.omittedScenes.scenes[0].key)
        XCTAssertTrue(laid(surface).contains("EXT. THE YARD - DUSK"))
        XCTAssertFalse(laid(surface).contains("INT. THE HALL - DAY"))
    }
}
