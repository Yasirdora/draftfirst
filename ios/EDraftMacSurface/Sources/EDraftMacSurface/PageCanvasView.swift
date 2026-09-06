import AppKit
import EDraftCore

/// The paper, sitting on the canvas.
///
/// The text view writes; this is the page the text sits on — 612pt wide,
/// centred on `underPageBackgroundColor`, with the 1.5″ left margin the
/// PDF prints. The edge is the ruler a screenwriter reads length by.
///
/// Appearance colours are applied in `viewDidChangeEffectiveAppearance`
/// because a layer's `cgColor` does not track dark/light on its own, and
/// a page card that only looks right in one of them has no edge in the other.
final class PageCanvasView: NSView {
    let pageView = FlippedView()
    private weak var textView: NSTextView?
    var canvasPadding: CGFloat = 36

    override var isFlipped: Bool { true }

    /// Matches the canvas and the text view. An unflipped card inside a
    /// flipped canvas puts y=72 at the bottom of the sheet, and a short
    /// window shows a blank page with the script scrolled off the foot.
    final class FlippedView: NSView {
        override var isFlipped: Bool { true }
    }

    func attach(_ textView: NSTextView) {
        self.textView = textView
        wantsLayer = true
        pageView.wantsLayer = true
        pageView.layer?.cornerRadius = 2
        pageView.layer?.shadowRadius = 8
        pageView.layer?.shadowOffset = CGSize(width: 0, height: -1)
        pageView.layer?.shadowOpacity = 0.22
        addSubview(pageView)
        pageView.addSubview(textView)
        applyAppearance()
    }

    /// Places the card in the viewport and the text view inside the card
    /// at the print margins. `textHeight` is the laid-out script; the card
    /// is never shorter than one letter page.
    /// Called the moment this view joins a window, which is the first moment
    /// a caret has anywhere to go. `ScriptSurface` uses it to put the writer
    /// in the page; SwiftUI's own update passes are not a reliable signal,
    /// because the first one runs before the view is in a window and there is
    /// no guarantee of a second.
    var onMoveToWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        onMoveToWindow?()
    }

    func layoutPage(textHeight: CGFloat, viewport: CGSize) {
        let format = PageFormat.current
        let pageSize = format.pageRect.size
        let textWidth = ScreenplayPageLayout.textBlockWidth(format)
        let pageHeight = max(
            pageSize.height,
            format.textTop + max(textHeight, 1) + format.textTop
        )
        let canvasWidth = max(viewport.width, pageSize.width + canvasPadding * 2)
        let canvasHeight = max(viewport.height, pageHeight + canvasPadding * 2)
        setFrameSize(CGSize(width: canvasWidth, height: canvasHeight))

        pageView.frame = CGRect(
            x: ((canvasWidth - pageSize.width) / 2).rounded(.down),
            y: canvasPadding,
            width: pageSize.width,
            height: pageHeight
        )
        // The text view fills the page's text block, not merely the lines
        // written so far. Sized to its glyphs it was a sliver at the top of an
        // otherwise empty sheet, and a sliver is the only place an I-beam
        // appears or a click lands — so the writer had to find one specific
        // strip of a full page to start typing.
        //
        // Where the text is longer than a page this is exactly the glyph
        // height, because `pageHeight` was derived from it two lines up; where
        // it is shorter, it is the whole block down to the bottom margin, and
        // clicking under the last line puts the caret at the end, which is
        // what every other editor does.
        textView?.frame = CGRect(
            x: ScreenplayPageLayout.textLeft,
            y: format.textTop,
            width: textWidth,
            height: max(pageHeight - format.textTop * 2, 1)
        )
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        // Subsequent page edges, so length is readable after page one.
        // The first page's bottom is the card's own edge when the script
        // still fits on one sheet; past that, a hairline every pageHeight.
        let pageHeight = PageFormat.current.pageRect.height
        NSColor.separatorColor.setStroke()
        var y = pageView.frame.minY + pageHeight
        while y < pageView.frame.maxY - 0.5 {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: pageView.frame.minX, y: y))
            path.line(to: NSPoint(x: pageView.frame.maxX, y: y))
            path.lineWidth = 1
            path.stroke()
            y += pageHeight
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }

    func applyAppearance() {
        // Layer `cgColor`s are snapshots. Taking them outside the view's
        // own appearance would paint a light page on a dark canvas (or
        // the reverse) and the edge would vanish in one of the two looks.
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.underPageBackgroundColor.cgColor
            pageView.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
            pageView.layer?.borderColor = NSColor.separatorColor.cgColor
            pageView.layer?.borderWidth = 1
            pageView.layer?.shadowColor = NSColor.black.cgColor
        }
    }
}
