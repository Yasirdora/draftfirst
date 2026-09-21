import EDraftEngine
import Foundation

/// Shareable renderings of a screenplay that need no drawing.
///
/// Fountain is the native, future-proof source; plain text mirrors the printed
/// layout. Both are laid out by the same engine paginator that drives the
/// editor's page estimates, so an export always matches what the writer sees.
///
/// The formats that must be *drawn* — PDF, and the RTF that borrows its font —
/// live with the surface that has a font and a graphics context. What they
/// share is here: pagination, the scene numbers a production draft carries in
/// its margins, the indent rules, and the staging of a file to hand on.
public enum ScreenplayExporter {

    // MARK: Text formats

    public static func fountainSource(_ screenplay: EDraftCore.Screenplay) -> String {
        Fountain.serialise(screenplay.engineModel)
    }

    /// Final Draft interchange XML, written by the engine's conformance-
    /// pinned exporter — the delivery format productions expect. Elements
    /// FDX cannot represent are omitted with an in-file warning comment,
    /// the same contract as the web app. The writer's notes are Final Draft
    /// ScriptNotes, signed with the name the writer gave (RFC-NOTES-SYSTEM §8).
    public static func fdxSource(_ screenplay: EDraftCore.Screenplay) -> String {
        Fdx.write(
            screenplay.engineModel,
            options: Fdx.ExportOptions(notes: Fdx.NoteWriting(writer: NoteIdentity.signature))
        ).xml
    }

    /// Monospaced text mirroring the printed layout: element indents applied,
    /// transitions flush right at the 60-character text block.
    public static func plainText(_ screenplay: EDraftCore.Screenplay) -> String {
        guard let pages = paginate(screenplay) else { return fountainSource(screenplay) }
        var out: [String] = []
        for page in pages {
            for line in page.lines {
                if line.type == .blank {
                    out.append("")
                } else {
                    out.append(String(repeating: " ", count: leadingSpaces(for: line)) + renderedText(for: line))
                }
            }
            out.append("")
        }
        return out.joined(separator: "\n")
    }
    // MARK: File staging

    /// Writes export data to a shareable temporary file named after the
    /// screenplay ("The Last Light.pdf").
    public static func temporaryFile(named title: String, extension ext: String, contents: Data) throws -> URL {
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

    /// Scene numbers by element index, empty for a script that has none.
    ///
    /// Numbers live on the element, not in its text — the parser splits `#1#`
    /// off the slug — so the page has to ask the screenplay for them. Reading
    /// them here rather than teaching the paginator to emit them keeps the
    /// paginator's output byte-identical to its conformance corpus, and puts
    /// the numbers where a production draft actually carries them: the
    /// margins, outside the measured text block.
    public static func sceneNumberIndex(_ screenplay: EDraftCore.Screenplay) -> [Int: String] {
        var index: [Int: String] = [:]
        for (position, element) in screenplay.elements.enumerated() {
            guard element.type == .scene,
                  let number = element.sceneNumber,
                  !number.isEmpty else { continue }
            index[position] = number
        }
        return index
    }

    /// Which lines of a page carry a scene number, by line index.
    ///
    /// A slug long enough to wrap occupies several lines that all point at the
    /// same element; only the first of them is numbered, or the margin would
    /// repeat the number down the side of one heading.
    public static func sceneNumberMarks(
        for page: EDraftEngine.ScriptPage, numbers: [Int: String]
    ) -> [Int: String] {
        var marks: [Int: String] = [:]
        var numbered: Int?
        for (index, line) in page.lines.enumerated() {
            guard case .element(.scene) = line.type, line.element != numbered else { continue }
            numbered = line.element
            if let number = numbers[line.element] { marks[index] = number }
        }
        return marks
    }

    public static func paginate(_ screenplay: EDraftCore.Screenplay) -> [EDraftEngine.ScriptPage]? {
        try? Paginator.paginate(screenplay.engineModel, linesPerPage: PageFormat.current.linesPerPage)
    }

    /// How much page a run of elements takes, in pages.
    ///
    /// The measure behind a cut scene's pill when the file recorded no
    /// `SceneProperties Length` — a scene eDraft omitted itself, or one
    /// whose heading carried none. Lines rather than pages, because a
    /// quarter-page scene and a whole one both paginate to a single page
    /// and the pill has to tell them apart.
    public static func pages(of elements: [ScriptElement]) -> Double {
        guard !elements.isEmpty else { return 0 }
        let perPage = PageFormat.current.linesPerPage
        guard perPage > 0,
              let pages = try? Paginator.paginate(
                  Screenplay(elements: elements).engineModel, linesPerPage: perPage
              )
        else { return 0 }
        let lines = pages.reduce(0) { $0 + $1.lines.count }
        return Double(lines) / Double(perPage)
    }

    /// The same pages at the cost of the changed region alone. The engine
    /// owns the diff and the proof (`paginateIncrementally == paginate`,
    /// fuzz-pinned in both languages); a caller with nothing cached gets the
    /// full pass, so this is the only call a live-editing surface needs.
    public static func paginateIncrementally(
        _ screenplay: EDraftCore.Screenplay,
        previous: EDraftCore.Screenplay,
        previousPages: [EDraftEngine.ScriptPage]
    ) -> [EDraftEngine.ScriptPage]? {
        try? Paginator.paginateIncrementally(
            screenplay.engineModel,
            previous: previous.engineModel,
            previousPages: previousPages,
            linesPerPage: PageFormat.current.linesPerPage
        )
    }

    /// Indent in spaces for the monospaced formats; transitions right-align
    /// against the 60-character text block. Widths count UTF-16 units, the
    /// engine's own measure.
    public static func leadingSpaces(for line: PageLine) -> Int {
        if case .element(.transition) = line.type {
            return max(0, Paginator.pageWidthChars - line.text.utf16.count)
        }
        return max(0, line.indent)
    }

    /// A dual-dialogue cue carries Fountain's `^` marker through the
    /// paginator so wrapping accounts for its width; a rendered page must
    /// never show it. Dual speeches print sequentially — nothing lost,
    /// nothing invented — the same contract as the web PDF exporter, until
    /// a true side-by-side layout exists.
    public static func renderedText(for line: PageLine) -> String {
        if case .element(.character) = line.type, line.text.hasSuffix(" ^") {
            return String(line.text.dropLast(2))
        }
        return line.text
    }
}
