import CoreGraphics
import EDraftCore
import UIKit

/// Drawing a string at a point, in a font.
///
/// Where each line sits is `ScreenplayPageLayout` in the core — the same
/// arithmetic the Mac draws. What remains here is the platform's half:
/// Courier as a `UIFont`, black as a `UIColor`, and a `UIGraphicsPDFRenderer`
/// to put the runs on paper. Sixty-odd lines, not two hundred: a second
/// copy of the placement maths would be two answers to the same question.
public enum ScreenplayPageRenderer {

    private static let courier = UIFont(name: "Courier", size: ScreenplayPageLayout.fontSize)
        ?? .monospacedSystemFont(ofSize: ScreenplayPageLayout.fontSize, weight: .regular)

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [.font: courier, .foregroundColor: UIColor.black]
    }

    private static var widthOf: (String) -> CGFloat {
        { ($0 as NSString).size(withAttributes: textAttributes).width }
    }

    /// Rich text with Courier at a fixed six-lines-per-inch rhythm. Word
    /// processors reflow page breaks; the on-screen layout still matches.
    public static func rtfData(_ screenplay: EDraftCore.Screenplay) -> Data? {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = ScreenplayPageLayout.lineHeight
        paragraph.maximumLineHeight = ScreenplayPageLayout.lineHeight
        paragraph.lineSpacing = 0
        let attributes: [NSAttributedString.Key: Any] = [
            .font: courier,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: ScreenplayExporter.plainText(screenplay), attributes: attributes)
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    // MARK: PDF

    /// The writer's choice, shared with the panel that offers it.
    static var includeTitlePageKey: String { ScreenplayExportPreference.includeTitlePageKey }

    public static func pdfData(_ screenplay: EDraftCore.Screenplay) -> Data {
        let format = PageFormat.current
        let rendererFormat = UIGraphicsPDFRendererFormat()
        rendererFormat.documentInfo = [
            kCGPDFContextKeywords as String: PdfSignal.encode(
                ScreenplayExporter.fountainSource(screenplay)
            )
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: format.pageRect, format: rendererFormat)
        let includeTitlePage = UserDefaults.standard.object(forKey: includeTitlePageKey) as? Bool ?? true
        let hasTitlePage = screenplay.titlePage.contains { line in
            !line.text.trimmingCharacters(in: .whitespaces).isEmpty
        }
        let pdf = renderer.pdfData { context in
            // The title page exists only when it has something to say — an
            // empty one must never yield a blank first page.
            if includeTitlePage && hasTitlePage {
                context.beginPage()
                draw(ScreenplayPageLayout.titlePageRuns(
                    screenplay, format: format, widthOf: widthOf
                ))
            }

            guard let pages = ScreenplayExporter.paginate(screenplay) else { return }
            let showPageNumbers = UserDefaults.standard.object(forKey: "showPageNumbers") as? Bool ?? true
            // No preference gates these: a script carries scene numbers only
            // because a writer or a production put them there, and a numbered
            // script that prints unnumbered pages is the wrong deliverable.
            let sceneNumbers = ScreenplayExporter.sceneNumberIndex(screenplay)
            for page in pages {
                context.beginPage()
                draw(ScreenplayPageLayout.scriptPageRuns(
                    page,
                    sceneNumbers: sceneNumbers,
                    format: format,
                    showPageNumbers: showPageNumbers,
                    widthOf: widthOf
                ))
            }
        }
        return pdf
    }

    private static func draw(_ runs: [ScreenplayPageLayout.Run]) {
        // The attention mark goes down before the ink, as the Mac draws it —
        // one document is one document on paper too (RFC HIGHLIGHTER D6).
        let characterWidth = ("0" as NSString).size(withAttributes: textAttributes).width
        for run in runs {
            let marked = run.segments.filter { $0.highlight != nil }
            if !marked.isEmpty {
                UIColor(red: 1.0, green: 0.93, blue: 0.42, alpha: 0.65).setFill()
                for segment in marked {
                    UIRectFill(CGRect(
                        x: run.origin.x + CGFloat(segment.start) * characterWidth,
                        y: run.origin.y,
                        width: CGFloat(segment.length) * characterWidth,
                        height: ScreenplayPageLayout.lineHeight
                    ))
                }
            }
            (run.text as NSString).draw(at: run.origin, withAttributes: textAttributes)
        }
    }
}
