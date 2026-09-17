import EDraftCore
import XCTest
@testable import EDraftUI

/// Narrowing the Navigator's scene list. Matching, not classification —
/// `EditorState.scenes` already decided what a scene is.
@MainActor
final class SceneListFilterTests: XCTestCase {

    private func scenes() -> [SceneRow] {
        [
            SceneRow(id: UUID(), number: 1, page: 1, sceneNumber: nil,
                     title: "INT. KITCHEN - DAY", elementIndex: 0),
            SceneRow(id: UUID(), number: 2, page: 3, sceneNumber: "12A",
                     title: "EXT. ALLEY - NIGHT", elementIndex: 4),
            SceneRow(id: UUID(), number: 3, page: 4, sceneNumber: nil,
                     title: "INT. CAR - DAY", elementIndex: 8)
        ]
    }

    func testAnEmptyQueryLeavesEveryScene() {
        XCTAssertEqual(SceneListFilter.included(scenes(), query: "").count, 3)
        XCTAssertEqual(SceneListFilter.included(scenes(), query: "   ").count, 3)
    }

    func testATitleFragmentNarrowsTheList() {
        let found = SceneListFilter.included(scenes(), query: "alley")
        XCTAssertEqual(found.map(\.title), ["EXT. ALLEY - NIGHT"])
    }

    func testAProductionNumberMatchesTheLabel() {
        let found = SceneListFilter.included(scenes(), query: "12A")
        XCTAssertEqual(found.map(\.label), ["12A"])
    }

    func testNothingMatchingIsEmptyRatherThanGuessed() {
        XCTAssertTrue(SceneListFilter.included(scenes(), query: "warehouse").isEmpty)
    }
}

/// Where each note falls, and narrowing the list of them.
///
/// Placing is the part worth pinning: a note carries the line it sits on, and
/// the scene is a reading of that line's position — the same reading the
/// "you are here" mark makes for the caret.
@MainActor
final class NoteRowsTests: XCTestCase {

    private let kitchen = UUID()
    private let kettle = UUID()
    private let alley = UUID()
    private let rain = UUID()

    private func elements() -> [ScriptElement] {
        [
            ScriptElement(id: kitchen, type: .scene, text: "INT. KITCHEN - DAY"),
            ScriptElement(id: kettle, type: .action, text: "She puts the kettle on."),
            ScriptElement(id: alley, type: .scene, text: "EXT. ALLEY - NIGHT"),
            ScriptElement(id: rain, type: .action, text: "Rain, and no one under it.")
        ]
    }

    private func scenes() -> [SceneRow] {
        [
            SceneRow(id: kitchen, number: 1, page: 1, sceneNumber: nil,
                     title: "INT. KITCHEN - DAY", elementIndex: 0),
            SceneRow(id: alley, number: 2, page: 3, sceneNumber: nil,
                     title: "EXT. ALLEY - NIGHT", elementIndex: 2)
        ]
    }

    private func note(_ text: String, on anchor: UUID?) -> ScriptAside {
        ScriptAside(element: ScriptElement(type: .note, text: text), anchor: anchor)
    }

    private func rows(_ notes: [ScriptAside]) -> [NoteRow] {
        NoteRows.rows(notes: notes, elements: elements(), scenes: scenes())
    }

    func testANoteTakesTheSceneItsLineFallsIn() {
        let placed = rows([note("louder", on: kettle), note("cut this", on: rain)])
        XCTAssertEqual(placed.map(\.scene), ["INT. KITCHEN - DAY", "EXT. ALLEY - NIGHT"])
        XCTAssertEqual(placed.map(\.page), [1, 3])
    }

    func testANoteOnAHeadingBelongsToThatSceneNotThePreviousOne() {
        XCTAssertEqual(rows([note("new setup", on: alley)]).map(\.scene),
                       ["EXT. ALLEY - NIGHT"])
    }

    func testNotesAreOrderedByThePageNotByWhenTheyWereWritten() {
        let placed = rows([note("second", on: rain), note("first", on: kettle)])
        XCTAssertEqual(placed.map(\.text), ["first", "second"])
    }

