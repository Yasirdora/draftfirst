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
    /// The desk around the whole stack. Not the space between sheets: those
    /// meet, and used to stand this far apart, which is why a page boundary
    /// read as a gutter.
    var canvasPadding: CGFloat = 36

    /// How far apart two sheets stand in `pages`.
    ///
    /// Five points: enough that each page is plainly its own sheet with its
    /// own edge and shadow, little enough that the column still reads as one
    /// script. The old 36 was the desk's own padding used for two jobs, and
    /// a gutter that size every fifty-five lines is what made the read break.
    static let pageGap: CGFloat = 5

    /// Sheets, or one column. See `PageLayoutMode`; the canvas only draws
    /// what it is told.
    ///
    /// Pages by default rather than the stored preference: a view that reads
    /// a global at construction makes every test that builds one depend on
    /// what some earlier test happened to leave in `UserDefaults`. The
    /// writer's choice arrives through the model, in `bind(to:)`.
    var layoutMode: PageLayoutMode = .pages

    private var breakMarkers: [PageBreakMarker] = []
    private var noteMarkers: [NoteMarker] = []

    var breakMarkerFrames: [CGRect] { breakMarkers.map(\.frame) }
    var breakMarkerPageNumbers: [Int] { breakMarkers.compactMap(\.pageNumber) }
    var noteMarkerFrames: [CGRect] { noteMarkers.map(\.frame) }

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

    /// The counterpart: the view left its window — closed, or torn down.
    /// A pinch in flight at that moment never sends its `didEnd`, and the
    /// surface needs to hear that or it goes on believing the fingers are
    /// still down.
    var onLeaveWindow: (() -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { onMoveToWindow?() } else { onLeaveWindow?() }
    }

    /// N letter-sized sheets with desk between them. `textHeight` is the
    /// laid-out script including exclusion gaps, so the text view fills
    /// through the last sheet's text block.
    func layoutPages(pageCount: Int, textHeight: CGFloat, viewport: CGSize) {
        let format = PageFormat.current
        let pageSize = format.pageRect.size
        let pages = max(1, pageCount)
        let desk = canvasPadding
        let slack = ScreenplayPageLayout.glyphOverflow
        let textWidth = ScreenplayPageLayout.textBlockWidth(format)
        let textBlock = ScreenplayPageLayout.textBlockHeight(format)

        // How tall the stack of paper is. In `pages` it is the sheets, which
        // meet; in `continuous` it is one sheet as tall as the script plus the
        // margins it opens and closes with — the ones *between* pages are the
        // 132 points the mode exists to collapse.
        let stackHeight: CGFloat = switch layoutMode {
        case .pages:
            CGFloat(pages) * pageSize.height + CGFloat(pages - 1) * Self.pageGap
        case .continuous:
            format.textTop + max(textHeight, textBlock) + ScreenplayPageLayout.textBottom(format)
        }

        // Exactly the paper and its desk — not the viewport. `CentringClipView`
        // puts a canvas smaller than the window in the middle of it, so this
        // stays the same size at every magnification and a pinch has nothing
        // to re-measure.
        let canvasWidth = pageSize.width + desk * 2
        setFrameSize(CGSize(width: canvasWidth, height: stackHeight + desk * 2))

        let x = ((canvasWidth - pageSize.width) / 2).rounded(.down)
        let sheets = layoutMode == .pages ? pages : 1
        while pageViews.count < sheets {
            let page = makePageView()
            pageViews.append(page)
            addSubview(page, positioned: .below, relativeTo: textView)
        }
        while pageViews.count > sheets {
            pageViews.removeLast().removeFromSuperview()
        }
        for index in 0..<sheets {
            pageViews[index].frame = CGRect(
                x: x,
                y: desk + CGFloat(index) * (pageSize.height + Self.pageGap),
                width: pageSize.width,
                height: layoutMode == .pages ? pageSize.height : stackHeight
            )
        }

        // Headroom for a glyph taller than its line. The view starts one line
        // above the text block and insets the text back down by the same
        // amount, so the first line of type still sits exactly on `textTop`
        // while an emoji's ascent has somewhere to go instead of being cut off
        // by the view's own edge. On every other line the room is the line
        // above; on the first there is none.
        let lastTextBottom =
            CGFloat(pages - 1) * (pageSize.height + Self.pageGap) + textBlock
        textView?.textContainerInset = NSSize(width: 0, height: slack)
        textView?.frame = CGRect(
            x: x + ScreenplayPageLayout.textLeft,
            y: desk + format.textTop - slack,
            width: textWidth,
            height: max(textHeight, layoutMode == .pages ? lastTextBottom : textHeight, 1) + slack * 2
        )
        applyAppearance()
        needsDisplay = true
    }

    /// Puts a marker at each page boundary.
    ///
    /// The positions come from the surface, because the surface is what laid
    /// the text out and knows where each page's first line landed; deriving
    /// them twice is how the type and the paper come to disagree. The page
    /// number is drawn only in `continuous`, where the marker is the only
    /// thing saying a page ended — in `pages` the sheets' own edges say it.
    /// Where a page begins, and which page it is.
    ///
    /// The two travel together on purpose. The number used to be the marker's
    /// index in this array plus two, and the array was built with a
    /// `compactMap` — so a page start whose rectangle did not resolve did not
    /// merely lose its own mark, it renamed every mark below it. A page
    /// number a production schedules against, wrong by one, and wrong by more
    /// the further down the script you read.
    struct PageBreak: Equatable {
        let page: Int
        let y: CGFloat
    }

    func showBreaks(at breaks: [PageBreak]) {
        while breakMarkers.count < breaks.count {
            let marker = PageBreakMarker(frame: .zero)
            breakMarkers.append(marker)
            addSubview(marker, positioned: .above, relativeTo: textView)
        }
        while breakMarkers.count > breaks.count {
            breakMarkers.removeLast().removeFromSuperview()
        }

        let format = PageFormat.current
        let x = ((frame.width - format.pageRect.width) / 2).rounded(.down)
        for (marker, item) in zip(breakMarkers, breaks) {
            marker.pageNumber = item.page
            marker.frame = CGRect(
                x: x,
                y: item.y - PageBreakMarker.height / 2,
                width: format.pageRect.width,
                height: PageBreakMarker.height
            )
        }
    }

    /// Where a note sits: its id, the top of the line it is about, and which
    /// mark it is among the ones sharing that line.
    struct NotePlacement: Equatable {
        let id: UUID
        let lineTop: CGFloat
        let lineHeight: CGFloat
        /// 0 for the first note on a line, 1 for the second, and so on.
        var column: Int = 0
    }

    /// Puts a marker in the right margin beside each note's line.
    ///
    /// The right margin is the marks margin of a screenplay — revision
    /// asterisks live there, and Final Draft's own note icons — and it is the
    /// side Pages puts a comment on. Nothing printed reaches it: action wraps
    /// at sixty characters and everything else is indented well inside that.
    ///
    /// In `continuous` a note beside the first line of a page draws over the
    /// page-break hairline. That is a bubble interrupting a 14%-ink rule for
    /// the width of a bubble, and it reads as one mark in front of another
    /// rather than as damage.
    func showNotes(
        _ placements: [NotePlacement],
        active: UUID?,
        onOpen: @escaping (UUID) -> Void
    ) {
        while noteMarkers.count < placements.count {
            let marker = NoteMarker(frame: .zero)
            noteMarkers.append(marker)
            addSubview(marker, positioned: .above, relativeTo: textView)
        }
        while noteMarkers.count > placements.count {
            noteMarkers.removeLast().removeFromSuperview()
        }

        let format = PageFormat.current
        let pageLeft = ((frame.width - format.pageRect.width) / 2).rounded(.down)
        let x = pageLeft
            + ScreenplayPageLayout.textLeft
            + ScreenplayPageLayout.textBlockWidth(format)
            + Self.noteMarkerGap
        // What the margin has left for a second, third and fourth mark. Past
        // that they fan closer together like a dealt hand rather than walking
        // off the sheet — every one still says "there are more here", and the
        // card's own pager reaches the ones that overlap.
        let room = max(0, pageLeft + format.pageRect.width - Self.noteMarkerEdgeInset
                          - (x + NoteMarker.size.width))
        let widest = placements.map(\.column).max() ?? 0
        let step = widest == 0
            ? 0
            : min(NoteMarker.size.width + 2, room / CGFloat(widest))

        for (marker, placement) in zip(noteMarkers, placements) {
            marker.noteID = placement.id
            marker.isActive = placement.id == active
            marker.onOpen = onOpen
            // Centred on the line rather than sitting on its baseline: a mark
            // beside a line should look level with it.
            marker.frame = CGRect(
                x: (x + step * CGFloat(placement.column)).rounded(),
                y: (placement.lineTop + (placement.lineHeight - NoteMarker.size.height) / 2).rounded(),
                width: NoteMarker.size.width,
                height: NoteMarker.size.height
            )
        }
    }

    /// Air kept at the sheet's right edge, so a fanned mark never sits on it.
    private static let noteMarkerEdgeInset: CGFloat = 6

    /// The view a note's card should point at, so the popover's arrow lands
    /// on the mark the writer clicked rather than on the page.
    func noteMarker(for id: UUID) -> NSView? {
        noteMarkers.first { $0.noteID == id }
    }

    /// Air between the last column of type and the mark, so the two read as
    /// text and margin rather than as a run-on.
    private static let noteMarkerGap: CGFloat = 8

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
            // The desk and its dots, for this appearance — see `DeskGrid`.
            enclosingScrollView?.backgroundColor = NSColor.screenplayDeskGrid(for: effectiveAppearance)
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
