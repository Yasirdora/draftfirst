import AppKit
import EDraftCore

/// The paper, sitting on the canvas.
///
/// The text view writes; this is the pages the text sits on — 612pt wide,
/// centred on `underPageBackgroundColor`, with the 1.5″ left margin the
/// PDF prints. The edge is the ruler a screenwriter reads length by.
/// Discrete sheets with desk between them, not one tall card with rules.
///
/// Appearance colours are applied in `viewDidChangeEffectiveAppearance`
/// because a layer's `cgColor` does not track dark/light on its own, and
/// a page card that only looks right in one of them has no edge in the other.
final class PageCanvasView: NSView {
    private(set) var pageViews: [FlippedView] = []
    private weak var textView: NSTextView?
    var canvasPadding: CGFloat = 36

    /// The first sheet — what callers mean by "the page" when they ask
    /// about width, the left margin, or the edge colour.
    var pageView: FlippedView {
        if let first = pageViews.first { return first }
        let page = makePageView()
        pageViews = [page]
        addSubview(page, positioned: .below, relativeTo: textView)
        return page
    }

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
        let first = makePageView()
        pageViews = [first]
        addSubview(first)
        addSubview(textView, positioned: .above, relativeTo: first)
        applyAppearance()
    }

    /// Places the cards in the viewport and the text view inside the
    /// first card's text block. Called the moment this view joins a
    /// window, which is the first moment a caret has anywhere to go.
    var onMoveToWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        onMoveToWindow?()
    }

    /// N letter-sized sheets with desk between them. `textHeight` is the
    /// laid-out script including exclusion gaps, so the text view fills
    /// through the last sheet's text block.
    func layoutPages(pageCount: Int, textHeight: CGFloat, viewport: CGSize) {
        let format = PageFormat.current
        let pageSize = format.pageRect.size
        let pages = max(1, pageCount)
        let desk = canvasPadding
        let stackHeight = CGFloat(pages) * pageSize.height + CGFloat(max(0, pages - 1)) * desk
        let canvasWidth = max(viewport.width, pageSize.width + desk * 2)
        let canvasHeight = max(viewport.height, stackHeight + desk * 2)
        setFrameSize(CGSize(width: canvasWidth, height: canvasHeight))

        let x = ((canvasWidth - pageSize.width) / 2).rounded(.down)
        while pageViews.count < pages {
            let page = makePageView()
            pageViews.append(page)
            addSubview(page, positioned: .below, relativeTo: textView)
        }
        while pageViews.count > pages {
            pageViews.removeLast().removeFromSuperview()
        }
        for index in 0..<pages {
            pageViews[index].frame = CGRect(
                x: x,
                y: desk + CGFloat(index) * (pageSize.height + desk),
                width: pageSize.width,
                height: pageSize.height
            )
        }

        let textWidth = ScreenplayPageLayout.textBlockWidth(format)
        let textBlock = ScreenplayPageLayout.textBlockHeight(format)
        let lastTextBottom = CGFloat(pages - 1) * (pageSize.height + desk) + textBlock
        // Headroom for a glyph taller than its line. The view starts one line
        // above the text block and insets the text back down by the same
        // amount, so the first line of type still sits exactly on `textTop`
        // while an emoji's ascent has somewhere to go instead of being cut off
        // by the view's own edge. On every other line the room is the line
        // above; on the first there is none.
        let slack = ScreenplayPageLayout.glyphOverflow
        textView?.textContainerInset = NSSize(width: 0, height: slack)
        textView?.frame = CGRect(
            x: x + ScreenplayPageLayout.textLeft,
            y: desk + format.textTop - slack,
            width: textWidth,
            height: max(textHeight, lastTextBottom, 1) + slack * 2
        )
        applyAppearance()
        needsDisplay = true
    }

    /// Back-compat for the one-card layout callers. Prefer `layoutPages`.
    func layoutPage(textHeight: CGFloat, viewport: CGSize) {
        layoutPages(pageCount: 1, textHeight: textHeight, viewport: viewport)
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
            for page in pageViews {
                page.layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
                page.layer?.borderColor = NSColor.separatorColor.cgColor
                page.layer?.borderWidth = 1
                page.layer?.shadowColor = NSColor.black.cgColor
            }
        }
    }

    private func makePageView() -> FlippedView {
        let page = FlippedView()
        page.wantsLayer = true
        page.layer?.cornerRadius = 2
        page.layer?.shadowRadius = 8
        page.layer?.shadowOffset = CGSize(width: 0, height: -1)
        page.layer?.shadowOpacity = 0.22
        return page
    }
}
