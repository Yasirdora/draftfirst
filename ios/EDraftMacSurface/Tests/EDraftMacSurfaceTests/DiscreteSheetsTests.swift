import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// Discrete sheets with desk between them, not one tall card with rules.
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

    func testAFourPageScriptIsFourSheetsWithDeskBetweenThem() throws {
        let elements = script(scenes: 25)
        let surface = surface(elements)
        let pages = try XCTUnwrap(ScreenplayExporter.paginate(Screenplay(elements: elements)))
        XCTAssertGreaterThanOrEqual(pages.count, 4, "25 scenes must paginate past four pages")

        XCTAssertEqual(surface.pageFrames.count, pages.count)
        let desk = surface.canvas.canvasPadding
        for (index, frame) in surface.pageFrames.enumerated() {
            XCTAssertEqual(frame.height, PageFormat.letter.pageRect.height, accuracy: 0.5)
            XCTAssertEqual(frame.width, PageFormat.letter.pageRect.width, accuracy: 0.5)
            if index > 0 {
                let previous = surface.pageFrames[index - 1]
                XCTAssertEqual(frame.minY - previous.maxY, desk, accuracy: 0.5)
            }
        }
        let union = surface.pageFrames.reduce(CGRect.null) { $0.union($1) }
        XCTAssertGreaterThan(
            union.height,
            PageFormat.letter.pageRect.height * CGFloat(pages.count) + 1,
            "the sheets collapsed into one rectangle; there is no desk between them"
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
        XCTAssertFalse(
            inCanvas.minY > surface.pageFrames[0].maxY && inCanvas.minY < card.minY,
            "the first line of page 2 sits in the desk between sheets"
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
