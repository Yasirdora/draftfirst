import AppKit
import CoreGraphics
import CoreText
import EDraftCore
import EDraftEngine
import PDFKit

/// Drawing a string at a point, in a font — the Mac's half.
///
/// Placement is `ScreenplayPageLayout`. This file puts those runs onto a
/// `CGPDFContext` with Courier, then stamps the Fountain source so the
/// PDF carries itself home. Print is that same PDF, not a second drawing.
public enum ScreenplayPageRenderer {

    private static let courier = NSFont(name: "Courier", size: ScreenplayPageLayout.fontSize)
        ?? .monospacedSystemFont(ofSize: ScreenplayPageLayout.fontSize, weight: .regular)

    /// What the PDF actually paints with, so a test can compare it against the
    /// screen rather than against its own arithmetic.
    static var textAttributesForTests: [NSAttributedString.Key: Any] { textAttributes }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [.font: courier, .foregroundColor: NSColor.black]
    }

    private static var widthOf: (String) -> CGFloat {
        { ($0 as NSString).size(withAttributes: textAttributes).width }
    }

    /// Rich Text of the printed script.
    public static func rtfData(_ output: ScreenplayOutput) -> Data? {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = ScreenplayPageLayout.lineHeight
        paragraph.maximumLineHeight = ScreenplayPageLayout.lineHeight
        paragraph.lineSpacing = 0
        let attributes: [NSAttributedString.Key: Any] = [
            .font: courier,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(
            string: ScreenplayExporter.plainText(output), attributes: attributes
        )
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// The printed script, carrying the document's Fountain in `/Keywords`.
    public static func pdfData(_ output: ScreenplayOutput) -> Data {
        pdfData(output.printed, carrying: output.fountain)
    }

    /// The page drawn as given. An app prints a `ScreenplayOutput`.
    static func pdfData(_ screenplay: EDraftCore.Screenplay, carrying fountain: String? = nil) -> Data {
        let format = PageFormat.current
        var mediaBox = format.pageRect
        let data = NSMutableData()
        let fountain = fountain ?? Fountain.serialise(screenplay.engineModel)
        // Hex is `[0-9a-f]`, legal inside a PDF literal with no escaping.
        // Core Graphics writes `/Keywords (hex)` into the Info dictionary,
        // which survives a viewer re-save; trailing bytes after `%%EOF` do not.
        let info: [CFString: Any] = [kCGPDFContextKeywords: PdfSignal.encode(fountain)]
        guard let consumer = CGDataConsumer(data: data),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)
        else { return Data() }

        let includeTitlePage = UserDefaults.standard.object(
            forKey: ScreenplayExportPreference.includeTitlePageKey
        ) as? Bool ?? true
        let hasTitlePage = screenplay.titlePage.contains { line in
            !line.text.trimmingCharacters(in: .whitespaces).isEmpty
        }

        if includeTitlePage && hasTitlePage {
            paint(
                ScreenplayPageLayout.titlePageRuns(
                    screenplay, format: format, widthOf: widthOf
                ),
                in: context,
                mediaBox: mediaBox
            )
        }

        if let pages = ScreenplayExporter.paginate(screenplay) {
            let showPageNumbers = UserDefaults.standard.object(forKey: "showPageNumbers") as? Bool ?? true
            let sceneNumbers = ScreenplayExporter.sceneNumberIndex(screenplay)
            let elements = screenplay.engineModel.elements
            // Where each element resumes on the next page — carried forward
            // page by page, the same walk `pageStartLocations` makes.
            var consumed: [Int: Int] = [:]
            for page in pages {
                paint(
                    ScreenplayPageLayout.scriptPageRuns(
                        page,
                        elements: elements,
                        consumed: consumed,
                        sceneNumbers: sceneNumbers,
                        format: format,
                        showPageNumbers: showPageNumbers,
                        widthOf: widthOf
                    ),
                    in: context,
                    mediaBox: mediaBox
                )
                ScreenplayPageLayout.consumePrintedLines(of: page, into: &consumed)
            }
        }

        context.closePDF()
        return Data(referencing: data)
    }

    /// Print the PDF we already export — not a second drawing that could
    /// drift from it. `NSPrintOperation` over a custom view lost: its
    /// paper size comes from `NSPrintInfo` and would paginate again.
    public static func printOperation(_ output: ScreenplayOutput) -> NSPrintOperation? {
        printOperation(pdf: pdfData(output))
    }

    static func printOperation(_ screenplay: EDraftCore.Screenplay) -> NSPrintOperation? {
        printOperation(pdf: pdfData(screenplay))
    }

    private static func printOperation(pdf: Data) -> NSPrintOperation? {
        guard let document = PDFDocument(data: pdf) else { return nil }
        return document.printOperation(
            for: .shared, scalingMode: .pageScaleToFit, autoRotate: true
        )
    }

    public static func runPrint(_ output: ScreenplayOutput) {
        printOperation(output)?.run()
    }

    // MARK: - Drawing

    /// UIKit's PDF renderer is y-down; `CGPDFContext` is y-up. Flip once
    /// so the shared runs (origin = top-left of the string) land where
    /// the iPhone draws them.
    private static func paint(
        _ runs: [ScreenplayPageLayout.Run],
        in context: CGContext,
        mediaBox: CGRect
    ) {
        context.beginPDFPage(nil)
        context.saveGState()
        context.translateBy(x: 0, y: mediaBox.height)
        context.scaleBy(x: 1, y: -1)
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for run in runs {
            drawFitted(run, in: context)
        }
        NSGraphicsContext.current = previous
        context.restoreGState()
        context.endPDFPage()
    }

    /// A glyph taller than the line is drawn smaller so that it sits inside
    /// it, matching the screen. Not a preference: TextKit clips glyph drawing
    /// to the line fragment, so the editor cannot let a tall glyph overflow
    /// while holding six lines to the inch — measured, and the PDF follows the
    /// screen so that one document is one document.
    ///
    /// Style segments are attributes on the line's own attributed string,
    /// read off per grapheme. Courier's fixed advance means a styled glyph
    /// occupies the same width as a plain one — the `x` walk below is as
    /// exact as it was before emphasis existed.
    private static func drawFitted(_ run: ScreenplayPageLayout.Run, in context: CGContext) {
        let attributed = NSMutableAttributedString(string: run.text, attributes: textAttributes)
        for segment in run.segments {
            let range = NSRange(location: segment.start, length: segment.length)
            guard range.location >= 0, NSMaxRange(range) <= attributed.length else { continue }
            attributed.addAttributes(ScriptLayout.styleAttributes(for: segment.styles), range: range)
        }
        // The attention mark goes down before the ink: one fill per
        // highlighted segment, behind everything it covers — a highlight
        // that vanishes on paper is a lie (RFC HIGHLIGHTER D6).
        drawHighlightRects(of: run, attributed: attributed, in: context)
        var x = run.origin.x
        (run.text as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: attributed.length),
            options: .byComposedCharacterSequences
        ) { substring, subrange, _, _ in
            guard let substring else { return }
            let attributes = attributed.attributes(at: subrange.location, effectiveRange: nil)
            let font = (attributes[.font] as? NSFont) ?? courier
            let size = (substring as NSString).size(withAttributes: attributes)
            let height = ScriptLayout.glyphPathHeight(substring, font: font)
            let scale = ScreenplayPageLayout.scaleToFitLine(measuredHeight: height)
            if scale < 0.999 {
                context.saveGState()
                context.translateBy(x: x, y: run.origin.y)
                context.scaleBy(x: scale, y: scale)
                (substring as NSString).draw(at: .zero, withAttributes: attributes)
                context.restoreGState()
                x += size.width * scale
            } else {
                (substring as NSString).draw(
                    at: CGPoint(x: x, y: run.origin.y), withAttributes: attributes
                )
                x += size.width
            }
        }
    }

    /// v1's one color, as paper wants it: a pastel that black Courier
    /// reads cleanly through, in print and on screen.
    private static let highlightFill = NSColor(
        calibratedRed: 1.0, green: 0.93, blue: 0.42, alpha: 0.65
    ).cgColor

    /// One filled rect per highlighted segment, computed with the same
    /// per-grapheme walk the ink uses, so the mark and the glyphs over it
    /// always agree about where a column sits.
    private static func drawHighlightRects(
        of run: ScreenplayPageLayout.Run,
        attributed: NSAttributedString,
        in context: CGContext
    ) {
        let marked = run.segments.filter { $0.highlight != nil }
        guard !marked.isEmpty else { return }
        var rects: [CGRect] = []
        var x = run.origin.x
        (run.text as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: attributed.length),
            options: .byComposedCharacterSequences
        ) { substring, subrange, _, _ in
            guard let substring else { return }
            let attributes = attributed.attributes(at: subrange.location, effectiveRange: nil)
            let width = (substring as NSString).size(withAttributes: attributes).width
            let height = ScriptLayout.glyphPathHeight(substring, font: (attributes[.font] as? NSFont) ?? courier)
            let scale = ScreenplayPageLayout.scaleToFitLine(measuredHeight: height)
            for segment in marked where subrange.location + subrange.length > segment.start
                && subrange.location < segment.start + segment.length {
                let rect = CGRect(
                    x: x, y: run.origin.y,
                    width: width * (scale < 0.999 ? scale : 1),
                    height: ScreenplayPageLayout.lineHeight
                )
                if let last = rects.last, abs(last.maxX - rect.minX) < 0.5 {
                    rects[rects.count - 1] = last.union(rect)
                } else {
                    rects.append(rect)
                }
            }
            x += width * (scale < 0.999 ? scale : 1)
        }
        context.setFillColor(highlightFill)
        for rect in rects { context.fill(rect) }
    }
}
