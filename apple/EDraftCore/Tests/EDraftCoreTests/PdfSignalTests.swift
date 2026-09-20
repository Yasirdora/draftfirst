import XCTest
@testable import EDraftCore

/// The PDF round-trip signal: a file we exported must come back whole,
/// including the punctuation and scripts that hex-encoding UTF-16 would
/// mangle. Named for the failure: if this breaks, the PDF no longer
/// carries its source home.
final class PdfSignalTests: XCTestCase {

    /// Curly quotes, an em dash, and Japanese — the exact reason the
    /// payload encodes UTF-8 bytes rather than UTF-16 code units.
    private let fountain = "Title: The Long Way Home\n\nINT. CAFÉ - DAY\n\nMolly’s kettle screams — “loudly.” 日本語も。\n"

    func testTheSignalRoundTripsUnicodeByteForByte() {
        let pdf = fakePdf(keywordsHex: PdfSignal.encode(fountain))
        XCTAssertEqual(PdfSignal.extract(from: pdf), fountain)
    }

    func testAPdfWithNoSignalIsRefused() {
        let pdf = fakePdf(keywordsHex: nil)
        XCTAssertNil(PdfSignal.extract(from: pdf))
    }

    func testAForeignKeywordsPayloadIsRefused() {
        XCTAssertNil(PdfSignal.extract(from: fakePdf(keywordsHex: hex("SOMEONE_ELSE:1\n{}"))))
    }

    func testAnUnknownVersionIsRefused() {
        XCTAssertNil(PdfSignal.extract(from: fakePdf(
            keywordsHex: hex("\(PdfSignal.markerPrefix):99\nfuture")
        )))
    }

    func testMalformedHexIsIgnored() {
        XCTAssertNil(PdfSignal.extract(from: fakePdf(keywordsHex: "abc")))
        XCTAssertNil(PdfSignal.extract(from: fakePdf(keywordsHex: "zz")))
    }

    func testALaterValidSignalIsFoundAfterAForeignOne() {
        var bytes = Data("%PDF-1.4\n1 0 obj\n<< /Keywords <\(hex("foreign"))> >>\nendobj\n".utf8)
        bytes.append(fakePdf(keywordsHex: PdfSignal.encode(fountain)))
        XCTAssertEqual(PdfSignal.extract(from: bytes), fountain)
    }

    func testADictionaryIsNotMistakenForHex() {
        let pdf = Data("%PDF-1.4\n<< /Keywords << /Nested true >> >>\n%%EOF".utf8)
        XCTAssertNil(PdfSignal.extract(from: pdf))
    }

    func testAPdfLiteralStringIsReadAsWellAsAHexString() {
        let hex = PdfSignal.encode(fountain)
        let asLiteral = Data("%PDF-1.4\n<< /Keywords (\(hex)) >>\n%%EOF".utf8)
        XCTAssertEqual(PdfSignal.extract(from: asLiteral), fountain)
        XCTAssertEqual(PdfSignal.extract(from: fakePdf(keywordsHex: hex)), fountain)
    }

    /// macOS 27's Quartz writes the value as an indirect object —
    /// `/Keywords 6 0 R` with the literal inside object 6 — and PDFKit's
    /// rewrite keeps the indirection. Measured 2026-09-19.
    func testAnIndirectKeywordsReferenceIsFollowed() {
        let hex = PdfSignal.encode(fountain)
        let pdf = Data((
            "%PDF-1.4\n5 0 obj\n<< /Producer (macOS Quartz) /Keywords 6 0 R >>\nendobj\n" +
            "6 0 obj\n(\(hex))\nendobj\ntrailer\n<< /Info 5 0 R >>\n%%EOF"
        ).utf8)
        XCTAssertEqual(PdfSignal.extract(from: pdf), fountain)
    }

    /// "6 0 obj" is a suffix of "26 0 obj"; the digit boundary must hold.
    func testObject26DoesNotAnswerAReferenceToObject6() {
        let hex = PdfSignal.encode(fountain)
        let pdf = Data((
            "%PDF-1.4\n26 0 obj\n(zz)\nendobj\n" +
            "5 0 obj\n<< /Keywords 6 0 R >>\nendobj\n" +
            "6 0 obj\n<\(hex)>\nendobj\n%%EOF"
        ).utf8)
        XCTAssertEqual(PdfSignal.extract(from: pdf), fountain)
    }

    /// PDFs exported during the brief window that stamped `<hex>` after
    /// `%%EOF` are writers' files. We do not write that way; we still read it.
    func testATrailingHexStampFromAnOlderExportStillExtracts() {
        let hex = PdfSignal.encode(fountain)
        var pdf = Data("%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF\n".utf8)
        pdf.append(contentsOf: Array("/Keywords <\(hex)>\n".utf8))
        XCTAssertEqual(PdfSignal.extract(from: pdf), fountain)
    }

    /// The rename compatibility contract, on the Swift side of the same
    /// prefix the TypeScript engine still reads.
    func testAPreRenamePrefixStillRecoversTheSource() {
        let payload = hex("DRAFT_FIRST_FOUNTAIN:1\nINT. KITCHEN - DAY\n")
        XCTAssertEqual(
            PdfSignal.extract(from: fakePdf(keywordsHex: payload)),
            "INT. KITCHEN - DAY\n"
        )
    }

    /// The pin the TypeScript suite already carries: a blanket
    /// find-and-replace once rewrote this list to the CURRENT prefix, and
    /// pre-rename PDFs silently stopped opening. Pin both halves.
    func testTheLegacyListKeepsTheOldMarkerAndNeverTheCurrentOne() {
        XCTAssertTrue(PdfSignal.legacyMarkerPrefixes.contains("DRAFT_FIRST_FOUNTAIN"))
        XCTAssertFalse(PdfSignal.legacyMarkerPrefixes.contains(PdfSignal.markerPrefix))
    }

    func testEncodeWritesTheCurrentPrefixAndLowercaseHex() {
        let encoded = PdfSignal.encode("INT. A - DAY\n")
        XCTAssertEqual(encoded, hex("\(PdfSignal.markerPrefix):\(PdfSignal.markerVersion)\nINT. A - DAY\n"))
        XCTAssertEqual(encoded, encoded.lowercased())
        XCTAssertEqual(PdfSignal.markerPrefix, "EDRAFT_FOUNTAIN")
    }

    // MARK: - Fixtures

    private func fakePdf(keywordsHex: String?) -> Data {
        let info = keywordsHex.map { "<< /Producer (eDraft) /Keywords <\($0)> >>" }
            ?? "<< /Producer (Someone Else) >>"
        return Data("%PDF-1.4\n3 0 obj\n\(info)\nendobj\ntrailer\n<< /Root 1 0 R /Info 3 0 R >>\n%%EOF".utf8)
    }

    private func hex(_ text: String) -> String {
        Array(text.utf8).map { String(format: "%02x", $0) }.joined()
    }
}
