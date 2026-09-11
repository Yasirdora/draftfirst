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
    ///
    /// A constant the window reads too: the window's widths are built from
    /// it, so the margins the page keeps are these. Eight points is a breath
    /// between paper and edge — ten at the opening size — and nothing more.
    static let deskPadding: CGFloat = 8
    var canvasPadding: CGFloat = PageCanvasView.deskPadding

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
    /// Lays a sheet under each page of type.
    ///
    /// `pageStarts` is where each page's first line actually ended up, in the
    /// text view's own coordinates — not a count. The sheets follow the type
    /// rather than the type being forced onto a grid of sheets, which is the
    /// difference between a page that begins at the top of its paper and one
    /// that begins thirty-five lines down it.
    func layoutPages(pageStarts: [CGFloat], textHeight: CGFloat, viewport: CGSize) {
        let starts = pageStarts.isEmpty ? [0] : pageStarts
        // Re-framing a feature's worth of sheets because the window breathed
        // is real work — nine hundred subviews moved on a 910-page draft —
        // and the same words in the same mode land on the same paper.
        let signature = PagesSignature(
            mode: layoutMode, starts: starts, textHeight: textHeight,
            viewport: viewport, padding: canvasPadding
        )
        if signature == laidSignature {
            applyAppearance()
            return
        }
        laidSignature = signature
        layoutPages(pageCount: starts.count, textHeight: textHeight, viewport: viewport,
                    starts: starts)
    }

    /// What the last `layoutPages` pass was asked for; a repeat is a no-op.
    private struct PagesSignature: Equatable {
        let mode: PageLayoutMode
        let starts: [CGFloat]
        let textHeight: CGFloat
        let viewport: CGSize
        let padding: CGFloat
    }
    private var laidSignature: PagesSignature?

    func layoutPages(pageCount: Int, textHeight: CGFloat, viewport: CGSize,
                     starts: [CGFloat]? = nil) {
        // Called directly, this is not the pass the signature remembers.
        laidSignature = nil
        let format = PageFormat.current
        let pageSize = format.pageRect.size
        let desk = canvasPadding
        let slack = ScreenplayPageLayout.glyphOverflow
        // The font's sixty characters, not the geometry's — see
        // `ScriptLayout.pageMeasure`. A container of exactly 432 points wraps
        // a full line one character early.
        let textWidth = ScriptLayout.measuredTextWidth(for: format)
        let textBlock = ScreenplayPageLayout.textBlockHeight(format)

        // Enough paper for the words, whatever the paginator said.
        //
        // The engine counts pages by wrapping at sixty Courier characters;
        // the text view lays out by measuring glyphs. The two agree almost
        // always and not quite always — measured on a real production draft,
        // the type needed a twenty-eighth sheet where the engine had counted
        // twenty-seven. The stack was built from the count alone, so the last
        // hundred points of the script were drawn past the final sheet and
        // past the canvas, where a scroll view cannot reach: the writer's
        // script simply ended early, and only in `pages`.
        //
        // The engine's number is still the page count — it is what the PDF
        // prints and what a production schedules against, and it is not
        // changed here. This decides only how much paper is laid out under
        // the type, and the answer is: never less than the type needs.
        let pages = max(1, pageCount, Self.sheetsHolding(textHeight, format: format))

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
        //
        // Never shorter than what is on it. The sheets above are sized to
        // hold the type, and this says the same thing a second time about
        // the canvas itself — because the one thing that must never happen
        // is a glyph drawn where the scroll view cannot travel.
        let canvasWidth = pageSize.width + desk * 2
        let typeBottom = format.textTop + textHeight + ScreenplayPageLayout.textBottom(format)
        setFrameSize(CGSize(
            width: canvasWidth,
            height: max(stackHeight, typeBottom) + desk * 2
        ))

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
            // Under the line that begins this page, when the caller has
            // measured it. The text view sits at `desk + textTop`, so a page
            // beginning at y in its coordinates puts its sheet's top at
            // `desk + y`.
            let top: CGFloat
            if layoutMode == .pages, let starts, index < starts.count {
                // Measured from the first page's own start rather than from
                // the text view's origin. The text view begins one line above
                // the text block and insets its text back down by the same
                // amount (`glyphOverflow`, so a tall glyph has somewhere to
                // go), and a rectangle measured inside it carries that inset.
                // Taking the difference cancels it, whatever it is, instead of
                // subtracting a constant that has to be kept in step.
                top = desk + starts[index] - starts[0]
            } else {
                top = desk + CGFloat(index) * (pageSize.height + Self.pageGap)
            }
            pageViews[index].frame = CGRect(
                x: x,
                y: top,
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
        //
        // Assigned only when it moves: setting the inset invalidates the
        // whole container, and the value is a constant — the assignment used
        // to buy a full re-layout of the script on every pass.
        let lastTextBottom =
            CGFloat(pages - 1) * (pageSize.height + Self.pageGap) + textBlock
        let inset = NSSize(width: 0, height: slack)
        if let textView, textView.textContainerInset != inset {
            textView.textContainerInset = inset
        }
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
        let noteIDs: [UUID]
        let lineTop: CGFloat
        let lineHeight: CGFloat
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
        onOpen: @escaping ([UUID]) -> Void
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
        for (marker, placement) in zip(noteMarkers, placements) {
            marker.noteIDs = placement.noteIDs
            marker.isActive = active.map(placement.noteIDs.contains) ?? false
            marker.onOpen = onOpen
            // Centred on the line rather than sitting on its baseline: a mark
            // beside a line should look level with it.
            marker.frame = CGRect(
                x: x.rounded(),
                y: (placement.lineTop + (placement.lineHeight - NoteMarker.size.height) / 2).rounded(),
                width: NoteMarker.size.width,
                height: NoteMarker.size.height
            )
        }
    }

    /// How many sheets it takes to hold this much type.
    ///
    /// Type on sheet *k* runs from that sheet's text top for at most one text
    /// block, so `n` sheets hold `(n - 1) * (page + gap) + block`. Inverted,
    /// and never fewer than one.
    static func sheetsHolding(_ textHeight: CGFloat, format: PageFormat) -> Int {
        let block = ScreenplayPageLayout.textBlockHeight(format)
        guard textHeight > block else { return 1 }
        let perSheet = format.pageRect.height + pageGap
        return 1 + Int(((textHeight - block) / perSheet).rounded(.up))
    }

    /// The view a note's card should point at, so the popover's arrow lands
    /// on the mark the writer clicked rather than on the page.
    func noteMarker(for id: UUID) -> NSView? {
        noteMarkers.first { $0.noteIDs.contains(id) }
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

    /// What `applyAppearance` last painted, so a repeat call — every layout
    /// pass whose geometry is unchanged asks for one — does not re-assign
    /// the same snapshots. Re-assigning the scroll view's background hands
    /// AppKit a fresh pattern colour it reads as a change, and the titlebar's
    /// glass answers that with a transition on every keystroke.
    private struct AppliedLook: Equatable {
        let dark: Bool
        let paper: PagePaper
        let pages: Int
    }
    private var appliedLook: AppliedLook?

    func applyAppearance() {
        let look = AppliedLook(
            dark: effectiveAppearance.isDark,
            paper: PagePaper.stored,
            pages: pageViews.count
        )
        guard look != appliedLook else { return }
        appliedLook = look
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

            // Clear: the canvas is only as large as the pages, so a colour
            // here would stop at its edge and draw a border round them.
            layer?.backgroundColor = NSColor.clear.cgColor
            // The desk itself is unpainted now — the system's surface shows
            // through — so there is no background colour to set here. The
            // dots are `DeskGridView`'s, and it rebuilds its own pattern when
            // the appearance changes; this only nudges the ones already on
            // screen, since a canvas can change appearance before they have.
            enclosingScrollView?.subviews
                .compactMap { $0 as? DeskGridView }
                .forEach { $0.needsDisplay = true }
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
