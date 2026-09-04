import Foundation
import Testing
@testable import DraftFirstEngine

@Suite("Revisions")
struct RevisionsTests {

    private func action(_ text: String) -> ScreenplayElement {
        ScreenplayElement(type: .action, text: text)
    }

    // MARK: Colours

    @Test("The colour run is the one every production uses")
    func colourRun() {
        let names = (0..<9).map { RevisionColour(index: $0).name }
        #expect(names == [
            "White", "Blue", "Pink", "Yellow", "Green", "Goldenrod", "Salmon", "Cherry", "Buff"
        ])
    }

    @Test("A long production goes round again on doubles")
    func secondPass() {
        #expect(RevisionColour(index: 9).name == "Double White")
        #expect(RevisionColour(index: 10).name == "Double Blue")
        #expect(RevisionColour(index: 19).name == "Triple Blue")
        #expect(RevisionColour.original.next.name == "Blue")
    }

    // MARK: Change detection

    @Test("An unchanged draft is marked nowhere")
    func noChanges() {
        let script = [action("One."), action("Two."), action("Three.")]
        #expect(RevisionDiff.changed(from: script, to: script).isEmpty)
    }

    @Test("An inserted line is marked and nothing after it is")
    func insertion() {
        let before = [action("One."), action("Three.")]
        let after = [action("One."), action("Two."), action("Three.")]
        #expect(Array(RevisionDiff.changed(from: before, to: after)) == [1])
    }

    @Test("A rewritten line is marked")
    func modification() {
        let before = [action("One."), action("Two."), action("Three.")]
        let after = [action("One."), action("Two, revised."), action("Three.")]
        #expect(Array(RevisionDiff.changed(from: before, to: after)) == [1])
    }

    @Test("A deleted line leaves nothing to mark")
    func deletion() {
        let before = [action("One."), action("Two."), action("Three.")]
        let after = [action("One."), action("Three.")]
        #expect(RevisionDiff.changed(from: before, to: after).isEmpty)
    }

    @Test("Changing an element's lane is a change")
    func kindChange() {
        let before = [ScreenplayElement(type: .action, text: "MARA")]
        let after = [ScreenplayElement(type: .character, text: "MARA")]
        #expect(Array(RevisionDiff.changed(from: before, to: after)) == [0])
    }

    /// Numbering scenes is bookkeeping. If it marked the page, every scene
    /// would carry an asterisk the first time a production locked its numbers.
    @Test("Assigning a scene number is not a rewrite")
    func sceneNumbersAreNotChanges() {
        let before = [ScreenplayElement(type: .scene, text: "INT. LAB - DAY")]
        let after = SceneNumbering.numberingAll(before)
        #expect(RevisionDiff.changed(from: before, to: after).isEmpty)
    }

    @Test("A change deep in a long script is found without comparing everything")
    func longScript() {
        var before = (0..<3_000).map { action("Line \($0).") }
        var after = before
        after[1_500] = action("Line 1500, revised.")
        #expect(Array(RevisionDiff.changed(from: before, to: after)) == [1_500])

        // And an insertion near the end, where trimming the tail matters.
        before = (0..<3_000).map { action("Line \($0).") }
        after = before
        after.insert(action("Inserted."), at: 2_900)
        #expect(Array(RevisionDiff.changed(from: before, to: after)) == [2_900])
    }

    @Test("An added opening and an added ending are both marked")
    func endsOfTheScript() {
        let before = [action("Middle.")]
        let after = [action("Opening."), action("Middle."), action("Closing.")]
        #expect(Array(RevisionDiff.changed(from: before, to: after)) == [0, 2])
    }
}
