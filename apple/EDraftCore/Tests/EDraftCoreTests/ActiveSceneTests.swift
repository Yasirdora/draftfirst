import XCTest
@testable import EDraftCore

/// The Navigator's "you are here" mark: which scene the caret is in.
///
/// A scene owns everything from its heading down to the next heading, so the
/// mark is a derivation over the document rather than a property a click
/// sets — choosing a row lights it because the jump lands the caret there,
/// and clicking into a paragraph moves it without the Navigator being
/// involved.
@MainActor
final class ActiveSceneTests: XCTestCase {

    private let script = """
    FADE IN:

    INT. LAB - DAY

    She waits by the centrifuge.

    INT. CORRIDOR - LATER

    He runs.

    EXT. ROOFTOP - NIGHT

    They argue.
    """

    private func editor(_ source: String) -> EditorState {
        EditorState(source: source)
    }

    /// The caret opens on the first element — FADE IN: — which is above every
    /// heading, and above the first heading there is no scene to be in.
    func testTheCaretAboveTheFirstHeadingIsInNoScene() {
        let editor = editor(script)
        XCTAssertEqual(editor.scenes.count, 3)
        XCTAssertNil(editor.activeSceneID)
    }

    /// The active element inside a scene is dialogue or action far more
    /// often than it is a slug; the mark must still name the scene overhead.
    func testASceneOwnsEverythingDownToTheNextHeading() {
        let editor = editor(script)
        let scenes = editor.scenes

        let corridorAction = editor.screenplay.elements.firstIndex { $0.text == "He runs." }!
        editor.selectionChanged(
            elementID: editor.screenplay.elements[corridorAction].id, offset: 0
        )
        XCTAssertEqual(
            editor.activeSceneID, scenes[1].id,
            "the caret in the corridor's action is in the corridor's scene"
        )
    }

    /// A caret on the heading itself is in that heading's scene, not the one
    /// above it.
    func testAHeadingIsInItsOwnScene() {
        let editor = editor(script)
        let rooftop = editor.scenes[2]
        editor.jump(to: rooftop.id)
        XCTAssertEqual(editor.activeSceneID, rooftop.id)
    }

    /// What a Navigator row does: the jump moves the caret, and the mark
    /// follows the caret — the row lights because of where the writer now
    /// is, not because of what they clicked.
    func testTheMarkFollowsAJumpFromTheNavigator() {
        let editor = editor(script)
        let lab = editor.scenes[0]
        editor.jump(to: lab.id)
        XCTAssertEqual(editor.activeSceneID, lab.id)

        // And it leaves when the caret does.
        let rooftop = editor.scenes[2]
        editor.jump(to: rooftop.id)
        XCTAssertEqual(editor.activeSceneID, rooftop.id)
    }

    func testAScriptWithNoScenesMarksNothing() {
        let editor = editor("Just action, no headings at all.")
        XCTAssertNil(editor.activeSceneID)
    }
}
