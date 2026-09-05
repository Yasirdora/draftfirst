import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// Shared drive for the Mac page, without a window.
///
/// Typing tests and ghost tests must not grow a second copy of this. The
/// caret is placed by setting the selection directly — never via `reveal`.
@MainActor
enum ScriptSurfaceHarness {

    static func bound(
        _ elements: [ScriptElement], active: Int = 0
    ) -> (EditorState, ScriptSurface) {
        let editor = EditorState(source: "An opening image.")
        editor.screenplay = Screenplay(titlePage: [], elements: elements)
        editor.activeElementID = elements[active].id
        editor.selectionOffset = (elements[active].text as NSString).length

        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        return (editor, surface)
    }

    /// Types the way a keyboard does: the delegate first, then the storage
    /// only when that returns true, then the change the surface listens to.
    @discardableResult
    static func type(
        _ replacement: String,
        into surface: ScriptSurface,
        at range: NSRange? = nil
    ) -> Bool {
        let textView = surface.textView
        let range = range ?? textView.selectedRange()
        let allowed = surface.textView(
            textView, shouldChangeTextIn: range, replacementString: replacement
        )
        if allowed {
            textView.textStorage?.replaceCharacters(in: range, with: replacement)
            textView.setSelectedRange(
                NSRange(
                    location: range.location + (replacement as NSString).length,
                    length: 0
                )
            )
            surface.textDidChange(
                Notification(name: NSText.didChangeNotification, object: textView)
            )
            surface.textViewDidChangeSelection(
                Notification(name: NSTextView.didChangeSelectionNotification, object: textView)
            )
        }
        return allowed
    }

    static func placeCaret(
        _ editor: EditorState,
        _ surface: ScriptSurface,
        on element: ScriptElement,
        atEnd: Bool = true
    ) {
        let mapped = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
            .first { $0.id == element.id }
        let location: Int
        if let mapped {
            location = atEnd ? NSMaxRange(mapped.range) : mapped.range.location
        } else {
            location = 0
        }
        surface.textView.setSelectedRange(NSRange(location: location, length: 0))
        surface.textViewDidChangeSelection(
            Notification(name: NSTextView.didChangeSelectionNotification, object: surface.textView)
        )
    }

    /// Predictions wait 65ms and then run off the main actor. Pump the run
    /// loop until `condition` holds, or fail.
    @discardableResult
    static func wait(
        timeout: TimeInterval = 2,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            // `run(mode:before:)` returns immediately when the loop is idle,
            // which starves the 65ms prediction Task. `run(until:)` actually
            // waits, so the MainActor job can resume.
            RunLoop.current.run(until: Date().addingTimeInterval(0.025))
        }
        return condition()
    }

    static func waitForGhost(
        _ editor: EditorState,
        _ surface: ScriptSurface,
        timeout: TimeInterval = 2
    ) -> Bool {
        guard wait(timeout: timeout, {
            (editor.currentSuggestionSuffix ?? "").isEmpty == false
        }) else { return false }
        // Draw after the engine has spoken, rather than racing the
        // 65ms callback. If present() cannot place the overlay, the
        // caller still sees a suffix without a frame.
        surface.updateGhost()
        return surface.isShowingGhost
    }

    static func waitForSuffix(
        _ editor: EditorState, timeout: TimeInterval = 2
    ) -> String? {
        _ = wait(timeout: timeout) {
            (editor.currentSuggestionSuffix ?? "").isEmpty == false
        }
        return editor.currentSuggestionSuffix
    }
}
