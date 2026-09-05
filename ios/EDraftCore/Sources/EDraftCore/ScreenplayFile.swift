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
        let text = try decode(data)
        guard type.conforms(to: .finalDraftScreenplay) else { return text }
        return Fountain.serialise(Fdx.parse(text).script)
    }

    /// The typed write boundary: an .fdx opened in place writes back as
    /// FDX — never Fountain source wearing an .fdx name, which Final Draft
    /// would refuse to open.
    public static func encode(_ source: String, as type: UTType) throws -> Data {
        if type.conforms(to: .finalDraftScreenplay) {
            let screenplay = try Fountain.parse(source)
            return try encode(Fdx.writeXml(screenplay))
        }
        return try encode(source)
    }

    /// A new screenplay is a blank page, not a pre-written ritual: title
    /// page plus nothing. FADE IN: is the writer's to type, not ours.
    public static let blankSource = """
    Title: Untitled Screenplay
    Credit: written by


    """
}
