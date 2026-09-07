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
    /// The desk around the whole stack. Not the space between sheets — see
    /// `gap(after:)`, which used to be this same number and is why a page
    /// break looked like a gutter.
    var canvasPadding: CGFloat = 36

    /// How far apart two sheets stand when the writer has opened the break
    /// between them. Ten points: enough to read as two pages, little enough
    /// that the column is still a column.
    static let openBreakGap: CGFloat = 10

    /// Which breaks the writer has opened, by the index of the page above
    /// the break. Empty is the default and the resting state: the sheets
    /// meet, and the break is a line.
    private(set) var openBreaks: Set<Int> = []

    /// Toggling one is a re-layout — every page below it moves, and the text
    /// has to be pushed down to match — so the canvas asks rather than acts.
    var onToggleBreak: ((Int) -> Void)?

    private var breakHandles: [PageBreakHandle] = []

    var breakHandleFrames: [CGRect] { breakHandles.map(\.frame) }

    /// The space between page `index` and the one after it.
    func gap(after index: Int) -> CGFloat {
        openBreaks.contains(index) ? Self.openBreakGap : 0
    }

    /// Whether every break is currently open.
    var allBreaksOpen: Bool {
        guard pageViews.count > 1 else { return false }
        return openBreaks.count >= pageViews.count - 1
    }

    /// Opens every break in the document.
    func openAllBreaks(pageCount: Int) {
        let breaks = max(0, pageCount - 1)
        openBreaks = Set(0..<breaks)
    }

    /// Closes every break.
    func closeAllBreaks() {
        openBreaks.removeAll()
    }

    /// Where page `index`'s first line sits, measured from the first page's
    /// first line. The opened gaps are part of it, which is what makes
    /// everything below a break move when one is opened.
    func textTopOffset(ofPage index: Int) -> CGFloat {
        let pageHeight = PageFormat.current.pageRect.height
        var offset = CGFloat(index) * pageHeight
        for boundary in 0..<max(0, index) { offset += gap(after: boundary) }
        return offset
    }

    /// Opens a joined break or closes an opened one.
    func toggleBreak(after index: Int) {
        if openBreaks.contains(index) {
            openBreaks.remove(index)
        } else {
            openBreaks.insert(index)
        }
    }

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
        // The stack is the sheets plus whatever breaks the writer has opened
        // — not one gutter per break, which is what it was.
        let openGaps = (0..<max(0, pages - 1)).reduce(CGFloat(0)) { $0 + gap(after: $1) }
        let stackHeight = CGFloat(pages) * pageSize.height + openGaps
        // Exactly the pages and their desk — not the viewport. `CentringClipView`
        // puts a canvas smaller than the window in the middle of it, so this
        // stays the same size at every magnification and a pinch has nothing
        // to re-measure.
        let canvasWidth = pageSize.width + desk * 2
        let canvasHeight = stackHeight + desk * 2
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
                y: desk + textTopOffset(ofPage: index),
                width: pageSize.width,
                height: pageSize.height
            )
        }
        layOutBreakHandles(pages: pages, x: x, pageSize: pageSize, desk: desk)

        let textWidth = ScreenplayPageLayout.textBlockWidth(format)
        let textBlock = ScreenplayPageLayout.textBlockHeight(format)
        let lastTextBottom = textTopOffset(ofPage: pages - 1) + textBlock
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

    /// One handle per break, straddling the join.
    ///
    /// Above the text view, because the text view spans every page and would
    /// otherwise take the click; over the margins on either side, which the
    /// format leaves blank, so it never sits on type.
    private func layOutBreakHandles(
        pages: Int, x: CGFloat, pageSize: CGSize, desk: CGFloat
    ) {
        let breaks = max(0, pages - 1)
        while breakHandles.count < breaks {
            let handle = PageBreakHandle(frame: .zero)
            let index = breakHandles.count
            handle.onClick = { [weak self] in self?.onToggleBreak?(index) }
            breakHandles.append(handle)
            addSubview(handle, positioned: .above, relativeTo: textView)
        }
        while breakHandles.count > breaks {
            breakHandles.removeLast().removeFromSuperview()
        }

        for index in 0..<breaks {
            let join = desk + textTopOffset(ofPage: index) + pageSize.height
            let opened = gap(after: index)
            let height = max(opened, PageBreakHandle.closedHeight)
            breakHandles[index].isOpen = opened > 0
            breakHandles[index].frame = CGRect(
                x: x,
                y: join + (opened - height) / 2,
                width: pageSize.width,
                height: height
            )
        }
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
            // The caret goes with them, and it has to be handed a *resolved*
            // colour. `insertionPointColor` keeps whatever `NSTextView`
            // resolved when it was set, and assigning the same dynamic colour
            // again does not make it look afresh — so switching the page
            // between paper and dark left the old caret behind: dark on a
            // dark page, or white on white paper. Either way, gone.
            textView?.insertionPointColor =
                NSColor.screenplayInk.usingColorSpace(.sRGB) ?? .labelColor

            // Clear: the scroll view paints the desk, all the way to the
            // window's edges. The canvas is only as large as the pages, so a
            // colour here would stop at its edge and draw a border round them.
            layer?.backgroundColor = NSColor.clear.cgColor
            for page in pageViews {
                // Everything the card is made of, in one place. The corner,
                // the shadow and the border used to be set once in
                // `makePageView`, where a detached view has no layer yet and
                // the assignments go nowhere — the card then had no shadow
                // until something else happened to re-make it. Here they are
                // applied every time the appearance changes, by which point
                // there is always a layer.
                page.layer?.backgroundColor = NSColor.screenplayPaper.cgColor
                page.layer?.borderWidth = 0
                page.layer?.cornerRadius = 2
                page.layer?.shadowColor = NSColor.black.cgColor
                page.layer?.shadowRadius = 8
                page.layer?.shadowOffset = CGSize(width: 0, height: -1)
                page.layer?.shadowOpacity = 0.22
            }
        }
    }

    private func makePageView() -> FlippedView {
        let page = FlippedView()
        page.wantsLayer = true
        // What it looks like is `applyAppearance`'s, all of it — see there.
        return page
    }
}
