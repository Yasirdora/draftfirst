import EDraftEngine
import UniformTypeIdentifiers
import XCTest
@testable import EDraftCore

/// An omitted scene's body appears in no output.
///
/// The page keeps a cut scene's lines and only the screen collapses them,
/// so every output that was handed the page printed the body. The card
/// follows each format: Plain Text is the card as its own line, Fountain
/// is a heading with its number, Final Draft nests the body in OmittedScene.
@MainActor
final class ScreenplayOutputOmissionTests: XCTestCase {

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

    private func squeezed(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func cutBody(_ editor: EditorState) -> [String] {
        let live = editor.screenplay.elements.filter { !editor.isOmitted($0) }.map { squeezed($0.text) }
        return editor.screenplay.elements
            .filter { editor.isOmitted($0) && $0.type.isPrinting }
            .map { squeezed($0.text) }
            .filter { line in line.count > 6 && !live.contains { $0.contains(line) } }
    }

    private func leaked(_ body: [String], in text: String) -> [String] {
        let output = squeezed(text)
        return body.filter { output.contains($0) }
    }

    private func card(_ editor: EditorState) throws -> ScriptElement {
        try XCTUnwrap(editor.screenplay.elements.first { editor.omittedScenes.isCard($0) })
    }

    func testThePrintedScriptIsThePageWithTheCardAndNoBody() throws {
        for name in fixtures {
            let (editor, origin) = try opened(name)
            let printed = editor.output(origin: origin).printed
            let body = Set(cutBody(editor))
            XCTAssertFalse(body.isEmpty, name)
            XCTAssertEqual(printed.elements.filter { body.contains(squeezed($0.text)) }.map(\.text), [],
                           "\(name): the cut scene's body is in the printed script")
            let cards = printed.elements.filter { editor.omittedScenes.isCard($0) }
            XCTAssertEqual(cards.map(\.text), [try card(editor).text], "\(name): the card prints")
            XCTAssertEqual(cards.first?.sceneNumber, "21", "\(name): the card carries its number")
            XCTAssertEqual(
                printed.elements.count,
                editor.screenplay.elements.filter { !editor.isOmitted($0) }.count,
                "\(name): everything else prints as the page holds it"
            )
        }
    }

    func testPlainTextCarriesTheCardAsFinalDraftDoesAndNoBody() throws {
        for name in fixtures {
            let (editor, origin) = try opened(name)
            let text = ScreenplayExporter.plainText(editor.output(origin: origin))
            XCTAssertEqual(leaked(cutBody(editor), in: text), [], "\(name): the body is in Plain Text")
            let words = try card(editor).text
            XCTAssertEqual(
                text.split(separator: "\n").filter { $0.trimmingCharacters(in: .whitespaces) == words }.count,
                1, "\(name): the card is one line of its own, without its number"
            )
        }
    }

    func testTheFountainExportCarriesTheCardAndNoBody() throws {
        for name in fixtures {
            let (editor, origin) = try opened(name)
            let fountain = ScreenplayExporter.fountainSource(editor.output(origin: origin))
            XCTAssertEqual(leaked(cutBody(editor), in: fountain), [], "\(name): the body is in the Fountain export")
            let reread = EditorState(source: fountain)
            let words = try card(editor).text
            let heading = reread.screenplay.elements.filter { $0.type == .scene && $0.text == words }
            XCTAssertEqual(heading.count, 1, "\(name): the card comes back as a heading")
            XCTAssertEqual(heading.first?.sceneNumber, "21", "\(name): with its number")
        }
    }

    func testTheFinalDraftExportKeepsTheBodyInsideItsOmittedScene() throws {
        for name in fixtures {
            let (editor, origin) = try opened(name)
            let data = try editor.output(origin: origin).finalDraft()
            let script = Fdx.parse(try XCTUnwrap(String(data: data, encoding: .utf8))).script
            let omissions = script.omissions ?? []
            XCTAssertEqual(omissions.count, 1, "\(name): one OmittedScene")
            let inside = Set(omissions.flatMap { Array($0.start..<$0.end) })
            let live = script.elements.indices.filter { !inside.contains($0) }
                .map { squeezed(script.elements[$0].text).uppercased() }
            let body = cutBody(editor).map { $0.uppercased() }
            XCTAssertEqual(body.filter { live.contains($0) }, [], "\(name): the body is live script in the export")
            let nested = inside.map { squeezed(script.elements[$0].text).uppercased() }
            XCTAssertEqual(body.filter { !nested.contains($0) }, [], "\(name): the body is kept under its card")
        }
    }

    func testASceneOmittedInEDraftLeavesEveryOutput() throws {
        let (editor, origin) = try opened("finaldraft-sample02.fdx")
        let scene = try XCTUnwrap(editor.scenes.last { editor.sceneActions(for: $0) == [.omit] && $0.elementIndex > 100 })
        let heading = editor.screenplay.elements[scene.elementIndex].id
        XCTAssertNotNil(editor.omitScene(scene.id))
        XCTAssertTrue(editor.screenplay.elements.contains { $0.id == heading && editor.isOmitted($0) },
                      "the omitted scene's heading is part of the cut")
        let body = cutBody(editor)
        XCTAssertFalse(body.isEmpty)
        let output = editor.output(origin: origin)
        XCTAssertEqual(leaked(body, in: ScreenplayExporter.plainText(output)), [], "Plain Text")
        XCTAssertEqual(leaked(body, in: ScreenplayExporter.fountainSource(output)), [], "Fountain")
        let script = Fdx.parse(try XCTUnwrap(String(data: try output.finalDraft(), encoding: .utf8))).script
        XCTAssertEqual(script.omissions?.count, 2, "Final Draft: the writer's omission is written")
    }

    func testAPlainScriptExportsAsItDidBefore() {
        let editor = EditorState(source: "INT. KITCHEN - NIGHT\n\nThe kettle screams.\n\nMARA\nNot again.")
        let output = editor.output(origin: nil)
        XCTAssertEqual(output.printed.elements, editor.screenplay.elements)
        XCTAssertEqual(output.fountain, ScreenplayExporter.fountainSource(editor.screenplay))
        XCTAssertEqual(ScreenplayExporter.plainText(output), ScreenplayExporter.plainText(editor.screenplay))
    }
}
