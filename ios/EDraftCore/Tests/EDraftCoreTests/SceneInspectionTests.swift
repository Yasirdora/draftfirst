import XCTest
@testable import EDraftCore

/// Scene properties the inspector reports. Two scenes, two voices in the
/// first, one in the second — a pane that listed DAVID in both would be
/// inventing a presence the script does not have.
@MainActor
final class SceneInspectionTests: XCTestCase {

    private let source = """
    Title: Inspection
    Credit: written by

    INT. LAB - DAY

    Hum.

    MARA
    One.

    DAVID
    Two.

    INT. HALL - NIGHT

    Quiet.

    MARA
    Three.

    """

    func testCharactersAreFirstSeenInTheSceneTheySpeak() {
        let editor = EditorState(source: source)
        let lab = editor.scenes[0]
        let hall = editor.scenes[1]
        let labInfo = editor.sceneInspection(containing: lab.id)
        let hallInfo = editor.sceneInspection(containing: hall.id)
        XCTAssertEqual(labInfo?.characters, ["MARA", "DAVID"])
        XCTAssertEqual(hallInfo?.characters, ["MARA"])
    }

    func testLengthCountsPrintingLinesIncludingTheHeading() {
        let editor = EditorState(source: source)
        let lab = editor.scenes[0]
        let info = editor.sceneInspection(containing: lab.id)
        // heading, action, MARA, one, DAVID, two
        XCTAssertEqual(info?.lines, 6)
        XCTAssertEqual(info?.row.title, "INT. LAB - DAY")
    }

    func testALineInsideTheSceneStillFindsTheHeading() {
        let editor = EditorState(source: source)
        let speech = editor.screenplay.elements.first { $0.text == "Two." }
        let info = editor.sceneInspection(containing: speech!.id)
        XCTAssertEqual(info?.row.title, "INT. LAB - DAY")
        XCTAssertEqual(editor.enclosingCharacterName(for: speech!.id), "DAVID")
    }

    func testActionDoesNotEncloseACharacter() {
        let editor = EditorState(source: source)
        let action = editor.screenplay.elements.first { $0.text == "Hum." }
        XCTAssertNil(editor.enclosingCharacterName(for: action!.id))
    }
}
