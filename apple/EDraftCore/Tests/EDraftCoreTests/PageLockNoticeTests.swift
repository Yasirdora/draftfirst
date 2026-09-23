import EDraftEngine
import UniformTypeIdentifiers
import XCTest
@testable import EDraftCore

/// The notice a writer gets on editing a Final Draft file with page locks —
/// IL-0090.
///
/// Final Draft moves each `<LockedPage Position>` with the text; eDraft's
/// save does not yet. So the first edit of a locked file is the moment the
/// saved locks may start pointing at the wrong text in Final Draft, and the
/// writer is told — once per document per session, never at open, never for
/// a file that has no locks.
@MainActor
final class PageLockNoticeTests: XCTestCase {

    /// A Final Draft file with two locked pages, laid out the way Final Draft
    /// writes the block: after `</MoresAndContinueds>`, one entry per page.
    private func locked(_ pages: Int = 2) -> Data {
        let entries = (0..<pages).map {
            "<LockedPage Deleted=\"0\" LevelIndex=\"\($0)\" LockLevel=\"0\" PageNumber=\"\($0 + 1)\" Position=\"\($0 * 120)\"/>"
        }
        return Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        <Paragraph Type="Scene Heading"><Text>INT. KITCHEN - NIGHT</Text></Paragraph>
        <Paragraph Type="Action"><Text>The kettle screams.</Text></Paragraph>
        <Paragraph Type="Scene Heading"><Text>EXT. THE YARD - DUSK</Text></Paragraph>
        <Paragraph Type="Action"><Text>Mara waits.</Text></Paragraph>
        </Content>
        <MoresAndContinueds>
        <FontSpec Style=""/>
        </MoresAndContinueds>
        <LockedPages>
        \(entries.joined(separator: "\n"))
        </LockedPages>
        </FinalDraft>
        """.utf8)
    }

    private func unlocked() -> Data {
        let file = String(decoding: locked(), as: UTF8.self)
        let start = file.range(of: "<LockedPages>")!.lowerBound
        let end = file.range(of: "</LockedPages>")!.upperBound
        return Data(file.replacingCharacters(in: start..<end, with: "").utf8)
    }

    private func opened(_ data: Data, as type: UTType = .finalDraftScreenplay) throws -> EditorState {
        let file = try ScreenplayFile.open(data, as: type)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        return editor
    }

    /// A structural edit — the same road the surface takes for a Return,
    /// a paste or an omit.
    private func edit(_ editor: EditorState, appending text: String = " Then silence.") {
        var elements = editor.screenplay.elements
        let last = elements.count - 1
        elements[last].text += text
        editor.replaceAllElements(elements, activeID: elements[last].id, offset: 0, structural: true)
    }

    // MARK: - Reading the locks

    func testTheLocksAreCountedFromTheBlock() {
        XCTAssertEqual(FinalDraftPageLocks.count(inOrigin: String(decoding: locked(23), as: UTF8.self)), 23)
        XCTAssertEqual(FinalDraftPageLocks.count(inOrigin: String(decoding: unlocked(), as: UTF8.self)), 0)
        XCTAssertEqual(FinalDraftPageLocks.count(inOrigin: "<FinalDraft><LockedPages></LockedPages></FinalDraft>"), 0)
        XCTAssertEqual(FinalDraftPageLocks.count(inOrigin: "<FinalDraft><LockedPages/></FinalDraft>"), 0)
    }

    // MARK: - When it is raised

    func testNothingIsSaidAtOpen() throws {
        let editor = try opened(locked())
        XCTAssertNil(editor.pageLockNotice)
    }

    func testTheFirstEditRaisesIt() throws {
        let editor = try opened(locked())
        edit(editor)
        XCTAssertEqual(editor.pageLockNotice, EditorState.pageLockNoticeText)
    }

    func testTypingIsAnEdit() throws {
        let editor = try opened(locked())
        let element = try XCTUnwrap(editor.screenplay.elements.last)
        let text = element.text + "!"
        editor.applyLiveText(
            id: element.id, text: text, selectionOffset: text.utf16.count,
            replaced: NSRange(location: element.text.utf16.count, length: 0), insertedLength: 1
        )
        XCTAssertEqual(editor.pageLockNotice, EditorState.pageLockNoticeText)
    }

    func testAnUndoIsAnEdit() throws {
        /* An edit made before the file's locks were attached leaves an undo
           step whose own undo is then the first edit of the locked file. */
        let data = locked()
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        edit(editor)
        editor.attachImportedNotes(from: file.origin)
        XCTAssertNil(editor.pageLockNotice)
        editor.undo()
        XCTAssertEqual(editor.pageLockNotice, EditorState.pageLockNoticeText)
    }

    // MARK: - Once per document per session

    func testItIsSaidOnce() throws {
        let editor = try opened(locked())
        edit(editor)
        editor.dismissPageLockNotice()
        XCTAssertNil(editor.pageLockNotice)
        edit(editor, appending: " And again.")
        XCTAssertNil(editor.pageLockNotice, "dismissed is dismissed")
        editor.undo()
        XCTAssertNil(editor.pageLockNotice)
    }

    func testRevertDoesNotSayItAgain() throws {
        let data = locked()
        let editor = try opened(data)
        edit(editor)
        editor.dismissPageLockNotice()
        // Revert To: the same file attached again under the same window.
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        editor.applyExternalSource(file.source)
        editor.attachImportedNotes(from: file.origin)
        edit(editor)
        XCTAssertNil(editor.pageLockNotice, "once per document per session")
    }

    // MARK: - Never where it does not apply

    func testAFileWithoutLocksSaysNothing() throws {
        let editor = try opened(unlocked())
        edit(editor)
        XCTAssertNil(editor.pageLockNotice)
    }

    func testAFountainDocumentSaysNothing() throws {
        let editor = try opened(Data("INT. KITCHEN - NIGHT\n\nThe kettle screams.\n".utf8), as: .plainText)
        edit(editor)
        XCTAssertNil(editor.pageLockNotice)
    }

    // MARK: - Nothing written changes

    func testTheSaveIsWhatItWas() throws {
        /* The notice is words on the screen; the file eDraft writes is the
           file it wrote before — locks included, byte for byte. */
        let data = locked()
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let saved = try ScreenplayFile.encode(file.source, as: .finalDraftScreenplay, origin: file.origin)
        XCTAssertEqual(saved, data)
    }
}
