import XCTest
@testable import EDraftCore

/// What is in the document but not on the page, and the trip out and back.
///
/// The rule under all of it: the page is the printing elements. A note, an act
/// heading and the prose under it are all in the file and none of them takes a
/// line of a page a production schedules against.
final class ScriptAsidesTests: XCTestCase {

    private func element(_ type: ScreenplayKind, _ text: String, depth: Int? = nil) -> ScriptElement {
        ScriptElement(type: type, text: text, depth: depth)
    }

    func testANoteComesOffThePageAnchoredToTheLineBelowIt() {
        let heading = element(.scene, "INT. LAB - DAY")
        let note = element(.note, "Same lab as scene 4?")
        let action = element(.action, "She waits.")
        let split = ScriptAsides.split([heading, note, action])

        XCTAssertEqual(split.page, [heading, action], "the note was left on the page")
        XCTAssertEqual(split.asides.map(\.text), ["Same lab as scene 4?"])
        XCTAssertEqual(split.asides.first?.anchor, action.id, "it belongs to the line under it")
    }

    /// The outline is the reason this stopped being about notes alone: read as
    /// General these printed as stage directions and paginated.
    func testTheOutlineComesOffThePageAndKeepsItsLevel() {
        let act = element(.section, "Act One", depth: 1)
        let beat = element(.section, "Set up Gold Key", depth: 3)
        let summary = element(.synopsis, "Tangle questions Uncle.")
        let heading = element(.scene, "INT. LIBRARY - DAY")
        let split = ScriptAsides.split([act, beat, summary, heading])

        XCTAssertEqual(split.page, [heading], "the outline was left on the page")
        XCTAssertEqual(split.asides.map(\.kind), [.section, .section, .synopsis])
        XCTAssertEqual(split.asides.map(\.depth), [1, 3, nil])
        XCTAssertEqual(
            ScriptAsides.merge(page: split.page, asides: split.asides),
            [act, beat, summary, heading],
            "the outline did not go back the way it came"
        )
    }

    /// Asked of `isPrinting` rather than a list here, so a kind added later
    /// cannot be printing in one place and not the other.
    func testEveryNonPrintingKindComesOff() {
        let page = element(.action, "She waits.")
        let all = ScreenplayKind.allCases.map { element($0, "x") } + [page]
        let split = ScriptAsides.split(all)

        XCTAssertTrue(
            split.page.allSatisfy { $0.type.isPrinting },
            "something that does not print was left on the page"
        )
        XCTAssertTrue(
            split.asides.allSatisfy { !$0.kind.isPrinting },
            "something that prints was taken off the page"
        )
    }

    /// Fountain writes `[[…]]` before the line it is about, and a writer who
    /// types two of them means both.
    func testTwoAsidesOnTheSameLineKeepTheirOrder() {
        let action = element(.action, "She waits.")
        let first = element(.note, "First.")
        let second = element(.note, "Second.")
        let split = ScriptAsides.split([first, second, action])

        XCTAssertEqual(split.asides.map(\.text), ["First.", "Second."])
        XCTAssertEqual(split.asides.map(\.anchor), [action.id, action.id])
        XCTAssertEqual(
            ScriptAsides.merge(page: split.page, asides: split.asides), [first, second, action]
        )
    }

    func testAnAsideAfterTheLastLineTrailsTheScript() {
        let action = element(.action, "She waits.")
        let note = element(.note, "End on this.")
        let split = ScriptAsides.split([action, note])

        XCTAssertNil(split.asides.first?.anchor, "an aside with nothing under it cannot anchor")
        XCTAssertEqual(ScriptAsides.merge(page: split.page, asides: split.asides), [action, note])
    }

    func testSplitAndMergeIsTheIdentityOnAWholeScript() {
        let elements = [
            element(.section, "Act One", depth: 1),
            element(.synopsis, "They meet."),
            element(.note, "Open colder."),
            element(.scene, "INT. LAB - DAY"),
            element(.action, "She waits."),
            element(.note, "Is she waiting for him or for it?"),
            element(.character, "MARA"),
            element(.dialogue, "You're late."),
            element(.note, "Trailing.")
        ]
        let split = ScriptAsides.split(elements)
        XCTAssertEqual(ScriptAsides.merge(page: split.page, asides: split.asides), elements)
    }

    /// The case the whole design turns on: the writer edits the page, and the
    /// asides have to find their way home to elements that moved.
    func testAsidesSurviveAnEditThatReordersThePage() {
        let heading = element(.scene, "INT. LAB - DAY")
        let action = element(.action, "She waits.")
        let note = element(.note, "About the action.")
        var split = ScriptAsides.split([heading, note, action])

        // The writer retypes the heading and moves the action above it. The
        // note is about the action, and follows it.
        split.page = [
            ScriptElement(id: action.id, type: .action, text: "She waits, badly."),
            ScriptElement(id: heading.id, type: .scene, text: "INT. LAB - NIGHT")
        ]
        let merged = ScriptAsides.merge(page: split.page, asides: split.asides)

        XCTAssertEqual(merged.map(\.type), [.note, .action, .scene])
        XCTAssertEqual(merged.first?.text, "About the action.")
    }

    /// Deleting the line an aside is about must not delete the aside. It goes
    /// where the writer can see it and decide.
    func testAnAsideWhoseLineIsGoneSurvivesAtTheEnd() {
        let heading = element(.scene, "INT. LAB - DAY")
        let note = element(.note, "Keep me.")
        let action = element(.action, "She waits.")
        var split = ScriptAsides.split([heading, note, action])

        split.page = [heading]
        let merged = ScriptAsides.merge(page: split.page, asides: split.asides)

        XCTAssertEqual(merged.map(\.type), [.scene, .note])
        XCTAssertEqual(merged.last?.text, "Keep me.")
    }

    func testAScriptWithNothingBesideItIsUntouched() {
        let elements = [element(.scene, "INT. LAB - DAY"), element(.action, "She waits.")]
        let split = ScriptAsides.split(elements)
        XCTAssertTrue(split.asides.isEmpty)
        XCTAssertEqual(split.page, elements)
        XCTAssertEqual(ScriptAsides.merge(page: split.page, asides: split.asides), elements)
    }
}