    func testTwoNotesOnOneLineKeepTheOrderTheLineHoldsThem() {
        let placed = rows([note("one", on: kettle), note("two", on: kettle)])
        XCTAssertEqual(placed.map(\.text), ["one", "two"])
    }

    func testANoteBeyondTheLastLineSortsLastAndSaysSo() {
        let placed = rows([note("trailing", on: nil), note("in the kitchen", on: kettle)])
        XCTAssertEqual(placed.map(\.text), ["in the kitchen", "trailing"])
        XCTAssertNil(placed.last?.anchor)
        XCTAssertEqual(placed.last?.place, "After the last line")
    }

    func testANoteBeforeTheFirstHeadingHasNoSceneAndSaysSo() {
        let orphan = UUID()
        let placed = NoteRows.rows(
            notes: [note("cold open?", on: orphan)],
            elements: [ScriptElement(id: orphan, type: .action, text: "Black.")]
                + elements(),
            scenes: []
        )
        XCTAssertNil(placed.first?.scene)
        XCTAssertEqual(placed.first?.place, "Before the first scene")
    }

    func testAnEmptyNoteReadsAsOneRatherThanAsABlankRow() {
        XCTAssertEqual(rows([note("", on: kettle)]).first?.display, "Empty note")
    }
}

/// Narrowing the Navigator's note list.
@MainActor
final class NoteListFilterTests: XCTestCase {

    private func notes() -> [NoteRow] {
        [
            NoteRow(id: UUID(), text: "louder here", anchor: UUID(),
                    sceneID: UUID(), scene: "INT. KITCHEN - DAY", page: 1),
            NoteRow(id: UUID(), text: "cut this beat", anchor: UUID(),
                    sceneID: UUID(), scene: "EXT. ALLEY - NIGHT", page: 3)
        ]
    }

    func testAnEmptyQueryLeavesEveryNote() {
        XCTAssertEqual(NoteListFilter.included(notes(), query: "").count, 2)
        XCTAssertEqual(NoteListFilter.included(notes(), query: "   ").count, 2)
    }

    func testTheNotesOwnWordsMatch() {
        XCTAssertEqual(NoteListFilter.included(notes(), query: "louder").map(\.text),
                       ["louder here"])
    }

    func testTheSceneANoteSitsInMatchesToo() {
        XCTAssertEqual(NoteListFilter.included(notes(), query: "alley").map(\.text),
                       ["cut this beat"])
    }

    func testNothingMatchingIsEmptyRatherThanGuessed() {
        XCTAssertTrue(NoteListFilter.included(notes(), query: "warehouse").isEmpty)
    }
}

/// Narrowing the note list to one person, and reading the author off a note.
@MainActor
final class NoteAuthorRowTests: XCTestCase {

    private let kitchen = UUID()
    private let kettle = UUID()

    private func elements() -> [ScriptElement] {
        [
            ScriptElement(id: kitchen, type: .scene, text: "INT. KITCHEN - DAY"),
            ScriptElement(id: kettle, type: .action, text: "She puts the kettle on.")
        ]
    }

    private func scenes() -> [SceneRow] {
        [SceneRow(id: kitchen, number: 1, page: 1, sceneNumber: nil,
                  title: "INT. KITCHEN - DAY", elementIndex: 0)]
    }

    private func note(_ text: String) -> ScriptAside {
        ScriptAside(element: ScriptElement(type: .note, text: text), anchor: kettle)
    }

    private func rows(_ texts: [String]) -> [NoteRow] {
        let notes = texts.map(note)
        return NoteRows.rows(
            notes: notes, elements: elements(), scenes: scenes(),
            roster: NoteAttribution.roster(of: texts)
        )
    }

    func testARecognisedAuthorIsLiftedOffTheWords() {
        let made = rows(["Dir: louder", "Dir: cut this"])
        XCTAssertEqual(made.map(\.author), ["Dir", "Dir"])
        XCTAssertEqual(made.map(\.text), ["louder", "cut this"],
                       "the prefix belongs to the chip, not to the words")
    }

