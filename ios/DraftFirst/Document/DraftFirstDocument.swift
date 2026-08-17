import SwiftUI
import UIKit
import UniformTypeIdentifiers
import DraftFirstEngine

extension UTType {
    nonisolated static let draftFirstScreenplay = UTType(
        exportedAs: "xyz.draftfirst.screenplay",
        conformingTo: .plainText
    )
}

struct DraftFirstDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        // Reading plain text keeps migration paths open (paste-ready .txt and
        // .fountain files); writing is always our own screenplay type.
        [.draftFirstScreenplay, .plainText]
    }

    static var writableContentTypes: [UTType] {
        [.draftFirstScreenplay]
    }

    var source: String

    init(source: String = DraftFirstDocument.blankSource) {
        self.source = source
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let source = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.source = source
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        guard let data = source.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return FileWrapper(regularFileWithContents: data)
    }

    private static let blankSource = """
    Title: Untitled Screenplay
    Credit: written by

    FADE IN:


    """
}

// MARK: - Export

/// Shareable renderings of a screenplay. Fountain is the native, future-proof
/// source; plain text, RTF, and PDF are laid out by the same engine paginator
/// that drives the editor's page estimates, so exports always match what the
/// writer sees. Page geometry honors the document's PageFormat setting.
enum ScreenplayExporter {

    // MARK: Text formats

    static func fountainSource(_ screenplay: Screenplay) -> String {
        Fountain.serialise(screenplay.engineModel)
    }

    /// Monospaced text mirroring the printed layout: element indents applied,
    /// transitions flush right at the 60-character text block.
    static func plainText(_ screenplay: Screenplay) -> String {
        guard let pages = paginate(screenplay) else { return fountainSource(screenplay) }
        var out: [String] = []
        for page in pages {
            for line in page.lines {
                if line.type == .blank {
                    out.append("")
                } else {
                    out.append(String(repeating: " ", count: leadingSpaces(for: line)) + line.text)
                }
            }
            out.append("")
        }
        return out.joined(separator: "\n")
    }

    /// Rich text with Courier at a fixed six-lines-per-inch rhythm. Word
    /// processors reflow page breaks; the on-screen layout still matches.
    static func rtfData(_ screenplay: Screenplay) -> Data? {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineSpacing = 0
        let attributes: [NSAttributedString.Key: Any] = [
            .font: courier,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: plainText(screenplay), attributes: attributes)
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }

    // MARK: PDF

    /// Courier 12pt: 1.5″ left margin, six lines per inch — the geometry
    /// `Paginator` paginates against. Measured from the real font so a
    /// fallback monospaced face still lays out correctly.
    private static let courier = UIFont(name: "Courier", size: 12)
        ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
    private static let lineHeight: CGFloat = 12
    private static let textLeft: CGFloat = 108

    static func pdfData(_ screenplay: Screenplay) -> Data {
        let format = PageFormat.current
        let renderer = UIGraphicsPDFRenderer(bounds: format.pageRect)
        return renderer.pdfData { context in
            context.beginPage()
            drawTitlePage(screenplay, format: format)

            guard let pages = paginate(screenplay) else { return }
            for page in pages {
                context.beginPage()
                drawScriptPage(page, format: format)
            }
        }
    }

    // MARK: File staging

    /// Writes export data to a shareable temporary file named after the
    /// screenplay ("The Last Light.pdf").
    static func temporaryFile(named title: String, extension ext: String, contents: Data) throws -> URL {
        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let base = title.components(separatedBy: illegal).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = base.isEmpty ? "Screenplay" : base
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(ext)
        try contents.write(to: url, options: .atomic)
        return url
    }

    // MARK: Drawing internals

    private static func paginate(_ screenplay: Screenplay) -> [DraftFirstEngine.ScriptPage]? {
        try? Paginator.paginate(screenplay.engineModel, linesPerPage: PageFormat.current.linesPerPage)
    }

    private static var textAttributes: [NSAttributedString.Key: Any] {
        [.font: courier, .foregroundColor: UIColor.black]
    }

    /// Indent in spaces for the monospaced formats; transitions right-align
    /// against the 60-character text block. Widths count UTF-16 units, the
    /// engine's own measure.
    private static func leadingSpaces(for line: PageLine) -> Int {
        if case .element(.transition) = line.type {
            return max(0, Paginator.pageWidthChars - line.text.utf16.count)
        }
        return max(0, line.indent)
    }

    private static func drawScriptPage(_ page: DraftFirstEngine.ScriptPage, format: PageFormat) {
        let attributes = textAttributes
        let characterWidth = ("0" as NSString).size(withAttributes: attributes).width
        let textTop = format.textTop

        /* Page numbers print top-right from the second page on, "2." style. */
        if page.number > 1 {
            drawRightAligned("\(page.number).", rightEdge: format.textRight, y: 36, attributes: attributes)
        }
        if page.continuedTop {
            ("CONTINUED:" as NSString).draw(
                at: CGPoint(x: textLeft, y: textTop - 24), withAttributes: attributes
            )
        }

        for (index, line) in page.lines.enumerated() where line.type != .blank {
            let y = textTop + CGFloat(index) * lineHeight
            switch line.type {
            case .element(.transition):
                drawRightAligned(line.text, rightEdge: format.textRight, y: y, attributes: attributes)
            case .element(.centered):
                drawCentered(line.text, y: y, format: format, attributes: attributes)
            default:
                let x = textLeft + CGFloat(leadingSpaces(for: line)) * characterWidth
                (line.text as NSString).draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
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

    /// Title ~1/3 down, then credit, then author — the classic centered
    /// title-page stack in the same Courier voice as the script.
    private static func drawTitlePage(_ screenplay: Screenplay, format: PageFormat) {
        func values(_ key: String) -> [String] {
            screenplay.titlePage
                .first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?
                .values.filter { !$0.isEmpty } ?? []
        }

        var y = format.pageRect.height * 0.32
        for line in values("Title") {
            drawCentered(line, y: y, format: format, attributes: textAttributes)
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

    private static func drawRightAligned(
        _ text: String, rightEdge: CGFloat, y: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        string.draw(at: CGPoint(x: rightEdge - size.width, y: y), withAttributes: attributes)
    }
}
