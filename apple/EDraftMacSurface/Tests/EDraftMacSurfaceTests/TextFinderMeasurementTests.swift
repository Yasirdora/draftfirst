import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// What AppKit actually does with Find, measured — not inferred from the docs.
///
/// These answers decide whether Replace ships. A Replace All that writes the
/// storage behind the planner is the failure `ScriptSurface` exists to prevent.
@MainActor
final class TextFinderMeasurementTests: XCTestCase {

    private final class Probe: NSObject, NSTextViewDelegate {
        var shouldChangeCalls: [(NSRange, String?)] = []
        var textDidChangeCount = 0

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            shouldChangeCalls.append((affectedCharRange, replacementString))
            return true
        }

        func textDidChange(_ notification: Notification) {
            textDidChangeCount += 1
        }
    }

    private func assembledView() -> (NSTextView, NSScrollView, Probe) {
        let container = NSTextContainer(size: CGSize(width: 400, height: 10_000))
        container.widthTracksTextView = true
        let layout = NSLayoutManager()
        let storage = NSTextStorage()
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let textView = NSTextView(
            frame: NSRect(x: 0, y: 0, width: 400, height: 200),
            textContainer: container
        )
        textView.isRichText = false
        textView.string = "INT. KITCHEN - DAY\n\nMARA\nKeep moving."
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 240))
        scroll.documentView = textView
        scroll.hasVerticalScroller = true

        let probe = Probe()
        textView.delegate = probe
        return (textView, scroll, probe)
    }

    /// `insertText` is the typing path. If this does not hit the delegate,
    /// the rest of the measurements are on a broken harness.
    func testInsertTextRoutesThroughTheDelegate() {
        let (textView, _, probe) = assembledView()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.insertText("X", replacementRange: NSRange(location: 0, length: 0))
        XCTAssertFalse(
            probe.shouldChangeCalls.isEmpty,
            "insertText did not call shouldChangeTextIn — the harness is wrong"
        )
    }

    /// NSTextFinder Replace talks to the text view through
    /// `replaceCharacters(in:with:)`. If that call does not go through
    /// `shouldChangeTextIn`, Replace must not ship.
    func testReplaceCharactersDoesNotCallShouldChange() {
        let (textView, _, probe) = assembledView()
        let before = textView.string
        textView.replaceCharacters(in: NSRange(location: 0, length: 3), with: "EXT")
        XCTAssertEqual(
            probe.shouldChangeCalls.count, 0,
            "replaceCharacters hit shouldChange — Replace can ship through the planner"
        )
        XCTAssertNotEqual(
            textView.string, before,
            "replaceCharacters did not change the storage, so the measurement is empty"
        )
        XCTAssertEqual(probe.textDidChangeCount, 0)
    }

    /// Replacing the whole storage after asking for the find bar. Needs a
    /// window for the bar to exist; records whether the bar stays up.
    func testAFindBarSessionAgainstAFullRender() {
        let (textView, scroll, _) = assembledView()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        XCTAssertTrue(window.makeFirstResponder(textView))

        textView.performFindPanelAction(nil)
        let barWasVisible = scroll.isFindBarVisible

        textView.textStorage?.setAttributedString(
            ScriptLayout.attributedScript(
                [
                    ScriptElement(type: .scene, text: "INT. KITCHEN - DAY"),
                    ScriptElement(type: .action, text: "She waits.")
                ],
                measure: 400
            ).text
        )

        let barStillVisible = scroll.isFindBarVisible
        window.close()

        // A windowed `performFindPanelAction(nil)` did not show a bar in this
        // harness (barWasVisible=\(barWasVisible)). The system find bar needs
        // a hand pass; this test exists to notice if a full render crashes.
        XCTAssertEqual(barStillVisible, barWasVisible)
        _ = barWasVisible
    }
}