    func testAOneOffPrefixIsLeftInTheWordsUnattributed() {
        let made = rows(["TODO: fix the slug"])
        XCTAssertNil(made.first?.author)
        XCTAssertNil(made.first?.slot)
        XCTAssertEqual(made.first?.text, "TODO: fix the slug")
    }

    func testTwoAuthorsTakeDifferentColours() {
        let made = rows(["Dir: a", "Dir: b", "Prod: c", "Prod: d"])
        let slots = Dictionary(grouping: made, by: { $0.author ?? "" })
            .mapValues { Set($0.compactMap(\.slot)) }
        XCTAssertEqual(slots["Dir"]?.count, 1)
        XCTAssertEqual(slots["Prod"]?.count, 1)
        XCTAssertNotEqual(slots["Dir"], slots["Prod"])
    }

    func testFilteringByAuthorLeavesOnlyTheirs() {
        let made = rows(["Dir: a", "Dir: b", "Prod: c", "Prod: d"])
        let theirs = NoteListFilter.included(made, query: "", author: "Prod")
        XCTAssertEqual(theirs.map(\.text), ["c", "d"])
    }

    func testSearchingMatchesTheAuthorAsWellAsTheWords() {
        let made = rows(["Dir: a", "Dir: b", "Prod: c", "Prod: d"])
        XCTAssertEqual(NoteListFilter.included(made, query: "prod").count, 2)
    }

    func testAuthorAndSearchNarrowTogether() {
        let made = rows(["Dir: louder", "Dir: softer", "Prod: louder", "Prod: cut"])
        let found = NoteListFilter.included(made, query: "louder", author: "Dir")
        XCTAssertEqual(found.map(\.text), ["louder"])
    }
}

/// Notes from a Final Draft file, in the same list.
///
/// They sit among the writer's own by the page, they are who the file says
/// wrote them, and one person is one colour whichever app they wrote in.
@MainActor
final class ImportedNoteRowTests: XCTestCase {

    private let kitchen = UUID()
    private let kettle = UUID()
    private let alley = UUID()
    private let rain = UUID()

    private func elements() -> [ScriptElement] {
        [
            ScriptElement(id: kitchen, type: .scene, text: "INT. KITCHEN - DAY"),
            ScriptElement(id: kettle, type: .action, text: "She puts the kettle on."),
            ScriptElement(id: alley, type: .scene, text: "EXT. ALLEY - NIGHT"),
            ScriptElement(id: rain, type: .action, text: "Rain, and no one under it.")
        ]
    }

    private func scenes() -> [SceneRow] {
        [
            SceneRow(id: kitchen, number: 1, page: 1, sceneNumber: nil,
                     title: "INT. KITCHEN - DAY", elementIndex: 0),
            SceneRow(id: alley, number: 2, page: 3, sceneNumber: nil,
                     title: "EXT. ALLEY - NIGHT", elementIndex: 2)
        ]
    }

    private func own(_ text: String, on anchor: UUID?) -> ScriptAside {
        ScriptAside(element: ScriptElement(type: .note, text: text), anchor: anchor)
    }

    private func rows(own notes: [ScriptAside], imported: [ImportedNote]) -> [NoteRow] {
        let roster = ImportedNotes.roster(
            NoteAttribution.roster(of: notes.map(\.text)), adding: imported
        )
        return NoteRows.rows(
            notes: notes, elements: elements(), scenes: scenes(),
            roster: roster, imported: imported
        )
    }

