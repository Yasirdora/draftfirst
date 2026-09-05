import AppKit
import CoreGraphics
import EDraftCore
import EDraftEngine
import PDFKit
import XCTest
@testable import EDraftMacSurface

/// Proof 1: a PDF the Mac exported carries its Fountain source home, and
/// it comes back whole — curly quotes, em dashes, non-Latin script.
@MainActor
final class MacPdfRoundTripTests: XCTestCase {

    /// The exact reason the payload hex-encodes UTF-8 bytes.
    private let fountain = """
    Title: The Long Way Home
    Credit: written by
    Author: A. Writer

    INT. CAFÉ - DAY

    Molly’s kettle screams — “loudly.” 日本語も。

    MARA
    We’re still here.

    """

    func testTheExportedPdfComesBackIdenticalIncludingUnicode() throws {
        let screenplay = EDraftCore.Screenplay(engineModel: try Fountain.parse(fountain))
        let pdf = ScreenplayPageRenderer.pdfData(screenplay)
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))

        let recovered = try XCTUnwrap(
            PdfSignal.extract(from: pdf),
            "the Mac PDF did not carry its source — extract found no signal"
        )
        XCTAssertEqual(
            recovered,
            ScreenplayExporter.fountainSource(screenplay),
            "round-trip must be identical, not merely parseable"
        )
        XCTAssertTrue(recovered.contains("Molly’s"), "curly apostrophe was lost")
        XCTAssertTrue(recovered.contains("—"), "em dash was lost")
        XCTAssertTrue(recovered.contains("“loudly.”"), "curly quotes were lost")
        XCTAssertTrue(recovered.contains("日本語も。"), "non-Latin script was lost")
    }

    /// Core Graphics writes `/Keywords` as a PDF string `(…)`. The engine
    /// extractor only accepts the hex form `<…>`. That is why we stamp
    /// rather than trusting `kCGPDFContextKeywords`.
    func testCgKeywordsStringIsNotTheHexSignal() {
        let fountain = "INT. ROOM - DAY\n"
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        let hex = PdfSignal.encode(fountain)
        let info: [CFString: Any] = [kCGPDFContextKeywords: hex]
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)
        else {
            return XCTFail("could not create a CGPDFContext to measure")
        }
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        let raw = Data(referencing: data)

        XCTAssertNil(
            PdfSignal.extract(from: raw),
            "if this starts passing, CG now writes hex and the stamp is redundant"
        )
        XCTAssertEqual(PdfSignal.extract(from: PdfSignal.stamped(raw, fountain: fountain)), fountain)
    }

    func testPrintOperationIsTheExportedPdf() throws {
        let screenplay = EDraftCore.Screenplay(engineModel: try Fountain.parse(fountain))
        XCTAssertNotNil(
            ScreenplayPageRenderer.printOperation(screenplay),
            "print is the exported PDF, via PDFKit; a nil operation means we would have to draw a second time"
        )
    }

    func testThePdfContainsTheDrawnBody() throws {
        let screenplay = EDraftCore.Screenplay(engineModel: try Fountain.parse(fountain))
        let pdf = ScreenplayPageRenderer.pdfData(screenplay)
        guard let document = PDFDocument(data: pdf) else {
            return XCTFail("PDFKit could not open the exported PDF")
        }
        XCTAssertGreaterThanOrEqual(document.pageCount, 1)
        let text = (0..<document.pageCount)
            .compactMap { document.page(at: $0)?.string }
            .joined(separator: "\n")
        XCTAssertTrue(text.contains("CAFÉ") || text.contains("CAFE") || text.contains("Mara") || text.contains("MARA") || text.contains("kettle"),
                      "the drawn page should carry the body, not just the signal. saw: \(text.prefix(200))")
    }

    /// The CG context is flipped once so shared y-down runs land at the
    /// top of the page. A second flip would put the slug in the bottom
    /// half, and production would get a page nobody typed.
    func testTheSlugSitsInTheTopHalfOfThePage() throws {
        let source = "INT. ROOM - DAY\n\nShe waits.\n"
        let screenplay = EDraftCore.Screenplay(engineModel: try Fountain.parse(source))
        let pdf = ScreenplayPageRenderer.pdfData(screenplay)
        let document = try XCTUnwrap(PDFDocument(data: pdf))
        let page = try XCTUnwrap(document.page(at: 0))
        let bounds = page.bounds(for: .mediaBox)
        let whole = try XCTUnwrap(page.selection(for: bounds))
        let slug = try XCTUnwrap(
            whole.selectionsByLine().first { ($0.string ?? "").contains("INT") },
            "the drawn PDF has no slug to locate"
        )
        let box = slug.bounds(for: page)
        XCTAssertGreaterThan(
            box.minY, bounds.height * 0.5,
            "slug is in the bottom half (y=\(box.minY) of \(bounds.height)) — the PDF context was flipped wrong"
        )
    }
}
