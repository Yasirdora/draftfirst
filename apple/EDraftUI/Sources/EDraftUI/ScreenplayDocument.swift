import EDraftCore
import SwiftUI
import UniformTypeIdentifiers

/// The document, as SwiftUI understands one.
///
/// A thin wrapper: every decision about what may be read, what is written back
/// and how bytes become a screenplay belongs to `ScreenplayFile` in the core,
/// where both surfaces and the tests can reach it. What is left here is the
/// conformance itself — which is what hands a `DocumentGroup` its open, save
/// and iCloud panels, on a phone and on a Mac alike.
public struct EDraftDocument: FileDocument {
    public static var readableContentTypes: [UTType] {
        // Plain text covers the migration paths — paste-ready .txt and
        // .fountain files (the imported fountain UTI conforms to it). FDX is
        // the professional migration path: a Final Draft file opens in place.
        [.edraftScreenplay, .plainText, .finalDraftScreenplay]
    }

    public static var writableContentTypes: [UTType] {
        // Every readable type is writable: a screenplay's source IS plain
        // text (Fountain), and an .fdx opened in place writes back as FDX —
        // never a read-only trap that would strand an hour of work.
        [.edraftScreenplay, .plainText, .finalDraftScreenplay]
    }

    public var source: String

    /// The Final Draft file this document was opened from, when it was one.
    ///
    /// Carried so a save can edit it rather than rebuild it: a screenplay
    /// cannot hold revisions, locked pages, tags or the arc beats nested in a
    /// scene heading, and a writer who opens a locked shooting script, fixes a
    /// typo and saves must not lose them. Never written to disk itself — it is
    /// the file, remembered. See `ScreenplayFile.open` and `Fdx.Document`.
    public var origin: String?

    public init(source: String = ScreenplayFile.blankSource) {
        self.source = source
        self.origin = nil
    }

    public init(configuration: ReadConfiguration) throws {
        let opened = try ScreenplayFile.open(
            configuration.file.regularFileContents,
            as: configuration.contentType
        )
        self.source = opened.source
        self.origin = opened.origin
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(
            regularFileWithContents: try ScreenplayFile.encode(
                source, as: configuration.contentType, origin: origin
            )
        )
    }
}
