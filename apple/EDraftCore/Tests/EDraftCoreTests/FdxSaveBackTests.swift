import XCTest
import UniformTypeIdentifiers
@testable import EDraftCore

/// Saving a Final Draft file must not cost the writer what it carries.
///
/// `.fdx` is a writable type by design — an .fdx opened in place writes back
/// as FDX, never a read-only trap. That promise is only safe if the save edits
/// the file instead of rebuilding it from a screenplay, which cannot hold
/// revisions, locked pages, tags, or the arc beats nested in a scene heading.
@MainActor
final class FdxSaveBackTests: XCTestCase {

    private static let production = """
    <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
    <FinalDraft DocumentType="Script" Template="No" Version="6">
      <Content>
        <Paragraph Type="Scene Heading" Number="1">
          <SceneProperties Length="4/8" Page="1" Title="Set up Gold Key">
            <SceneArcBeats>
              <CharacterArcBeat Name="TANGLE">
                <Paragraph><Text>Tangle is obsessed with the treasure.</Text></Paragraph>
              </CharacterArcBeat>
            </SceneArcBeats>
          </SceneProperties>
          <Text>INT. HOME LIBRARY - DAY</Text>
        </Paragraph>
        <Paragraph Type="Action"><Text>Majestic.</Text></Paragraph>
        <Paragraph Type="Note"><Text>Is this the same library as scene 9?</Text></Paragraph>
      </Content>
      <LockedPages><LockedPage Number="1"/></LockedPages>
      <Revisions><Revision Color="Blue" Mark="*" Name="First Revision" Number="1"/></Revisions>
      <TagData><TagDefinition Id="t1" Label="Spanish moss"/></TagData>
    </FinalDraft>
    """

    private func opened() throws -> (source: String, origin: String?) {
        try ScreenplayFile.open(
            Data(Self.production.utf8), as: .finalDraftScreenplay
        )
    }

    func testOpeningKeepsTheOriginal() throws {
        let file = try opened()
        XCTAssertEqual(file.origin, Self.production)
        XCTAssertTrue(file.source.contains("INT. HOME LIBRARY - DAY"))
    }

    /// Opened and saved with no edit: the same file, to the byte.
    func testSavingWithoutEditingReturnsTheIdenticalFile() throws {
        let file = try opened()
        let written = try ScreenplayFile.encode(
            file.source, as: .finalDraftScreenplay, origin: file.origin
        )
        XCTAssertEqual(String(data: written, encoding: .utf8), Self.production)
    }

    /// The case that matters: a typo fixed on a locked script.
    func testEditingKeepsRevisionsLockedPagesAndTags() throws {
        let file = try opened()
        let edited = file.source.replacingOccurrences(of: "Majestic.", with: "Majestic, and lit.")
        let written = try ScreenplayFile.encode(
            edited, as: .finalDraftScreenplay, origin: file.origin
        )
        let xml = try XCTUnwrap(String(data: written, encoding: .utf8))

        XCTAssertTrue(xml.contains("Majestic, and lit."))
        XCTAssertTrue(xml.contains("<LockedPage"), "the locked pages were lost")
        XCTAssertTrue(xml.contains("<Revision"), "the revision history was lost")
        XCTAssertTrue(xml.contains("<TagDefinition"), "the production tags were lost")
        XCTAssertTrue(xml.contains("<CharacterArcBeat"), "the arc beats were lost")
    }

    /// A Final Draft Note is a line in the script that does not print, which
    /// is what Fountain's [[ ]] is — so it reaches the writer as a note rather
    /// than as a stage direction printed on the page, and goes home as one.
    func testANoteArrivesAsANoteAndGoesHomeAsOne() throws {
        let file = try opened()
        XCTAssertTrue(
            file.source.contains("[[Is this the same library as scene 9?]]"),
            "a Final Draft note did not survive the trip into the editor"
        )

        let edited = file.source.replacingOccurrences(
            of: "same library as scene 9", with: "same library as scene 12"
        )
        let written = try ScreenplayFile.encode(
            edited, as: .finalDraftScreenplay, origin: file.origin
        )
        let xml = try XCTUnwrap(String(data: written, encoding: .utf8))

        XCTAssertTrue(xml.contains("Type=\"Note\""), "the note stopped being a note")
        XCTAssertTrue(xml.contains("same library as scene 12"), "the edit was lost")
        XCTAssertFalse(xml.contains("Type=\"General\""), "the note was printed as General")
    }

    /// Without an original there is nothing to preserve, and a whole file is
    /// the right answer — exporting a screenplay that began life here.
    func testExportingWithoutAnOriginalWritesAWholeFile() throws {
        let written = try ScreenplayFile.encode(
            "INT. LAB - DAY\n\nShe waits.", as: .finalDraftScreenplay
        )
        let xml = try XCTUnwrap(String(data: written, encoding: .utf8))
        XCTAssertTrue(xml.contains("<FinalDraft"))
        XCTAssertTrue(xml.contains("INT. LAB - DAY"))
    }
}
