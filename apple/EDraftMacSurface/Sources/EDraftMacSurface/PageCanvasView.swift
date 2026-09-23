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

    /// The rule between facing pages — a binding, not a gutter.
    static let spreadHairline: CGFloat = 1

    /// Air between thumbnails in the bird's-eye.
    static let gridGap: CGFloat = 12

    /// Grid is a map, not a typesetting. Four across is fast to open and
    /// enough to read as an overview; counting columns from the window
    /// was slower and no clearer.
    static let gridColumns = 4

    static func gridColumnCount(
        viewportWidth: CGFloat, pageWidth: CGFloat, desk: CGFloat
    ) -> Int {
        gridColumns
    }

    /// How far to shrink an opening so both sheets sit in the window.
    ///
    /// Never above life size. Width and height both count, so a short
    /// window does not clip the foot and a narrow one does not clip the
    /// binding.
    static func spreadScale(
        viewport: CGSize, page: CGSize, desk: CGFloat
    ) -> CGFloat {
        guard viewport.width > 1, viewport.height > 1 else { return 1 }
        let pairW = page.width * 2 + spreadHairline + desk * 2
        let pairH = page.height + desk * 2
        return min(1, viewport.width / pairW, viewport.height / pairH)
    }

    /// Sheets, or one column. See `PageLayoutMode`; the canvas only draws
    /// what it is told.
    ///
    /// Pages by default rather than the stored preference: a view that reads
    /// a global at construction makes every test that builds one depend on
    /// what some earlier test happened to leave in `UserDefaults`. The
    /// writer's choice arrives through the model, in `bind(to:)`.
    var layoutMode: PageLayoutMode = .pages
    /// Single, two-page or grid. Ignored in `continuous`.
    var arrangement: PageArrangement = .single
    /// A click on a grid sheet. Single and two-page type on the page.
    var onPickPage: ((Int) -> Void)?
    /// The sheet a Navigator click lit, if any. Grid only.
    var highlightedPage: Int? {
        didSet { if oldValue != highlightedPage { applyAppearance(); needsDisplay = true } }
    }

    /// How a vertical stack of type maps onto facing pages, in the text
    /// view's own coordinates.
    private(set) var spreadFold: SpreadFold?

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
            mode: layoutMode, arrangement: arrangement, starts: starts,
            textHeight: textHeight, viewport: viewport, padding: canvasPadding
        )
        if signature == laidSignature {
            applyAppearance()
            if arrangement == .grid { refreshVisibleGridPreviews() }
            return
        }
        laidSignature = signature
        laidStarts = starts
        layoutPages(pageCount: starts.count, textHeight: textHeight, viewport: viewport,
                    starts: starts)
    }

    /// Stage 2 uses ordinary views on the same paper geometry. The frame-to-
    /// bounds scale belongs to AppKit, so the layout manager and view hierarchy
    /// agree; no SpreadFold participates in drawing these views.
    func layoutSheets(_ sheets: [PageSheet], viewport: CGSize) {
        precondition(layoutMode == .pages && arrangement == .spread)
        layoutPages(pageCount: sheets.count, textHeight: 1, viewport: viewport)
        textView?.isHidden = true
        let format = PageFormat.current
        sheetScale = Self.spreadScale(viewport: viewport, page: format.pageRect.size,
                                      desk: canvasPadding)
        /* Only the sheets in view are measured. Measuring a sheet lays its
           text out, and TextKit lays containers out in order — measuring
           them all re-laid the whole script on every keystroke (IL-0091:
           88 of 103 ms a key on a 115-page script). A sheet out of view is
           framed to its page's text block, which is what the engine filled
           it to, and is measured when it scrolls in (`measureVisibleSheets`). */
        let visible = sheetMeasuringRect()
        for (sheet, paper) in zip(sheets, pageViews) {
            let view = sheet.textView
            if view.superview !== self { addSubview(view, positioned: .above, relativeTo: paper) }
            frame(sheet, on: paper, measuring: paper.frame.intersects(visible))
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                view.insertionPointColor = NSColor.screenplayInk.usingColorSpace(.sRGB) ?? .labelColor
            }
        }
    }

    /// Measures the sheets that have scrolled into view, and gives any whose
    /// type runs past its text block the room it needs.
    func measureVisibleSheets(_ sheets: [PageSheet]) {
        guard layoutMode == .pages, arrangement == .spread, !sheets.isEmpty else { return }
        let visible = sheetMeasuringRect()
        for (sheet, paper) in zip(sheets, pageViews) where paper.frame.intersects(visible) {
            frame(sheet, on: paper, measuring: true)
        }
    }

    /// The scale the sheets were last laid out at.
    private var sheetScale: CGFloat = 1

    /// What is on screen, and a row either side, so a sheet is measured
    /// before the writer reaches it.
    private func sheetMeasuringRect() -> CGRect {
        let row = (pageViews.first?.frame.height ?? 0) + Self.pageGap
        return gridVisibleRect().insetBy(dx: 0, dy: -row)
    }

    private func frame(_ sheet: PageSheet, on paper: NSView, measuring: Bool) {
        let format = PageFormat.current
        let slack = ScreenplayPageLayout.glyphOverflow
        var text = ScreenplayPageLayout.textBlockHeight(format)
        if measuring, let manager = sheet.textContainer.layoutManager {
            let glyphs = manager.glyphRange(for: sheet.textContainer)
            let ink = manager.boundingRect(forGlyphRange: glyphs, in: sheet.textContainer)
            let extra = manager.extraLineFragmentTextContainer === sheet.textContainer
                ? manager.extraLineFragmentUsedRect.maxY : 0
            text = max(ink.maxY, extra, text)
        }
        let size = CGSize(width: sheet.textContainer.size.width, height: text + slack * 2)
        let rect = CGRect(
            x: paper.frame.minX + ScreenplayPageLayout.textLeft * sheetScale,
            y: paper.frame.minY + (format.textTop - slack) * sheetScale,
            width: size.width * sheetScale, height: size.height * sheetScale
        )
        let view = sheet.textView
        if view.frame != rect { view.frame = rect }
        if view.bounds.size != size { view.setBoundsSize(size) }
    }

    /// What the last `layoutPages` pass was asked for; a repeat is a no-op.
    private struct PagesSignature: Equatable {
        let mode: PageLayoutMode
        let arrangement: PageArrangement
        let starts: [CGFloat]
        let textHeight: CGFloat
        let viewport: CGSize
        let padding: CGFloat
    }
    private var laidSignature: PagesSignature?
    private var laidStarts: [CGFloat] = [0]
    private var gridPreviewEpoch = 0
    private var gridPreviewKeys: [ObjectIdentifier: GridPreviewKey] = [:]

    func layoutPages(pageCount: Int, textHeight: CGFloat, viewport: CGSize,
                     starts: [CGFloat]? = nil) {
        // Called directly, this is not the pass the signature remembers.
        laidSignature = nil
        if let starts, !starts.isEmpty { laidStarts = starts }
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
        let sheets = layoutMode == .pages ? pages : 1
        let usingSheets = layoutMode == .pages
        let arranged = usingSheets ? arrangement : .single

        let columns: Int
        let rows: Int
        let colGap: CGFloat
        let rowGap: CGFloat
        let scale: CGFloat
        switch arranged {
        case .single:
            columns = 1
            rows = sheets
            colGap = 0
            rowGap = usingSheets ? Self.pageGap : 0
            scale = 1
        case .spread:
            columns = 2
            rows = (sheets + 1) / 2
            scale = Self.spreadScale(viewport: viewport, page: pageSize, desk: desk)
            colGap = Self.spreadHairline * scale
            rowGap = Self.pageGap * scale
        case .grid:
            columns = Self.gridColumns
            rows = max(1, (sheets + columns - 1) / columns)
            colGap = Self.gridGap
            rowGap = Self.gridGap
            let usable = max(pageSize.width, viewport.width - desk * 2)
            scale = max(
                0.12,
                (usable - colGap * CGFloat(max(0, columns - 1)))
                    / (pageSize.width * CGFloat(columns))
            )
        }

        let card = CGSize(width: pageSize.width * scale, height: pageSize.height * scale)
        let stackHeight: CGFloat = switch layoutMode {
        case .continuous:
            format.textTop + max(textHeight, textBlock) + ScreenplayPageLayout.textBottom(format)
        case .pages:
            CGFloat(rows) * card.height + CGFloat(max(0, rows - 1)) * rowGap
        }

        // Exactly the paper and its desk — not the viewport — except Grid,
        // which *is* a view of the window: the thumbnails size to what fits.
        // `CentringClipView` puts a canvas smaller than the window in the
        // middle of it, so Single and Two-page stay the same size at every
        // magnification and a pinch has nothing to re-measure.
        let canvasWidth: CGFloat = switch arranged {
        case .single:
            pageSize.width + desk * 2
        case .spread, .grid:
            CGFloat(columns) * card.width + CGFloat(max(0, columns - 1)) * colGap + desk * 2
        }
        let typeBottom = format.textTop + textHeight + ScreenplayPageLayout.textBottom(format)
        let canvasHeight: CGFloat = switch arranged {
        case .grid:
            stackHeight + desk * 2
        case .single, .spread:
            max(stackHeight, arranged == .single ? typeBottom : stackHeight) + desk * 2
        }
        setFrameSize(CGSize(width: canvasWidth, height: canvasHeight))

        let x0 = desk
        while pageViews.count < sheets {
            let page = makePageView()
            pageViews.append(page)
            addSubview(page, positioned: .below, relativeTo: textView)
        }
        while pageViews.count > sheets {
            pageViews.removeLast().removeFromSuperview()
        }
        gridPreviewEpoch += 1
        gridPreviewKeys.removeAll(keepingCapacity: true)
        for index in 0..<sheets {
            let col = index % columns
            let row = index / columns
            let top: CGFloat
            if arranged == .single, usingSheets, let starts, index < starts.count {
                // Measured from the first page's own start rather than from
                // the text view's origin. The text view begins one line above
                // the text block and insets its text back down by the same
                // amount (`glyphOverflow`, so a tall glyph has somewhere to
                // go), and a rectangle measured inside it carries that inset.
                top = desk + starts[index] - starts[0]
            } else {
                top = desk + CGFloat(row) * (card.height + rowGap)
            }
            pageViews[index].frame = CGRect(
                x: x0 + CGFloat(col) * (card.width + colGap),
                y: top,
                width: card.width,
                height: usingSheets ? card.height : stackHeight
            )
            pageViews[index].layer?.contents = nil
        }

        syncGridChrome()

        spreadFold = nil
        if arranged == .spread, let starts, !starts.isEmpty {
            spreadFold = SpreadFold(
                pageTops: starts.map { $0 - starts[0] },
                columnPitch: pageSize.width + Self.spreadHairline,
                rowPitch: pageSize.height + Self.pageGap,
                scale: scale
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
        let textWidthOnCanvas: CGFloat = switch arranged {
        case .spread: (textWidth + pageSize.width + Self.spreadHairline) * scale
        case .single, .grid: textWidth
        }
        let textHeightOnCanvas: CGFloat = switch arranged {
        case .spread:
            (max(CGFloat(rows) * (pageSize.height + Self.pageGap) - Self.pageGap, textBlock, 1)
                + slack * 2) * scale
        case .single, .grid:
            max(textHeight, usingSheets ? lastTextBottom : textHeight, 1) + slack * 2
        }
        textView?.frame = CGRect(
            x: x0 + ScreenplayPageLayout.textLeft * scale,
            y: desk + (format.textTop - slack) * scale,
            width: textWidthOnCanvas,
            height: textHeightOnCanvas
        )
        textView?.isHidden = arranged == .grid
        applyAppearance()
        needsDisplay = true
        if arranged == .grid {
            refreshVisibleGridPreviews()
        }
    }

    func pageIndex(at point: CGPoint) -> Int? {
        pageViews.firstIndex { $0.frame.contains(point) }
    }

    /// Grid opens a sheet on the second click. A first click is not a jump.
    func handleGridClick(at point: CGPoint, count: Int) {
        guard arrangement == .grid, count >= 2, let index = pageIndex(at: point) else { return }
        onPickPage?(index)
    }

    override func mouseDown(with event: NSEvent) {
        guard arrangement == .grid else {
            super.mouseDown(with: event)
            return
        }
        handleGridClick(at: convert(event.locationInWindow, from: nil), count: event.clickCount)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard layoutMode == .pages, arrangement == .spread, pageViews.count >= 2 else { return }
        NSColor.separatorColor.withAlphaComponent(0.7).setStroke()
        let line = NSBezierPath()
        line.lineWidth = 0.5
        for i in stride(from: 0, to: pageViews.count - 1, by: 2) {
            let left = pageViews[i].frame
            let right = pageViews[i + 1].frame
        let x = (left.maxX + right.minX) / 2
            line.move(to: NSPoint(x: x, y: left.minY))
            line.line(to: NSPoint(x: x, y: left.maxY))
        }
        line.stroke()
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
        /// The colour slot the whole line agrees on, or nil — see
        /// `NoteMarker.authorSlot`.
        var authorSlot: Int?
        let lineTop: CGFloat
        let lineHeight: CGFloat
        var marginX: CGFloat? = nil
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
        let drawn: CGFloat
        if layoutMode == .pages, arrangement == .grid, let card = pageViews.first {
            let scale = card.frame.width / max(PageFormat.current.pageRect.width, 1)
            drawn = max(10, (NoteMarker.size.height * scale).rounded())
        } else {
            drawn = NoteMarker.size.height
        }
        for (marker, placement) in zip(noteMarkers, placements) {
            marker.noteIDs = placement.noteIDs
            marker.authorSlot = placement.authorSlot
            marker.isActive = active.map(placement.noteIDs.contains) ?? false
            marker.onOpen = onOpen
            marker.drawnSize = drawn
            // Centred on the line rather than sitting on its baseline: a mark
            // beside a line should look level with it. The frame stays the
            // life-size hit target; Grid only shrinks what is drawn.
            marker.frame = CGRect(
                x: (placement.marginX ?? x).rounded(),
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
    static let noteMarkerGap: CGFloat = 8

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
                page.layer?.cornerRadius = 2
                page.layer?.shadowColor = NSColor.black.cgColor
                page.layer?.shadowRadius = 8
                page.layer?.shadowOffset = CGSize(width: 0, height: -1)
                page.layer?.shadowOpacity = 0.22
            }
            if arrangement == .grid { syncGridChrome() }
        }
    }

    func highlightGridPage(_ index: Int) {
        highlightedPage = index
        syncGridChrome()
        guard index >= 0, index < pageViews.count else { return }
        scrollToVisible(pageViews[index].frame.insetBy(dx: 0, dy: -16))
    }


    private var gridLabels: [NSTextField] = []

    /// Page numbers on the map, and the one sheet a Navigator click lit.
    /// Visible cards carry a miniature of the page; the rest stay empty
    /// paper so a feature-length draft does not snapshot every sheet on open.
    private func syncGridChrome() {
        let grid = layoutMode == .pages && arrangement == .grid
        while gridLabels.count < pageViews.count {
            let label = NSTextField(labelWithString: "")
            label.alignment = .center
            label.font = .systemFont(ofSize: 9, weight: .medium)
            label.isBordered = false
            label.drawsBackground = false
            label.isSelectable = false
            gridLabels.append(label)
        }
        while gridLabels.count > pageViews.count {
            gridLabels.removeLast().removeFromSuperview()
        }
        let numberColor = NSColor.screenplayInk.usingColorSpace(.sRGB) ?? .labelColor
        for (index, page) in pageViews.enumerated() {
            let label = gridLabels[index]
            if grid {
                if label.superview !== page { page.addSubview(label) }
                label.textColor = numberColor
                label.stringValue = "\(index + 1)"
                label.sizeToFit()
                let pad: CGFloat = 6
                label.frame.origin = CGPoint(
                    x: (page.bounds.width - label.frame.width) / 2,
                    y: page.bounds.height - label.frame.height - pad
                )
                label.isHidden = false
            } else {
                label.isHidden = true
            }
            let lit = grid && highlightedPage == index
            page.layer?.borderWidth = lit ? 3 : 0
            page.layer?.borderColor = NSColor.controlAccentColor.cgColor
        }
    }

    /// The colour Grid actually painted the page numbers, for contrast tests.
    var gridPageNumberColors: [NSColor] {
        zip(gridLabels, pageViews).compactMap { label, _ in
            label.isHidden ? nil : label.textColor
        }
    }

    var gridPageNumberPointSize: CGFloat? {
        gridLabels.first { !$0.isHidden }?.font?.pointSize
    }

    /// The miniature last assigned to that card, if this card has been painted.
    func gridPreviewImage(at index: Int) -> CGImage? {
        guard pageViews.indices.contains(index) else { return nil }
        return pageViews[index].layer?.contents as! CGImage?
    }

    /// Maps a line in the hidden column onto the Grid card that holds it.
    func gridNotePlacement(
        textRect: CGRect, page: Int
    ) -> (lineTop: CGFloat, lineHeight: CGFloat, marginX: CGFloat)? {
        guard arrangement == .grid, pageViews.indices.contains(page) else { return nil }
        let card = pageViews[page]
        let format = PageFormat.current
        let scale = card.frame.width / max(format.pageRect.width, 1)
        let start = page < laidStarts.count ? laidStarts[page] : 0
        let lineTop = card.frame.minY + (format.textTop + textRect.minY - start) * scale
        let lineHeight = max(textRect.height * scale, 1)
        let marginX = card.frame.minX + (
            ScreenplayPageLayout.textLeft
                + ScreenplayPageLayout.textBlockWidth(format)
                + Self.noteMarkerGap
        ) * scale
        return (lineTop, lineHeight, marginX)
    }

    private struct GridPreviewKey: Equatable {
        let epoch: Int
        let pixels: CGSize
        let dark: Bool
        let paper: PagePaper
    }

    /// Paint only the cards in (or one row past) the clip. Called from layout
    /// and from the scroll-view bounds observer.
    func refreshVisibleGridPreviews() {
        guard layoutMode == .pages, arrangement == .grid else { return }
        let keep = Set(visibleGridPageIndexes())
        for (index, page) in pageViews.enumerated() {
            if keep.contains(index) {
                paintGridPreview(index: index, page: page)
            } else if page.layer?.contents != nil {
                page.layer?.contents = nil
                gridPreviewKeys.removeValue(forKey: ObjectIdentifier(page))
            }
        }
    }

    private func visibleGridPageIndexes() -> [Int] {
        guard !pageViews.isEmpty else { return [] }
        let vis = gridVisibleRect()
        let row = pageViews[0].frame.height + Self.gridGap
        let expanded = vis.insetBy(dx: 0, dy: -row)
        return pageViews.indices.filter { pageViews[$0].frame.intersects(expanded) }
    }

    /// The window's viewport in canvas coordinates. Clip `bounds` can be the
    /// whole document when the scroll view has no window yet — the tests, and
    /// the first layout before attach — so the scroll view's *frame* is the
    /// size that is actually on screen, matching `ScriptSurface.visibleViewport`.
    private func gridVisibleRect() -> CGRect {
        guard let scroll = enclosingScrollView else { return bounds }
        let mag = max(scroll.magnification, 0.001)
        let origin = scroll.contentView.bounds.origin
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: max(scroll.frame.width / mag, 1),
            height: max(scroll.frame.height / mag, 1)
        )
    }

    private func paintGridPreview(index: Int, page: FlippedView) {
        let card = page.bounds.size
        guard card.width > 1, card.height > 1 else { return }
        let backing = window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1
        let pixels = CGSize(
            width: max(1, (card.width * backing).rounded()),
            height: max(1, (card.height * backing).rounded())
        )
        let key = GridPreviewKey(
            epoch: gridPreviewEpoch,
            pixels: pixels,
            dark: effectiveAppearance.isDark,
            paper: PagePaper.stored
        )
        if gridPreviewKeys[ObjectIdentifier(page)] == key, page.layer?.contents != nil {
            return
        }

        let pxW = Int(pixels.width)
        let pxH = Int(pixels.height)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pxW,
            pixelsHigh: pxH,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }
        rep.size = card
        guard let bitmap = NSGraphicsContext(bitmapImageRep: rep) else { return }
        let cg = bitmap.cgContext
        cg.translateBy(x: 0, y: card.height)
        cg.scaleBy(x: 1, y: -1)
        let flipped = NSGraphicsContext(cgContext: cg, flipped: true)
        flipped.shouldAntialias = true
        flipped.imageInterpolation = .medium

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = flipped
        effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.screenplayPaper.setFill()
            NSRect(origin: .zero, size: card).fill()
            let pageSize = PageFormat.current.pageRect.size
            let scale = card.width / max(pageSize.width, 1)
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            transform.concat()
            drawGridPageGlyphs(index: index, pageSize: pageSize)
        }
        NSGraphicsContext.restoreGraphicsState()

        page.wantsLayer = true
        page.layer?.contentsScale = backing
        page.layer?.contentsGravity = .resize
        page.layer?.contents = rep.cgImage
        gridPreviewKeys[ObjectIdentifier(page)] = key
    }

    private func drawGridPageGlyphs(index: Int, pageSize: CGSize) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }
        let format = PageFormat.current
        let slack = ScreenplayPageLayout.glyphOverflow
        let start = index < laidStarts.count ? laidStarts[index] : 0
        let end = index + 1 < laidStarts.count
            ? laidStarts[index + 1]
            : layoutManager.usedRect(for: container).maxY
        NSBezierPath.clip(NSRect(origin: .zero, size: pageSize))
        let origin = CGPoint(
            x: ScreenplayPageLayout.textLeft,
            y: slack + format.textTop - start
        )
        let containerRect = CGRect(
            x: 0,
            y: start - slack,
            width: max(container.size.width, 1),
            height: max(end - start, 1)
        )
        let glyphs = layoutManager.glyphRange(
            forBoundingRectWithoutAdditionalLayout: containerRect, in: container
        )
        guard glyphs.length > 0 else { return }
        layoutManager.drawGlyphs(forGlyphRange: glyphs, at: origin)
    }

    private func makePageView() -> FlippedView {
        let page = FlippedView()
        page.wantsLayer = true
        // What it looks like is `applyAppearance`'s, all of it — see there.
        return page
    }
}

