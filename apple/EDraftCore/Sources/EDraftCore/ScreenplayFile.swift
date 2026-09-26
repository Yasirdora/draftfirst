import EDraftEngine
import Foundation
import UniformTypeIdentifiers

extension UTType {
    public nonisolated static let edraftScreenplay = UTType(
        exportedAs: "xyz.edraft.screenplay",
        conformingTo: .plainText
    )
    /// Final Draft's interchange format. The declaration is imported: when
    /// Final Draft itself is installed its own declaration wins; ours makes
    /// .fdx openable everywhere else.
    public nonisolated static let finalDraftScreenplay = UTType(
        importedAs: "com.finaldraft.fdx",
        conformingTo: .xml
    )
}

/// What a screenplay is, on disk.
///
/// The bytes, their types, and the conversions between them — nothing about
/// how a document is presented, so both surfaces read and write the same file
/// the same way. `EDraftDocument` in EDraftUI is the SwiftUI wrapper over
/// this; everything that decides what is legal on disk decides it here.
/// Reading and writing a file is not main-actor work, and a document is opened
/// before there is any actor to be on: `FileDocument.init(configuration:)` is
/// nonisolated, so everything it calls must be too.
public nonisolated enum ScreenplayFile {

    /// A file as it was read. `source` is Fountain. `script` is the Final
    /// Draft reading, runs included, and is nil for a text file. Fountain
    /// cannot spell a highlight, so a highlight lives only on `script`.
    public struct Opened: Sendable {
        public let source: String
        public let origin: String?
        public let script: EDraftEngine.Screenplay?

        public init(source: String, origin: String?, script: EDraftEngine.Screenplay?) {
            self.source = source
            self.origin = origin
            self.script = script
        }
    }

    /// UTF-8 is the only on-disk encoding; anything else is corruption,
    /// never a silent lossy conversion.
    public static func decode(_ data: Data?) throws -> String {
        guard let data, let source = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return source
    }

    public static func encode(_ source: String) throws -> Data {
        guard let data = source.data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return data
    }

    /// The typed read boundary. FDX is converted to the Fountain source of
    /// truth on the way in: the engine's reader is total (best-effort,
    /// never throws), so a foreign file can corrupt nothing.
    public static func decode(_ data: Data?, as type: UTType) throws -> String {
        try open(data, as: type).source
    }

    /// The same read, keeping the original when it is one we must write back
    /// whole.
    ///
    /// A screenplay cannot hold what a Final Draft file carries — revisions,
    /// locked pages, tags, the arc beats nested inside a scene heading — so a
    /// save that rebuilt the file from the screenplay would delete all of it.
    /// The original comes along, and `encode` edits it. See `Fdx.Document`.
    public static func open(_ data: Data?, as type: UTType) throws -> (source: String, origin: String?) {
        let opened = try read(data, as: type)
        return (opened.source, opened.origin)
    }

    /// `open`, plus the Final Draft reading whose runs a highlight lives on.
    public static func read(_ data: Data?, as type: UTType) throws -> Opened {
        let text = try decode(data)
        guard type.conforms(to: .finalDraftScreenplay) else {
            return Opened(source: text, origin: nil, script: nil)
        }
        let script = shouted(Fdx.parse(text).script)
        return Opened(source: Fountain.serialise(script), origin: text, script: script)
    }

    /// The kinds a screenplay shouts, shouted — for a document arriving from
    /// Final Draft.
    ///
    /// Final Draft stores what the writer typed and applies the capitals in the
    /// *view*, so a perfectly ordinary .fdx can hold `cUT TO:`, `UnCLE` and
    /// `yOUNG GIRL (tRANSLATED)` while looking immaculate on screen for years.
    /// Opened anywhere else the file says what it really says.
    ///
    /// Fixing it on the way in is not cosmetic. Fountain detects a transition
    /// by its capitals, so `cUT TO:` is not a transition to any Fountain tool;
    /// the only way to carry it across as one is a forcing marker, and a clean
    /// script would arrive — and later export — as a thicket of `>` and `@`.
    /// This is also the one moment it is safe to do: while a writer is typing,
    /// their casing is their own, and the editor's conversion rule keeps the
    /// original so that converting a line back restores what they wrote.
    private static func shouted(_ screenplay: EDraftEngine.Screenplay)
    -> EDraftEngine.Screenplay {
        var corrected = screenplay
        corrected.elements = screenplay.elements.map { element in
            var element = element
            element.text = Normalize.canonicalCasing(kind: element.type, text: element.text)
            return element
        }
        return corrected
    }

    /// The typed write boundary: an .fdx opened in place writes back as
    /// FDX — never Fountain source wearing an .fdx name, which Final Draft
    /// would refuse to open.
    ///
    /// With `origin` — the file as it was read — the save *edits* it: only the
    /// paragraphs the writer changed are rewritten, and everything eDraft does
    /// not model survives untouched. Without one, as when exporting a
    /// screenplay that began life here, a whole file is written.
    ///
    /// `omissions` are the scenes the writer has omitted, as the editor
    /// published them with this source (§7.3). Fountain cannot spell an
    /// omission, so without them the file's own structure decides — which
    /// is right until the writer omits or restores a scene, and wrong after.
    public static func encode(
        _ source: String, as type: UTType, origin: String? = nil, omissions: OmissionSpans? = nil
    ) throws -> Data {
        guard type.conforms(to: .finalDraftScreenplay) else { return try encode(source) }
        let screenplay = Omissions.applying(omissions, to: try Fountain.parse(source, emphasis: .runs))
        return try encode(screenplay, as: type, origin: origin, omissions: nil, alreadyApplied: true)
    }

    /// The save the editor performs. `screenplay` is the live script, so a
    /// highlight is written as `EDraft:Highlight`. The string entry above is
    /// for a caller that only has text; a save that has the editor does not
    /// use it. `omissions` mark cut scenes the model still holds as body.
    public static func encode(
        _ screenplay: EDraftEngine.Screenplay, as type: UTType, origin: String? = nil, omissions: OmissionSpans? = nil
    ) throws -> Data {
        try encode(screenplay, as: type, origin: origin, omissions: omissions, alreadyApplied: false)
    }

    private static func encode(
        _ screenplay: EDraftEngine.Screenplay,
        as type: UTType,
        origin: String?,
        omissions: OmissionSpans?,
        alreadyApplied: Bool
    ) throws -> Data {
        guard type.conforms(to: .finalDraftScreenplay) else {
            return try encode(Fountain.serialise(screenplay))
        }
        let script = alreadyApplied ? screenplay : Omissions.applying(omissions, to: screenplay)
        let notes = Fdx.NoteWriting(writer: NoteIdentity.signature)
        guard let origin else { return try encode(Fdx.write(script, options: Fdx.ExportOptions(notes: notes)).xml) }
        return try encode(Fdx.open(origin).rewrite(script, unedited: uneditedReading(of: origin), notes: notes))
    }

    /// The script as the editor first held it: the file carried through
    /// Fountain, exactly as `open` carries it, and read back.
    ///
    /// Fountain cannot carry everything a Final Draft file does — production
    /// tags, revision marks, an emphasised heading as a heading — so without
    /// this every such paragraph looked edited to the save and was rewritten:
    /// measured on a file Final Draft wrote, a save that changed nothing lost
    /// 400 of its 407 tags. With it, a paragraph that comes back as it was read
    /// is written as its original bytes. Deterministic from the origin, and
    /// measured: an unedited document publishes exactly this reading.
    private static func uneditedReading(of origin: String) -> EDraftEngine.Screenplay? {
        try? Fountain.parse(Fountain.serialise(shouted(Fdx.parse(origin).script)), emphasis: .runs)
    }

    /// A new screenplay is a blank page, not a pre-written ritual: title
    /// page plus nothing. FADE IN: is the writer's to type, not ours.
    public static let blankSource = """
    Title: Untitled Screenplay
    Credit: written by


    """
}
