import EDraftEngine
import UniformTypeIdentifiers
import XCTest
@testable import EDraftCore

/// A reload keeps the page the page — the external-reload tear of 2026-09-23.
///
/// The owner saved a script in Final Draft while it was open here. The open
/// had lifted its notes, sections and synopses off the page (`ScriptAsides`);
/// the reload put every one of them back on it, beside the copies it still
/// held. The page then laid lines the paginator never counts — a page longer
/// than its paper — and the next save wrote each aside twice. With the page
/// forty lines longer than the file, the file's cut scene could no longer be
/// placed, and it came back live.
///
/// The same reload serves the iPhone's iCloud delivery (`EditorView`), so
/// this is the document's rule, not the Mac's.
@MainActor
final class ExternalSourceAsidesTests: XCTestCase {

    /// A script with one of each kind that does not print.
    private let source = """
    # ACT ONE

    = Mara learns the kettle is a signal.

    INT. KITCHEN - NIGHT

    [[Same kitchen as the pilot?]]

    The kettle screams.

    MARA
    Not again.
    """

    /// What the editor would write to the file now.
    private func published(_ editor: EditorState) -> String {
        var written = ""
        editor.onSourceChange = { written = $0 }
        editor.flushPendingWork()
        return written
    }

    private func assertThePageIsOnlyWhatPrints(
        _ editor: EditorState, file: StaticString = #filePath, line: UInt = #line
    ) {
        let offPage = editor.screenplay.elements.filter { !$0.type.isPrinting }.map(\.text)
        XCTAssertEqual(offPage, [], "a reload put asides on the page", file: file, line: line)
    }

    func testAnUnchangedReloadLeavesTheAsidesBesideThePage() {
        let editor = EditorState(source: source)
        let before = published(editor)
        let asides = editor.asides.map(\.text)
        XCTAssertEqual(asides.count, 3)

        editor.applyExternalSource(source)

        assertThePageIsOnlyWhatPrints(editor)
        XCTAssertEqual(editor.asides.map(\.text), asides, "the asides are the file's, once each")
        XCTAssertEqual(published(editor), before, "the next save writes what the file holds, nothing twice")
    }

    /// Aligned over the whole document, as the lines are: a note that is
    /// still in the file is still the same note.
    func testANoteKeepsItsIdentityThroughAReload() throws {
        let editor = EditorState(source: source)
        let note = try XCTUnwrap(editor.notes.first)

        editor.applyExternalSource(source.replacingOccurrences(of: "Not again.", with: "Not again. Not tonight."))

        XCTAssertEqual(editor.notes.map(\.id), [note.id])
        XCTAssertEqual(editor.notes.first?.anchor, note.anchor, "it is still in front of the same line")
    }

    /// The file is the truth for what sits beside the page too: a note added
    /// elsewhere arrives, once, and one removed there is gone.
    func testTheAsidesComeFromTheChangedFile() {
        let editor = EditorState(source: source)
        let changed = source
            .replacingOccurrences(of: "[[Same kitchen as the pilot?]]\n\n", with: "")
            .replacingOccurrences(of: "MARA\nNot again.", with: "[[Louder?]]\n\nMARA\nNot again.")

        editor.applyExternalSource(changed)

        assertThePageIsOnlyWhatPrints(editor)
        XCTAssertEqual(editor.notes.map(\.text), ["Louder?"])
        XCTAssertEqual(editor.asides.filter { $0.kind != .note }.count, 2, "the outline is kept")
    }

    /// One undo takes the reload back — the lines and what sits beside them.
    func testUndoTakesBackTheAsidesWithTheLines() {
        let editor = EditorState(source: source)
        let before = published(editor)

        editor.applyExternalSource(source.replacingOccurrences(of: "Same kitchen as the pilot?", with: "Cut this?"))
        editor.undo()

        assertThePageIsOnlyWhatPrints(editor)
        XCTAssertEqual(editor.notes.map(\.text), ["Same kitchen as the pilot?"])
        XCTAssertEqual(published(editor), before)
    }

    // MARK: - Final Draft saves the file while it is open here

    private func sample02() throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EDraftCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // EDraftCore/
            .deletingLastPathComponent()   // apple/
            .appendingPathComponent("eDraftEngine/Fixtures/finaldraft-sample02.fdx"))
    }

    /// What `ScreenplayDocument.read(from:ofType:)` does, at open and again
    /// when the file changes under an open window.
    func testAFinalDraftSaveKeepsItsCutSceneAndWritesNothingTwice() throws {
        let file = try ScreenplayFile.open(try sample02(), as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let before = published(editor)
        let asides = editor.asides.count
        XCTAssertEqual(editor.omittedScenes.scenes.count, 1)

        editor.applyExternalSource(file.source)
        editor.attachImportedNotes(from: file.origin)

        assertThePageIsOnlyWhatPrints(editor)
        XCTAssertEqual(editor.asides.count, asides)
        XCTAssertEqual(editor.omittedScenes.scenes.count, 1, "the file's cut scene is still placed")
        XCTAssertEqual(published(editor), before, "the next save writes what the file holds, nothing twice")
    }
}
