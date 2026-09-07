import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// Sheets, or one column, and the same pagination either way.
///
/// The sheets used to stand 36 points apart, which is a gutter every
/// fifty-five lines and breaks the read for no gain. They meet now, marked by
/// a hairline — and `PageLayoutMode.continuous` drops the sheets altogether,
/// collapsing the 132 points of margin every boundary repeats. What neither
/// may do is move a line onto a different page.
@MainActor
final class DiscreteSheetsTests: XCTestCase {

    /// `setLayoutMode` writes the preference, which is right for the app and
    /// poison for a suite: a test that switches to continuous leaves every
    /// later test — and the writer's own app — in continuous. Put back what
    /// was there.
    override func setUp() {
        super.setUp()
        let original = PageLayoutMode.stored
        addTeardownBlock { PageLayoutMode.store(original) }
    }

    private func script(scenes: Int) -> [ScriptElement] {
        var elements: [ScriptElement] = []
        for beat in 1...scenes {
            elements.append(ScriptElement(type: .scene, text: "INT. ROOM \(beat) - DAY"))
            elements.append(ScriptElement(
                type: .action,
                text: "Action for beat \(beat). The road holds its breath for a full line of the page."
            ))
            elements.append(ScriptElement(type: .character, text: "MARA"))
            elements.append(ScriptElement(
                type: .dialogue,
                text: "Line \(beat), spoken plainly and without hurry at all."
            ))
        }
        return elements
    }

    private func surface(_ elements: [ScriptElement]) -> ScriptSurface {
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
        surface.render(elements)
        return surface
    }

    private func surface(_ elements: [ScriptElement], mode: PageLayoutMode) -> ScriptSurface {
        let surface = surface(elements)
        surface.setLayoutMode(mode)
        return surface
    }

    func testAFourPageScriptIsFourSheetsJoinedAtALine() throws {
        let elements = script(scenes: 25)
        let surface = surface(elements, mode: .pages)
        let pages = try XCTUnwrap(ScreenplayExporter.paginate(Screenplay(elements: elements)))
        XCTAssertGreaterThanOrEqual(pages.count, 4, "25 scenes must paginate past four pages")

        XCTAssertEqual(surface.pageFrames.count, pages.count)
        for (index, frame) in surface.pageFrames.enumerated() {
            XCTAssertEqual(frame.height, PageFormat.letter.pageRect.height, accuracy: 0.5)
            XCTAssertEqual(frame.width, PageFormat.letter.pageRect.width, accuracy: 0.5)
            if index > 0 {
                XCTAssertEqual(
                    frame.minY - surface.pageFrames[index - 1].maxY, 0, accuracy: 0.5,
                    "the sheets are meant to meet; a gap here is the old gutter"
                )
            }
        }
        XCTAssertEqual(surface.breakMarkerFrames.count, pages.count - 1)
    }

    /// Continuous is one sheet, and it is shorter than the sheets it replaces
    /// by the margins it stops repeating.
    func testContinuousIsOneSheetWithoutTheRepeatedMargins() throws {
        let elements = script(scenes: 25)
        let paged = surface(elements, mode: .pages)
        let pages = try XCTUnwrap(ScreenplayExporter.paginate(Screenplay(elements: elements)))
        let pagedHeight = paged.pageFrames.reduce(CGRect.null) { $0.union($1) }.height

        let flowing = surface(elements, mode: .continuous)
        XCTAssertEqual(flowing.pageFrames.count, 1, "continuous is one sheet")

        let saved = pagedHeight - flowing.pageFrames[0].height
        let perBoundary = PageFormat.letter.textTop + ScreenplayPageLayout.textBottom(.letter)
        XCTAssertGreaterThan(
            saved, perBoundary * CGFloat(pages.count - 1) * 0.5,
            "continuous did not collapse the margins it exists to collapse"
        )
        // Still marked, and still one marker per boundary.
        XCTAssertEqual(flowing.breakMarkerFrames.count, pages.count - 1)
    }

