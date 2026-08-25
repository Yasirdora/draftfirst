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
        XCTAssertEqual(editor.screenplay.elements.first?.type, .action)
        XCTAssertEqual(editor.screenplay.elements.first?.text, "")
        XCTAssertEqual(editor.screenplay.title, "Untitled Screenplay")
    }
}

/// The round-trip contract behind "no lock-in, your file is yours": a
/// collaborator's Fountain file must survive open → edit → save untouched,
/// including structure the editor has no UI for yet (sections, synopses,
/// notes, dual dialogue, forced scene numbers).
final class RoundTripTests: XCTestCase {

    private typealias Shape = (type: ScreenplayKind, text: String, dual: Bool?, sceneNumber: String?, depth: Int?)

    @MainActor
    private func shapes(of source: String) -> [Shape] {
        EditorState(source: source).screenplay.elements.map {
            ($0.type, $0.text, $0.dual, $0.sceneNumber, $0.depth)
        }
    }

    @MainActor
    func testSectionDepthAndStructureSurviveRoundTrip() {
        let source = """
        # Act One

        ## Sequence B

        INT. LAB - NIGHT #42#

        = A quiet opening.

        [[a margin note]]

        MARA ^
        Overlapping.

        """
        let before = shapes(of: source)
        XCTAssertEqual(before.first(where: { $0.type == .section })?.depth, 1)
        XCTAssertEqual(before.filter { $0.type == .section }.map(\.depth), [1, 2])
        XCTAssertEqual(before.first(where: { $0.type == .scene })?.sceneNumber, "42")
        XCTAssertEqual(before.first(where: { $0.type == .character })?.dual, true)

        // Serialise through the app model (the debounced publish path), then
        // reparse: the structure must be identical — nothing flattened.
        let serialised = ScreenplayExporter.fountainSource(EditorState(source: source).screenplay)
        XCTAssertTrue(serialised.contains("# Act One"))
        XCTAssertTrue(serialised.contains("## Sequence B"))
        let after = shapes(of: serialised)
        XCTAssertEqual(after.map { "\($0.type)|\($0.text)|\($0.depth ?? 0)|\($0.dual ?? false)|\($0.sceneNumber ?? "")" },
                       before.map { "\($0.type)|\($0.text)|\($0.depth ?? 0)|\($0.dual ?? false)|\($0.sceneNumber ?? "")" })
    }

    /// Serialisation must converge: one normalisation pass, then stable
    /// output forever — no document drifts with every save.
    @MainActor
    func testSerialisationIsIdempotent() {
        let messy = "INT.  LAB - NIGHT\n\nSome action.  \n\nMARA\nHello.\n"
        let once = ScreenplayExporter.fountainSource(EditorState(source: messy).screenplay)
        let twice = ScreenplayExporter.fountainSource(EditorState(source: once).screenplay)
        XCTAssertEqual(once, twice)
    }
}

/// §2.6 — an external change (iCloud delivery, conflict resolution) must be
/// applied in place: the caret stays with its element, undo history is
/// untouched, and the sync never echoes back as a write.
final class ExternalSyncTests: XCTestCase {

    private let base = "FADE IN:\n\nINT. LAB - NIGHT\n\nSome action.\n"

    @MainActor
    private func makeEditor() throws -> EditorState {
        let editor = EditorState(source: base)
        let sceneID = try XCTUnwrap(editor.screenplay.elements.first { $0.type == .scene }?.id)
        editor.jump(to: sceneID)
        editor.selectionOffset = 5
        return editor
    }

    @MainActor
    func testExternalChangeKeepsCaretOnSurvivingElement() throws {
        let editor = try makeEditor()
        let sceneID = try XCTUnwrap(editor.activeElementID)
        editor.applyExternalSource("FADE IN:\n\nINT. LAB - NIGHT\n\nThe action changed.\n")
        XCTAssertEqual(editor.activeElementID, sceneID)
        XCTAssertEqual(editor.selectionOffset, 5)
        XCTAssertEqual(editor.screenplay.elements.last?.text, "The action changed.")
    }

    @MainActor
    func testExternalChangePreservesUndoTimeline() throws {
        let editor = try makeEditor()
        let actionID = try XCTUnwrap(editor.screenplay.elements.last?.id)
        editor.replaceElementText(id: actionID, text: "The writer typed this.")
        XCTAssertTrue(editor.canUndo)

        editor.applyExternalSource("FADE IN:\n\nINT. LAB - NIGHT\n\nSynced from elsewhere.\n")
        XCTAssertTrue(editor.canUndo, "The undo timeline must survive an external change")

        editor.undo()
        XCTAssertEqual(editor.screenplay.elements.last?.text, "The writer typed this.",
                       "Undo after a sync returns to the writer's own last edit")
    }

    @MainActor
    func testDeletedCaretElementFallsBackToPredecessor() throws {
        let editor = try makeEditor()
        let actionID = try XCTUnwrap(editor.screenplay.elements.last?.id)
        editor.jump(to: actionID)
        // The writer's element vanished in the synced copy: the caret lands
        // on the nearest surviving predecessor — never teleported blindly to
        // the top while the rest of the document still exists.
        editor.applyExternalSource("FADE IN:\n\nOnly action remains.\n")
        let active = editor.screenplay.elements.first { $0.id == editor.activeElementID }
        XCTAssertEqual(active?.text, "FADE IN:")
    }

