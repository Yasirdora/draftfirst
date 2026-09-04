import Foundation
import Testing
@testable import DraftFirstEngine

@Suite("Scene numbering")
struct SceneNumberingTests {

    private func scene(_ text: String, _ number: String? = nil) -> ScreenplayElement {
        ScreenplayElement(type: .scene, text: text, sceneNumber: number)
    }
    private func action(_ text: String) -> ScreenplayElement {
        ScreenplayElement(type: .action, text: text)
    }

    @Test("A fresh script numbers straight through")
    func numbersFromOne() {
        let out = SceneNumbering.numberingAll([
            scene("INT. A - DAY"), action("Something happens."),
            scene("EXT. B - NIGHT"), action("Something else."),
            scene("INT. C - DAY")
        ])
        #expect(out.compactMap(\.sceneNumber) == ["1", "2", "3"])
        // Only scenes are addressed; action carries nothing.
        #expect(out[1].sceneNumber == nil)
    }

    @Test("A distributed script keeps its numbers and letters the new scenes")
    func lettersNewScenes() {
        let out = SceneNumbering.numberingNewScenes([
            scene("INT. A - DAY", "12"),
            scene("EXT. NEW ONE - DAY"),
            scene("EXT. NEW TWO - DAY"),
            scene("INT. B - NIGHT", "13")
        ])
        #expect(out.compactMap(\.sceneNumber) == ["12", "12A", "12B", "13"])
    }

    @Test("Scenes added ahead of the first number take the letter in front")
    func lettersBeforeTheFirstNumber() {
        let out = SceneNumbering.numberingNewScenes([
            scene("EXT. COLD OPEN - DAWN"),
            scene("INT. A - DAY", "1")
        ])
        #expect(out.compactMap(\.sceneNumber) == ["A1", "1"])
    }

    @Test("A letter already in the script is never handed out twice")
    func skipsNumbersAlreadyUsed() {
        // 12A exists further down; the new scene after 12 must not claim it.
        let out = SceneNumbering.numberingNewScenes([
            scene("INT. A - DAY", "12"),
            scene("EXT. NEW - DAY"),
            scene("INT. INSERT - DAY", "12A"),
            scene("INT. B - NIGHT", "13")
        ])
        #expect(out.compactMap(\.sceneNumber) == ["12", "12B", "12A", "13"])
        #expect(Set(out.compactMap(\.sceneNumber)).count == 4, "every number is unique")
    }

    @Test("Locked numbering on an unnumbered script simply numbers it")
    func unnumberedScriptIsNumbered() {
        let out = SceneNumbering.numberingNewScenes([
            scene("INT. A - DAY"), scene("EXT. B - NIGHT")
        ])
        #expect(out.compactMap(\.sceneNumber) == ["1", "2"])
    }

    @Test("Clearing removes every number")
    func clearing() {
        let out = SceneNumbering.cleared([scene("INT. A - DAY", "12"), scene("EXT. B - NIGHT", "13")])
        #expect(out.allSatisfy { $0.sceneNumber == nil })
        #expect(!SceneNumbering.isNumbered(out))
    }

    @Test("Letters run in spreadsheet order")
    func letterOrder() {
        #expect(SceneNumbering.letters(0) == "A")
        #expect(SceneNumbering.letters(25) == "Z")
        #expect(SceneNumbering.letters(26) == "AA")
        #expect(SceneNumbering.letters(27) == "AB")
    }

    @Test("Numbers survive a round trip through Fountain")
    func roundTrip() throws {
        let numbered = SceneNumbering.numberingAll([
            scene("INT. WAREHOUSE - NIGHT"), action("Mara steps through."),
            scene("EXT. ROOFTOP - LATER"), action("Wind.")
        ])
        let source = Fountain.serialise(Screenplay(titlePage: [], elements: numbered))
        let reread = try Fountain.parse(source)
        #expect(reread.elements.compactMap(\.sceneNumber) == ["1", "2"])
    }
}
