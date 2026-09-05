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

    public init(source: String = ScreenplayFile.blankSource) {
        self.source = source
    }

    public init(configuration: ReadConfiguration) throws {
        self.source = try ScreenplayFile.decode(
            configuration.file.regularFileContents,
            as: configuration.contentType
        )
    }

    public func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(
            regularFileWithContents: try ScreenplayFile.encode(source, as: configuration.contentType)
        )
    }
}
