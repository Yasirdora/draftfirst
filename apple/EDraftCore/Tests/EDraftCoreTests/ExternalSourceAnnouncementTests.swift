import EDraftEngine
import XCTest
@testable import EDraftCore

/// What a reload of the document says — IL-0099.
///
/// The iPhone announces every change that reaches it from outside. The Mac
/// reaches the same reload for the writer's own Revert To, which is not a
/// change from elsewhere, so it can ask for the text without the sentence.
@MainActor
final class ExternalSourceAnnouncementTests: XCTestCase {

    private let opened = "INT. KITCHEN - NIGHT\n\nThe kettle screams."
    private let changed = "INT. KITCHEN - NIGHT\n\nThe kettle screams. Then silence."

    func testAChangeFromOutsideIsAnnouncedByDefault() {
        let editor = EditorState(source: opened)
        editor.applyExternalSource(changed)
        XCTAssertEqual(editor.banner, "Updated elsewhere")
        XCTAssertEqual(editor.screenplay.elements.last?.text, "The kettle screams. Then silence.")
    }

    func testAQuietReloadAppliesTheTextWithoutAnnouncingIt() {
        let editor = EditorState(source: opened)
        editor.applyExternalSource(changed, announcing: false)
        XCTAssertNil(editor.banner)
        XCTAssertEqual(editor.screenplay.elements.last?.text, "The kettle screams. Then silence.")
    }

    /// A failure is never silenced: text the parser refuses — here, past its
    /// size limit — is reported even on a quiet reload, and the writer's own
    /// copy is kept.
    func testAnUnreadableChangeIsReportedEvenWhenQuiet() {
        let editor = EditorState(source: opened)
        let tooLong = String(repeating: "a", count: Fountain.defaultMaxSourceCharacters + 1)
        editor.applyExternalSource(tooLong, announcing: false)
        XCTAssertEqual(editor.banner, "A change from elsewhere couldn't be read")
        XCTAssertEqual(editor.screenplay.elements.last?.text, "The kettle screams.")
    }
}
