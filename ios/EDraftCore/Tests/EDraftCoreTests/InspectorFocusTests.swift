import XCTest
@testable import EDraftCore

/// Which inspector section a selection proposes. A view must not decide
/// this — a cue is a character whether the pane is on a desk or in a hand.
@MainActor
final class InspectorFocusTests: XCTestCase {

    func testACueProposesTheCharacterSection() {
        XCTAssertEqual(InspectorFocus.proposed(for: .character), .character)
    }

    func testDialogueAndAParentheticalProposeTheCharacterSection() {
        XCTAssertEqual(InspectorFocus.proposed(for: .dialogue), .character)
        XCTAssertEqual(InspectorFocus.proposed(for: .parenthetical), .character)
        XCTAssertEqual(InspectorFocus.proposed(for: .lyrics), .character)
    }

    func testASceneAndActionProposeTheSceneSection() {
        XCTAssertEqual(InspectorFocus.proposed(for: .scene), .scene)
        XCTAssertEqual(InspectorFocus.proposed(for: .action), .scene)
        XCTAssertEqual(InspectorFocus.proposed(for: .shot), .scene)
        XCTAssertEqual(InspectorFocus.proposed(for: .transition), .scene)
    }

    func testNoSelectionProposesTheTitlePage() {
        XCTAssertEqual(InspectorFocus.proposed(for: nil), .title)
    }

    func testRevisionIsNotASection() {
        XCTAssertEqual(InspectorFocus.allCases.map(\.rawValue), ["title", "scene", "character"])
    }
}
