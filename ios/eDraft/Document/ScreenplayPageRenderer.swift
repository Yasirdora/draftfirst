import EDraftCore
import EDraftEngine
import EDraftUI
import UIKit
import UniformTypeIdentifiers

/// The renderings that have to be drawn.
///
/// PDF is the deliverable a production actually receives, and RTF borrows its
/// font, so both need a typeface and a graphics context — the two things a
/// platform owns and the core deliberately does not. Everything they are drawn
/// *from* — pagination, indents, the scene numbers a draft carries in its
/// margins — comes from `ScreenplayExporter`, so the page this writes and the
/// page the editor shows can never be laid out by two different rules.
///
/// The Mac's counterpart will be this file with AppKit's names in it.
enum ScreenplayPageRenderer {

    /// Courier 12pt: 1.5″ left margin, six lines per inch — the geometry
    /// `Paginator` paginates against. Measured from the real font so a
    /// fallback monospaced face still lays out correctly.
    private static let courier = UIFont(name: "Courier", size: 12)
        ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let lineHeight: CGFloat = 12
    private static let textLeft: CGFloat = 108

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [.font: courier, .foregroundColor: UIColor.black]
    }

    /// Rich text with Courier at a fixed six-lines-per-inch rhythm. Word
    /// processors reflow page breaks; the on-screen layout still matches.
    static func rtfData(_ screenplay: EDraftCore.Screenplay) -> Data? {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
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

    static func pdfData(_ screenplay: EDraftCore.Screenplay) -> Data {
        let format = PageFormat.current
        let renderer = UIGraphicsPDFRenderer(bounds: format.pageRect)
        let includeTitlePage = UserDefaults.standard.object(forKey: includeTitlePageKey) as? Bool ?? true
        let hasTitlePage = screenplay.titlePage.contains { entry in
            entry.values.contains { !$0.isEmpty }
        }
        return renderer.pdfData { context in
            // The title page exists only when it has something to say — an
            // empty one must never yield a blank first page.
            if includeTitlePage && hasTitlePage {
                context.beginPage()
                drawTitlePage(screenplay, format: format)
            }

            guard let pages = ScreenplayExporter.paginate(screenplay) else { return }
            let showPageNumbers = UserDefaults.standard.object(forKey: "showPageNumbers") as? Bool ?? true
            // No preference gates these: a script carries scene numbers only
            // because a writer or a production put them there, and a numbered
            // script that prints unnumbered pages is the wrong deliverable.
            let sceneNumbers = ScreenplayExporter.sceneNumberIndex(screenplay)
            for page in pages {
                context.beginPage()
                drawScriptPage(
                    page,
                    sceneNumbers: sceneNumbers,
                    format: format,
                    showPageNumbers: showPageNumbers
                )
            }
        }
    }

    private static func drawScriptPage(
        _ page: EDraftEngine.ScriptPage,
        sceneNumbers: [Int: String],
        format: PageFormat,
        showPageNumbers: Bool
    ) {
        let attributes = textAttributes
        let characterWidth = ("0" as NSString).size(withAttributes: attributes).width
        let textTop = format.textTop
        let marks = ScreenplayExporter.sceneNumberMarks(for: page, numbers: sceneNumbers)

        /* Page numbers print top-right from the second page on, "2." style. */
        if page.number > 1 && showPageNumbers {
            drawRightAligned("\(page.number).", rightEdge: format.textRight, y: 36, attributes: attributes)
        }
        if page.continuedTop {
            ("CONTINUED:" as NSString).draw(
                at: CGPoint(x: textLeft, y: textTop - 24), withAttributes: attributes
            )
        }

        for (index, line) in page.lines.enumerated() where line.type != .blank {
            let y = textTop + CGFloat(index) * lineHeight
            let text = ScreenplayExporter.renderedText(for: line)
            switch line.type {
            case .element(.transition):
                drawRightAligned(text, rightEdge: format.textRight, y: y, attributes: attributes)
            case .element(.centered):
                drawCentered(text, y: y, format: format, attributes: attributes)
            default:
                let x = textLeft + CGFloat(ScreenplayExporter.leadingSpaces(for: line)) * characterWidth
                (text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
            }
            if let number = marks[index] {
                drawSceneNumber(
                    number, y: y, format: format,
                    characterWidth: characterWidth, attributes: attributes
                )
            }
        }

        if page.continuedBottom {
            drawRightAligned(
                "(CONTINUED)", rightEdge: format.textRight,
                y: textTop + CGFloat(format.linesPerPage + 1) * lineHeight,
                attributes: attributes
            )
        }
    }

    /// The classic centered title-page stack in the same Courier voice as
    /// the script: the title in uppercase ~1/3 down, the credit beneath it,
    /// then the writers, then any source or custom credit lines in document
    /// order. Contact details sit bottom-left, as productions expect them.
    private static func drawTitlePage(_ screenplay: EDraftCore.Screenplay, format: PageFormat) {
        func values(_ key: String) -> [String] {
            screenplay.titlePage
                .first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?
                .values.filter { !$0.isEmpty } ?? []
        }

        var y = format.pageRect.height * 0.32
        for line in values("Title") {
            drawCentered(line.uppercased(), y: y, format: format, attributes: textAttributes)
            y += lineHeight
        }
        y += lineHeight
        for line in values("Credit") {
            drawCentered(line, y: y, format: format, attributes: textAttributes)
            y += lineHeight
        }
        y += lineHeight
        for line in values("Author") {
            drawCentered(line, y: y, format: format, attributes: textAttributes)
            y += lineHeight
        }

        /* Source and custom credits follow in stored order: custom keys
           print their label line first ("Additional writing by"), Source
           prints its values verbatim (the phrase already carries it). */
        for entry in screenplay.titlePage {
            let key = entry.key.lowercased()
            guard !["title", "credit", "author", "contact"].contains(key) else { continue }
            let lines = entry.values.filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }
            y += lineHeight
            if key != "source" {
                drawCentered(entry.key, y: y, format: format, attributes: textAttributes)
                y += lineHeight
            }
            for line in lines {
                drawCentered(line, y: y, format: format, attributes: textAttributes)
                y += lineHeight
            }
        }

        let contact = values("Contact")
        if !contact.isEmpty {
            var contactY = format.pageRect.height - 72 - CGFloat(contact.count - 1) * lineHeight
            for line in contact {
                (line as NSString).draw(
                    at: CGPoint(x: Self.textLeft, y: contactY), withAttributes: textAttributes
                )
                contactY += lineHeight
            }
        }
    }

    private static func drawCentered(
        _ text: String, y: CGFloat, format: PageFormat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        string.draw(
            at: CGPoint(x: (format.pageRect.width - size.width) / 2, y: y),
            withAttributes: attributes
        )
    }

    /// A scene number in both margins, level with its slug.
    ///
    /// Both sides, because a production draft is read from either: a script
    /// supervisor works down the left, a first AD breaking down a page reads
    /// the right. The left number is right-aligned and the right one
    /// left-aligned, so both sit a constant gap from the text however many
    /// digits they carry — "7" and "112A" line up against the same edge.
    private static func drawSceneNumber(
        _ number: String, y: CGFloat, format: PageFormat,
        characterWidth: CGFloat, attributes: [NSAttributedString.Key: Any]
    ) {
        let gap = characterWidth * 2
        drawRightAligned(number, rightEdge: textLeft - gap, y: y, attributes: attributes)
        (number as NSString).draw(
            at: CGPoint(x: format.textRight + gap, y: y), withAttributes: attributes
        )
    }

    private static func drawRightAligned(
        _ text: String, rightEdge: CGFloat, y: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        string.draw(at: CGPoint(x: rightEdge - size.width, y: y), withAttributes: attributes)
    }
}
