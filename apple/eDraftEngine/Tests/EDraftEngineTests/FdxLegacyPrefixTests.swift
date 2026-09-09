import Foundation
import Testing
@testable import EDraftEngine

/// The rename compatibility contract, on the Swift side.
///
/// An `.fdx` exported before the eDraft rename carries `draftfirst:` extension
/// attributes — the fields Final Draft has no place for, like a lyrics element
/// or a keyed title page. Those files must keep importing with full fidelity
/// forever; we read the old prefix and never write it again.
///
/// This exists because the constant that carries it was silently emptied during
/// the rename and nothing here noticed. The TypeScript engine has always held
/// this contract under test; the port had the same constant and no test, so the
/// two could disagree in exactly the way that loses a writer's work. Now both
/// are held to it.
@Suite("FDX legacy prefix")
struct FdxLegacyPrefixTests {

    private let legacy = """
    <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
    <FinalDraft xmlns:DraftFirst="https://draftfirst.xyz/ns/fdx/1" DocumentType="Script" Version="3">
    <Content>
    <Paragraph Type="General" DraftFirst:ElementType="lyrics"><Text>Sing me home</Text></Paragraph>
    </Content>
    <TitlePage>
    <Content>
    <Paragraph Alignment="Center" Type="General" DraftFirst:TitleKey="Title" DraftFirst:TitleEntry="0"><Text>Old Name</Text></Paragraph>
    <Paragraph Alignment="Center" Type="General" DraftFirst:TitleKey="Author" DraftFirst:TitleEntry="1"><Text>A. Writer</Text></Paragraph>
    </Content>
    </TitlePage>
    </FinalDraft>
    """

    @Test("A lyrics line survives the old prefix")
    func lyrics() {
        let script = Fdx.parse(legacy).script
        #expect(script.elements.first?.type == .lyrics)
        #expect(script.elements.first?.text == "Sing me home")
    }

    @Test("A keyed title page survives the old prefix")
    func titlePage() {
        let script = Fdx.parse(legacy).script
        #expect(script.titlePage == [
            TitlePageEntry(key: "Title", values: ["Old Name"]),
            TitlePageEntry(key: "Author", values: ["A. Writer"])
        ])
    }

    @Test("It is written back under the current namespace only")
    func rewritten() {
        let xml = Fdx.writeXml(Fdx.parse(legacy).script)
        #expect(xml.contains("EDraft:ElementType=\"lyrics\""))
        #expect(!xml.contains("draftfirst.xyz"))
        #expect(!xml.contains("DraftFirst:"))
    }
}