/// Vertical type folded onto facing pages.
///
/// Layout still happens as a column — the same bands, the same page
/// starts — and drawing and hit-testing ask this where that column sits
/// on an open book. Pagination is not consulted; the starts already are.
struct SpreadFold: Equatable {
    let pageTops: [CGFloat]
    let columnPitch: CGFloat
    let rowPitch: CGFloat
    /// 1 is life size. Smaller when the opening is fitted to the window.
    var scale: CGFloat = 1

    func pageIndex(atVerticalY y: CGFloat) -> Int {
        guard pageTops.count > 1 else { return 0 }
        var i = 0
        while i + 1 < pageTops.count, pageTops[i + 1] <= y + 0.01 {
            i += 1
        }
        return i
    }

    func spreadPoint(fromVertical p: CGPoint) -> CGPoint {
        let page = pageIndex(atVerticalY: p.y)
        let col = page % 2
        let row = page / 2
        let top = page < pageTops.count ? pageTops[page] : 0
        let s = scale
        return CGPoint(
            x: (p.x + CGFloat(col) * columnPitch) * s,
            y: (CGFloat(row) * rowPitch + (p.y - top)) * s
        )
    }

    func verticalPoint(fromSpread p: CGPoint) -> CGPoint {
        let s = max(scale, 0.0001)
        let q = CGPoint(x: p.x / s, y: p.y / s)
        let col = q.x >= columnPitch - 0.5 ? 1 : 0
        let row = max(0, Int((q.y / max(rowPitch, 1)).rounded(.down)))
        let page = min(pageTops.count - 1, max(0, row * 2 + col))
        let top = pageTops.indices.contains(page) ? pageTops[page] : 0
        let yInPage = q.y - CGFloat(row) * rowPitch
        return CGPoint(
            x: q.x - CGFloat(col) * columnPitch,
            y: top + yInPage
        )
    }

    func spreadRect(fromVertical r: CGRect) -> CGRect {
        let origin = spreadPoint(fromVertical: r.origin)
        return CGRect(
            origin: origin,
            size: CGSize(width: r.width * scale, height: r.height * scale)
        )
    }
}
