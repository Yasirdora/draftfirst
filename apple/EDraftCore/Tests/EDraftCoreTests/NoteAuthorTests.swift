import XCTest
@testable import EDraftCore

/// Reading a note's author out of its own words.
///
/// The asymmetry is the whole design: missing an author costs nothing, and
/// inventing one puts a name on a thought that was nobody's. Most of what
/// follows pins the second from happening.
final class NoteAuthorCandidateTests: XCTestCase {

    func testAPlainNoteOffersNobody() {
        XCTAssertNil(NoteAttribution.candidate(in: "too passive here"))
    }

    func testAPrefixBeforeAColonIsOffered() {
        let found = NoteAttribution.candidate(in: "Dir: too passive here")
        XCTAssertEqual(found?.name, "Dir")
        XCTAssertEqual(found?.body, "too passive here")
    }

    func testAFullNameIsOffered() {
        XCTAssertEqual(NoteAttribution.candidate(in: "Joe Jarvis: cut it")?.name, "Joe Jarvis")
    }

    func testOnlyTheFirstColonSplits() {
        let found = NoteAttribution.candidate(in: "Dir: the ratio is 3:1")
        XCTAssertEqual(found?.name, "Dir")
        XCTAssertEqual(found?.body, "the ratio is 3:1")
    }

    func testASentenceIsNotAName() {
        XCTAssertNil(NoteAttribution.candidate(in: "She turns, slowly: the room is empty"))
    }

    func testSomethingTooLongIsNotAName() {
        let long = String(repeating: "a", count: NoteAttribution.longestName + 1)
        XCTAssertNil(NoteAttribution.candidate(in: "\(long): no"))
    }

    func testAPrefixWithNoLetterIsNotAName() {
        XCTAssertNil(NoteAttribution.candidate(in: "12:30 — move this"))
    }

    func testAPrefixWithNoBodyIsNotAnAttribution() {
        XCTAssertNil(NoteAttribution.candidate(in: "Dir:"))
        XCTAssertNil(NoteAttribution.candidate(in: "Dir:   "))
    }
}

/// Which names the document is prepared to believe in.
final class NoteAuthorRosterTests: XCTestCase {

    func testOneOccurrenceIsNotAPerson() {
        XCTAssertTrue(NoteAttribution.roster(of: ["TODO: fix the slug"]).isEmpty)
    }

    func testTwoOccurrencesArePerson() {
        let roster = NoteAttribution.roster(of: ["Dir: louder", "Dir: cut this"])
        XCTAssertEqual(roster, ["Dir"])
    }

    func testTheSignatureIsBelievedOnSight() {
        let roster = NoteAttribution.roster(of: ["Amir: only note"], signature: "Amir")
        XCTAssertEqual(roster, ["Amir"])
    }

    func testTheSignatureIsMatchedWithoutRegardToCase() {
        let roster = NoteAttribution.roster(of: ["amir: only note"], signature: "AMIR")
        XCTAssertEqual(roster, ["amir"])
    }

    func testOneNameTypedTwoWaysIsOnePerson() {
        let roster = NoteAttribution.roster(of: ["Dir: louder", "dir: cut this"])
        XCTAssertEqual(roster, ["Dir"], "the first spelling should win")
    }

    func testATodoAmongRealAuthorsStaysUnattributed() {
        let notes = ["Dir: louder", "Dir: cut this", "TODO: fix the slug"]
        let roster = NoteAttribution.roster(of: notes)
        XCTAssertEqual(roster, ["Dir"])
        XCTAssertNil(NoteAttribution.author(of: "TODO: fix the slug", roster: roster))
    }

    func testAnAuthorInTheRosterYieldsTheBodyWithoutThePrefix() {
        let found = NoteAttribution.author(of: "Dir: louder", roster: ["Dir"])
        XCTAssertEqual(found?.name, "Dir")
        XCTAssertEqual(found?.body, "louder")
    }
}

/// Which colour each name gets.
final class NoteAuthorSlotTests: XCTestCase {

    func testEveryoneInADocumentGetsTheirOwnColour() {
        let roster: Set<String> = ["Dir", "JW", "Joe Jarvis", "Mario Moreno"]
        let slots = NoteAttribution.slots(for: roster)
        XCTAssertEqual(Set(slots.values).count, roster.count,
                       "four authors must not share a colour")
    }

    func testTheOrderIsTheRosterSortedSoItIsTheSameEverywhere() {
        let slots = NoteAttribution.slots(for: ["Mario Moreno", "Joe Jarvis"])
        XCTAssertEqual(slots["Joe Jarvis"], 0)
        XCTAssertEqual(slots["Mario Moreno"], 1)
    }

    func testTheSameRosterAlwaysGivesTheSameColours() {
        let roster: Set<String> = ["Dir", "Prod", "JW"]
        XCTAssertEqual(NoteAttribution.slots(for: roster), NoteAttribution.slots(for: roster))
    }

    func testMoreAuthorsThanColoursWrapsRatherThanCrashing() {
        let many = Set((0..<NoteAttribution.paletteSlots + 3).map { "Name\($0)" })
        let slots = NoteAttribution.slots(for: many)
        XCTAssertEqual(slots.count, many.count)
        XCTAssertTrue(slots.values.allSatisfy { (0..<NoteAttribution.paletteSlots).contains($0) })
    }
}

/// Signing.
final class NoteSignatureTests: XCTestCase {

    func testAnEmptyNoteIsSignedReadyToBeWrittenIn() {
        XCTAssertEqual(NoteAttribution.signed("", as: "Amir"), "Amir: ")
    }

    func testANoteIsSignedInFront() {
        XCTAssertEqual(NoteAttribution.signed("louder", as: "Amir"), "Amir: louder")
    }

    func testANoteThatAlreadyNamesSomebodyIsLeftAlone() {
        XCTAssertEqual(NoteAttribution.signed("Dir: louder", as: "Amir"), "Dir: louder")
    }

    func testNoSignatureSignsNothing() {
        XCTAssertEqual(NoteAttribution.signed("louder", as: "   "), "louder")
    }
}
