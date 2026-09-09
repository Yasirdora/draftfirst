import EDraftEngine
import UniformTypeIdentifiers
import XCTest
@testable import EDraftCore

/// FDX must survive a round trip with the extension data intact. Lyrics
/// types and keyed title pages live in attributes Final Draft has no
/// field for; emptying `LEGACY_ATTRIBUTE_PREFIXES` once dropped them
/// from every file exported under the old name. Named for that failure.
@MainActor
final class FdxRoundTripTests: XCTestCase {

    func testExportingFdxKeepsLyricsAndKeyedTitlePage() throws {
        let original = EDraftCore.Screenplay(
            titlePage: [
                TitlePageEntry(key: "Title", values: ["Keyed Title"]),
                TitlePageEntry(key: "Author", values: ["A. Writer"]),
                TitlePageEntry(key: "CustomCredit", values: ["Additional writing"])
            ],
            elements: [
                ScriptElement(type: .scene, text: "INT. HALL - NIGHT"),
                ScriptElement(type: .lyrics, text: "Sing me home")
            ]
        )

        let xml = ScreenplayExporter.fdxSource(original)
        XCTAssertTrue(xml.contains("EDraft:ElementType=\"lyrics\""), "lyrics must be written as an extension, not silently as General")
        XCTAssertTrue(xml.contains("EDraft:TitleKey=\"Title\""))
        XCTAssertTrue(xml.contains("EDraft:TitleKey=\"CustomCredit\""))
        XCTAssertFalse(xml.contains("DraftFirst:"), "we read the old prefix and never write it")

        let parsed = Fdx.parse(xml).script
        XCTAssertEqual(parsed.elements.first { $0.type == .lyrics }?.text, "Sing me home")
        XCTAssertEqual(parsed.elements.first { $0.type == .lyrics }?.type, .lyrics)
        XCTAssertEqual(parsed.titlePage.first { $0.key == "Title" }?.values, ["Keyed Title"])
        XCTAssertEqual(parsed.titlePage.first { $0.key == "CustomCredit" }?.values, ["Additional writing"])

        let fountain = try ScreenplayFile.decode(Data(xml.utf8), as: .finalDraftScreenplay)
        let reopened = EDraftCore.Screenplay(engineModel: try Fountain.parse(fountain))
        XCTAssertEqual(reopened.elements.first { $0.type == .lyrics }?.text, "Sing me home")
        XCTAssertEqual(reopened.titlePage.first { $0.key == "Title" }?.values, ["Keyed Title"])
        XCTAssertEqual(reopened.titlePage.first { $0.key == "CustomCredit" }?.values, ["Additional writing"])
    }

    func testALegacyPrefixFileStillImportsLyricsAndTitleKeys() {
        let legacy = """
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft xmlns:DraftFirst="https://draftfirst.xyz/ns/fdx/1" DocumentType="Script" Version="3">
        <Content>
        <Paragraph Type="General" DraftFirst:ElementType="lyrics"><Text>Sing me home</Text></Paragraph>
        </Content>
        <TitlePage>
        <Content>
        <Paragraph Alignment="Center" Type="General" DraftFirst:TitleKey="Title" DraftFirst:TitleEntry="0"><Text>Old Name</Text></Paragraph>
        </Content>
        </TitlePage>
        </FinalDraft>
        """
        let script = Fdx.parse(legacy).script
        XCTAssertEqual(script.elements.first?.type, .lyrics)
        XCTAssertEqual(script.elements.first?.text, "Sing me home")
        XCTAssertEqual(script.titlePage.first { $0.key == "Title" }?.values, ["Old Name"])

        let rewritten = ScreenplayExporter.fdxSource(EDraftCore.Screenplay(engineModel: script))
        XCTAssertTrue(rewritten.contains("EDraft:ElementType=\"lyrics\""))
        XCTAssertFalse(rewritten.contains("draftfirst.xyz"))
    }
}
