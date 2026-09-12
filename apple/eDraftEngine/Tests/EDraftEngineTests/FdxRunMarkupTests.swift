import XCTest
@testable import EDraftEngine

/// Runs in FDX — emphasis, revision, tags and the highlight. Mirrors the
/// TypeScript cases in `fdx.test.ts`: the model's runs become the file's,
/// and the file's become the model's, losslessly in both directions.
final class FdxRunMarkupTests: XCTestCase {

    func testTheParserReadsARunsAttributesIntoTheModel() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft xmlns:EDraft="https://edraft.xyz/ns/fdx/1" DocumentType="Script" Version="3"><Content>
        <Paragraph Type="Action"><Text>plain </Text><Text Style="Bold+Italic">strong</Text><Text RevisionID="2"> revised</Text><Text EDraft:Highlight="Yellow"> marked</Text></Paragraph>
        </Content></FinalDraft>
        """
        let imported = Fdx.parse(xml)
        let element = imported.script.elements[0]
        XCTAssertEqual(element.text, "plain strong revised marked")
        XCTAssertEqual(
            element.runs,
            [
                StyleRun(start: 6, end: 12, styles: [.bold, .italic]),
                StyleRun(start: 12, end: 20, styles: [], revisionID: 2),
                StyleRun(start: 20, end: 27, styles: [], highlight: .yellow),
            ]
        )
    }

    func testTheWriterEmitsRunsInCanonicalStyleOrder() {
        let script = Screenplay(titlePage: [], elements: [
            ScreenplayElement(
                type: .action, text: "The strong marked words.",
                runs: [
                    StyleRun(start: 4, end: 10, styles: [.italic, .bold]),
                    StyleRun(start: 11, end: 17, styles: [], highlight: .yellow),
                ]
            ),
        ])
        let xml = Fdx.writeXml(script)
        XCTAssertTrue(xml.contains("<Text>The </Text>"))
        XCTAssertTrue(xml.contains("<Text Style=\"Bold+Italic\">strong</Text>"))
        XCTAssertTrue(xml.contains("<Text EDraft:Highlight=\"Yellow\">marked</Text>"))
        XCTAssertTrue(xml.contains("<Text> words.</Text>"))
    }

    func testRunsRoundTripLosslesslyThroughOurOwnWriteAndRead() {
        let script = Screenplay(titlePage: [], elements: [
            ScreenplayElement(
                type: .dialogue, text: "A bold thing, a marked thing.",
                runs: [
                    StyleRun(start: 2, end: 6, styles: .bold),
                    StyleRun(start: 16, end: 22, styles: [], highlight: .yellow),
                ]
            ),
        ])
        let back = Fdx.parse(Fdx.writeXml(script)).script.elements[0]
        XCTAssertEqual(back.text, "A bold thing, a marked thing.")
        XCTAssertEqual(
            back.runs,
            [
                StyleRun(start: 2, end: 6, styles: .bold),
                StyleRun(start: 16, end: 22, styles: [], highlight: .yellow),
            ]
        )
    }

    func testARunlessDocumentWritesTheSamePlainTextItAlwaysDid() {
        let script = Screenplay(titlePage: [], elements: [
            ScreenplayElement(type: .action, text: "No runs here."),
        ])
        let xml = Fdx.writeXml(script)
        XCTAssertTrue(xml.contains("<Paragraph Type=\"Action\"><Text>No runs here.</Text></Paragraph>"))
        XCTAssertFalse(xml.contains("Style="))
        XCTAssertFalse(xml.contains("Highlight"))
    }

    func testThePreservingRewriteDeclaresTheNamespaceWhenItFirstNeedsIt() {
        let xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Template="No" Version="6">
          <Content>
            <Paragraph Type="Action"><Text>Mark me.</Text></Paragraph>
          </Content>
        </FinalDraft>
        """
        let document = Fdx.open(xml)
        let edited = Screenplay(titlePage: [], elements: [
            ScreenplayElement(
                type: .action, text: "Mark me.",
                runs: [StyleRun(start: 0, end: 4, styles: [], highlight: .yellow)]
            ),
        ])
        let out = document.rewrite(edited)
        XCTAssertTrue(out.contains("xmlns:EDraft=\"https://edraft.xyz/ns/fdx/1\""))
        XCTAssertTrue(out.contains("<Text EDraft:Highlight=\"Yellow\">Mark</Text>"))
    }
}
