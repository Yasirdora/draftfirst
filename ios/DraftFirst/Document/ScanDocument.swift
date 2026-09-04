import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// A scanned document, opened for reading.
///
/// Writers arrive with paper: a printed draft covered in a director's notes, a
/// contract, a page of research. Those live alongside the screenplay they
/// belong to, and the browser the app already opens with is the natural place
/// to keep them — declaring the type is all it takes for them to appear there,
/// with no second library to build or keep in sync.
///
/// Read-only by design. A scan is a record of something that happened on paper;
/// editing it would make it a different kind of object, and the writable types
/// are deliberately empty so the system never offers to save changes that
/// cannot be meaningful.
struct ScanDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.pdf] }
    static var writableContentTypes: [UTType] { [] }

    /// The file's bytes, held as read. Scans produced by the scanner carry an
    /// invisible text layer, which is what makes their words selectable here
    /// without any recognition being run again.
    let data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    /// Every word the scan carries, read from its text layer.
    ///
    /// Recognition already happened when the scan was made; this only reads
    /// what was written. Doing it lazily keeps opening a large scan as fast as
    /// opening a small one.
    var text: String {
        guard let pdf = PDFDocument(data: data) else { return "" }
        return (0..<pdf.pageCount)
            .compactMap { pdf.page(at: $0)?.string }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        data = contents
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        // Unreachable while `writableContentTypes` is empty; throwing rather
        // than writing keeps that guarantee true if the list ever changes.
        throw CocoaError(.fileWriteNoPermission)
    }
}