    /// The property the whole thing rests on: the mode draws, the engine
    /// paginates. Switching must not move a line onto a different page.
    func testTheModeDoesNotRepaginate() throws {
        let elements = script(scenes: 25)
        let pages = try XCTUnwrap(ScreenplayExporter.paginate(Screenplay(elements: elements)))
        let locations = ScreenplayPageLayout.pageStartLocations(
            elements: elements, pages: pages
        )

        for mode in PageLayoutMode.allCases {
            let surface = surface(elements, mode: mode)
            let after = try XCTUnwrap(
                ScreenplayExporter.paginate(Screenplay(elements: surface.renderedElements))
            )
            XCTAssertEqual(after.count, pages.count, "\(mode.title) changed the page count")
            XCTAssertEqual(
                ScreenplayPageLayout.pageStartLocations(
                    elements: surface.renderedElements, pages: after
                ),
                locations,
                "\(mode.title) moved a line onto a different page"
            )
        }
    }

    /// And the writer keeps their place across the switch.
    ///
    /// A hundred pages carry a hundred repeated margin pairs — about thirteen
    /// thousand points — so preserving the scroll *offset* would throw the
    /// writer to a different part of the script entirely. The line at the top
    /// of the viewport is what has to be preserved.
    func testSwitchingModesKeepsTheWriterOnTheSameLine() throws {
        let elements = script(scenes: 25)
        let surface = surface(elements, mode: .pages)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
        surface.scrollView.layoutSubtreeIfNeeded()

        // Somewhere well down the script, where the mode change moves a lot.
        let clip = surface.scrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: surface.canvas.frame.height * 0.6))
        surface.scrollView.reflectScrolledClipView(clip)
        let before = try XCTUnwrap(surface.topmostVisibleCharacter)

        surface.setLayoutMode(.continuous)

        let after = try XCTUnwrap(surface.topmostVisibleCharacter)
        XCTAssertEqual(
            after, before, accuracy: 400,
            "the writer was thrown \(abs(after - before)) characters from where they were"
        )
    }

    func testPageTwoOpensOnTheSecondSheetNotInTheGap() throws {
        let elements = script(scenes: 25)
        let surface = surface(elements, mode: .pages)
        let pages = try XCTUnwrap(ScreenplayExporter.paginate(Screenplay(elements: elements)))
        XCTAssertGreaterThan(pages.count, 1)
        let locations = ScreenplayPageLayout.pageStartLocations(
            elements: elements, pages: pages
        )
        let start = locations[1]
        let rect = try XCTUnwrap(
            ScriptLayout.boundingRect(
                of: NSRange(location: start, length: min(1, max(0, (surface.textView.string as NSString).length - start))),
                in: surface.textView
            )
        )
        let inCanvas = surface.canvas.convert(rect, from: surface.textView)
        let card = surface.pageFrames[1]
        let textTop = card.minY + PageFormat.current.textTop
        let textBottom = card.maxY - ScreenplayPageLayout.textBottom(.letter)
        XCTAssertGreaterThanOrEqual(inCanvas.minY, textTop - 8)
        XCTAssertLessThan(inCanvas.minY, textBottom)
        XCTAssertGreaterThanOrEqual(inCanvas.minY, card.minY - 1, "page 2's first line is above its own sheet")
    }

    func testAPushedHeadingOpensItsSheet() throws {
        var elements: [ScriptElement] = []
        for beat in 1...26 {
            elements.append(ScriptElement(type: .action, text: "Action line \(beat) sits on one row."))
        }
        let heading = ScriptElement(type: .scene, text: "INT. PUSHED - DAY")
        elements.append(heading)
        elements.append(ScriptElement(type: .action, text: "The heading was not left alone at the foot."))
        let surface = surface(elements, mode: .pages)
        let pages = try XCTUnwrap(ScreenplayExporter.paginate(Screenplay(elements: elements)))
        XCTAssertEqual(pages.count, 2)
        XCTAssertEqual(surface.pageFrames.count, 2)

        let range = try XCTUnwrap(ScreenplayEditPlanner.ranges(for: elements).first { $0.id == heading.id })
        let rect = try XCTUnwrap(ScriptLayout.boundingRect(of: range.range, in: surface.textView))
        let inCanvas = surface.canvas.convert(rect, from: surface.textView)
        XCTAssertTrue(
            surface.pageFrames[1].insetBy(dx: -1, dy: -1).contains(
                CGPoint(x: inCanvas.midX, y: inCanvas.minY)
            ),
            "the pushed heading \(inCanvas) is not on sheet 2 \(surface.pageFrames[1])"
        )
    }
}
