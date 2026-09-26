import EDraftEngine
import UniformTypeIdentifiers
import XCTest
@testable import EDraftCore

/// Nothing Final Draft wrote is lost through an export, and a highlight the
/// writer made survives the save the document performs.
@MainActor
final class ExportRoundTripTests: XCTestCase {

    private let fixtures = ["finaldraft-sample02.fdx", "finaldraft-acts.fdx"]

    private func opened(_ name: String) throws -> (EditorState, String) {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("eDraftEngine/Fixtures/\(name)"))
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        return (editor, try XCTUnwrap(file.origin))
    }

    private func outline(_ script: EDraftEngine.Screenplay) -> [String] {
        EDraftCore.Screenplay(engineModel: script).elements
            .filter { $0.type == .section || $0.type == .synopsis }
            .map { "\($0.type.rawValue)|\($0.depth ?? 0)|\($0.text)" }
    }

    func testExportFinalDraftWritesWhatSaveWrites() throws {
        for name in fixtures {
            let (editor, origin) = try opened(name)
            let exported = try editor.output(origin: origin).finalDraft()
            XCTAssertEqual(exported, try editor.savedFile(as: .finalDraftScreenplay, origin: origin), "\(name): the export is not Save's writer")
        }
    }

    func testExportFinalDraftKeepsEverythingFinalDraftWrote() throws {
        for name in fixtures {
            let (editor, origin) = try opened(name)
            let original = Fdx.parse(origin)
            let exported = Fdx.parse(try XCTUnwrap(String(data: try editor.output(origin: origin).finalDraft(), encoding: .utf8)))
            XCTAssertEqual(exported.scriptNotes.count, original.scriptNotes.count, "\(name): Final Draft's notes")
            XCTAssertEqual(exported.scriptNotes, original.scriptNotes, "\(name): each note as written — words, writer, place")
            XCTAssertEqual(outline(exported.script), outline(original.script), "\(name): sections and synopses")
            XCTAssertFalse(outline(original.script).isEmpty, "\(name): the fixture has an outline")
            XCTAssertEqual(exported.script.elements.map(\.text), original.script.elements.map(\.text), "\(name): every line")
            XCTAssertEqual(exported.script.elements.map(\.type), original.script.elements.map(\.type), "\(name): every kind")
            XCTAssertEqual(exported.script.omissions, original.script.omissions, "\(name): the omission")
            XCTAssertEqual(exported.script.titlePage, original.script.titlePage, "\(name): the title page")
        }
    }

    func testExportFountainKeepsTheOutlineAndEveryNote() throws {
        for name in fixtures {
            let (editor, origin) = try opened(name)
            let fountain = ScreenplayExporter.fountainSource(editor.output(origin: origin))
            let reread = EditorState(source: fountain)
            let before = editor.asides
                .filter { $0.kind != .note && !editor.omittedScenes.contains($0.element) }
                .map { "\($0.kind.rawValue)|\($0.depth ?? 0)|\($0.text)" }
            let after = reread.asides.filter { $0.kind != .note }.map { "\($0.kind.rawValue)|\($0.depth ?? 0)|\($0.text)" }
            XCTAssertFalse(before.isEmpty, "\(name): the fixture has an outline")
            XCTAssertEqual(after, before, "\(name): sections and synopses through Fountain")
            let notes = reread.notes.map(\.text)
            for note in editor.notes {
                XCTAssertTrue(notes.contains(note.text), "\(name): the writer's note \(note.text.prefix(20))")
            }
            for note in editor.importedNotes where !note.text.isEmpty {
                XCTAssertTrue(notes.contains { $0.hasSuffix(note.text) }, "\(name): Final Draft's note \(note.text.prefix(20))")
            }
            XCTAssertEqual(
                reread.notes.count, editor.notes.count + editor.importedNotes.filter { !$0.text.isEmpty }.count,
                "\(name): every note once"
            )
        }
    }

    /// The Mac document's `data(ofType:)` is `editor.savedFile`, and the
    /// reopen is `EditorState(opened:)`. At 175809d those calls were
    /// `ScreenplayFile.encode` of the published Fountain and
    /// `EditorState(source:)`, and this assertion failed: the highlight
    /// came back nil.
    func testAHighlightSurvivesAnFdxSaveThroughTheDocumentPath() throws {
        let editor = EditorState(source: "INT. KITCHEN - DAY\n\nShe waits.")
        var page = editor.screenplay
        let index = try XCTUnwrap(page.elements.lastIndex { $0.type == .action })
        page.elements[index].runs = [StyleRun(start: 0, end: 3, styles: [], highlight: .yellow)]
        editor.screenplay = page

        let saved = try editor.savedFile(as: .finalDraftScreenplay, origin: nil)
        let again = EditorState(opened: try ScreenplayFile.read(saved, as: .finalDraftScreenplay))
        let action = try XCTUnwrap(again.screenplay.elements.last { $0.type == .action })
        XCTAssertEqual(
            action.runs?.first?.highlight, .yellow,
            "the document's save and reopen dropped the highlight"
        )
    }
}
