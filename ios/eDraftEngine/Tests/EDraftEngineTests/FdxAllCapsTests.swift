import Foundation
import Testing
@testable import EDraftEngine

/// How Final Draft shouts.
///
/// It stores what the writer typed and marks the run `Style="AllCaps"`, so a
/// file can hold `cHroNo-aGEnT vAL` and have displayed CHRONO-AGENT VAL for the
/// life of the document. Read the text without the style and a script that
/// looked immaculate for years opens as though it were typed with a broken
/// shift key. Every string here is lifted verbatim from a writer's own .fdx.
@Suite("FDX AllCaps runs")
struct FdxAllCapsTests {

    private let fdx = """
    <?xml version="1.0" encoding="UTF-8" standalone="no"?>
    <FinalDraft DocumentType="Script" Template="No" Version="6">
      <Content>
        <Paragraph Type="Scene Heading"><Text Style="AllCaps">iNt. eARThLInG cAFe - MoRNiNg</Text></Paragraph>
        <Paragraph Type="Action"><Text>The espresso machine hisses violently.</Text></Paragraph>
        <Paragraph Type="Character"><Text Style="AllCaps">cHroNo-aGEnT vAL</Text></Paragraph>
        <Paragraph Type="Dialogue"><Text>Greetings, carbon-based ancestors!</Text></Paragraph>
        <Paragraph Type="Transition"><Text Style="AllCaps">mATcH cUt tO:</Text></Paragraph>
        <Paragraph Type="Action"><Text Style="Bold+Underline+AllCaps">a shouted stage direction</Text></Paragraph>
      </Content>
    </FinalDraft>
    """

    @Test("Every run the file marks AllCaps is shouted")
    func shouted() {
        let texts = Fdx.parse(fdx).script.elements.map(\.text)
        #expect(texts == [
            "INT. EARTHLING CAFE - MORNING",
            "The espresso machine hisses violently.",
            "CHRONO-AGENT VAL",
            "Greetings, carbon-based ancestors!",
            "MATCH CUT TO:",
            "A SHOUTED STAGE DIRECTION"
        ])
    }

    @Test("AllCaps is one entry in the style list, never a substring")
    func notASubstring() {
        #expect(Fdx.runIsAllCaps("AllCaps"))
        #expect(Fdx.runIsAllCaps("Bold+Underline+AllCaps"))
        #expect(!Fdx.runIsAllCaps("AllCapsish"))
        #expect(!Fdx.runIsAllCaps("Bold+HiddenText"))
        #expect(!Fdx.runIsAllCaps(nil))
    }
}
