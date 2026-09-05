import XCTest
import SwiftUI
import EDraftCore
@testable import EDraftMacSurface

@MainActor
final class ElementModeControlTests: XCTestCase {
    func testEditingShowsContextualKindsFirst() {
        let editor = EditorState(source: "")
        let surface = ScriptSurface()
        surface.bind(to: editor)
        
        let notification = Notification(name: NSText.didBeginEditingNotification, object: surface.textView)
        surface.textDidBeginEditing(notification)
        
        XCTAssertTrue(editor.isEditing)
        
        let control = ElementModeControl(editor: editor)
        let body = String(describing: control.body)
        
        XCTAssertTrue(body.contains("Suggested"))
        XCTAssertTrue(body.contains("All Elements"))
    }
}
