import CoreGraphics
import CoreText
import EDraftCore
import EDraftEngine
import SwiftUI
import UniformTypeIdentifiers
import Vision
import VisionKit

/// Turns photographed paper into a searchable PDF in the writer's documents.
///
/// Everything here is a system framework: VisionKit captures, Vision reads, and
/// Core Graphics writes. No model ships with the app and nothing is added to
/// the binary, which is the whole reason scanning can live in a screenwriting
/// app without weighing it down.
///
/// The point is the text layer. A scan whose words cannot be selected is a
/// photograph; one whose words can be is a document a writer can quote from.
enum ScanCreation {

    /// Assumed capture resolution, used to size PDF pages in points.
    private static let assumedDPI: CGFloat = 200

    /// Base-14 PDF font: present in every conforming reader, so nothing is
    /// embedded and the text layer costs almost nothing in file size.
    private static let fontName = "Helvetica"

    /// Fraction of a line's box below the baseline. Vision's boxes span the
    /// whole glyph extent including descenders; text draws from the baseline.
    private static let descenderFraction: CGFloat = 0.21

    /// A finished scan: the paper as a searchable PDF, and the screenplay read
    /// off it. Both come from one pass of recognition — the words are read
    /// once and used twice.
    struct Outcome {
        let pdf: URL
        let fountain: String
    }

    /// Reads paper as screenplay source, filing nothing.
    ///
    /// Pages added to a script the writer already has open become part of that
    /// script; leaving a PDF behind in their documents for each one would be
    /// filing paperwork they did not ask for.
    static func readScreenplay(from pages: [UIImage]) async -> String {
        ScreenplayTranscription.fountain(from: scannedLines(await recognise(pages)))
    }

    /// Scans paper into a screenplay, keeping the pages as a searchable PDF.
    static func makeScreenplay(from pages: [UIImage], named title: String) async throws -> Outcome {
        let recognised = await recognise(pages)
        let url = try writeDocument(pages: pages, text: recognised, named: title)
        return Outcome(
            pdf: url,
            fountain: ScreenplayTranscription.fountain(from: scannedLines(recognised))
        )
    }

    /// Vision reports a lower-left origin; transcription reads down the page.
    nonisolated static func scannedLines(_ runs: [TextRun], page: Int) -> [ScannedTextLine] {
        runs.map { run in
            ScannedTextLine(
                text: run.text,
                page: page,
                left: run.box.minX,
                top: 1 - run.box.maxY,
                bottom: 1 - run.box.minY
            )
        }
    }

    private static func scannedLines(_ pages: [[TextRun]]) -> [ScannedTextLine] {
        pages.enumerated().flatMap { scannedLines($1, page: $0) }
    }

    /// Writes the scanned pages as one searchable PDF and returns its location.
    private static func writeDocument(
        pages: [UIImage], text recognised: [[TextRun]], named title: String
    ) throws -> URL {
        let url = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(title).pdf")
        try write(pages: pages, text: recognised, to: url)
        return url
    }

    private static func recognise(_ pages: [UIImage]) async -> [[TextRun]] {
        await withTaskGroup(of: (Int, [TextRun]).self) { group in
            for (index, page) in pages.enumerated() {
                group.addTask { (index, await readText(in: page.cgImage)) }
            }
            var byIndex: [Int: [TextRun]] = [:]
            for await (index, runs) in group { byIndex[index] = runs }
            return (0..<pages.count).map { byIndex[$0] ?? [] }
        }
    }

    // MARK: - Reading

    /// One recognised line, positioned in Vision's normalised space.
    struct TextRun: Sendable {
        var text: String
        var box: CGRect
    }

