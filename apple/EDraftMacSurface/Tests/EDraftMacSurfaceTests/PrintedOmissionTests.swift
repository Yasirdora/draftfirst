import AppKit
import EDraftCore
import EDraftEngine
import PDFKit
import XCTest
@testable import EDraftMacSurface

/// Print and PDF carry an omitted scene as its card, never its body.
/// MACOS-DESIGN §3.2: the page and the PDF share one set of metrics, so
/// what a writer sees is what production receives.
@MainActor
final class PrintedOmissionTests: XCTestCase {

    private func opened() throws -> (EditorState, String) {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("eDraftEngine/Fixtures/finaldraft-sample02.fdx")
        let file = try ScreenplayFile.open(try Data(contentsOf: url), as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        return (editor, try XCTUnwrap(file.origin))
    }

    private func squeezed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func cutBody(_ editor: EditorState) -> [String] {
        let live = editor.screenplay.elements.filter { !editor.isOmitted($0) }.map { squeezed($0.text) }
        return editor.screenplay.elements
            .filter { editor.isOmitted($0) && $0.type.isPrinting }
            .map { squeezed($0.text) }
            .filter { line in line.count > 6 && !live.contains { $0.contains(line) } }
    }

    func testThePdfPrintsTheCardAndNoBody() throws {
        let (editor, origin) = try opened()
        let output = editor.output(origin: origin)
        let data = ScreenplayPageRenderer.pdfData(output)
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        let text = squeezed(pdf.string ?? "")
        let body = cutBody(editor)
        XCTAssertFalse(body.isEmpty)
        XCTAssertEqual(body.filter { text.contains($0) }, [], "the cut scene's body prints")
        let card = try XCTUnwrap(editor.screenplay.elements.first { editor.omittedScenes.isCard($0) })
        XCTAssertTrue(text.contains(card.text), "the card prints")
        let pages = try XCTUnwrap(ScreenplayExporter.paginate(output.printed)).count
        let titled = output.printed.titlePage.contains { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        XCTAssertLessThanOrEqual(pdf.pageCount - pages, titled ? 1 : 0, "the PDF is the printed script's pages")
        XCTAssertGreaterThanOrEqual(pdf.pageCount, pages)
    }

    func testThePdfCarriesTheFountainExport() throws {
        let (editor, origin) = try opened()
        let output = editor.output(origin: origin)
        let carried = try XCTUnwrap(PdfSignal.extract(from: ScreenplayPageRenderer.pdfData(output)))
        XCTAssertEqual(carried, ScreenplayExporter.fountainSource(output))
        let body = cutBody(editor)
        XCTAssertEqual(body.filter { squeezed(carried).contains($0) }, [], "the PDF carries the cut body home as script")
    }

    func testPrintIsThatPdf() throws {
        let (editor, origin) = try opened()
        let output = editor.output(origin: origin)
        let operation = try XCTUnwrap(ScreenplayPageRenderer.printOperation(output))
        let pdf = try XCTUnwrap(PDFDocument(data: ScreenplayPageRenderer.pdfData(output)))
        let view = try XCTUnwrap(operation.view)
        var range = NSRange(location: 0, length: 0)
        XCTAssertTrue(view.knowsPageRange(&range), "the print view states its pages")
        XCTAssertEqual(range.length, pdf.pageCount, "Print prints the printed script's PDF")
    }
}
