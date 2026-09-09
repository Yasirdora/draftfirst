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
}
