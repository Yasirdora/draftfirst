import XCTest
import SwiftUI
import EDraftCore
@testable import EDraftMacSurface

/// The element selector, which on a Mac is the only thing in the toolbar's
/// leading position and never anything else.
@MainActor
final class ElementMenuTests: XCTestCase {

    func testEditingShowsContextualKindsFirst() {
        let editor = EditorState(source: "")
        let surface = ScriptSurface()
        surface.bind(to: editor)

        let notification = Notification(name: NSText.didBeginEditingNotification, object: surface.textView)
        surface.textDidBeginEditing(notification)

        XCTAssertTrue(editor.isEditing)

        let menu = NSMenu()
        ScriptMenus.fillElementMenu(menu, for: editor)
        let titles = menu.items.map(\.title)

        XCTAssertEqual(titles.first, "Suggested")
        XCTAssertTrue(titles.contains("All Elements"))
        // The suggested kinds lead, in the order the caret's position ranks them.
        let suggested = Array(titles.dropFirst().prefix(editor.contextualKinds.count))
        XCTAssertEqual(suggested, editor.contextualKinds.map(\.title))
    }

    /// There is no reading mode on a Mac.
    ///
    /// The control used to become an "Edit" button whenever the page was not
    /// first responder, which meant it changed identity every time the writer
    /// clicked the Navigator — and meant a new document could not be typed
    /// into until they found the button. On a phone `isEditing` describes
    /// something the writer can see, the keyboard; on a Mac it describes
    /// which view holds focus, which says nothing about the document.
    func testTheControlNamesTheElementEvenWhenThePageIsNotFocused() {
        let editor = EditorState(source: "INT. LAB - DAY")
        XCTAssertFalse(editor.isEditing, "the premise of this test is an unfocused page")

        let window = ScriptWindowController(editor: editor)
        withExtendedLifetime(window) {
            XCTAssertEqual(
                window.elementControlTitle, editor.activeKind.shortTitle,
                "the toolbar names the element under the caret whether or not the page holds focus"
            )
        }
    }
}

/// A Mac document window opens ready to be typed into.
@MainActor
final class InitialFocusTests: XCTestCase {

    private func windowed() -> (EditorState, ScriptSurface, NSWindow) {
        let editor = EditorState(source: "INT. LAB - DAY")
        let surface = ScriptSurface(measure: 500)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView?.addSubview(surface.scrollView)
        surface.scrollView.frame = window.contentView?.bounds ?? .zero
        window.makeKeyAndOrderFront(nil)
        return (editor, surface, window)
    }

    func testTheCaretIsInThePageWhenTheWindowOpens() {
        let (editor, surface, window) = windowed()

        surface.takeInitialFocus()

        XCTAssertTrue(
            window.firstResponder === surface.textView,
            "⌘N gave a screenplay that could not be typed into until an Edit "
                + "button was found; TextEdit, Pages and Xcode all open ready"
        )
    }

    /// `isEditing` is not asserted above, and the reason is worth writing down.
    ///
    /// AppKit posts `textDidBeginEditing` when editing *begins* — a keystroke,
    /// a programmatic edit — not when a text view becomes first responder, and
    /// in a test process with no event loop pumping it does not arrive at all.
    /// So focus landing and `isEditing` becoming true are two different
    /// moments, which is the deeper reason chrome on this platform should not
    /// be built on that flag: it answers "is the writer mid-edit", not "can
    /// the writer type here", and the toolbar was asking the second question.
    func testFocusAndTheEditingFlagAreNotTheSameMoment() {
        let (editor, surface, window) = windowed()

        surface.takeInitialFocus()

        XCTAssertTrue(window.firstResponder === surface.textView)
        XCTAssertFalse(
            editor.isEditing,
            "if this now passes, AppKit reports editing on focus after all, and "
                + "the note above is stale"
        )
    }

    /// Focus is the writer's after that. Clicking the Navigator or the scene
    /// filter must not be undone by the next SwiftUI layout pass.
    func testFocusIsNotTakenBackOnLaterPasses() {
        let (_, surface, window) = windowed()
        surface.takeInitialFocus()
        window.makeFirstResponder(nil)

        surface.takeInitialFocus()

        XCTAssertFalse(
            window.firstResponder === surface.textView,
            "the page snatched focus back from whatever the writer had clicked"
        )
    }

    /// Before there is a window there is nowhere to put a caret, and asking
    /// must not consume the one chance to do it.
    func testAskingBeforeThereIsAWindowIsNotWasted() {
        let editor = EditorState(source: "INT. LAB - DAY")
        let surface = ScriptSurface(measure: 500)
        surface.bind(to: editor)

        surface.takeInitialFocus()
        XCTAssertFalse(editor.isEditing)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView?.addSubview(surface.scrollView)
        surface.takeInitialFocus()

        XCTAssertTrue(window.firstResponder === surface.textView)
    }
}