    func testImportedNotesJoinTheListInPageOrderAfterTheWritersOwnOnALine() {
        let made = rows(
            own: [own("mine, on the rain", on: rain), own("mine, on the kettle", on: kettle)],
            imported: [
                ImportedNote(author: "Writer A", text: "theirs, on the rain", anchor: rain),
                ImportedNote(author: "Writer B", text: "theirs, on the kettle", anchor: kettle)
            ]
        )
        XCTAssertEqual(made.map(\.text), [
            "mine, on the kettle", "theirs, on the kettle", "mine, on the rain", "theirs, on the rain"
        ])
        XCTAssertEqual(made.map(\.isImported), [false, true, false, true])
        XCTAssertEqual(made.map(\.scene), [
            "INT. KITCHEN - DAY", "INT. KITCHEN - DAY", "EXT. ALLEY - NIGHT", "EXT. ALLEY - NIGHT"
        ])
    }

    func testTheWriterTheFileNamesIsTheAuthorFromOneNote() {
        let made = rows(own: [], imported: [ImportedNote(author: "Writer A", text: "Love this.", anchor: kettle)])
        XCTAssertEqual(made.first?.author, "Writer A")
        XCTAssertNotNil(made.first?.slot)
        XCTAssertEqual(made.first?.text, "Love this.", "a WriterName is not a prefix to lift off")
    }

    func testTwoWritersTakeTwoColoursAndTheFilterFindsEach() {
        let made = rows(own: [], imported: [
            ImportedNote(author: "Writer A", text: "a", anchor: kettle),
            ImportedNote(author: "Writer B", text: "b", anchor: rain)
        ])
        XCTAssertNotEqual(made[0].slot, made[1].slot)
        XCTAssertEqual(NoteListFilter.included(made, query: "", author: "Writer B").map(\.text), ["b"])
    }

    func testOnePersonIsOneColourInEitherApp() {
        let made = rows(
            own: [own("dir: louder", on: kettle), own("dir: softer", on: rain)],
            imported: [ImportedNote(author: "Dir", text: "Faster.", anchor: rain)]
        )
        XCTAssertEqual(Set(made.map(\.author)), ["Dir"])
        XCTAssertEqual(Set(made.compactMap(\.slot)).count, 1)
    }

    func testANoteNobodySignedKeepsTheYellow() {
        let made = rows(own: [], imported: [ImportedNote(text: "Unsigned.", anchor: kettle)])
        XCTAssertNil(made.first?.author)
        XCTAssertNil(made.first?.slot)
    }

    func testATitleLeadsTheWords() {
        let made = rows(own: [], imported: [
            ImportedNote(author: "Writer B", title: "Re: Gold Key", text: "Will they be confused?", anchor: kettle)
        ])
        XCTAssertEqual(made.first?.display, "Re: Gold Key — Will they be confused?")
    }

    func testANoteWhoseLineWasNotFoundSaysSoAndSortsLast() {
        let made = rows(
            own: [own("mine", on: kettle)],
            imported: [ImportedNote(author: "Writer A", text: "lost", anchor: nil)]
        )
        XCTAssertEqual(made.map(\.text), ["mine", "lost"])
        XCTAssertEqual(made.last?.place, "Line not found in this draft")
    }
}

/// Narrowing by where a scene plays.
///
/// The classification is `SceneSetting`'s and tested there; this covers the
/// list behaviour — that the two narrowings compose, and that a scene with no
/// setting is hidden by one rather than swept in.
@MainActor
final class SceneSettingFilterTests: XCTestCase {

    private func scenes() -> [SceneRow] {
        [
            SceneRow(id: UUID(), number: 1, page: 1, sceneNumber: nil,
                     title: "INT. KITCHEN - DAY", elementIndex: 0),
            SceneRow(id: UUID(), number: 2, page: 3, sceneNumber: nil,
                     title: "EXT. ALLEY - NIGHT", elementIndex: 4),
            SceneRow(id: UUID(), number: 3, page: 4, sceneNumber: nil,
                     title: "I/E. CAR - DAY", elementIndex: 8),
            SceneRow(id: UUID(), number: 4, page: 5, sceneNumber: nil,
                     title: "INT./EXT. TRAIN - DUSK", elementIndex: 12),
            SceneRow(id: UUID(), number: 5, page: 6, sceneNumber: nil,
                     title: "THE LONG WAY ROUND", elementIndex: 16)
        ]
    }

