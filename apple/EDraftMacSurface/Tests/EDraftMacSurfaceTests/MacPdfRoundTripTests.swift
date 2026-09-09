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

    /// Core Graphics writes `/Keywords (hex)` as a PDF literal in the Info
    /// dictionary. The extractor must accept that spelling, or a Mac PDF
    /// only round-trips until someone re-saves it.
    func testCgKeywordsLiteralExtracts() {
        let fountain = "INT. ROOM - DAY\n"
        XCTAssertEqual(PdfSignal.extract(from: cgPdf(keywords: PdfSignal.encode(fountain))), fountain)
    }

    /// The test that would have caught a `%%EOF` stamp: a PDF reader that
    /// rewrites the file must still yield the source. Preview, Acrobat,
    /// Quartz filters all do this.
    func testTheExportedPdfSurvivesAPdfReaderRewrite() throws {
        let screenplay = EDraftCore.Screenplay(engineModel: try Fountain.parse(fountain))
        let pdf = ScreenplayPageRenderer.pdfData(screenplay)
        let document = try XCTUnwrap(PDFDocument(data: pdf), "PDFKit refused the export")
        let rewritten = try XCTUnwrap(document.dataRepresentation(), "PDFKit produced no bytes on write-back")
        let recovered = try XCTUnwrap(
            PdfSignal.extract(from: rewritten),
            "the signal did not survive a PDFDocument rewrite — it was not in the Info dictionary"
        )
        XCTAssertEqual(recovered, ScreenplayExporter.fountainSource(screenplay))
        XCTAssertTrue(recovered.contains("Molly’s"))
        XCTAssertTrue(recovered.contains("日本語も。"))
    }

    /// Measured: Core Graphics carried 500_000 hex characters in
    /// `/Keywords` and PDFKit's rewrite kept them. A feature script is
    /// ~240KB of hex; well under that. File-attachment fallback not needed.
    func testAFeatureLengthKeywordsPayloadSurvivesAPdfReaderRewrite() {
        let fountain = String(repeating: "INT. STAGE - DAY\n\nThe lights hold.\n\n", count: 3500)
        let hex = PdfSignal.encode(fountain)
        XCTAssertGreaterThan(hex.count, 200_000, "the fixture must be in the feature-length band")
        let raw = cgPdf(keywords: hex)
        let rewritten = PDFDocument(data: raw)?.dataRepresentation()
        XCTAssertEqual(PdfSignal.extract(from: raw), fountain)
        XCTAssertEqual(PdfSignal.extract(from: rewritten ?? Data()), fountain)
    }

    private func cgPdf(keywords: String) -> Data {
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = NSMutableData()
        let info: [CFString: Any] = [kCGPDFContextKeywords: keywords]
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)
        else { return Data() }
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return Data(referencing: data)
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
