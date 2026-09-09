import XCTest
import EDraftCore
@testable import EDraftMacSurface

/// The reveal mark sits on the line it reveals — not one line under it.
///
/// `ScriptLayout.boundingRect` answers in the text view's coordinates, inset
/// included. The surface once added the inset again, and because the inset is
/// exactly one line of headroom, every mark landed one line low, on screen,
/// where no test was looking. This one looks.
@MainActor
final class RevealMarkPlacementTests: XCTestCase {

    func testTheMarkCoversTheRevealedLine() {
        let editor = EditorState(source: "INT. LAB - DAY\n\nDust hangs in the light.\n\nEXT. STREET - NIGHT\n\nRain.")
        let surface = ScriptSurface(measure: 640)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView?.addSubview(surface.scrollView)
        surface.scrollView.frame = window.contentView?.bounds ?? .zero

        let street = editor.scenes.last!
        XCTAssertTrue(surface.reveal(street.id))

        let heading = (surface.textView.string as NSString).range(of: "EXT. STREET - NIGHT")
        let line = ScriptLayout.boundingRect(of: heading, in: surface.textView)!
        let mark = surface.highlight.frame
        XCTAssertEqual(mark.midY, line.midY, accuracy: 1, "the mark is centred on the heading's own line")
        XCTAssertEqual(mark.minX, line.minX - RevealMark.horizontalPadding, accuracy: 1)
    }

    /// A reveal does not land flush against the chrome: it rests a quarter
    /// of the visible height below the top, so the lines that led to the
    /// mark — the exchange a cue answers — are still on the glass.
    func testARevealRestsBelowTheTopWithAir() {
        var elements: [ScriptElement] = []
        for beat in 1...40 {
            elements.append(ScriptElement(type: .scene, text: "INT. ROOM \(beat) - DAY"))
            elements.append(ScriptElement(
                type: .action, text: "Action for beat \(beat), held for a full line of the page."
            ))
        }
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView?.addSubview(surface.scrollView)
        surface.scrollView.frame = window.contentView?.bounds ?? .zero
        surface.scrollView.layoutSubtreeIfNeeded()
        // Settle the opening size before revealing, so the air is measured
        // against the same magnification the reveal computed with.
        surface.remeasure(to: 900, elements: editor.screenplay.elements)

        XCTAssertTrue(surface.reveal(elements[40].id))

        let heading = (surface.textView.string as NSString).range(of: "INT. ROOM 21 - DAY")
        let line = ScriptLayout.boundingRect(of: heading, in: surface.textView)!
        let clip = surface.scrollView.contentView
        let readableTop = clip.bounds.origin.y + surface.scrollView.contentInsets.top
        let belowTop = line.minY + surface.textView.frame.minY - readableTop
        XCTAssertEqual(
            belowTop, clip.bounds.height * 0.25, accuracy: 2,
            "the reveal landed flush against the top of the window"
        )
    }
}
