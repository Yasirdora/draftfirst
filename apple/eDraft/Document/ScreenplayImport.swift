import CoreGraphics
import EDraftCore
import EDraftEngine
import EDraftUI
import ImageIO
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// Brings an existing script into eDraft.
///
/// A writer's back catalogue is not in eDraft's format, and telling them to
/// retype it is telling them to go elsewhere. Final Draft files and Fountain
/// convert exactly. PDFs are the interesting case: a screenplay PDF is how
/// scripts are actually circulated, and almost all of them already carry their
/// own text — reading it is exact where recognition only guesses.
enum ScreenplayImport {

    /// What the picker will offer. Every one of these becomes a screenplay
    /// that opens in the editor, not a file the writer has to convert first.
    static let readableTypes: [UTType] = [
        .edraftScreenplay, .finalDraftScreenplay, .pdf, .plainText, .image
    ]

    /// Below this many lines per page, whatever text a PDF carries is
    /// furniture — a watermark, a footer stamped over pictures — rather than
    /// the script, and the pages have to be read by recognition instead.
    private static let minimumLinesPerPage = 5

    /// 200 dpi: enough for 12pt type, and small enough that a long script does
    /// not hold many full-resolution pages in memory at once.
    private static let renderDPI: CGFloat = 200

    /// Pages recognised together. Recognition is the expensive part, and each
    /// page holds a rendered bitmap for as long as it runs.
    private static let batchSize = 4

    static func document(at url: URL) async throws -> EDraftDocument {
        EDraftDocument(source: try await source(at: url))
    }

    /// Screenplay source read from whatever the writer chose.
    static func source(at url: URL) async throws -> String {
        // A file chosen from another app's storage is only readable inside
        // this pair; iCloud Drive and Files both hand back scoped URLs.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) ?? .data
        if type.conforms(to: .pdf) {
            return try await fountain(fromPDFAt: url)
        }
        if type.conforms(to: .image) {
            return try await fountain(fromImageAt: url)
        }
        // Fountain, plain text and .draft are already source; FDX converts on
        // the way in through the same boundary the browser uses.
        return try ScreenplayFile.decode(try Data(contentsOf: url), as: type)
    }

    /// A photograph of a page — the picture a writer already took, rather than
    /// one taken through the scanner.
    private static func fountain(fromImageAt url: URL) async throws -> String {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let runs = await ScanCreation.readText(in: image)
        return ScreenplayTranscription.fountain(from: ScanCreation.scannedLines(runs, page: 0))
    }

    // MARK: - PDF

    private static func fountain(fromPDFAt url: URL) async throws -> String {
        let data = try Data(contentsOf: url)
        // A PDF we exported carries its Fountain source as a hex payload in
        // /Keywords. That round-trip is exact — curly quotes, em dashes,
        // non-Latin script — and must win over OCR, which can only guess.
        if let fountain = PdfSignal.extract(from: data) {
            return fountain
        }

        guard let pdf = PDFDocument(url: url) else { throw CocoaError(.fileReadCorruptFile) }

        let embedded = textLayerLines(of: pdf)
        let usable = embedded.count >= pdf.pageCount * minimumLinesPerPage
            && !isLetterSpaced(embedded)
        let lines = usable ? embedded : await recognisedLines(of: pdf)
        return ScreenplayTranscription.fountain(from: lines)
    }

    /// The text a PDF already contains, line by line, with each line's place on
    /// the page — which is what makes a screenplay's margins readable, and so
    /// what makes the difference between recovering a script and recovering a
    /// wall of words.
    private static func textLayerLines(of pdf: PDFDocument) -> [ScannedTextLine] {
        var lines: [ScannedTextLine] = []

        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0,
                  let whole = page.selection(for: bounds) else { continue }

            for line in whole.selectionsByLine() {
                let text = (line.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let box = line.bounds(for: page)
                lines.append(ScannedTextLine(
                    text: text,
                    page: index,
                    left: (box.minX - bounds.minX) / bounds.width,
                    // PDF measures up from the bottom-left; transcription
                    // reads down the page.
                    top: (bounds.maxY - box.maxY) / bounds.height,
                    bottom: (bounds.maxY - box.minY) / bounds.height
                ))
            }
        }
        return lines
    }

    /// Whether a text layer has come apart into loose letters.
    ///
    /// Many scanners fit their invisible text to the ink by stretching it, and
    /// a stretched line leaves gaps between glyphs that every reader takes for
    /// spaces: "A busy, cozy" comes back as "A b u s y , c o z y". The word
    /// breaks are not recoverable — measured on a real file, true spaces run
    /// 26 to 28 points and the false ones 12 to 46, straight through that
    /// range — so a layer like this cannot be repaired, only distrusted. The
    /// pages themselves are still good, and reading them again costs a few
    /// seconds against returning nonsense.
    private static func isLetterSpaced(_ lines: [ScannedTextLine]) -> Bool {
        var total = 0
        var single = 0
        for line in lines {
            for token in line.text.split(separator: " ") {
                total += 1
                if token.count == 1 { single += 1 }
            }
        }
        // English runs a few per cent single-letter words — "a", "I", stray
        // punctuation. Two in five is not prose.
        guard total >= 20 else { return false }
        return Double(single) / Double(total) > 0.4
    }

    /// Reads a PDF that is pages of pictures — a scan someone was mailed.
    private static func recognisedLines(of pdf: PDFDocument) async -> [ScannedTextLine] {
        var lines: [ScannedTextLine] = []
        var start = 0

        while start < pdf.pageCount {
            let end = min(start + batchSize, pdf.pageCount)
            let batch = await withTaskGroup(of: (Int, [ScannedTextLine]).self) { group in
                for index in start..<end {
                    guard let image = render(page: index, of: pdf) else { continue }
                    group.addTask {
                        let runs = await ScanCreation.readText(in: image)
                        return (index, ScanCreation.scannedLines(runs, page: index))
                    }
                }
                var byIndex: [Int: [ScannedTextLine]] = [:]
                for await (index, page) in group { byIndex[index] = page }
                return (start..<end).flatMap { byIndex[$0] ?? [] }
            }
            lines.append(contentsOf: batch)
            start = end
        }
        return lines
    }

    private static func render(page index: Int, of pdf: PDFDocument) -> CGImage? {
        guard let page = pdf.page(at: index) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale = renderDPI / 72
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)

        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              ) else { return nil }

        // A PDF page paints only its marks; the paper under them is assumed.
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}
