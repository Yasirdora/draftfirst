import SwiftUI
import UIKit
import UniformTypeIdentifiers
import DraftFirstEngine

extension UTType {
    nonisolated static let draftFirstScreenplay = UTType(
        exportedAs: "xyz.draftfirst.screenplay",
        conformingTo: .plainText
    )
    /// Final Draft's interchange format. The declaration is imported: when
    /// Final Draft itself is installed its own declaration wins; ours makes
    /// .fdx openable everywhere else.
    nonisolated static let finalDraftScreenplay = UTType(
        importedAs: "com.finaldraft.fdx",
        conformingTo: .xml
    )
}

struct DraftFirstDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        // Plain text covers the migration paths — paste-ready .txt and
        // .fountain files (the imported fountain UTI conforms to it). FDX is
        // the professional migration path: a Final Draft file opens in place.
        [.draftFirstScreenplay, .plainText, .finalDraftScreenplay]
    }

    static var writableContentTypes: [UTType] {
        // Every readable type is writable: a screenplay's source IS plain
        // text (Fountain), and an .fdx opened in place writes back as FDX —
        // never a read-only trap that would strand an hour of work.
        [.draftFirstScreenplay, .plainText, .finalDraftScreenplay]
    }

    var source: String

    init(source: String = DraftFirstDocument.blankSource) {
        self.source = source
    }

    init(configuration: ReadConfiguration) throws {
        self.source = try Self.decode(
            configuration.file.regularFileContents,
            as: configuration.contentType
        )
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: try Self.encode(source, as: configuration.contentType))
    }

    /// UTF-8 is the only on-disk encoding; anything else is corruption,
    /// never a silent lossy conversion.
    static func decode(_ data: Data?) throws -> String {
        guard let data, let source = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return source
    }

    static func encode(_ source: String) throws -> Data {
        guard let data = source.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    /// The typed read boundary. FDX is converted to the Fountain source of
    /// truth on the way in: the engine's reader is total (best-effort,
    /// never throws), so a foreign file can corrupt nothing.
    static func decode(_ data: Data?, as type: UTType) throws -> String {
        let text = try decode(data)
        guard type.conforms(to: .finalDraftScreenplay) else { return text }
        return Fountain.serialise(Fdx.parse(text).script)
    }

    /// The typed write boundary: an .fdx opened in place writes back as
    /// FDX — never Fountain source wearing an .fdx name, which Final Draft
    /// would refuse to open.
    static func encode(_ source: String, as type: UTType) throws -> Data {
        if type.conforms(to: .finalDraftScreenplay) {
            let screenplay = try Fountain.parse(source)
            return try encode(Fdx.writeXml(screenplay))
        }
        return try encode(source)
    }

    /// A new screenplay is a blank page, not a pre-written ritual: title
    /// page plus nothing. FADE IN: is the writer's to type, not ours.
    private static let blankSource = """
    Title: Untitled Screenplay
    Credit: written by


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

    /// Final Draft interchange XML, written by the engine's conformance-
    /// pinned exporter — the delivery format productions expect. Elements
    /// FDX cannot represent are omitted with an in-file warning comment,
    /// the same contract as the web app.
    static func fdxSource(_ screenplay: Screenplay) -> String {
        Fdx.writeXml(screenplay.engineModel)
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

    /// The Options toggle's storage key — one app-level export behavior,
    /// on by default.
    static let includeTitlePageKey = "includeTitlePageInPDF"

    static func pdfData(_ screenplay: Screenplay) -> Data {
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

            guard let pages = paginate(screenplay) else { return }
            let showPageNumbers = UserDefaults.standard.object(forKey: "showPageNumbers") as? Bool ?? true
            for page in pages {
                context.beginPage()
                drawScriptPage(page, format: format, showPageNumbers: showPageNumbers)
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

    private static func drawScriptPage(_ page: DraftFirstEngine.ScriptPage, format: PageFormat, showPageNumbers: Bool) {
        let attributes = textAttributes
        let characterWidth = ("0" as NSString).size(withAttributes: attributes).width
        let textTop = format.textTop

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

    /// The classic centered title-page stack in the same Courier voice as
    /// the script: the title in uppercase ~1/3 down, the credit beneath it,
    /// then the writers, then any source or custom credit lines in document
    /// order. Contact details sit bottom-left, as productions expect them.
    private static func drawTitlePage(_ screenplay: Screenplay, format: PageFormat) {
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

    private static func drawRightAligned(
        _ text: String, rightEdge: CGFloat, y: CGFloat,
        attributes: [NSAttributedString.Key: Any]
    ) {
        let string = text as NSString
        let size = string.size(withAttributes: attributes)
        string.draw(at: CGPoint(x: rightEdge - size.width, y: y), withAttributes: attributes)
    }
}
