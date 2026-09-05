import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// The inspector is hidden until summoned. Following the caret must not
/// open it — that would steal width from the page on every arrow key.
@MainActor
final class InspectorChromeTests: XCTestCase {

    func testTheInspectorStartsDismissed() {
        XCTAssertFalse(InspectorChrome().isPresented)
    }

    func testFollowingTheCaretDoesNotPresentTheInspector() {
        let chrome = InspectorChrome()
        chrome.follow(kind: .character)
        XCTAssertFalse(chrome.isPresented)
        XCTAssertEqual(chrome.segment, .character)
        chrome.follow(kind: .action)
        XCTAssertFalse(chrome.isPresented)
        XCTAssertEqual(chrome.segment, .scene)
    }

    func testTogglePresentsAndDismisses() {
        let chrome = InspectorChrome()
        chrome.toggle()
        XCTAssertTrue(chrome.isPresented)
        chrome.toggle()
        XCTAssertFalse(chrome.isPresented)
    }
}
