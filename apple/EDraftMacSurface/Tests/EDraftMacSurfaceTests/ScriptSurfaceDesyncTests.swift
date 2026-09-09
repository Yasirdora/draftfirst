import XCTest
import EDraftCore
@testable import EDraftMacSurface

@MainActor
final class ScriptSurfaceDesyncTests: XCTestCase {
    func testAnEditTheStorageTakesButTheModelDoesNotIsReverted() {
        let editor = EditorState(source: "INT. CAFE\u{0301} - DAY")
        let surface = ScriptSurface()
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        
        let previousRevision = editor.revision
        
        // Mutate the text view natively. The string length changes from 16 to 15 (UTF-16).
        // Since "E\u{0301}" and "É" are canonically equivalent, the model will reject the edit.
        let storage = surface.textView.textStorage!
        storage.replaceCharacters(in: NSRange(location: 8, length: 2), with: "É")
        
        // Trigger textDidChange
        surface.textDidChange(Notification(name: NSText.didChangeNotification, object: surface.textView))
        
        XCTAssertEqual(editor.revision, previousRevision, "Model should not have bumped revision")
        
        let nativeText = surface.textView.string as NSString
        let expectedRange = nativeText.range(of: "E\u{0301}", options: .literal)
        XCTAssertTrue(expectedRange.location != NSNotFound, "Surface should revert to the model's decomposed text")
    }
}
