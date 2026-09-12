import XCTest
import PDFKit
import EDraftEngine
import EDraftCore
@testable import EDraftUIKitSurface

/// The highlight prints from the phone too — one document is one document
/// on paper (docs/RFC-HIGHLIGHTER.md, D6). Rasterizes the exported PDF and
/// looks for the mark, as the Mac's own test does.
@MainActor
final class HighlightPdfTests: XCTestCase {

    private func renderedPixels(of screenplay: EDraftCore.Screenplay) -> NSBitmapImageRep? {
        let pdf = ScreenplayPageRenderer.pdfData(screenplay)
        guard let document = PDFDocument(data: pdf),
              let page = document.page(at: 0) else { return nil }
        let image = page.thumbnail(of: NSSize(width: 612, height: 792), for: .mediaBox)
        return NSBitmapImageRep(data: image.tiffRepresentation ?? Data())
    }

    private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int)? {
        var rgba: [Int] = [0, 0, 0, 0]
        rep.getPixel(&rgba, atX: x, y: y)
        return (rgba[0], rgba[1], rgba[2])
    }

    private func hasYellowMark(_ rep: NSBitmapImageRep) -> Bool {
        for y in 68..<92 {
            for x in 120..<180 {
                if let p = pixel(rep, x, y), p.r > 220, p.g > 200, p.b < 215, p.r - p.b > 20 {
                    return true
                }
            }
        }
        return false
    }

    func testAHighlightedWordPrintsItsMarkBehindTheInk() throws {
        let screenplay = EDraftCore.Screenplay(engineModel: Screenplay(titlePage: [], elements: [
            ScreenplayElement(
                type: .action, text: "The marked word.",
                runs: [StyleRun(start: 4, end: 10, styles: [], highlight: .yellow)]
            ),
        ]))
        let rep = try XCTUnwrap(renderedPixels(of: screenplay))
        XCTAssertTrue(hasYellowMark(rep), "the exported PDF shows no highlight behind the word")
    }

    func testAWordWithoutHighlightPrintsNoMark() throws {
        let screenplay = EDraftCore.Screenplay(engineModel: Screenplay(titlePage: [], elements: [
            ScreenplayElement(type: .action, text: "The marked word."),
        ]))
        let rep = try XCTUnwrap(renderedPixels(of: screenplay))
        XCTAssertFalse(hasYellowMark(rep), "a plain word gained a highlight it never had")
    }
}
