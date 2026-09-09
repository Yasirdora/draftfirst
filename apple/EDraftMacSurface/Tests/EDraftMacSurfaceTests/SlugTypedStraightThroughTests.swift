import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// Typing a slug the way a writer trained on any other screenwriting app types
/// one: straight through, spaces and all.
///
/// The dash key writes `" - "` and leaves the caret after it, so the space the
/// writer types next lands against one that is already there. Fountain still
/// reads the heading and so does `splitSceneHeading` — the cost is that the
/// double space reaches the page, the PDF and the file.
///
/// Found by typing into the running Mac app, not by a test, which is where
/// every defect this project has had was found.
@MainActor
final class SlugTypedStraightThroughTests: XCTestCase {

    private func typeSlug(_ slug: String) -> EditorState {
        let (editor, surface) = ScriptSurfaceHarness.bound([ScriptElement(type: .action, text: "")])
        for character in slug {
            ScriptSurfaceHarness.type(String(character), into: surface)
        }
        return editor
    }

    func testTheSpaceAfterTheDashIsNotTypedTwice() {
        let editor = typeSlug("int. kitchen - day")

        XCTAssertEqual(
            editor.screenplay.elements[0].text, "INT. KITCHEN - DAY",
            "the separator already carries its space; the writer's landed on top of it"
        )
    }

    /// The writer who does *not* type the space must still get the separator's.
    func testTheSeparatorStillSuppliesItsOwnSpace() {
        let editor = typeSlug("int. kitchen -day")

        XCTAssertEqual(editor.screenplay.elements[0].text, "INT. KITCHEN - DAY")
    }

    /// A hyphen inside a location is not a separator, and the escape that takes
    /// it back must survive this change.
    func testATightHyphenIsStillReachable() {
        let (editor, surface) = ScriptSurfaceHarness.bound([ScriptElement(type: .action, text: "")])
        for character in "int. drive-" {
            ScriptSurfaceHarness.type(String(character), into: surface)
        }
        ScriptSurfaceHarness.type("", into: surface, at: NSRange(
            location: surface.textView.selectedRange().location - 1, length: 1
        ))
        for character in "in - night" {
            ScriptSurfaceHarness.type(String(character), into: surface)
        }

        XCTAssertEqual(editor.screenplay.elements[0].text, "INT. DRIVE-IN - NIGHT")
    }
}
