import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// The paper covers the words.
///
/// The engine counts pages by wrapping at sixty Courier characters; the text
/// view lays out by measuring glyphs. They agree almost always and not quite
/// always — measured on a real production draft, the type needed a
/// twenty-eighth sheet where the engine had counted twenty-seven. The stack
/// was built from that count alone, so the last hundred points of the script
/// were drawn past the final sheet and past the canvas, where a scroll view
/// cannot travel. In `pages` the script simply ended early; `continuous`
/// showed the rest, which is how it was noticed.
///
/// Losing the end of someone's script is the worst thing this app can do, so
/// the invariant is stated on its own rather than left to follow from the
/// page count.
@MainActor
final class PaperHoldsTheTypeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        let original = PageLayoutMode.stored
        addTeardownBlock { PageLayoutMode.store(original) }
    }

    private let format = PageFormat.letter

    // MARK: - The arithmetic

    func testOneSheetHoldsUpToOneTextBlock() {
        let block = ScreenplayPageLayout.textBlockHeight(format)
        XCTAssertEqual(PageCanvasView.sheetsHolding(0, format: format), 1)
        XCTAssertEqual(PageCanvasView.sheetsHolding(block, format: format), 1)
    }

    func testAnythingPastOneBlockNeedsASecondSheet() {
        let block = ScreenplayPageLayout.textBlockHeight(format)
        XCTAssertEqual(PageCanvasView.sheetsHolding(block + 1, format: format), 2)
    }

    /// Type on sheet *k* starts at that sheet's text top, so each further
    /// sheet buys a whole page plus the gap between them.
    func testEachFurtherSheetBuysAPageAndAGap() {
        let block = ScreenplayPageLayout.textBlockHeight(format)
        let perSheet = format.pageRect.height + PageCanvasView.pageGap
        XCTAssertEqual(PageCanvasView.sheetsHolding(block + perSheet, format: format), 2)
        XCTAssertEqual(PageCanvasView.sheetsHolding(block + perSheet + 1, format: format), 3)
    }

    // MARK: - The canvas

    /// The case that shipped: the paginator says two pages, the type needs
    /// five sheets' worth. The paper must follow the type, not the count.
    func testTheStackGrowsWhenTheTypeNeedsMorePaperThanThePageCountSays() {
        let canvas = PageCanvasView()
        canvas.layoutMode = .pages
        let textView = NSTextView(frame: .zero)
        canvas.attach(textView)

        let block = ScreenplayPageLayout.textBlockHeight(format)
        let perSheet = format.pageRect.height + PageCanvasView.pageGap
        let tallType = block + perSheet * 4 - 1        // needs five sheets

        canvas.layoutPages(
            pageCount: 2, textHeight: tallType, viewport: CGSize(width: 900, height: 700)
        )

        XCTAssertGreaterThanOrEqual(
            canvas.pageViews.count, 5,
            "the paginator's two pages left the type running off the second sheet"
        )
        let lastSheet = try? XCTUnwrap(canvas.pageViews.last?.frame)
        XCTAssertGreaterThanOrEqual(
            (lastSheet?.maxY ?? 0) + canvas.canvasPadding, canvas.frame.height - 1,
            "the canvas does not reach the last sheet"
        )
    }

    /// No line of the script may be drawn in a sheet's bottom margin.
    ///
    /// This is the one a writer sees: a character cue left at the foot of a
    /// page with its dialogue on the next, and type running across the gap
    /// between two sheets into the margin of the one below. Both were the
    /// same thing — the exclusion paths are built from the engine's page
    /// starts and stopped at the last of them, so whatever the text view laid
    /// out past the final counted page simply flowed on.
    ///
    /// Measured on the draft it was reported from: type ran past the block on
    /// 25 of 26 sheets before the measure was taken from the font, 1 of 28
    /// after, and 0 of 28 once the overflow was placed on paper of its own.
    func testNoLineIsDrawnInASheetsBottomMargin() throws {
        let surface = ScriptSurface(measure: ScriptLayout.pageMeasure)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        surface.render(longScript())
        surface.setLayoutMode(.pages)
        surface.scrollView.layoutSubtreeIfNeeded()

        let format = PageFormat.current
        let block = ScreenplayPageLayout.textBlockHeight(format)
        let layoutManager = try XCTUnwrap(surface.textView.layoutManager)
        let container = try XCTUnwrap(surface.textView.textContainer)
        layoutManager.ensureLayout(for: container)
        let text = surface.textView.string as NSString

        for (index, sheet) in surface.pageFrames.enumerated() {
            let blockBottom = sheet.minY + format.textTop + block
            var deepest: CGFloat = 0
            var offender = ""
            layoutManager.enumerateLineFragments(
                forGlyphRange: NSRange(location: 0, length: layoutManager.numberOfGlyphs)
            ) { _, used, _, glyphRange, _ in
                let characters = layoutManager.characterRange(
                    forGlyphRange: glyphRange, actualGlyphRange: nil
                )
                guard characters.location + characters.length <= text.length else { return }
                let line = text.substring(with: characters)
                guard !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let inCanvas = surface.canvas.convert(used, from: surface.textView)
                guard inCanvas.minY >= sheet.minY - 1, inCanvas.minY < sheet.maxY else { return }
                if inCanvas.maxY > deepest { deepest = inCanvas.maxY; offender = line }
            }
            XCTAssertLessThanOrEqual(
                deepest, blockBottom + 1,
                "sheet \(index + 1) has type \(Int(deepest - blockBottom))pt into its bottom "
                    + "margin — \(offender.prefix(40))"
            )
        }
    }

    /// Long enough to run past several page boundaries, with full-measure
    /// action so the wrap is the thing under test.
    private func longScript() -> [ScriptElement] {
        var elements: [ScriptElement] = []
        for beat in 1...120 {
            elements.append(ScriptElement(type: .scene, text: "INT. ROOM \(beat) - DAY"))
            elements.append(ScriptElement(
                type: .action,
                text: "Action for beat \(beat), written long enough that it fills the measure and "
                    + "wraps, which is where the engine's characters and the text view's glyphs "
                    + "can part company."
            ))
            elements.append(ScriptElement(type: .character, text: "MARA"))
            elements.append(ScriptElement(type: .dialogue, text: "Line \(beat), plainly said."))
        }
        return elements
    }

    /// Whatever the mode and whatever the count, no glyph may be drawn where
    /// the scroll view cannot go.
    func testNoGlyphIsEverDrawnPastTheCanvas() throws {
        for mode in [PageLayoutMode.pages, .continuous] {
            var elements: [ScriptElement] = []
            for beat in 1...90 {
                elements.append(ScriptElement(type: .scene, text: "INT. ROOM \(beat) - DAY"))
                elements.append(ScriptElement(
                    type: .action,
                    text: "Action for beat \(beat), long enough to wrap across the measure twice "
                        + "and put the wrap points where the engine and the text view can differ."
                ))
                elements.append(ScriptElement(type: .character, text: "MARA"))
                elements.append(ScriptElement(type: .dialogue, text: "Line \(beat), plainly."))
            }

            let surface = ScriptSurface(measure: 500)
            surface.scrollView.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
            surface.render(elements)
            surface.setLayoutMode(mode)
            surface.scrollView.layoutSubtreeIfNeeded()

            let length = (surface.textView.string as NSString).length
            let layoutManager = try XCTUnwrap(surface.textView.layoutManager)
            let container = try XCTUnwrap(surface.textView.textContainer)
            layoutManager.ensureLayout(for: container)
            let last = layoutManager.boundingRect(
                forGlyphRange: NSRange(location: max(0, length - 1), length: 1), in: container
            )
            let bottom = surface.canvas.convert(last, from: surface.textView).maxY

            XCTAssertLessThanOrEqual(
                bottom, surface.canvas.frame.height,
                "in \(mode) the last line is \(Int(bottom - surface.canvas.frame.height)) points "
                    + "past the canvas, where the writer cannot scroll to it"
            )
        }
    }
}