    func testNoSettingLeavesEveryScene() {
        XCTAssertEqual(SceneListFilter.included(scenes(), query: "").count, 5)
    }

    func testInteriorsOnly() {
        let visible = SceneListFilter.included(scenes(), query: "", setting: .interior)
        XCTAssertEqual(visible.map(\.title), ["INT. KITCHEN - DAY"])
    }

    func testExteriorsOnly() {
        let visible = SceneListFilter.included(scenes(), query: "", setting: .exterior)
        XCTAssertEqual(visible.map(\.title), ["EXT. ALLEY - NIGHT"])
    }

    /// Both spellings of the crossing case land in the same bucket, which is
    /// the whole reason this is read through the engine.
    func testTheCrossingCaseGathersItsSpellings() {
        let visible = SceneListFilter.included(scenes(), query: "", setting: .both)
        XCTAssertEqual(visible.map(\.title), ["I/E. CAR - DAY", "INT./EXT. TRAIN - DUSK"])
    }

    /// A forced slug has no intro token, so it belongs to no setting. Asking
    /// for interiors and being handed one would be a wrong answer, not a
    /// generous one.
    func testASlugWithNoIntroTokenIsHiddenByAnySetting() {
        for setting in SceneSetting.allCases {
            let visible = SceneListFilter.included(scenes(), query: "", setting: setting)
            XCTAssertFalse(visible.contains { $0.title == "THE LONG WAY ROUND" }, "\(setting)")
        }
    }

    func testTheSearchAndTheFilterCompose() {
        let visible = SceneListFilter.included(scenes(), query: "CAR", setting: .both)
        XCTAssertEqual(visible.map(\.title), ["I/E. CAR - DAY"])

        XCTAssertTrue(
            SceneListFilter.included(scenes(), query: "KITCHEN", setting: .exterior).isEmpty,
            "a search inside a filter must not escape it"
        )
    }
}

/// Narrowing and ordering the Navigator's cast list. Matching, not
/// ranking — `EditorState.cast` already counted the cues; this covers
/// search and the two ways of looking at the same rows.
@MainActor
final class CastListFilterTests: XCTestCase {

    private func cast() -> [CastRow] {
        [
            CastRow(id: "WALT", name: "WALT", cues: 5, firstCueID: UUID()),
            CastRow(id: "ANNA", name: "ANNA", cues: 3, firstCueID: UUID()),
            CastRow(id: "MIKE", name: "MIKE", cues: 3, firstCueID: UUID())
        ]
    }

    func testAnEmptyQueryLeavesEveryone() {
        XCTAssertEqual(CastListFilter.included(cast(), query: "").count, 3)
        XCTAssertEqual(CastListFilter.included(cast(), query: "   ").count, 3)
    }

    func testLeadIsMostCuesThenName() {
        let visible = CastListFilter.included(cast(), query: "", sort: .lead)
        XCTAssertEqual(visible.map(\.name), ["WALT", "ANNA", "MIKE"])
    }

    func testAlphabeticalOrdersByName() {
        let visible = CastListFilter.included(cast(), query: "", sort: .alphabetical)
        XCTAssertEqual(visible.map(\.name), ["ANNA", "MIKE", "WALT"])
    }

    func testANameFragmentNarrowsTheList() {
        let found = CastListFilter.included(cast(), query: "ann")
        XCTAssertEqual(found.map(\.name), ["ANNA"])
    }

    func testNothingMatchingIsEmptyRatherThanGuessed() {
        XCTAssertTrue(CastListFilter.included(cast(), query: "warehouse").isEmpty)
    }

    func testTheSearchAndTheSortCompose() {
        let lead = CastListFilter.included(cast(), query: "a", sort: .lead)
        XCTAssertEqual(lead.map(\.name), ["WALT", "ANNA"])
        let alpha = CastListFilter.included(cast(), query: "a", sort: .alphabetical)
        XCTAssertEqual(alpha.map(\.name), ["ANNA", "WALT"])
    }
}
