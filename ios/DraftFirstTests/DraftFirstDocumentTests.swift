import DraftFirstEngine
import PDFKit
import XCTest
import UniformTypeIdentifiers
@testable import DraftFirst

/// The document layer's data-loss guards: every type the app opens must be
/// savable, and the byte-level encode/decode path must round-trip exactly.
final class DraftFirstDocumentTests: XCTestCase {

    /// The §2.5 regression pin: a .txt opened in place, edited for an hour,
    /// must never turn out to be a read-only trap.
    func testEveryReadableTypeIsWritable() {
        for type in DraftFirstDocument.readableContentTypes {
            XCTAssertTrue(
                DraftFirstDocument.writableContentTypes.contains(type),
                "\(type.identifier) is readable but not writable"
            )
        }
    }

    func testEncodeDecodeRoundTripsExactly() throws {
        let source = """
        Title: The Last Light
        Credit: written by

        FADE IN:

        INT. LAB - NIGHT

        MARA
        (whispering)
        We made it.

        """
        let decoded = try DraftFirstDocument.decode(try DraftFirstDocument.encode(source))
        XCTAssertEqual(decoded, source)
    }

    func testDecodeRejectsNonUTF8() {
        let latin1 = Data([0xE9, 0x20, 0x62, 0x79, 0x74, 0x65, 0x73]) // "é" in Latin-1
        XCTAssertThrowsError(try DraftFirstDocument.decode(latin1))
    }

    /// A brand-new document opens as a title page and one empty Action —
    /// a truly blank page — with the title already readable from the title
    /// page for the document browser.
    @MainActor
    func testBlankDocumentParsesToOpeningState() throws {
        let editor = EditorState(source: try DraftFirstDocument.decode(
            DraftFirstDocument().source.data(using: .utf8)
        ))
        XCTAssertEqual(editor.screenplay.elements.count, 1)
        // One empty element, and it is a scene heading: a screenplay opens on
        // a slug, so the caret starts where the writing starts and the
        // keyboard comes up in capitals.
        XCTAssertEqual(editor.screenplay.elements.first?.type, .scene)
        XCTAssertEqual(editor.screenplay.elements.first?.text, "")
        XCTAssertEqual(editor.screenplay.title, "Untitled Screenplay")
    }

    /// A screenplay made a moment ago and not yet written to is the one the
    /// writer has just asked for, and it opens ready to write.
    @MainActor
    func testAScreenplayJustMadeOpensForWriting() throws {
        let url = try Self.makeTemporaryScreenplay()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(DocumentArrival.isNewlyCreated(at: url))
    }

    /// Coming back to it is a return, however little is in it: the session
    /// remembers what it has already opened.
    @MainActor
    func testComingBackToTheSameScreenplayReads() throws {
        let url = try Self.makeTemporaryScreenplay()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(DocumentArrival.isNewlyCreated(at: url))
        XCTAssertFalse(DocumentArrival.isNewlyCreated(at: url), "the second arrival is a return")
    }

    /// A screenplay with writing in it is one to read, however recently it
    /// was started.
    @MainActor
    func testAScreenplayWrittenToSinceItWasMadeReads() throws {
        let url = try Self.makeTemporaryScreenplay()
        defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(30)], ofItemAtPath: url.path
        )
        XCTAssertFalse(DocumentArrival.isNewlyCreated(at: url))
    }

    /// Nothing to ask of a screenplay with no file behind it yet.
    @MainActor
    func testNoFileReads() {
        XCTAssertFalse(DocumentArrival.isNewlyCreated(at: nil))
    }

    private static func makeTemporaryScreenplay() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).draft")
        try Data("Title: Untitled Screenplay\n\n".utf8).write(to: url)
        return url
    }
}
