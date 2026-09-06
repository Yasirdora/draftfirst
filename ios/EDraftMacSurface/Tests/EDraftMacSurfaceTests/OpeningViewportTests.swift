import AppKit
import EDraftCore
import SwiftUI
import XCTest
@testable import EDraftMacSurface

/// A document opens showing its first line, at the top of the page.
///
/// The existing short-window test only asks whether the first line
/// *intersects* the clip view. A line cut in half at the top still
/// intersects, which is how this shipped green. The contract is
/// `contentView.bounds.origin.y == 0` after the first layout of a
/// multi-page script in a window — and the window has to be SwiftUI's,
/// because a bare `ScriptSurface` magnifies before it joins a window
/// and never moves y.
@MainActor
final class OpeningViewportTests: XCTestCase {

    /// Starts on action, as the report did, and is long enough that the
    /// page can actually move.
    private func elements() -> [ScriptElement] {
        var elements = [
            ScriptElement(
                type: .action,
                text: "An opening image. The city holds its breath before the cut."
            )
        ]
        for beat in 1...20 {
            elements.append(ScriptElement(type: .scene, text: "INT. ROOM \(beat) - DAY"))
            elements.append(ScriptElement(
                type: .action,
                text: "Action for beat \(beat). The road holds its breath."
            ))
            elements.append(ScriptElement(type: .character, text: "MARA"))
            elements.append(ScriptElement(
                type: .dialogue,
                text: "Line \(beat), spoken plainly and without hurry at all."
            ))
        }
        return elements
    }

    private func editor(_ elements: [ScriptElement]) -> EditorState {
        let editor = EditorState(source: "An opening image.")
        editor.screenplay = Screenplay(titlePage: [], elements: elements)
        editor.activeElementID = elements[0].id
        editor.selectionOffset = 0
        return editor
    }

    /// Offset 0 on the first element, which is how a document actually
    /// opens. The typing harness parks the caret at the end; that is a
    /// different moment.
    private func bound(_ elements: [ScriptElement]) -> (EditorState, ScriptSurface) {
        let editor = editor(elements)
        let surface = ScriptSurface(measure: 900)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        return (editor, surface)
    }

    @discardableResult
    private func windowed(_ surface: ScriptSurface) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        surface.scrollView.frame = window.contentView?.bounds
            ?? NSRect(x: 0, y: 0, width: 900, height: 600)
        window.contentView?.addSubview(surface.scrollView)
        window.makeKeyAndOrderFront(nil)
        surface.scrollView.layoutSubtreeIfNeeded()
        return window
    }

    /// Host `ScriptPageView` the way a document window does, so
    /// magnification is applied after the clip view has its real size.
    private func hosted(_ elements: [ScriptElement]) -> (NSWindow, NSScrollView) {
        let hosting = NSHostingView(rootView: ScriptPageView(editor: editor(elements)))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 860),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.contentView = hosting
        hosting.frame = window.contentView?.bounds ?? .zero
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let scroll = firstScrollView(in: hosting)
        scroll?.layoutSubtreeIfNeeded()
        return (window, scroll ?? NSScrollView())
    }

    private func firstScrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for child in view.subviews {
            if let found = firstScrollView(in: child) { return found }
        }
        return nil
    }

    /// The contract the owner named. SwiftUI's first layout is the one
    /// that crops: the page is sized at 100%, then magnified to 150%
    /// about the clip-view centre, which is 143pt down an 860pt window.
    func testADocumentOpensAtTheTopOfThePage() throws {
        let elements = elements()
        let (window, scroll) = hosted(elements)
        _ = window

        XCTAssertEqual(
            scroll.contentView.bounds.origin.y, 0, accuracy: 0.5,
            "the page opened at y=\(scroll.contentView.bounds.origin.y) rather than at the top"
        )
        XCTAssertEqual(scroll.magnification, PageZoom.opening, accuracy: 0.05)

        let first = try XCTUnwrap(ScreenplayEditPlanner.ranges(for: elements).first)
        let textView = try XCTUnwrap(firstTextView(in: scroll))
        let firstRect = try XCTUnwrap(
            ScriptLayout.boundingRect(of: first.range, in: textView)
        )
        let inClip = textView.convert(firstRect, to: scroll.contentView)
        XCTAssertTrue(
            scroll.contentView.bounds.insetBy(dx: 0, dy: -0.5).contains(inClip),
            "the first line \(inClip) is not fully inside the visible rect \(scroll.contentView.bounds)"
        )
    }

    /// If this fails (y still 0) while the contract above fails, the
    /// crop is not the opening zoom. Measured: it is. Stubbing the pin
    /// leaves y at 143 on an 860pt window — `height/2 * (1 - 1/1.5)`.
    func testWithoutTheOpeningPinThePageOpensOffTheTop() throws {
        let elements = elements()
        let editor = editor(elements)
        let surface = ScriptSurface()
        surface.pinsOpeningViewport = false
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)

        let hosting = NSHostingView(rootView: ScriptPageHost(surface: surface))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 860),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.contentView = hosting
        hosting.frame = window.contentView?.bounds ?? .zero
        window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.takeInitialFocus()
        surface.applyZoomForCurrentSize()

        XCTAssertGreaterThan(
            surface.scrollView.contentView.bounds.origin.y, 0.5,
            "without the pin the opening zoom still left the page at the top; the crop is somewhere else"
        )
        XCTAssertEqual(
            surface.scrollView.magnification, PageZoom.opening, accuracy: 0.05
        )
        _ = window
    }

    /// The pin is once, on open. A size the writer asks for later must
    /// not jump them back to page one.
    func testALaterZoomDoesNotJumpThePageToTheTop() throws {
        let elements = elements()
        let (_, surface) = bound(elements)
        _ = windowed(surface)
        surface.takeInitialFocus()
        surface.applyZoomForCurrentSize()

        XCTAssertTrue(surface.reveal(elements[elements.count - 4].id))
        let afterReveal = surface.scrollView.contentView.bounds.origin.y
        XCTAssertGreaterThan(afterReveal, 0.5, "the reveal must have moved the page or this test cannot speak")

        surface.applyZoom(.zoomIn)

        XCTAssertGreaterThan(
            surface.scrollView.contentView.bounds.origin.y, 100,
            "choosing a size jumped the writer back to the top of the document (y=\(surface.scrollView.contentView.bounds.origin.y))"
        )
    }

    private func firstTextView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        for child in view.subviews {
            if let found = firstTextView(in: child) { return found }
        }
        return nil
    }
}

/// Puts an already-built surface on screen, so a test can flip
/// `pinsOpeningViewport` before SwiftUI sizes the clip view.
private struct ScriptPageHost: NSViewRepresentable {
    let surface: ScriptSurface

    func makeNSView(context: Context) -> NSScrollView {
        surface.scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        surface.applyZoomForCurrentSize()
    }
}