    @MainActor
    func testExternalChangeNeverPublishesBack() throws {
        let editor = try makeEditor()
        var published = false
        editor.onSourceChange = { _ in published = true }
        editor.applyExternalSource("FADE IN:\n\nINT. LAB - NIGHT\n\nChanged remotely.\n")
        XCTAssertFalse(published, "Applying a sync must not echo a write")
        XCTAssertEqual(editor.banner, "Updated from iCloud")
    }
}

/// The professional migration path: a Final Draft file opens in place,
/// converts to the app's Fountain source of truth, and saves back as valid
/// FDX — scene numbers, dual dialogue, and title page intact. The codec
/// itself is pinned byte-for-byte by the engine's FDX conformance corpus;
/// these tests guard the document boundary around it.
final class FdxInterchangeTests: XCTestCase {

    private static let foreignFdx = """
    <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
    <FinalDraft DocumentType="Script" Version="3">
      <Content>
        <Paragraph Type="Scene Heading" Number="1"><Text>INT. FISH &amp; CHIP SHOP - DAY</Text></Paragraph>
        <Paragraph Type="Character"><Text>MOLLY (V.O.)</Text></Paragraph>
        <Paragraph Type="Dialogue"><Text>We&apos;re closed.</Text></Paragraph>
      </Content>
      <TitlePage>
        <Content>
          <Paragraph Alignment="Center" Type="General"><Text>Chips</Text></Paragraph>
          <Paragraph Alignment="Center" Type="General"><Text>written by</Text></Paragraph>
          <Paragraph Alignment="Center" Type="General"><Text>A. Writer</Text></Paragraph>
        </Content>
      </TitlePage>
    </FinalDraft>
    """

    private func read(_ text: String, as type: UTType) throws -> DraftFirstDocument {
        DraftFirstDocument(
            source: try DraftFirstDocument.decode(
                XCTUnwrap(text.data(using: .utf8)), as: type
            )
        )
    }

    private func write(_ document: DraftFirstDocument, as type: UTType) throws -> String {
        String(decoding: try DraftFirstDocument.encode(document.source, as: type), as: UTF8.self)
    }

    func testFdxIsReadableAndWritable() {
        XCTAssertTrue(DraftFirstDocument.readableContentTypes.contains(.finalDraftScreenplay))
        XCTAssertTrue(DraftFirstDocument.writableContentTypes.contains(.finalDraftScreenplay))
    }

    /// Import converts FDX to the Fountain source: scene numbers become
    /// forced-number markers, the title page becomes title-page keys.
    func testImportConvertsToFountainSource() throws {
        let document = try read(Self.foreignFdx, as: .finalDraftScreenplay)
        XCTAssertTrue(document.source.contains("Title: Chips"), document.source)
        XCTAssertTrue(document.source.contains("INT. FISH & CHIP SHOP - DAY #1#"), document.source)
        XCTAssertTrue(document.source.contains("MOLLY (V.O.)"), document.source)
        XCTAssertTrue(document.source.contains("We're closed."), document.source)
    }

    /// Saving an .fdx in place writes FDX back out — never Fountain source
    /// wearing an .fdx name, which Final Draft would refuse to open.
    func testWriteBackToFdxProducesValidXml() throws {
        let document = try read(Self.foreignFdx, as: .finalDraftScreenplay)
        let written = try write(document, as: .finalDraftScreenplay)
        XCTAssertTrue(written.contains("<FinalDraft"), written)
        XCTAssertTrue(written.contains("</FinalDraft>"), written)
        XCTAssertTrue(written.contains(#"Type="Scene Heading" Number="1""#), written)
        XCTAssertTrue(written.contains("INT. FISH &amp; CHIP SHOP - DAY"), written)
        XCTAssertTrue(written.contains("MOLLY (V.O.)"), written)
    }

    /// Open → save → open is an identity: a migrated file never drifts.
    func testInPlaceEditRoundTripIsStable() throws {
        let once = try read(Self.foreignFdx, as: .finalDraftScreenplay)
        let written = try write(once, as: .finalDraftScreenplay)
        let twice = try read(written, as: .finalDraftScreenplay)
        XCTAssertEqual(twice.source, once.source)
    }

    /// Dual dialogue and a forced scene number survive the export path that
    /// the share sheet's "Final Draft (FDX)" action uses.
    @MainActor
    func testExportCarriesDualDialogueAndSceneNumbers() {
        let screenplay = Screenplay(
            titlePage: [],
            elements: [
                ScriptElement(type: .scene, text: "INT. LAB - NIGHT", sceneNumber: "7"),
                ScriptElement(type: .character, text: "MARA", dual: true),
                ScriptElement(type: .dialogue, text: "Overlapping.")
            ]
        )
        let fdx = ScreenplayExporter.fdxSource(screenplay)
        XCTAssertTrue(fdx.contains(#"Number="7""#), fdx)
        XCTAssertTrue(fdx.contains(#"Dual="Yes""#), fdx)
        XCTAssertTrue(fdx.contains(#"xmlns:DraftFirst="https://draftfirst.xyz/ns/fdx/1""#), fdx)
    }

    /// A non-FDX document is untouched by the codec: plain text in, the same
    /// bytes out.
    func testPlainTextPathIsUnaffected() throws {
        let source = "INT. LAB - NIGHT\n\nHum.\n"
        let document = try read(source, as: .plainText)
        XCTAssertEqual(document.source, source)
        XCTAssertEqual(try write(document, as: .plainText), source)
    }
}
