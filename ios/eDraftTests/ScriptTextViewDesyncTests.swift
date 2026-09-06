import XCTest
import EDraftCore
@testable import EDraftUIKitSurface

@MainActor
final class ScriptTextViewDesyncTests: XCTestCase {
    func testAnEditTheStorageTakesButTheModelDoesNotIsReverted() {
        let editor = EditorState(source: "INT. CAFE\u{0301} - DAY")
        let coordinator = ScriptTextView.Coordinator(editor: editor)
        let textView = ScreenplayTextView(frame: .zero)
        coordinator.attach(to: textView)
        coordinator.renderModel(selecting: nil, offset: nil)
        
        let previousRevision = editor.revision
        
        // Mutate the text view natively. The string length changes from 16 to 15 (UTF-16).
        // Since "E\u{0301}" and "É" are canonically equivalent, the model will reject the edit.
        let storage = textView.textStorage
        storage.replaceCharacters(in: NSRange(location: 8, length: 2), with: "É")
        
        // Trigger textViewDidChange
        coordinator.textViewDidChange(textView)
        
        XCTAssertEqual(editor.revision, previousRevision, "Model should not have bumped revision")
        
        let nativeText = textView.text as NSString
        let expectedRange = nativeText.range(of: "E\u{0301}", options: .literal)
        XCTAssertTrue(expectedRange.location != NSNotFound, "Surface should revert to the model's decomposed text")
    }
}
