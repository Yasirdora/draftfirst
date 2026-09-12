import EDraftEngine
import XCTest
import EDraftCore
@testable import EDraftMacSurface

/// Bold, italic, underline and strikethrough are style runs in the model
/// now (RFC v2.1): the bar adjusts the runs directly, no marker character
/// ever enters the text, and one undo step lifts the whole change. Centre
/// still rewrites the line through the input path.
@MainActor
final class SelectionFormatBarTests: XCTestCase {

    private func surface(_ source: String) -> (EditorState, ScriptSurface) {
        let editor = EditorState(source: source)
        let surface = ScriptSurface()
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        return (editor, surface)
    }

    private func select(_ text: String, in surface: ScriptSurface) {
        surface.textView.setSelectedRange((surface.textView.string as NSString).range(of: text))
    }

    func testBoldPaintsARunAndAgainLiftsIt() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        select("hangs", in: surface)

        surface.applyMark(.bold)
        XCTAssertTrue(surface.textView.string.contains("Dust hangs in"))
        XCTAssertFalse(
            surface.textView.string.contains("**"),
            "no marker characters enter the text"
        )
        XCTAssertEqual(
            editor.screenplay.elements.last?.runs,
            [StyleRun(start: 5, end: 10, styles: .bold)],
            "the model carries the style as data"
        )
        XCTAssertEqual(
            surface.textView.selectedRange().length, ("hangs" as NSString).length,
            "the word stays selected, so a second press takes it off"
        )

