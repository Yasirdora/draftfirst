import XCTest
@testable import EDraftCore

/// The blast-radius sentence. Copied out of CharacterThreadView so the
/// Mac's Cast thread and the phone cannot drift.
final class CharacterRenameTests: XCTestCase {

    func testANameWithNoMentionsStatesTheCueCount() {
        XCTAssertEqual(
            CharacterRename.warning(name: "MARA", cues: 3, mentions: 0, merges: false),
            "Renames 3 cues for MARA."
        )
    }

    func testASingularCueIsNotPluralised() {
        XCTAssertEqual(
            CharacterRename.warning(name: "MARA", cues: 1, mentions: 0, merges: false),
            "Renames 1 cue for MARA."
        )
    }

    func testMentionsAreNamedBeforeAnythingMoves() {
        XCTAssertEqual(
            CharacterRename.warning(name: "WILL", cues: 2, mentions: 4, merges: false),
            "Renames 2 cues. WILL is also named 4 times in action and dialogue."
        )
    }

    func testAMergeIsAnnounced() {
        let text = CharacterRename.warning(name: "MARA", cues: 1, mentions: 0, merges: true)
        XCTAssertTrue(text.contains("two characters merge"))
    }
}
