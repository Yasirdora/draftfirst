import AppKit
import CoreGraphics
import CoreText
import EDraftCore
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

    public static func rtfData(_ screenplay: EDraftCore.Screenplay) -> Data? {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = ScreenplayPageLayout.lineHeight
        paragraph.maximumLineHeight = ScreenplayPageLayout.lineHeight
        paragraph.lineSpacing = 0
        let attributes: [NSAttributedString.Key: Any] = [
            .font: courier,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(
            string: ScreenplayExporter.plainText(screenplay), attributes: attributes
        )
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    /// The printable deliverable, with the Fountain source in `/Keywords`.
    public static func pdfData(_ screenplay: EDraftCore.Screenplay) -> Data {
        let format = PageFormat.current
        var mediaBox = format.pageRect
        let data = NSMutableData()
        let fountain = ScreenplayExporter.fountainSource(screenplay)
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
        let hasTitlePage = screenplay.titlePage.contains { entry in
            entry.values.contains { !$0.isEmpty }
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
            for page in pages {
                paint(
                    ScreenplayPageLayout.scriptPageRuns(
                        page,
                        sceneNumbers: sceneNumbers,
                        format: format,
                        showPageNumbers: showPageNumbers,
                        widthOf: widthOf
                    ),
                    in: context,
                    mediaBox: mediaBox
                )
            }
        }

        context.closePDF()
        return Data(referencing: data)
    }

    /// Print the PDF we already export — not a second drawing that could
    /// drift from it. `NSPrintOperation` over a custom view lost: its
    /// paper size comes from `NSPrintInfo` and would paginate again.
    public static func printOperation(_ screenplay: EDraftCore.Screenplay) -> NSPrintOperation? {
        guard let document = PDFDocument(data: pdfData(screenplay)) else { return nil }
        return document.printOperation(
            for: .shared, scalingMode: .pageScaleToFit, autoRotate: true
        )
    }

    public static func runPrint(_ screenplay: EDraftCore.Screenplay) {
        printOperation(screenplay)?.run()
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
            drawFitted(run.text, at: run.origin, in: context)
        }
        NSGraphicsContext.current = previous
        context.restoreGState()
        context.endPDFPage()
    }

    /// A glyph taller than the line — an emoji — overflows into the space
    /// above it, exactly as it does on screen and as it does in every other
    /// editor. It is not scaled: line height is an advance, not a clipping
    /// box, and shrinking the picture to fit the box was the screen's old
    /// `maximumLineHeight` problem wearing a different hat.
    private static func drawFitted(_ string: String, at origin: CGPoint, in context: CGContext) {
        (string as NSString).draw(at: origin, withAttributes: textAttributes)
    }
}
