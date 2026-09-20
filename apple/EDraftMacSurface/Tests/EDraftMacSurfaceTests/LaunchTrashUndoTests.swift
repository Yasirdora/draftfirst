import XCTest
@testable import EDraftMacSurface

/// Put-back after Move to Trash, without rendering the banner.
final class LaunchTrashUndoTests: XCTestCase {

    private let original = URL(fileURLWithPath: "/tmp/edraft-launch/Night Train.draft")
    private let trashed = URL(fileURLWithPath: "/tmp/edraft-launch-trash/Night Train.draft")

    private var item: LaunchTrashUndo {
        LaunchTrashUndo(name: "Night Train", originalURL: original, trashURL: trashed)
    }

    func testTheBannerNamesTheScript() {
        XCTAssertEqual(item.message, "“Night Train” moved to Trash")
    }

    func testPutBackMovesTheFileHome() {
        var moved: (from: URL, to: URL)?
        let ok = item.putBack(
            exists: { $0 == trashed },
            move: { from, to in moved = (from, to) }
        )
        XCTAssertTrue(ok)
        XCTAssertEqual(moved?.from, trashed)
        XCTAssertEqual(moved?.to, original)
    }

    func testPutBackAfterTrashEmptiedDoesNotMoveAndReturnsFalse() {
        var moved = false
        let ok = item.putBack(
            exists: { _ in false },
            move: { _, _ in moved = true }
        )
        XCTAssertFalse(ok, "Undo must fail closed when the file is gone")
        XCTAssertFalse(moved, "a missing file must not be moved, and must not throw")
    }

    func testCanPutBackTracksWhetherTheTrashStillHoldsTheFile() {
        XCTAssertTrue(item.canPutBack(exists: { $0 == trashed }))
        XCTAssertFalse(item.canPutBack(exists: { _ in false }))
    }

    func testAFailedMoveDisablesQuietly() {
        let ok = item.putBack(
            exists: { $0 == trashed },
            move: { _, _ in throw CocoaError(.fileWriteUnknown) }
        )
        XCTAssertFalse(ok)
    }
}