    nonisolated static func readText(in image: CGImage?) async -> [TextRun] {
        guard let image else { return [] }

        // The document reader rather than plain text recognition: it groups
        // lines into paragraphs and handles rotated and small type, which is
        // most of what a photographed page contains.
        let request = RecognizeDocumentsRequest()
        guard let observations = try? await request.perform(on: image),
              let document = observations.first?.document else {
            return []
        }

        return document.text.lines.map { line in
            let xs = [line.topLeft.x, line.topRight.x, line.bottomLeft.x, line.bottomRight.x]
            let ys = [line.topLeft.y, line.topRight.y, line.bottomLeft.y, line.bottomRight.y]
            let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
            let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
            return TextRun(
                text: line.transcript,
                box: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            )
        }
    }

    // MARK: - Writing

    /// The type size at which a string's natural width matches `width`.
    private static func fontSize(fitting text: String, toWidth width: CGFloat) -> CGFloat? {
        // Measured once at a reference size and scaled: type advances are
        // linear in point size, so one measurement is exact.
        let reference: CGFloat = 100
        let line = CTLineCreateWithAttributedString(NSAttributedString(
            string: text,
            attributes: [kCTFontAttributeName as NSAttributedString.Key:
                CTFontCreateWithName(fontName as CFString, reference, nil)]
        ))
        let naturalWidth = CTLineGetTypographicBounds(line, nil, nil, nil)
        guard naturalWidth > 0 else { return nil }
        return reference * width / CGFloat(naturalWidth)
    }

    private static func write(pages: [UIImage], text: [[TextRun]], to url: URL) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw CocoaError(.fileWriteUnknown)
        }
        var defaultBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &defaultBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }

        for (index, page) in pages.enumerated() {
            guard let image = page.cgImage else { continue }
            let scale = 72 / assumedDPI
            var box = CGRect(
                x: 0, y: 0,
                width: CGFloat(image.width) * scale,
                height: CGFloat(image.height) * scale
            )
            context.beginPage(mediaBox: &box)
            context.draw(image, in: box)
            draw(text[index], in: box, context: context)
            context.endPage()
        }
        context.closePDF()
    }

    private static func draw(_ runs: [TextRun], in box: CGRect, context: CGContext) {
        context.saveGState()
        // `Tr 3`, the PDF render mode for text that is present but not painted.
        // Drawing with a transparent fill instead — the common shortcut — still
        // emits paint operations, and some readers and printers honour them.
        context.setTextDrawingMode(.invisible)

        for run in runs {
            let text = run.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            // Vision normalises to the lower-left origin, which is also PDF's,
            // so this is a scale with no flip.
            let frame = CGRect(
                x: run.box.minX * box.width,
                y: run.box.minY * box.height,
                width: run.box.width * box.width,
                height: run.box.height * box.height
            )
            guard frame.width > 0.5, frame.height > 0.5 else { continue }

            // Fit by choosing the type size, never by stretching the text
            // matrix.
            //
            // Helvetica's advances will not match the scanned typeface, so a
            // run has to be fitted to the ink it stands for or selection
            // highlights drift across the line. Doing that with a horizontal
            // scale works visually and ruins the text: a stretched matrix
            // leaves wide gaps between glyphs, and every PDF reader takes those
            // gaps for spaces. A scanned "INT. COFFEE SHOP" came back out of
            // the file as "I N T . C O F F E E S H O P", which is unusable for
            // the one thing this layer exists to allow — pasting the words into
            // a script.
            //
            // Sizing the font so its natural width already equals the box
            // leaves the advances untouched, so the text extracts as written.
            guard let size = fontSize(fitting: text, toWidth: frame.width) else { continue }
            let line = CTLineCreateWithAttributedString(NSAttributedString(
                string: text,
                attributes: [kCTFontAttributeName as NSAttributedString.Key:
                    CTFontCreateWithName(fontName as CFString, size, nil)]
            ))

            var matrix = CGAffineTransform.identity
            matrix.tx = frame.minX
            matrix.ty = frame.minY + frame.height * descenderFraction
            context.textMatrix = matrix
            CTLineDraw(line, context)
        }
        context.restoreGState()
    }
}
