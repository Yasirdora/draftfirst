import XCTest
@testable import EDraftMacSurface

/// What the launch window decides, tested where the decision is made.
///
/// The window itself is SwiftUI and cannot be asserted without rendering it, so
/// nothing here pretends to. These are the choices a writer would notice if
/// they were wrong: a script listed twice, a script that is gone, a filename
/// where a title should be, a date said in arithmetic.
final class LaunchModelTests: XCTestCase {

    private let day = 60.0 * 60 * 24

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/edraft-launch/\(name)")
    }

    // MARK: - Which scripts

    func testTheSameScriptOpenedTwiceIsOneRow() {
        let rows = LaunchModel.rows(
            from: [url("Act One.draft"), url("Act One.draft")],
            exists: { _ in true },
            modified: { _ in nil }
        )
        XCTAssertEqual(rows.count, 1)
    }

    func testAScriptThatIsNoLongerThereIsNotOffered() {
        let gone = url("Deleted.draft")
        let rows = LaunchModel.rows(
            from: [gone, url("Here.draft")],
            exists: { $0 != gone },
            modified: { _ in nil }
        )
        XCTAssertEqual(rows.map(\.name), ["Here"], "a row that cannot be opened is worse than none")
    }

    func testTheListIsCappedSoTheWindowStaysAWindow() {
        let many = (1...20).map { url("Script \($0).draft") }
        let rows = LaunchModel.rows(from: many, exists: { _ in true }, modified: { _ in nil })
        XCTAssertEqual(rows.count, LaunchModel.limit)
        XCTAssertEqual(rows.first?.name, "Script 1", "newest first, as the controller supplies them")
    }

    func testTheRowSaysWhatTheWriterCalledItNotWhatTheFilesystemDoes() {
        let rows = LaunchModel.rows(
            from: [url("The Long Goodbye.draft")],
            exists: { _ in true },
            modified: { _ in nil }
        )
        XCTAssertEqual(rows.first?.name, "The Long Goodbye")
    }

    // MARK: - When

    func testTodayAndYesterdayHaveNamesRatherThanDates() {
        let now = Date()
        XCTAssertEqual(LaunchModel.when(now, now: now), "Today")
        XCTAssertEqual(LaunchModel.when(now.addingTimeInterval(-day), now: now), "Yesterday")
    }

    func testAnOlderScriptIsGivenADateNotArithmetic() {
        let now = Date()
        let older = now.addingTimeInterval(-day * 9)
        let said = LaunchModel.when(older, now: now)
        XCTAssertFalse(said.isEmpty)
        XCTAssertNotEqual(said, "Today")
        XCTAssertNotEqual(said, "Yesterday")
        XCTAssertFalse(
            said.contains("ago"),
            "\"9 days ago\" is arithmetic the reader has to undo; a date is not"
        )
    }

    func testAScriptWithNoModificationDateSaysNothingRatherThanGuessing() {
        XCTAssertEqual(LaunchModel.when(nil), "")
    }
}