        surface.applyMark(.bold)
        XCTAssertNil(editor.screenplay.elements.last?.runs)
        XCTAssertTrue(surface.textView.string.contains("Dust hangs in"))
    }

    func testTheToggleIsOneNamedUndoStep() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        select("hangs", in: surface)
        surface.applyMark(.bold)
        XCTAssertNotNil(editor.screenplay.elements.last?.runs)

        editor.undo()
        XCTAssertNil(
            editor.screenplay.elements.last?.runs,
            "one undo lifts the whole toggle"
        )
        editor.redo()
        XCTAssertEqual(
            editor.screenplay.elements.last?.runs,
            [StyleRun(start: 5, end: 10, styles: .bold)]
        )
    }

    func testAMixedSelectionOnlyAdds() {
        // One paragraph already bold, one plain; selecting across both and
        // pressing Bold must not strip the bold one — the global decision is
        // "not all covered, so add".
        let (editor, surface) = surface("plain\n\nworn")
        select("worn", in: surface)
        surface.applyMark(.bold)
        XCTAssertEqual(
            editor.screenplay.elements.last?.runs,
            [StyleRun(start: 0, end: 4, styles: .bold)]
        )

        let whole = surface.textView.string as NSString
        surface.textView.setSelectedRange(NSRange(location: 0, length: whole.length))
        surface.applyMark(.bold)
        XCTAssertEqual(
            editor.screenplay.elements.first?.runs,
            [StyleRun(start: 0, end: 5, styles: .bold)],
            "the plain paragraph gains the style"
        )
        XCTAssertEqual(
            editor.screenplay.elements.last?.runs,
            [StyleRun(start: 0, end: 4, styles: .bold)],
            "the styled paragraph keeps it — a mixed selection adds, never strips"
        )

        surface.applyMark(.bold)
        XCTAssertNil(editor.screenplay.elements.first?.runs)
        XCTAssertNil(editor.screenplay.elements.last?.runs)
    }

    func testTheBarReadsWhatTheSelectionWears() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        select("hangs", in: surface)
        surface.applyMark(.bold)

        select("hangs", in: surface)
        XCTAssertEqual(
            surface.styleCoverage(at: surface.textView.selectedRange()),
            [.bold],
            "a covered selection lights its mark"
        )
        select("Dust", in: surface)
        XCTAssertEqual(
            surface.styleCoverage(at: surface.textView.selectedRange()),
            [],
            "a bare selection lights nothing"
        )
        _ = editor
    }

    func testACaretReadsTheNextKeystrokesStyle() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        select("hangs", in: surface)
        surface.applyMark(.bold)

        // Caret inside the bold word: the donor rule says the next keystroke
        // is bold, and the bar agrees.
        let word = (surface.textView.string as NSString).range(of: "hangs")
        surface.textView.setSelectedRange(NSRange(location: word.location + 2, length: 0))
        XCTAssertEqual(surface.styleCoverage(at: surface.textView.selectedRange()), [.bold])

        // Caret in the plain word beside it: nothing lights.
        let plain = (surface.textView.string as NSString).range(of: "Dust")
        surface.textView.setSelectedRange(NSRange(location: plain.location + 2, length: 0))
        XCTAssertEqual(surface.styleCoverage(at: surface.textView.selectedRange()), [])
        _ = editor
    }

    /// Centre Line flips the element's type, and the text stays exactly the
    /// writer's — no `> <` marker ever enters it. The line draws centred
    /// because that is what the type means.
    func testCentreMarksTheWholeLineAndAgainUnmarksIt() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nThe end.")
        select("end", in: surface)

        surface.toggleCentered(named: "Center Line")
        XCTAssertEqual(editor.screenplay.elements.last?.type, .centered)
        XCTAssertFalse(
            surface.textView.string.contains(">") || surface.textView.string.contains("<"),
            "no marker characters enter the text"
        )
        let lineRange = (surface.textView.string as NSString).range(of: "The end.")
        let paragraph = surface.textView.textStorage?
            .attribute(.paragraphStyle, at: lineRange.location, effectiveRange: nil)
            as? NSParagraphStyle
        XCTAssertEqual(paragraph?.alignment, .center, "a centred line draws centred")

        surface.toggleCentered(named: "Center Line")
        XCTAssertEqual(editor.screenplay.elements.last?.type, .action,
                       "centring again takes the line back to action")
        XCTAssertFalse(surface.textView.string.contains("> The end. <"))
    }

    /// One undo lifts the whole flip, named like the styles are.
    func testCentreIsOneNamedUndoStep() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nThe end.")
        select("end", in: surface)
        surface.toggleCentered(named: "Center Line")
        XCTAssertEqual(editor.screenplay.elements.last?.type, .centered)

        editor.undo()
        XCTAssertEqual(editor.screenplay.elements.last?.type, .action,
                       "one undo takes the line back to action")
    }

    /// One decision for the whole selection, the rule the styles set: a
    /// selection spanning a centred line and a plain one centres them all —
    /// it does not strip the first and centre the second.
    func testCentreDecidesOnceForAMixedSelection() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nThe end.")
        select("LAB", in: surface)
        surface.toggleCentered(named: "Center Line")
        XCTAssertEqual(editor.screenplay.elements.first?.type, .centered)
        XCTAssertEqual(editor.screenplay.elements.last?.type, .action)

        let whole = surface.textView.string as NSString
        let span = NSUnionRange(whole.range(of: "LAB"), whole.range(of: "The"))
        surface.textView.setSelectedRange(span)
        surface.toggleCentered(named: "Center Line")
        XCTAssertEqual(editor.screenplay.elements.first?.type, .centered,
                       "the centred line is not stripped")
        XCTAssertEqual(editor.screenplay.elements.last?.type, .centered,
                       "the plain line joins it")

        surface.toggleCentered(named: "Center Line")
        XCTAssertEqual(editor.screenplay.elements.first?.type, .action)
        XCTAssertEqual(editor.screenplay.elements.last?.type, .action)
    }

    func testAStyleMarkNeedsASelection() {
        let (editor, surface) = surface("INT. LAB - DAY")
        surface.textView.setSelectedRange(NSRange(location: 0, length: 0))
        surface.applyMark(.italic)
        XCTAssertNil(editor.screenplay.elements.last?.runs)
        XCTAssertFalse(surface.textView.string.contains("*"))
    }

    // MARK: - The bar as chrome

    /// The bar is chrome, not content: it never joins the magnification
    /// transform, so it stays crisp at any zoom. But a bar pinned to one
    /// size reads as *shrinking* beside a growing page, so it breathes with
    /// the zoom at the square root of it (`PageZoom.chromeScale`): the page
    /// doubles at 200% while the bar rises 41% — and it never leaves its
    /// selection.
    func testTheBarScalesWithTheZoomButSlowerThanThePage() {
        let tall = (1...200).map { "Line \($0) of action and a few more words." }
            .joined(separator: "\n\n")
        let (_, surface) = surface("INT. LAB - DAY\n\n" + tall)
        select("Line 100 of action", in: surface)
        surface.applyMark(.bold)

        let selection = surface.textView.selectedRange()
        let clip = surface.scrollView.contentView
        func placed() -> CGRect {
            surface.scrollView.convert(
                ScriptLayout.boundingRect(of: selection, in: surface.textView)!,
                from: surface.textView
            )
        }

        // Centre the selection vertically in the viewport: a zoom anchors
        // the viewport's centre, so what is centred stays on screen through
        // it. Horizontally the document fits the window at 100%, so the page
        // sits centred and nothing is near an edge.
        let canvasY = surface.canvas.convert(
            ScriptLayout.boundingRect(of: selection, in: surface.textView)!,
            from: surface.textView
        ).midY
        clip.scroll(to: NSPoint(x: 0, y: canvasY - clip.bounds.height / 2))

        guard let before = surface.formatBarFrame else {
            return XCTFail("the bar should be up over a selection")
        }
        XCTAssertEqual(before.midX, placed().midX, accuracy: 1.5, "centred on the selection")
        XCTAssertEqual(before.maxY, placed().minY - 8, accuracy: 1.5, "just above it, eight points of air")

        surface.scrollView.magnification = 2.0
        // The zoom anchored the viewport's centre, which is not where the
        // selection sits horizontally; pan the page left edge into view so
        // the selection stands clear of the window's edge again.
        clip.scroll(to: NSPoint(x: 0, y: clip.bounds.origin.y))

        guard let zoomed = surface.formatBarFrame else {
            return XCTFail("a centred selection stays on screen through a zoom, bar included")
        }
        let growth = PageZoom.chromeScale(at: 2) / PageZoom.chromeScale(at: 1)
        XCTAssertEqual(zoomed.width, before.width * growth, accuracy: 1.5,
                       "the bar breathes with the zoom at its square root")
        XCTAssertEqual(zoomed.height, before.height * growth, accuracy: 1.5)
        XCTAssertGreaterThan(zoomed.width, before.width, "a pinned size reads as shrinking")
        XCTAssertLessThan(zoomed.width, before.width * 2, "and the bar never outruns the page")
        XCTAssertEqual(
            zoomed.midX, placed().midX, accuracy: 1.5,
            "still centred on the selection after the page moved under it"
        )
        XCTAssertEqual(
            zoomed.maxY, placed().minY - 8, accuracy: 1.5,
            "still floating just above the selection"
        )
    }

    /// A palette never takes the keyboard. A bar that accepts first responder
    /// turns the selection grey and eats the next keystroke.
    func testTheBarNeverTakesFirstResponder() {
        let (_, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        select("hangs", in: surface)
        surface.applyMark(.bold)
        XCTAssertFalse(surface.formatBarHostView.acceptsFirstResponder)
    }

    /// A click that misses a button lands on glass, not on the script: every
    /// point inside the frame hits the bar, so the caret can never be punched
    /// into the text the writer was about to format. And a hidden bar — the
    /// glass pulled away — swallows nothing.
    func testAClickAnywhereOnTheBarReachesTheBarNeverTheText() {
        let (_, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        select("hangs", in: surface)
        surface.applyMark(.bold)
        let host = surface.formatBarHostView

        let inside = NSPoint(x: host.frame.midX, y: host.frame.midY)
        XCTAssertEqual(host.hitTest(inside), host)
        let outside = NSPoint(x: host.frame.minX - 40, y: host.frame.minY - 40)
        XCTAssertNil(host.hitTest(outside))

        surface.textView.setSelectedRange(NSRange(location: 0, length: 0))
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: surface.textView)
        )
        XCTAssertNil(surface.formatBarFrame, "a collapsed selection hides the bar")
        XCTAssertNil(host.hitTest(inside), "a hidden bar swallows no click")
    }

    /// The bar speaks for text on screen. Scrolled away from its selection,
    /// it leaves rather than hovering over the desk and pointing at nothing;
    /// scrolled back, it returns.
    func testTheBarLeavesWithItsSelectionAndReturnsWithIt() {
        let tall = (1...200).map { "Line \($0) of action and a few more words." }
            .joined(separator: "\n\n")
        let (_, surface) = surface("INT. LAB - DAY\n\n" + tall)
        select("Line 3 of action", in: surface)
        surface.applyMark(.bold)
        XCTAssertNotNil(surface.formatBarFrame, "the bar is up over its selection")

        let clip = surface.scrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: 100_000))
        XCTAssertNil(
            surface.formatBarFrame,
            "the selection scrolled out of sight, so the bar went with it"
        )

        clip.scroll(to: NSPoint(x: 0, y: 0))
        XCTAssertNotNil(
            surface.formatBarFrame,
            "the selection scrolled back into sight, so the bar returned"
        )
    }

    /// Over chrome the cursor is the arrow. The text view's document-wide
    /// I-beam is a cursor rect, which the window re-resolves on every mouse
    /// move — so an answer given only at the boundary (a cursor rect, or a
    /// `cursorUpdate`-only area) holds until the first move inside the bar.
    /// The bar's tracking area therefore also carries `.mouseMoved`, and the
    /// host re-states the arrow on each one; the events reach it because its
    /// `hitTest` claims the whole frame.
    func testTheBarClaimsTheArrowCursor() {
        let (_, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        let host = surface.formatBarHostView

        host.updateTrackingAreas()
        host.updateTrackingAreas()
        let areas = host.trackingAreas.filter {
            ($0.owner as? NSView) === host && $0.options.contains(.cursorUpdate)
        }
        XCTAssertEqual(areas.count, 1, "the bar needs exactly one cursor voice")
        XCTAssertTrue(
            areas[0].options.contains(.mouseMoved),
            "the I-beam is re-applied on every move, so the arrow must be too"
        )
        XCTAssertTrue(
            areas[0].options.contains(.inVisibleRect),
            "the bar is re-framed on every scroll tick; the area must follow on its own"
        )
        XCTAssertTrue(
            areas[0].options.contains(.activeAlways),
            "a palette answers before its window is key"
        )
    }

    /// The highlighter is the run's other property through the same model
    /// path: one decision for the whole selection, one named undo step,
    /// and the mark in the storage where content belongs.
    func testHighlightMarksAndAgainLiftsIt() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        select("hangs", in: surface)

        surface.applyMark(.highlight)
        XCTAssertEqual(
            editor.screenplay.elements.last?.runs,
            [StyleRun(start: 5, end: 10, styles: [], highlight: .yellow)]
        )
        let range = (surface.textView.string as NSString).range(of: "hangs")
        let background = surface.textView.textStorage?
            .attribute(.backgroundColor, at: range.location, effectiveRange: nil)
        XCTAssertNotNil(background, "the mark draws as a wash on the paper")
        XCTAssertTrue(
            surface.styleCoverage(at: surface.textView.selectedRange()).contains(.highlight),
            "the bar reads the mark the selection wears"
        )

        surface.applyMark(.highlight)
        XCTAssertNil(editor.screenplay.elements.last?.runs, "one more takes it off")
        XCTAssertFalse(
            surface.styleCoverage(at: surface.textView.selectedRange()).contains(.highlight)
        )
    }

    /// One undo lifts the whole mark, named like the styles are.
    func testHighlightIsOneNamedUndoStep() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        select("hangs", in: surface)
        surface.applyMark(.highlight)
        XCTAssertNotNil(editor.screenplay.elements.last?.runs)

        editor.undo()
        XCTAssertNil(editor.screenplay.elements.last?.runs, "one undo lifts the mark")
    }

    /// A mixed selection decides once: a span half-marked gets marked
    /// everywhere; it does not strip the marked half.
    func testHighlightDecidesOnceForAMixedSelection() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        select("hangs", in: surface)
        surface.applyMark(.highlight)
        XCTAssertEqual(editor.screenplay.elements.last?.runs?.count, 1)

        let whole = (surface.textView.string as NSString).range(of: "Dust hangs in the light.")
        surface.textView.setSelectedRange(whole)
        surface.applyMark(.highlight)
        XCTAssertTrue(
            Emphasis.highlightCovered(
                editor.screenplay.elements.last?.runs ?? [],
                from: 0, to: ("Dust hangs in the light." as NSString).length
            ),
            "the mixed selection is marked everywhere, not stripped"
        )
    }

    /// The wash yields to the mark: a noted line keeps its tint everywhere
    /// except where a highlight stands (docs/RFC-HIGHLIGHTER.md §4).
    func testTheNoteWashYieldsToTheMark() {
        let (editor, surface) = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        let action = editor.screenplay.elements.last!
        editor.addNote("check this", to: action.id)
        surface.renderIfNeeded(editor)
        let noted = (surface.textView.string as NSString).range(of: "Dust hangs in the light.")
        let storage = surface.textView.textStorage!
        let lm = surface.textView.layoutManager!

        select("hangs", in: surface)
        surface.applyMark(.highlight)

        let hangs = (surface.textView.string as NSString).range(of: "hangs")
        let washOnHangs = lm.temporaryAttribute(
            .backgroundColor, atCharacterIndex: hangs.location, effectiveRange: nil
        )
        XCTAssertNil(washOnHangs, "the note's wash sits on the mark it must yield to")

        let washOnDust = lm.temporaryAttribute(
            .backgroundColor, atCharacterIndex: noted.location, effectiveRange: nil
        )
        XCTAssertNotNil(washOnDust, "the rest of the noted line keeps its tint")
        XCTAssertNotNil(
            storage.attribute(.backgroundColor, at: hangs.location, effectiveRange: nil),
            "the mark itself is in the storage"
        )
    }
}
