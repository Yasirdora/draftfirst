import EDraftEngine
import UniformTypeIdentifiers
import XCTest
@testable import EDraftCore

/// Omitting and restoring a scene — RFC-DRAFT-PRODUCTION §7.3, IL-0087.
///
/// Until this, a writer could not omit a scene: the app only showed the
/// omissions that arrived inside a Final Draft file. These are the model's
/// side of the command — the card and the span it records, the restore that
/// puts back exactly what was there, undo, where the command is offered, and
/// the save that keeps what the writer decided.
@MainActor
final class OmitSceneCommandTests: XCTestCase {

    // MARK: - Fixtures

    /// Three numbered scenes, all live, with an act marker in front of the
    /// second — an aside anchored to its heading.
    private func live() -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        <Paragraph Type="Action"><Text>FADE IN:</Text></Paragraph>
        <Paragraph Number="20" Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
        <Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>
        <Paragraph Type="Outline 1"><Text>ACT TWO</Text></Paragraph>
        <Paragraph Number="21" Type="Scene Heading"><Text TagNumber="317">EXT. THE YARD - DUSK</Text></Paragraph>
        <Paragraph Type="Action"><Text>Mara waits.</Text></Paragraph>
        <Paragraph Type="Character"><Text>MARA</Text></Paragraph>
        <Paragraph Type="Dialogue"><Text>Not yet.</Text></Paragraph>
        <Paragraph Number="22" Type="Scene Heading"><Text>INT. THE HALL - DAY</Text></Paragraph>
        <Paragraph Type="Action"><Text>She waits.</Text></Paragraph>
        </Content>
        </FinalDraft>
        """.utf8)
    }

    /// The yard as Final Draft omits it: the number on the card, the scene
    /// nested inside it with none of its own.
    private func omittedByFinalDraft() -> Data {
        Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        <Paragraph Number="20" Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
        <Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>
        <Paragraph Number="21" Type="Scene Heading">
        <Text>OMITTED</Text>
        <OmittedScene>
        <Paragraph Type="Scene Heading"><SceneProperties Length="2/8" Page="1"></SceneProperties><Text TagNumber="317">EXT. THE YARD - DUSK</Text></Paragraph>
        <Paragraph Type="Action"><Text>Mara waits.</Text></Paragraph>
        </OmittedScene>
        </Paragraph>
        <Paragraph Number="22" Type="Scene Heading"><Text>INT. THE HALL - DAY</Text></Paragraph>
        <Paragraph Type="Action"><Text>She waits.</Text></Paragraph>
        </Content>
        </FinalDraft>
        """.utf8)
    }

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EDraftCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // EDraftCore/
            .deletingLastPathComponent()   // apple/
            .appendingPathComponent("eDraftEngine/Fixtures/\(name)"))
    }

    /// A document as the Mac app opens one: its source, and the origin it
    /// keeps for the save.
    private struct Opened {
        let editor: EditorState
        let origin: String?
        var source: String
    }

    private func opened(_ data: Data, as type: UTType = .finalDraftScreenplay) throws -> Opened {
        let file = try ScreenplayFile.open(data, as: type)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        return Opened(editor: editor, origin: file.origin, source: file.source)
    }

    /// Saves the way `ScreenplayDocument` does: the published source, the
    /// origin, and the omissions published with that source.
    private func saved(_ document: Opened) throws -> Data {
        var source = document.source
        document.editor.onSourceChange = { source = $0 }
        document.editor.flushPendingWork()
        return try ScreenplayFile.encode(
            source, as: .finalDraftScreenplay, origin: document.origin,
            omissions: document.editor.publishedOmissions
        )
    }

    private func heading(_ editor: EditorState, _ text: String) throws -> ScriptElement {
        try XCTUnwrap(editor.screenplay.elements.first { $0.type == .scene && $0.text == text })
    }

    private func row(_ editor: EditorState, _ id: UUID) throws -> SceneRow {
        try XCTUnwrap(editor.scenes.first { $0.id == id })
    }

    private func texts(_ editor: EditorState) -> [String] {
        editor.screenplay.elements.map { "\(editor.isOmitted($0) ? "omitted" : "live") \($0.text)" }
    }

    // MARK: - Omit

    func testOmitPutsACardInFrontOfTheSceneAndCutsTheScene() throws {
        let editor = try opened(live()).editor
        let yard = try heading(editor, "EXT. THE YARD - DUSK")
        let scene = try XCTUnwrap(editor.omitScene(yard.id))

        XCTAssertEqual(texts(editor), [
            "live FADE IN:",
            "live INT. KITCHEN - NIGHT",
            "live The kettle screams.",
            "live OMITTED",
            "omitted EXT. THE YARD - DUSK",
            "omitted Mara waits.",
            "omitted MARA",
            "omitted Not yet.",
            "live INT. THE HALL - DAY",
            "live She waits."
        ])
        let card = editor.screenplay.elements[3]
        XCTAssertEqual(card.type, .scene)
        XCTAssertEqual(card.sceneNumber, "21", "the card carries the scene's number")
        XCTAssertEqual(scene.card, card.draftID)
        XCTAssertEqual(scene.sceneNumber, "21")
        XCTAssertEqual(scene.key, yard.draftID, "the span starts at the scene's heading")
        XCTAssertEqual(editor.omittedScenes.scenes, [scene], "real model state, not a view")
        XCTAssertEqual(editor.activeElementID, card.id, "the caret lands on the card")
    }

    func testTheSceneIsTheHeadingThroughItsLastLineBeforeTheNextHeading() throws {
        let editor = try opened(live()).editor
        let kitchen = try heading(editor, "INT. KITCHEN - NIGHT")
        let scene = try XCTUnwrap(editor.omitScene(kitchen.id))
        let omitted = editor.screenplay.elements.filter(editor.isOmitted).map(\.text)
        XCTAssertEqual(omitted, ["INT. KITCHEN - NIGHT", "The kettle screams."])
        /* The act marker stands in front of the next heading — it belongs to
           what follows, and is not cut with the scene before it. */
        let act = try XCTUnwrap(editor.asides.first { $0.text == "ACT TWO" })
        XCTAssertFalse(scene.elements.contains(try XCTUnwrap(act.element.draftID)))
    }

    func testAnAsideInFrontOfTheHeadingMovesToTheCard() throws {
        let editor = try opened(live()).editor
        let yard = try heading(editor, "EXT. THE YARD - DUSK")
        XCTAssertEqual(editor.asides.first { $0.text == "ACT TWO" }?.anchor, yard.id)
        editor.omitScene(yard.id)
        let card = editor.screenplay.elements[3]
        XCTAssertEqual(editor.asides.first { $0.text == "ACT TWO" }?.anchor, card.id,
                       "the act marker still stands where it stood: in front of the scene's place")
    }

    // MARK: - Restore

    func testRestoreReturnsTheDocumentExactlyAsItWas() throws {
        let document = try opened(live())
        let editor = document.editor
        let before = editor.screenplay.elements
        let asidesBefore = editor.asides
        var sourceBefore = ""
        editor.onSourceChange = { sourceBefore = $0 }
        editor.flushPendingWork()

        let yard = try heading(editor, "EXT. THE YARD - DUSK")
        let scene = try XCTUnwrap(editor.omitScene(yard.id))
        let card = try XCTUnwrap(editor.screenplay.elements.first { $0.draftID == scene.card })
        XCTAssertEqual(editor.restoreScene(card.id), scene)

        XCTAssertEqual(editor.screenplay.elements, before, "every line, identity and number as it was")
        XCTAssertEqual(editor.asides, asidesBefore)
        XCTAssertTrue(editor.omittedScenes.isEmpty)
        var sourceAfter = ""
        editor.onSourceChange = { sourceAfter = $0 }
        editor.flushPendingWork()
        XCTAssertEqual(sourceAfter, sourceBefore, "byte for byte")
        XCTAssertEqual(editor.activeElementID, yard.id, "the caret lands on the restored heading")
    }

    func testRestoringFinalDraftsOmissionGivesTheHeadingBackItsNumber() throws {
        let editor = try opened(omittedByFinalDraft()).editor
        let card = try XCTUnwrap(editor.screenplay.elements.first { editor.omittedScenes.isCard($0) })
        editor.restoreScene(card.id)
        let yard = try heading(editor, "EXT. THE YARD - DUSK")
        XCTAssertEqual(yard.sceneNumber, "21", "Final Draft keeps the number on the card; it comes back with the scene")
        XCTAssertFalse(editor.isOmitted(yard))
        XCTAssertEqual(editor.scenes.map(\.label), ["20", "21", "22"])
    }

    // MARK: - Undo

    func testUndoReversesAnOmitAndRedoRepeatsIt() throws {
        let editor = try opened(live()).editor
        let before = editor.screenplay.elements
        let yard = try heading(editor, "EXT. THE YARD - DUSK")
        let scene = try XCTUnwrap(editor.omitScene(yard.id))
        let omitted = editor.screenplay.elements

        editor.undo()
        XCTAssertEqual(editor.screenplay.elements, before)
        XCTAssertTrue(editor.omittedScenes.isEmpty, "the omission goes with the card")

        editor.redo()
        XCTAssertEqual(editor.screenplay.elements, omitted)
        XCTAssertEqual(editor.omittedScenes.scenes, [scene], "the same card, the same span")
    }

    func testUndoReversesARestore() throws {
        let editor = try opened(omittedByFinalDraft()).editor
        let omitted = editor.omittedScenes
        let before = editor.screenplay.elements
        let card = try XCTUnwrap(editor.screenplay.elements.first { editor.omittedScenes.isCard($0) })
        editor.restoreScene(card.id)
        editor.undo()
        XCTAssertEqual(editor.screenplay.elements, before)
        XCTAssertEqual(editor.omittedScenes, omitted)
    }

    func testTheUndoStateCarriesTheOmissionsWithTheLines() throws {
        let editor = try opened(live()).editor
        let lines = editor.screenplay.elements
        let state = editor.omissionState
        let yard = try heading(editor, "EXT. THE YARD - DUSK")
        editor.omitScene(yard.id, recordsUndo: false)
        XCTAssertFalse(editor.canUndo, "the surface owns this undo")
        XCTAssertTrue(editor.replaceAllElements(lines, restoring: state, activeID: yard.id, offset: 0))
        XCTAssertEqual(editor.screenplay.elements, lines)
        XCTAssertEqual(editor.omissionState, state)
    }

    // MARK: - Where the command is offered

    func testTheCommandFollowsTheCaret() throws {
        let editor = try opened(live()).editor
        let elements = editor.screenplay.elements
        editor.jump(to: elements[0].id) // FADE IN:, above the first heading
        XCTAssertNil(editor.caretSceneAction, "no scene above the first heading")

        let yard = try heading(editor, "EXT. THE YARD - DUSK")
        let dialogue = try XCTUnwrap(elements.first { $0.text == "Not yet." })
        editor.jump(to: dialogue.id)
        XCTAssertEqual(editor.caretSceneAction?.action, .omit)
        XCTAssertEqual(editor.caretSceneAction?.sceneID, yard.id, "anywhere in the scene, it is this scene")

        editor.omitScene(yard.id)
        XCTAssertEqual(editor.caretSceneAction?.action, .restore, "on the card, the command restores")

        let hall = try heading(editor, "INT. THE HALL - DAY")
        editor.jump(to: hall.id)
        XCTAssertEqual(editor.caretSceneAction?.action, .omit)
        XCTAssertEqual(editor.caretSceneAction?.sceneID, hall.id)
    }

    func testTheRowsOfferWhatEachSceneAllows() throws {
        let editor = try opened(live()).editor
        let yard = try heading(editor, "EXT. THE YARD - DUSK")
        XCTAssertEqual(editor.sceneActions(for: try row(editor, yard.id)), [.omit])
        editor.omitScene(yard.id)
        let card = editor.screenplay.elements[3]
        XCTAssertEqual(editor.sceneActions(for: try row(editor, card.id)), [.restore])
        XCTAssertNil(editor.scenes.first { $0.id == yard.id }, "the cut heading is not a row of its own")
    }

    func testAnOmittedCardTypedByHandIsNotASceneToOmit() throws {
        let editor = try opened(Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6"><Content>
        <Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
        <Paragraph Number="7" Type="Scene Heading"><Text>OMITTED</Text></Paragraph>
        </Content></FinalDraft>
        """.utf8)).editor
        let card = try heading(editor, "OMITTED")
        XCTAssertEqual(editor.sceneActions(for: try row(editor, card.id)), [])
        XCTAssertNil(editor.omitScene(card.id))
    }

    // MARK: - A document that could not keep it

    func testAFountainDocumentDoesNotOfferOmit() throws {
        let document = try opened(Data("INT. KITCHEN - NIGHT\n\nThe kettle screams.\n\nEXT. THE YARD - DUSK\n\nMara waits.\n".utf8),
                                  as: .plainText)
        let editor = document.editor
        XCTAssertFalse(editor.keepsOmissions)
        XCTAssertEqual(editor.omissionUnavailableReason, "Omissions are kept in Final Draft (.fdx) files.")
        let yard = try heading(editor, "EXT. THE YARD - DUSK")
        editor.jump(to: yard.id)
        XCTAssertNil(editor.caretSceneAction)
        XCTAssertEqual(editor.sceneActions(for: try row(editor, yard.id)), [])
        XCTAssertNil(editor.omitScene(yard.id), "a cut that would not survive the save is not made")
        XCTAssertEqual(editor.screenplay.elements.count, 4)
    }

    func testAFinalDraftDocumentSaysNothingIsInTheWay() throws {
        let editor = try opened(live()).editor
        XCTAssertTrue(editor.keepsOmissions)
        XCTAssertNil(editor.omissionUnavailableReason)
    }

    // MARK: - Pages

    func testTheCutBodyIsOnNoPage() throws {
        let editor = try opened(live()).editor
        let yard = try heading(editor, "EXT. THE YARD - DUSK")
        let scene = try XCTUnwrap(editor.omitScene(yard.id))
        let paginable = Omissions.paginable(
            editor.screenplay.engineModel, document: editor.screenplay.elements, omitted: editor.omittedScenes
        )
        XCTAssertEqual(paginable.model.elements.map(\.text), [
            "FADE IN:", "INT. KITCHEN - NIGHT", "The kettle screams.", "OMITTED",
            "INT. THE HALL - DAY", "She waits."
        ])
        XCTAssertGreaterThan(scene.pages, 0, "the pill measures what was cut")
    }

    func testThePageCountRetellsItself() throws {
        /* A scene long enough to take a page of its own. */
        let lines = (1...60).map { "<Paragraph Type=\"Action\"><Text>Line \($0) of the long scene.</Text></Paragraph>" }
        let editor = try opened(Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6"><Content>
        <Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
        <Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>
        <Paragraph Type="Scene Heading"><Text>EXT. THE YARD - DUSK</Text></Paragraph>
        \(lines.joined(separator: "\n"))
        <Paragraph Type="Scene Heading"><Text>INT. THE HALL - DAY</Text></Paragraph>
        <Paragraph Type="Action"><Text>She waits.</Text></Paragraph>
        </Content></FinalDraft>
        """.utf8)).editor
        let pages = { () -> Int in
            let paginable = Omissions.paginable(
                editor.screenplay.engineModel, document: editor.screenplay.elements, omitted: editor.omittedScenes
            )
            return (try? Paginator.paginate(paginable.model, linesPerPage: PageFormat.current.linesPerPage).count) ?? 0
        }
        let whole = pages()
        let yard = try heading(editor, "EXT. THE YARD - DUSK")
        editor.omitScene(yard.id)
        XCTAssertLessThan(pages(), whole, "the cut scene's page leaves the count")
        let card = try XCTUnwrap(editor.screenplay.elements.first { editor.omittedScenes.isCard($0) })
        editor.restoreScene(card.id)
        XCTAssertEqual(pages(), whole)
    }

    // MARK: - What VoiceOver hears

    func testTheResultIsAnnouncedInTheCardsOwnWords() throws {
        let editor = try opened(live()).editor
        let yard = try heading(editor, "EXT. THE YARD - DUSK")
        let scene = try XCTUnwrap(editor.omitScene(yard.id))
        let omitted = scene.announcement(for: .omit)
        XCTAssertTrue(omitted.hasPrefix("Scene 21 omitted, "), omitted)
        XCTAssertTrue(omitted.hasSuffix(" pages cut"), omitted)
        XCTAssertEqual(scene.announcement(for: .restore), "Scene 21 restored")
        XCTAssertEqual(SceneAction.omit.title, "Omit Scene")
        XCTAssertEqual(SceneAction.restore.title, "Restore Scene")
    }

    // MARK: - Save, and open again

    func testAnOmitSurvivesSaveAndReopen() throws {
        let document = try opened(live())
        let yard = try heading(document.editor, "EXT. THE YARD - DUSK")
        document.editor.omitScene(yard.id)
        let data = try saved(document)
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssertEqual(xml.components(separatedBy: "<OmittedScene>").count - 1, 1)
        XCTAssertTrue(xml.contains("TagNumber=\"317\""), "the omitted heading keeps its tag")

        let reopened = try opened(data).editor
        XCTAssertEqual(texts(reopened), texts(document.editor), "the same lines, the same scene cut")
        XCTAssertEqual(reopened.omittedScenes.scenes.count, 1)
        XCTAssertEqual(reopened.omittedScenes.scenes.first?.sceneNumber, "21")
        XCTAssertEqual(reopened.scenes.map(\.label), ["20", "21", "22"])
        XCTAssertEqual(reopened.scenes.map(\.omitted), [false, true, false])
    }

    func testARestoreSurvivesSaveAndReopen() throws {
        let document = try opened(omittedByFinalDraft())
        let card = try XCTUnwrap(document.editor.screenplay.elements.first { document.editor.omittedScenes.isCard($0) })
        document.editor.restoreScene(card.id)
        let data = try saved(document)
        let xml = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(xml.contains("<OmittedScene"), "not re-omitted by the save")
        XCTAssertTrue(xml.contains("TagNumber=\"317\""))

        let reopened = try opened(data).editor
        XCTAssertTrue(reopened.omittedScenes.isEmpty, "the scene is whole")
        XCTAssertEqual(texts(reopened), texts(document.editor))
        XCTAssertEqual(reopened.scenes.map(\.label), ["20", "21", "22"])
    }

    func testAnOrdinaryEditSavesExactlyAsBefore() throws {
        let document = try opened(omittedByFinalDraft())
        var elements = document.editor.screenplay.elements
        let last = elements.count - 1
        elements[last].text = "She waits. Then she goes."
        document.editor.replaceAllElements(elements, activeID: elements[last].id, offset: 0, structural: true)
        XCTAssertNil(document.editor.publishedOmissions, "the file's structure still decides")
        let xml = String(decoding: try saved(document), as: UTF8.self)
        XCTAssertEqual(xml.components(separatedBy: "<OmittedScene>").count - 1, 1)
    }

    func testOmitThenUndoSavesTheFileAsItWas() throws {
        let data = try fixture("finaldraft-sample02.fdx")
        let document = try opened(data)
        let editor = document.editor
        let live = try XCTUnwrap(editor.scenes.first { !$0.omitted && editor.sceneActions(for: $0) == [.omit] })
        editor.omitScene(live.id)
        editor.undo()
        XCTAssertNotNil(editor.publishedOmissions, "said explicitly now")
        XCTAssertEqual(try saved(document), data, "Final Draft's own file, byte for byte")
    }

    /// The measured before/after on a file Final Draft wrote: omit a live
    /// scene → save → reopen; restore Final Draft's own → save → reopen.
    func testTheRealFileRoundTripsBothWays() throws {
        let data = try fixture("finaldraft-sample02.fdx")
        let original = String(decoding: data, as: UTF8.self)
        let tags = original.components(separatedBy: "TagNumber=").count - 1

        // Omit a live scene.
        let first = try opened(data)
        let live = try XCTUnwrap(first.editor.scenes.last { !$0.omitted && first.editor.sceneActions(for: $0) == [.omit] })
        first.editor.omitScene(live.id)
        let omittedData = try saved(first)
        let omittedXML = String(decoding: omittedData, as: UTF8.self)
        XCTAssertEqual(omittedXML.components(separatedBy: "<OmittedScene>").count - 1, 2)
        XCTAssertEqual(omittedXML.components(separatedBy: "TagNumber=").count - 1, tags, "no tag lost")
        let second = try opened(omittedData)
        XCTAssertEqual(second.editor.omittedScenes.scenes.count, 2, "the omission is there after reopen")
        XCTAssertEqual(texts(second.editor), texts(first.editor))

        // Restore Final Draft's own.
        let card = try XCTUnwrap(second.editor.screenplay.elements.first { second.editor.omittedScenes.isCard($0) })
        second.editor.restoreScene(card.id)
        let restoredData = try saved(second)
        let restoredXML = String(decoding: restoredData, as: UTF8.self)
        XCTAssertEqual(restoredXML.components(separatedBy: "<OmittedScene>").count - 1, 1)
        XCTAssertEqual(restoredXML.components(separatedBy: "TagNumber=").count - 1, tags)
        let third = try opened(restoredData)
        XCTAssertEqual(third.editor.omittedScenes.scenes.count, 1, "the restored scene is whole")
        XCTAssertEqual(texts(third.editor), texts(second.editor))
    }
}
