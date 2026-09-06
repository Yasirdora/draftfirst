import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// Discrete sheets, joined at a line the writer can open.
///
/// They used to stand 36 points apart, which is a gutter every fifty-five
/// lines and breaks the read for no gain. They meet now: still separate
/// sheets with their own edges, but the boundary is a hairline, and clicking
/// it opens that one break to `PageCanvasView.openBreakGap`.
@MainActor
final class DiscreteSheetsTests: XCTestCase {

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

    func testAFourPageScriptIsFourSheetsJoinedAtALine() throws {
        let elements = script(scenes: 25)
        let surface = surface(elements)
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
        // Still sheets, not one tall card: each has its own edge, and there
        // is a line to press between every pair.
        XCTAssertEqual(surface.canvas.pageViews.count, pages.count)
        XCTAssertEqual(surface.breakHandleFrames.count, pages.count - 1)
    }

    /// Opening one break moves that sheet and every sheet below it, by
    /// exactly the gap, and leaves the ones above where they were.
    func testOpeningABreakSeparatesOnlyFromThereDown() throws {
        let elements = script(scenes: 25)
        let surface = surface(elements)
        let before = surface.pageFrames
        XCTAssertGreaterThanOrEqual(before.count, 4)

        surface.canvas.onToggleBreak?(1)
        let after = surface.pageFrames
        let gap = PageCanvasView.openBreakGap

        XCTAssertEqual(after[0].minY, before[0].minY, accuracy: 0.5, "sheet 1 moved")
        XCTAssertEqual(after[1].minY, before[1].minY, accuracy: 0.5, "sheet 2 moved")
        for index in 2..<after.count {
            XCTAssertEqual(
                after[index].minY - before[index].minY, gap, accuracy: 0.5,
                "sheet \(index + 1) did not come down by the gap"
            )
        }
        XCTAssertEqual(after[2].minY - after[1].maxY, gap, accuracy: 0.5)
        XCTAssertEqual(after[1].minY - after[0].maxY, 0, accuracy: 0.5, "an untouched break opened")
    }

    /// And closing it puts them back exactly.
    func testClosingABreakRestoresTheJoin() throws {
        let elements = script(scenes: 25)
        let surface = surface(elements)
        let before = surface.pageFrames

        surface.canvas.onToggleBreak?(1)
        surface.canvas.onToggleBreak?(1)

        for (index, frame) in surface.pageFrames.enumerated() {
            XCTAssertEqual(frame.minY, before[index].minY, accuracy: 0.5)
        }
    }

    /// The property that makes the whole thing safe: the gap is presentation
    /// and pagination is the engine's. Opening a break must not move a single
    /// line onto a different page.
    func testOpeningABreakDoesNotRepaginate() throws {
        let elements = script(scenes: 25)
        let surface = surface(elements)
        let pages = try XCTUnwrap(ScreenplayExporter.paginate(Screenplay(elements: elements)))
        let locations = ScreenplayPageLayout.pageStartLocations(
            elements: elements, pages: pages
        )

        func lineOfPageTwoRelativeToItsSheet() throws -> CGFloat {
            let start = locations[1]
            let length = (surface.textView.string as NSString).length
            let rect = try XCTUnwrap(ScriptLayout.boundingRect(
                of: NSRange(location: start, length: min(1, max(0, length - start))),
                in: surface.textView
            ))
            let inCanvas = surface.canvas.convert(rect, from: surface.textView)
            return inCanvas.minY - surface.pageFrames[1].minY
        }

        let joined = try lineOfPageTwoRelativeToItsSheet()
        surface.canvas.onToggleBreak?(0)
        let separated = try lineOfPageTwoRelativeToItsSheet()

        XCTAssertEqual(
            joined, separated, accuracy: 0.5,
            "opening the break moved the first line of page 2 within its own sheet — "
                + "the text and the sheets are being measured from different places"
        )
    }

    func testPageTwoOpensOnTheSecondSheetNotInTheGap() throws {
        let elements = script(scenes: 25)
        let surface = surface(elements)
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
        // With the sheets joined there is no gap to fall into, so this only
        // says anything once the break is open. Open it.
        surface.canvas.onToggleBreak?(0)
        let opened = try XCTUnwrap(
            ScriptLayout.boundingRect(
                of: NSRange(location: start, length: min(1, max(0, (surface.textView.string as NSString).length - start))),
                in: surface.textView
            )
        )
        let openedInCanvas = surface.canvas.convert(opened, from: surface.textView)
        XCTAssertFalse(
            openedInCanvas.minY > surface.pageFrames[0].maxY
                && openedInCanvas.minY < surface.pageFrames[1].minY,
            "the first line of page 2 sits in the gap between the sheets"
        )
    }

    func testAPushedHeadingOpensItsSheet() throws {
        var elements: [ScriptElement] = []
        for beat in 1...26 {
            elements.append(ScriptElement(type: .action, text: "Action line \(beat) sits on one row."))
        }
        let heading = ScriptElement(type: .scene, text: "INT. PUSHED - DAY")
        elements.append(heading)
        elements.append(ScriptElement(type: .action, text: "The heading was not left alone at the foot."))
        let surface = surface(elements)
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
