import AppKit
import EDraftCore
import EDraftEngine
import Foundation
import SwiftUI

/// The page, on a Mac.
///
/// Everything that happens between the model and an `NSTextView`: setting the
/// script, remembering which characters belong to which element, taking a
/// keystroke, moving the page when a Navigator row asks, and marking where it
/// landed.
///
/// It is a plain class rather than a view so it can be driven by a test. The
/// SwiftUI wrapper around it (`ScriptPageView`) adds nothing but lifetime — a
/// deliberate arrangement, because every hard bug this project has had lived
/// in exactly this arithmetic and none of them were visible from a screenshot.
///
/// TextKit 1, following the measurements in `ScriptLayoutTests`: its rectangles
/// are the ones `PageScroll` and the reveal were written against, so the phone's
/// hard-won behaviour ports rather than being invented again.
///
/// Ordinary letters stay with AppKit. The surface steps in only for
/// screenplay-level actions — Return, a boundary delete, Tab, a scene-heading
/// dash — and asks `ScreenplayEditPlanner` and `Choreography` what they mean.
/// A rule that lived here would be a second editor, and the two apps would
/// disagree eventually.
@MainActor
public final class ScriptSurface: NSObject, NSTextViewDelegate, NSPopoverDelegate {

    public let scrollView: NSScrollView
    public let textView: NSTextView
    /// Bold, italic, underline and centre, over whatever is selected.
    private let formatBar = SelectionFormatBar()
    let canvas: PageCanvasView

    private var ranges: [ScriptLayout.ElementRange] = []
    let highlight = RevealHighlightViewMac()
    private let ghost = GhostTextOverlay()

    /// The text-block width, locked to the printed page. A resized window
    /// recentres the card; it does not stretch the script.
    private var measure: CGFloat

    private weak var editor: EditorState?
    /// The model's revision this surface last drew. Live typing updates it
    /// without replacing the storage; a SwiftUI refresh that sees the same
    /// number must not rebuild the page, or the caret visits the top of the
    /// document on every keystroke. See `CaretTransitTests` on the phone.
    private var renderedRevision = -1
    private var paperObserver: NSObjectProtocol?
    /// What the page was last drawn on, so a defaults change that is about
    /// something else does not relay the script.
    private var renderedPaper = PagePaper.stored
    /// Elements last laid into the text view. Pagination for the sheets
    /// reads this, not `editor.stats` (debounced, estimated at open).
    private var lastLaidElements: [ScriptElement] = []
    private var applyingModel = false
    private var pendingEdit: PendingEdit?
    private var pendingSeparatorEscape: SeparatorEscape?

    /// AppKit's text view takes its undo manager off the responder chain, which
    /// is the window — so a surface driven without one, as every test here is,
    /// would see `textView.undoManager == nil` and silently drop structural
    /// undo. Vend this instead, through `undoManager(for:)`.
    private let editingUndo = UndoManager()

    /// System find bar, Replace disabled. See `FindBarClient`.
    private let textFinder = NSTextFinder()
    private let findClient: FindBarClient

    /// The note whose card is open, and the popover showing it. One at a
    /// time, which is what a `.transient` popover enforces anyway — clicking
    /// the page closes the card, and clicking another mark opens that one.
    private var openNoteID: UUID?
    private var notePopover: NSPopover?
    /// What the open card currently reads, so closing it can write that to
    /// the model. The card reports every keystroke here; the model is written
    /// once, when the card goes away — see `NoteCard.onEdit`.
    private var openNoteDraft: String?
    /// The element the context menu was opened over, so "Add Note" leaves the
    /// note where the writer pointed.
    private var rightClickedElement: UUID?

    public init(measure: CGFloat = 640) {
        let textWidth = ScriptLayout.pageMeasure
        self.measure = textWidth

        let container = NSTextContainer(
            size: CGSize(width: textWidth, height: .greatestFiniteMagnitude)
        )
        // The page is paper, not the window: tracking the clip view would
        // stretch a 60-character block across whatever the writer resized to.
        container.widthTracksTextView = false
        let layoutManager = NSLayoutManager()
        let storage = NSTextStorage()
        layoutManager.delegate = fixedLeading
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        let textView = NSTextView(
            frame: NSRect(x: 0, y: 0, width: textWidth, height: 0), textContainer: container
        )
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        // `init(frame:textContainer:)` copies the frame into minSize/maxSize.
        // Height 0 means sizeToFit cannot grow the view, so the script is
        // laid out in the layout manager and displayed one point tall —
        // which is invisible. NSScrollView used to hide this by sizing
        // its document view; the page card does not.
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.autoresizingMask = []
        textView.textContainerInset = .zero
        container.lineFragmentPadding = 0
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        // The screenplay's own rules decide what a line looks like; nothing
        // the system might helpfully add belongs on a page that has to print
        // exactly as it reads.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true
        self.textView = textView

        let canvas = PageCanvasView()
        canvas.attach(textView)
        self.canvas = canvas
        formatBar.attach(to: canvas)

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: measure, height: 480))
        scrollView.hasVerticalScroller = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = PageZoom.actualSize
        scrollView.maxMagnification = PageZoom.maximum
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        // The clip view centres a page smaller than the window, so the canvas
        // never has to be grown to the viewport and a pinch needs no
        // re-measure to stay centred.
        //
        // It is installed *before* the desk is coloured, and the order is not
        // arbitrary: a scroll view's background is its clip view's, so
        // replacing the clip view afterwards throws the colour away.
        scrollView.contentView = CentringClipView()
        scrollView.documentView = canvas
        // The scroll view paints the desk, and it is the only thing that does.
        // The canvas is exactly the pages, so anything it painted itself would
        // end at its edge and read as a border around them.
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .screenplayDesk
        self.scrollView = scrollView

        let findClient = FindBarClient(textView: textView)
        self.findClient = findClient

        super.init()
        formatBar.onApply = { [weak self] mark in
            if mark == .note { self?.addNoteAtCaret() } else { self?.applyMark(mark) }
        }
        // The canvas is the scroll view's document view, so it joins the
        // window at the same moment the surface does — and that moment, not a
        // SwiftUI update pass, is when the page can take the caret.
        canvas.onMoveToWindow = { [weak self] in
            self?.openTheWindowToItsFullHeight()
            self?.takeInitialFocus()
            self?.applyZoomForCurrentSize()
        }
        // How large the page is drawn depends on the clip view's *frame* — the
        // visible width in screen points. `remeasureIfNeeded` watches its
        // bounds instead, which are already divided by the magnification, so
        // it is the wrong signal and can miss the first layout entirely: the
        // page then opens at 100% however wide the window is. This is AppKit's
        // own notification for the thing that actually changed.
        // A trackpad pinch changes this behind our back; without watching it
        // the control reads a stale number and a resize can undo the writer's
        // choice.
        magnificationObserver = scrollView.observe(
            \.magnification, options: [.new]
        ) { [weak self] scrollView, _ in
            MainActor.assumeIsolated {
                guard let self, !self.isSettingMagnification else { return }
                self.magnificationChanged(to: scrollView.magnification, fromGesture: true)
            }
        }
        for (name, live) in [
            (NSScrollView.willStartLiveMagnifyNotification, true),
            (NSScrollView.didEndLiveMagnifyNotification, false)
        ] {
            liveMagnifyObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: scrollView, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isLiveMagnifying = live
                    if !live { self.settleAfterGesture() }
                }
            })
        }
        // The page's ink, its ghost and its caret are all resolved from
        // `PagePaper`, and a `cgColor` on a layer is a snapshot — so a change
        // has to be re-applied rather than waited for.
        paperObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.paperChanged() }
        }
        scrollView.contentView.postsFrameChangedNotifications = true
        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.applyZoomForCurrentSize() }
        }
        textView.delegate = self
        ghost.onAccept = { [weak self] in self?.acceptPrediction() }
        textView.addSubview(ghost, positioned: .above, relativeTo: nil)

        // Own the finder so we can refuse Replace. `usesFindBar` on the
        // text view would use the view as client, and an editable view
        // offers Replace — which writes storage without the planner.
        textFinder.client = findClient
        textFinder.findBarContainer = scrollView
        textFinder.incrementalSearchingShouldDimContentView = false
    }

    // MARK: - Binding

    /// Points the model's callbacks at this surface.
    ///
    /// Re-run when SwiftUI hands over a different `EditorState` after an
    /// external document change — the same rebinding the phone's surface does,
    /// for the same reason: a surface still bound to a state nobody owns is an
    /// editor that has quietly stopped working.
    public func bind(to editor: EditorState) {
        guard self.editor !== editor else { return }
        self.editor = editor
        renderedRevision = -1
        editor.onJumpToElement = { [weak self] id in
            self?.reveal(
                id,
                reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            )
        }
        editor.onChangeElementKind = { [weak self] kind in self?.changeKind(to: kind) }
        editor.onPredictionChange = { [weak self] in self?.updateGhost() }
        editor.onAcceptPrediction = { [weak self] in self?.acceptPrediction() }
        editor.onShowFind = { [weak self] in self?.showFind() }
        editor.onFindNext = { [weak self] in self?.find(next: true) }
        editor.onFindPrevious = { [weak self] in self?.find(next: false) }
        editor.onInsertElements = { [weak self] pages in self?.insertElements(pages) }
        editor.onApplyElements = { [weak self] elements, name in
            self?.applyElements(elements, actionName: name)
        }
        editor.onNativeUndo = { [weak self] in self?.performNativeUndo() ?? false }
        editor.onNativeRedo = { [weak self] in self?.performNativeRedo() ?? false }
        editor.onClearNativeUndo = { [weak self] in self?.clearNativeUndoHistory() }
        editor.onZoom = { [weak self] command in self?.applyZoom(command) }
        editor.onSetEditing = { [weak self] editing in
            guard let self else { return }
            if editing {
                self.placeCaretForEditing()
                self.scrollView.window?.makeFirstResponder(self.textView)
            } else if self.scrollView.window?.firstResponder === self.textView {
                self.scrollView.window?.makeFirstResponder(nil)
            }
        }
        editor.onSetLayoutMode = { [weak self] mode in self?.setLayoutMode(mode) }
        editor.onAddNote = { [weak self] in self?.addNoteAtCaret() }
        // The writer's choice reaches the canvas here rather than being read
        // from a global when the view was built — see `layoutMode`.
        canvas.layoutMode = editor.layoutMode
    }

    /// Draws the model only when this surface has not already mirrored this
    /// revision. Live typing bumps `editor.revision` and then records it here
    /// so a later SwiftUI pass — the subtitle reading `stats`, for example —
    /// cannot replace the storage and send the caret to the top.
    public func renderIfNeeded(_ editor: EditorState) {
        guard editor.revision != renderedRevision else { return }
        render(editor.screenplay.elements) { [self] in
            restoreSelection(elementID: editor.activeElementID, offset: editor.selectionOffset)
        }
        renderedRevision = editor.revision
        updateTypingAttributes()
        updateGhost()
    }

    // MARK: - Setting the script

    /// Replaces the page with the model's current text.
    ///
    /// The whole string at once, as on the phone: the elements are the
    /// document, and rebuilding from them is what keeps the text and the model
    /// from ever disagreeing about what is on the page.
    /// Replaces the page with the model's current text, puts the caret back,
    /// and settles the viewport — in that order, which is the whole point of
    /// `restoringCaret` being a parameter rather than something the caller does
    /// afterwards.
    ///
    /// The viewport is settled by following the caret: the page moves by
    /// however far the insertion point moved, so a reflow above it does not
    /// drag the writer's line around. That only works if the caret is where it
    /// is going to be. Callers used to `render(...)` and *then* restore the
    /// selection, so the page was settled against whatever position replacing
    /// the storage happened to leave behind — and a dash typed into a heading
    /// scrolled that heading off the top of the window. See `PageStillnessTests`.
    public func render(
        _ elements: [ScriptElement],
        restoringCaret restore: (() -> Void)? = nil
    ) {
        let shouldHoldPage = editor != nil && renderedRevision >= 0
        let preserved = scrollView.contentView.bounds.origin

        applyingModel = true
        let script = ScriptLayout.attributedScript(elements, measure: measure)
        ranges = script.ranges
        lastLaidElements = elements
        textView.textStorage?.setAttributedString(script.text)
        layOut()
        applyingModel = false

        restore?()

        if shouldHoldPage {
            restoreViewport(preserved: preserved)
        }
        updateGhost()
    }

    /// Brings the view's own geometry up to date with the text in it.
    ///
    /// Laying the glyphs out is not enough: a text view's height — and so the
    /// distance the page can travel — is a *result* of that layout, and is not
    /// recomputed until the view is asked. Measure in between and the page
    /// looks a single screen tall, the arithmetic concludes there is nowhere to
    /// scroll, and a reveal quietly does nothing. That is precisely the bug the
    /// phone shipped: a Navigator row that worked on the second tap, because by
    /// then the layout had caught up on its own.
    ///
    /// Asking is also not enough if `maxSize.height` is 0. `sizeToFit` will
    /// not grow past `maxSize`, and a view that started with frame height 0
    /// inherits that ceiling. The layout manager still has the glyphs; the
    /// view does not display them. See `testTheLastElementLandsOnTheCard`.
    private func layOut() {
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            container.size = CGSize(width: measure, height: .greatestFiniteMagnitude)
            applyPageBreaks(
                in: layoutManager, container: container, elements: lastLaidElements
            )
            layoutManager.ensureLayout(for: container)
            // sizeToFit uses usedRect, which is shorter than the glyph
            // bounding boxes (Courier's descent sits a couple of points
            // past the used rect). A view sized to usedRect clips the last
            // line's bounding box, and a containment test — or a selection
            // highlight — would miss it.
            let used = layoutManager.usedRect(for: container)
            let extra = layoutManager.extraLineFragmentUsedRect
            let glyphs = layoutManager.numberOfGlyphs
            let glyphBounds = glyphs > 0
                ? layoutManager.boundingRect(
                    forGlyphRange: NSRange(location: 0, length: glyphs), in: container
                )
                : .zero
            let height = max(used.maxY, extra.maxY, glyphBounds.maxY, 1)
            var frame = textView.frame
            frame.size.width = measure
            frame.size.height = ceil(height)
            textView.frame = frame
        } else {
            textView.sizeToFit()
        }
        let viewport = scrollView.contentView.bounds.size
        let size = viewport.width > 1 ? viewport : scrollView.frame.size
        let pages = ScreenplayExporter.paginate(Screenplay(elements: lastLaidElements))
        canvas.layoutPages(
            pageCount: max(1, pages?.count ?? 1),
            textHeight: max(textView.frame.height, 1),
            viewport: size
        )
        // Only in `continuous`, where the rule is the one thing saying a page
        // ended. In `pages` the gap between the sheets and their own edges
        // already say it, and a rule as well is a third mark for one
        // boundary.
        canvas.showBreaks(at: canvas.layoutMode == .continuous ? pageBreakPositions() : [])
        placeNoteMarkers()
        washNotedLines()
        scrollView.layoutSubtreeIfNeeded()
    }

    /// Draws the script as sheets or as one column.
    ///
    /// The whole point of the switch is that the document's height changes
    /// enormously — a hundred pages carry a hundred repeated margin pairs,
    /// about thirteen thousand points of it — so the writer has to be put
    /// back on the line they were reading, not at the scroll offset they
    /// happened to be at. Those are the same number only when nothing above
    /// them moved, which is exactly what this does not guarantee.
    func setLayoutMode(_ mode: PageLayoutMode) {
        guard canvas.layoutMode != mode else { return }
        let anchor = anchoredLine()
        canvas.layoutMode = mode
        PageLayoutMode.store(mode)
        editor?.reportLayoutMode(mode)
        layOut()
        scrollBack(to: anchor)
        updateGhost()
    }

    /// The line at the top of what the writer can see, and how far below the
    /// viewport's edge it sits.
    private func anchoredLine() -> (location: Int, offset: CGFloat)? {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return nil }
        let visible = scrollView.contentView.bounds
        let inText = canvas.convert(NSPoint(x: 0, y: visible.minY), to: textView)
        let glyph = layoutManager.glyphIndex(for: inText, in: container)
        let location = layoutManager.characterIndexForGlyph(at: glyph)
        guard let rect = boundingRect(atCharacter: location) else { return nil }
        return (location, canvas.convert(rect, from: textView).minY - visible.minY)
    }

    private func scrollBack(to anchor: (location: Int, offset: CGFloat)?) {
        guard let anchor, let rect = boundingRect(atCharacter: anchor.location) else { return }
        let y = canvas.convert(rect, from: textView).minY - anchor.offset
        let clip = scrollView.contentView
        clip.scroll(to: NSPoint(
            x: clip.bounds.origin.x,
            y: min(max(0, y), max(0, canvas.frame.height - clip.bounds.height))
        ))
        scrollView.reflectScrolledClipView(clip)
    }

    /// One character's rectangle, clamped so the end of the document does not
    /// need a special case at every call site.
    private func boundingRect(atCharacter location: Int) -> CGRect? {
        let length = (textView.string as NSString).length
        let clamped = min(max(0, location), length)
        let probe = NSRange(location: clamped, length: min(1, max(0, length - clamped)))
        return ScriptLayout.boundingRect(of: probe, in: textView)
    }

    /// Where each page after the first actually begins, in canvas
    /// coordinates, measured after the layout rather than predicted from it.
    ///
    /// Both modes ask the same question of the same laid-out text, so a
    /// marker cannot land anywhere but on the line the engine says starts
    /// that page.
    private func pageBreakPositions() -> [CGFloat] {
        guard let pages = ScreenplayExporter.paginate(Screenplay(elements: lastLaidElements)),
              pages.count > 1 else { return [] }
        let locations = ScreenplayPageLayout.pageStartLocations(
            elements: lastLaidElements, pages: pages
        )
        return locations.dropFirst().compactMap { location in
            boundingRect(atCharacter: location).map { canvas.convert($0, from: textView).minY }
        }
    }

    /// Exclusion paths for the desk between sheets, placed from the
    /// paginator's page-start locations — not from a second line count.
    /// Where each page after the first begins, in the text view's own
    /// coordinates — and, in `pages`, the exclusion paths that put it there.
    ///
    /// The engine decides which line starts which page; this only decides
    /// where that line is *drawn*. `continuous` inserts nothing, so line 56
    /// follows line 55 and the 132 points of margin the two pages would have
    /// repeated are simply not there. `pages` pushes each page's first line
    /// down to its own sheet, which is the same arithmetic as before.
    private func applyPageBreaks(
        in layoutManager: NSLayoutManager,
        container: NSTextContainer,
        elements: [ScriptElement]
    ) {
        container.exclusionPaths = []
        layoutManager.ensureLayout(for: container)
        guard let pages = ScreenplayExporter.paginate(Screenplay(elements: elements)),
              pages.count > 1
        else { return }

        let locations = ScreenplayPageLayout.pageStartLocations(
            elements: elements, pages: pages
        )
        let length = (textView.string as NSString).length
        var ungapped: [CGFloat] = []
        ungapped.reserveCapacity(locations.count)
        for location in locations {
            let loc = min(max(0, location), length)
            let probe = loc < length
                ? NSRange(location: loc, length: min(1, length - loc))
                : NSRange(location: max(0, length - 1), length: 0)
            let rect = ScriptLayout.boundingRect(of: probe, in: textView)
                ?? layoutManager.extraLineFragmentUsedRect
            ungapped.append(rect.minY)
        }

        // `continuous` inserts nothing: line 56 follows line 55, and the
        // 132 points of margin the two pages would have repeated are simply
        // not there.
        guard canvas.layoutMode == .pages else { return }

        var paths: [NSBezierPath] = []
        var placed: CGFloat = 0
        let sheet = PageFormat.current.pageRect.height
        for index in 0..<(pages.count - 1) {
            let target = CGFloat(index + 1) * (sheet + PageCanvasView.pageGap)
            let ungappedY = index + 1 < ungapped.count ? ungapped[index + 1] : 0
            let gap = target - ungappedY - placed
            guard gap > 0.5 else { continue }
            paths.append(NSBezierPath(rect: CGRect(
                x: 0, y: ungappedY + placed, width: container.size.width, height: gap
            )))
            placed += gap
        }
        container.exclusionPaths = paths
    }

    /// Recentres the page card in a resized window. The script's measure is
    /// the printed text block, so a wider window does not stretch a line.
    public func remeasure(to width: CGFloat, elements: [ScriptElement]) {
        guard width > 0 else { return }
        lastLaidElements = elements
        // Lay out before magnifying. `NSScrollView` clamps a magnification set
        // while its document view is still the wrong size, so fitting first and
        // laying out second let a keystroke knock the page back to its own
        // metrics. Laying out again afterwards only costs a pass when the
        // magnification actually moved, which is when the canvas needs
        // re-centring anyway.
        layOut()
        if applyPreferredMagnification() { layOut() }
        updateGhost()
    }

    /// Draws the page at the size the current preference asks for, given how
    /// much room there is now. Cheap to call often: magnification is a no-op
    /// unless it actually moved. The opening pin still runs, once.
    func applyZoomForCurrentSize() {
        // Never mid-pinch: setting the magnification while AppKit is animating
        // its own is what made the page shrink and bounce.
        guard !isLiveMagnifying, scrollView.contentView.frame.width > 1 else { return }
        if applyPreferredMagnification() {
            layOut()
            updateGhost()
        }
        pinOpeningViewportIfNeeded()
    }

    // MARK: - How large the page is drawn

    /// The size the writer is working at, as distinct from the size on screen.
    ///
    /// They are the same thing until the percentage button is used: that shows
    /// actual size *temporarily*, so pressing it twice must give back the size
    /// that was there before rather than leaving the writer to find it again.
    private enum SizePreference {
        /// Follow the window. The default, because it needs no decision and no
        /// setting to remember.
        case fit
        /// A size the writer asked for, which a resize must not undo.
        case fixed(CGFloat)
    }

    /// The size the writer is working at — where the percentage button goes
    /// when it is not showing actual size.
    ///
    /// Starts at `PageZoom.opening` rather than at the fit or at 100%: a page
    /// at its own metrics is under half life size on a laptop, and a page
    /// fitted to a wide window is larger than anyone writes at. A notch above
    /// actual size is where word processors have settled, from the same
    /// arithmetic.
    private var preference: SizePreference = .fixed(PageZoom.opening)

    /// Whether the percentage button is currently holding the page at 100%.
    private var atActualSize = false

    func applyZoom(_ command: PageZoom.Command) {
        switch command {
        case .fit:
            preference = .fit
            atActualSize = false
        case .zoomIn, .zoomOut:
            preference = .fixed(PageZoom.stepped(from: scrollView.magnification, command))
            atActualSize = false
        case .actualSize:
            // Leaves the preference alone, so the percentage button still
            // knows where to go back to. ⌘0 and that button are the same
            // gesture reached two ways.
            atActualSize = true
        case .toggleActualSize:
            atActualSize.toggle()
        }
        layOut()
        if applyPreferredMagnification() { layOut() }
        updateGhost()
    }

    /// Sets the magnification the current preference asks for, and says
    /// whether it moved — the caller re-centres the canvas when it did.
    @discardableResult
    private func applyPreferredMagnification() -> Bool {
        magnify(to: atActualSize ? PageZoom.actualSize : preferredMagnification())
    }

    private func preferredMagnification() -> CGFloat {
        switch preference {
        case .fixed(let value): value
        case .fit:
            // The clip view's *frame* is the width in screen points; its bounds
            // are already divided by the magnification, which is the number
            // being solved for here.
            scrollView.contentView.frame.width > 1
                ? PageZoom.fitting(
                    canvasWidth: scrollView.contentView.frame.width,
                    pageWidth: PageFormat.current.pageRect.width,
                    padding: canvas.canvasPadding
                )
                : scrollView.magnification
        }
    }

    @discardableResult
    /// The scroll view's magnification is the only truth about how large the
    /// page is drawn, because it is what draws it. Everything else follows it
    /// from one place — `magnificationChanged` — rather than each writer of the
    /// size also remembering to announce it. A trackpad pinch goes straight to
    /// the scroll view and told nobody, which is how the control came to show a
    /// number the page did not have.
    private func magnify(to value: CGFloat) -> Bool {
        guard abs(scrollView.magnification - value) > 0.001 else {
            editor?.reportZoom(value)
            return false
        }
        isSettingMagnification = true
        scrollView.magnification = value
        isSettingMagnification = false
        magnificationChanged(to: value, fromGesture: false)
        return true
    }

    /// One place where a new size becomes known, however it was chosen.
    ///
    /// A pinch is the writer choosing a size, exactly as ⌘+ is, so it becomes
    /// the preference — otherwise the next window resize would take it away
    /// again while the page was "fitting".
    private func magnificationChanged(to value: CGFloat, fromGesture: Bool) {
        editor?.reportZoom(value)
        // While the fingers are still down, the readout above is all that
        // moves. AppKit is mid-gesture and settling its own rubber-band;
        // anything else here is two hands on the same wheel.
        guard fromGesture, !isLiveMagnifying else { return }
        settleAfterGesture()
    }

    /// The size the gesture left behind becomes the writer's choice, and the
    /// canvas is measured for it.
    private func settleAfterGesture() {
        preference = .fixed(scrollView.magnification)
        atActualSize = false
        editor?.reportZoom(scrollView.magnification)
        // The canvas is measured in document coordinates, which a pinch
        // changes: zooming out widens the viewport and the card has to be
        // re-centred in it, or the page sits where it was — against the left
        // edge. The menu and the corner buttons already lay out afterwards;
        // the gesture went straight to the scroll view and skipped it.
        //
        // Deliberately no scroll correction here. `NSScrollView` anchors a
        // pinch on the point under the fingers, and forcing the viewport back
        // to centre would drag the page out from under them.
        //
        // Nothing to re-measure. The canvas is the pages and their desk at any
        // magnification, and `CentringClipView` keeps it in the middle of the
        // window — so the page is centred throughout the gesture rather than
        // arriving there in a jump when the fingers lift.
        updateGhost()
    }

    /// The writer changed what the page is made of.
    ///
    /// Everything that carries the paper's colour is a snapshot: the sheet's
    /// layer, the caret, and the ink baked into the text storage's attributes.
    /// Re-taking all three is what makes the choice land without a relaunch.
    private func paperChanged() {
        guard renderedPaper != PagePaper.stored else { return }
        renderedPaper = PagePaper.stored
        // `applyAppearance` re-takes the paper, the card and the caret.
        canvas.applyAppearance()
        guard let editor else { return }
        renderedRevision = -1
        renderIfNeeded(editor)
    }

    /// Lets the page run under the toolbar, which is the whole of what the
    /// header needed.
    ///
    /// macOS softens content passing beneath the chrome by itself —
    /// `NSScrollEdgeEffectStyle`, applied by the titlebar to whatever scrolls
    /// under it. It never appeared here because nothing scrolled under it: a
    /// window's content view stops below the titlebar unless it is told
    /// otherwise, so the toolbar had its own opaque ground beneath it and
    /// ended in a step. `.fullSizeContentView` is the switch, and it is the
    /// same one TextEdit and Pages throw.
    ///
    /// Nothing needs to move to make room. `NSScrollView` insets its *content*
    /// below the titlebar on its own — `automaticallyAdjustsContentInsets`,
    /// left at its default — so the first line still starts in the clear while
    /// the desk carries on up behind the glass.
    private func openTheWindowToItsFullHeight() {
        guard let window = scrollView.window else { return }
        window.styleMask.insert(.fullSizeContentView)
        askForApplesSoftScrollEdge()
    }

    /// Asks AppKit for the soft edge on the column the page is in.
    ///
    /// See `SoftScrollEdgeAccessory` for why it is the split view item's
    /// accessory and not the titlebar's. Finding the item means walking up to
    /// the split view, because `NavigationSplitView` builds it and does not
    /// hand it over — the walk is guarded at every step and does nothing at
    /// all if the shape is ever not what it is today.
    private func askForApplesSoftScrollEdge() {
        guard #available(macOS 26.1, *) else { return }

        var ancestor: NSView? = scrollView.superview
        while let view = ancestor, !(view is NSSplitView) { ancestor = view.superview }
        guard let splitView = ancestor as? NSSplitView,
              let controller = splitView.delegate as? NSSplitViewController,
              let column = controller.splitViewItems.first(where: {
                  scrollView.isDescendant(of: $0.viewController.view)
              }),
              !column.topAlignedAccessoryViewControllers.contains(where: {
                  $0 is SoftScrollEdgeAccessory
              })
        else { return }

        column.addTopAlignedAccessoryViewController(SoftScrollEdgeAccessory())

        if ProcessInfo.processInfo.environment["EDRAFT_EDGE_DEBUG"] != nil {
            fputs("EDGE column accessories="
                  + "\(column.topAlignedAccessoryViewControllers.count)\n", stderr)
        }
    }

    /// Puts the caret in the page the first time there is a window to put it
    /// in, and never again.
    ///
    /// A Mac document window opens ready to be typed into — that is true of
    /// TextEdit, Pages and Xcode, and a screenplay app that asks first is
    /// asking for nothing. Until now the only thing that gave the page focus
    /// was an "Edit" button in the toolbar, which meant ⌘N produced a
    /// screenplay you could not type in until you found it.
    ///
    /// Once only, because focus is the writer's after that: clicking the
    /// Navigator or the scene filter should not be undone by the page
    /// snatching it back on the next layout pass.
    func takeInitialFocus() {
        guard !hasTakenInitialFocus, let window = scrollView.window else { return }
        hasTakenInitialFocus = true
        placeCaretForEditing()
        window.makeFirstResponder(textView)
        pinOpeningViewportIfNeeded()
    }

    /// `NSScrollView` keeps the clip-view centre when magnification
    /// changes. The opening size is 1.5×, so a window that first lays
    /// out at 100% and then magnifies lands about a third of a screen
    /// down the page: the first line is off the top, the next is cut
    /// in half. Pin once, after that size is actually applied, and
    /// never again — a later ⌘+ must not jump the writer to page one.
    private func pinOpeningViewportIfNeeded() {
        guard pinsOpeningViewport, !hasPinnedOpeningViewport else { return }
        guard scrollView.window != nil, scrollView.contentView.frame.width > 1 else { return }
        let target = atActualSize ? PageZoom.actualSize : preferredMagnification()
        guard abs(scrollView.magnification - target) <= 0.01 else { return }
        hasPinnedOpeningViewport = true
        let origin = scrollView.contentView.bounds.origin
        guard abs(origin.y) > 0.5 else { return }
        scrollView.contentView.scroll(to: NSPoint(x: origin.x, y: 0))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// The first sheet, in the canvas's coordinates — what a test asks when
    /// it wants to know the paper is actually there.
    public var pageFrame: CGRect { canvas.pageView.frame }

    /// Every sheet. Empty only before the first layout.
    public var pageFrames: [CGRect] { canvas.pageViews.map(\.frame) }

    /// Where the lines between the sheets are, for a test that has to know
    /// there is something to press.
    public var breakMarkerFrames: [CGRect] { canvas.breakMarkerFrames }

    /// What is currently laid out, so a test can ask the engine whether the
    /// page boundaries moved rather than trusting that they did not.
    public var renderedElements: [ScriptElement] { lastLaidElements }

    /// The character at the top of what the writer can see. This is the thing
    /// a mode change has to preserve — not the scroll offset, which means
    /// something different once the document's height has changed.
    public var topmostVisibleCharacter: Int? { anchoredLine()?.location }

    /// Six lines to the inch without cropping a tall glyph. Held here because
    /// `NSLayoutManager.delegate` is weak.
    private let fixedLeading = FixedLeading()
    /// True while this class is the one changing the magnification, so the
    /// observer can tell the writer's pinch from our own setting.
    private var isSettingMagnification = false
    private var magnificationObserver: NSKeyValueObservation?
    /// True between `willStartLiveMagnify` and `didEndLiveMagnify`.
    ///
    /// A pinch is not one change of size, it is dozens a second, and AppKit
    /// rubber-bands past the limits and settles back on its own. Recording a
    /// preference and re-measuring the canvas on every one of those fights the
    /// gesture — the page shrinks, snaps and bounces under the fingers. So the
    /// readout follows live and nothing else moves until the fingers lift.
    private var isLiveMagnifying = false
    private var liveMagnifyObservers: [any NSObjectProtocol] = []
    private var hasTakenInitialFocus = false
    private var hasPinnedOpeningViewport = false
    /// Tests that isolate the opening zoom set this false; the SwiftUI
    /// path then still crops, which is how we know the crop is the
    /// zoom, not the caret.
    var pinsOpeningViewport = true
    private var frameObserver: (any NSObjectProtocol)?

    // MARK: - Notes

    /// Puts a mark in the margin beside every note's line.
    ///
    /// The line comes from the laid-out text, not from a count of elements:
    /// an element wraps, and the mark belongs beside the line the note is
    /// about rather than beside the line a tally says it should be.
    private func placeNoteMarkers() {
        canvas.showNotes(notePlacements(), active: openNoteID) { [weak self] id in
            self?.openNote(id)
        }
    }

    /// Tints the lines that have notes on them, so the mark in the margin
    /// says *which* line it is about.
    ///
    /// A temporary attribute rather than one written into the text storage:
    /// the storage is the script, and a colour put there would follow the
    /// writer's words into a copy, a paste and a PDF. Temporary attributes
    /// live on the layout manager, which is exactly the distinction — how
    /// this text is drawn right now, not what it is.
    private func washNotedLines() {
        guard let layoutManager = textView.layoutManager else { return }
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
        guard let editor, !editor.notes.isEmpty else { return }

        let byElement = Dictionary(ranges.map { ($0.id, $0.range) }) { first, _ in first }
        // Resolved for the page's own appearance, the way the ink is: a light
        // page in a dark app takes the wash meant for paper.
        var wash: NSColor = .screenplayNoteWash
        var open: NSColor = .screenplayOpenNoteWash
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            wash = NSColor.screenplayNoteWash.usingColorSpace(.sRGB) ?? wash
            open = NSColor.screenplayOpenNoteWash.usingColorSpace(.sRGB) ?? open
        }

        for note in editor.notes {
            guard let anchor = note.anchor, let range = byElement[anchor], range.length > 0,
                  NSMaxRange(range) <= whole.length else { continue }
            layoutManager.addTemporaryAttribute(
                .backgroundColor,
                value: note.id == openNoteID ? open : wash,
                forCharacterRange: range
            )
        }
    }

    /// Where each note's mark goes, in canvas coordinates.
    private func notePlacements() -> [PageCanvasView.NotePlacement] {
        guard let editor else { return [] }
        let byElement = Dictionary(ranges.map { ($0.id, $0.range) }) { first, _ in first }
        return editor.notes.compactMap { note -> PageCanvasView.NotePlacement? in
            // A note anchored to nothing trails the script, and belongs
            // beside its last line — which is where the writer left it.
            let range = note.anchor.flatMap { byElement[$0] } ?? ranges.last?.range
            guard let range, let rect = boundingRect(atCharacter: range.location) else { return nil }
            let inCanvas = canvas.convert(rect, from: textView)
            return PageCanvasView.NotePlacement(
                id: note.id, lineTop: inCanvas.minY, lineHeight: inCanvas.height
            )
        }
    }

    /// Leaves a note beside the line the caret is on, and opens it.
    ///
    /// Laid out before the card is shown, because the card points at the
    /// mark in the margin and the mark is placed by the layout.
    private func addNoteAtCaret() {
        addNote(to: nil)
    }

    /// `nil` means the caret's own element — see `EditorState.addNote`.
    private func addNote(to anchor: UUID?) {
        guard let editor, let note = editor.addNote(to: anchor) else { return }
        renderIfNeeded(editor)
        openNote(note.id)
    }

    /// Opens a note's card, pointing at its mark.
    ///
    /// An `NSPopover` rather than a card parked in the margin: the desk is
    /// 36 points wide either side of the paper and a Pages comment card is
    /// 260, so a card that lived out there would either cover the script or
    /// push the page off centre every time a note existed. A popover is the
    /// same rounded, elevated card with an arrow to the mark it came from,
    /// and it is the system's own.
    public func openNote(_ id: UUID) {
        guard let editor, let note = editor.notes.first(where: { $0.id == id }),
              let marker = canvas.noteMarker(for: id) else { return }

        commitOpenNote()
        notePopover?.performClose(nil)
        let total = editor.notes.count
        let position = (editor.notes.firstIndex { $0.id == id } ?? 0) + 1

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: NoteCard(
                note: note,
                position: position,
                total: total,
                onEdit: { [weak self] text in self?.openNoteDraft = text },
                onDone: { [weak self] in self?.commitOpenNote() },
                onDelete: { [weak self] in
                    guard let self else { return }
                    // Dropped before the popover closes, so `popoverDidClose`
                    // does not write the deleted note's text back and
                    // resurrect it.
                    self.openNoteDraft = nil
                    self.notePopover?.performClose(nil)
                    self.editor?.deleteNote(id: id)
                },
                onMove: { [weak self] step in
                    guard let self, let editor = self.editor else { return }
                    let index = (editor.notes.firstIndex { $0.id == id } ?? 0) + step
                    guard editor.notes.indices.contains(index) else { return }
                    let next = editor.notes[index].id
                    // Reveal first: a mark scrolled off the page has no view
                    // for the next card to point at.
                    self.revealNote(next)
                    self.openNote(next)
                }
            )
        )
        notePopover = popover
        openNoteID = id
        openNoteDraft = nil
        placeNoteMarkers()
        washNotedLines()
        popover.show(relativeTo: marker.bounds, of: marker, preferredEdge: .maxX)
    }

    /// However the card ends — clicked away from, replaced, or closed with
    /// the window — this is where the writing lands.
    public func popoverDidClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === notePopover else { return }
        commitOpenNote()
        openNoteID = nil
        notePopover = nil
        placeNoteMarkers()
        washNotedLines()
    }

    /// Writes what the open card reads into the model, if it changed.
    ///
    /// The one place a note is written. Called when the card closes — by the
    /// writer clicking away, by the next note replacing it, or by the window
    /// going away — so the arrangement holds however the card ends.
    private func commitOpenNote() {
        guard let id = openNoteID else { return }
        let draft = openNoteDraft
        openNoteDraft = nil
        // What to do with a blank one is the model's rule, not the card's —
        // the phone's surface will close a note too. See `finishNote`.
        editor?.finishNote(id: id, text: draft)
    }

    /// Brings a note's mark into view — and only if it is not already there.
    ///
    /// Stepping to the next note must not move the page when the next note is
    /// already on screen. Revealing unconditionally scrolled the line to the
    /// top of the window and took the caret with it, so reading two notes on
    /// one page threw the writer's place away twice.
    ///
    /// `scrollToVisible` is the system's own minimum scroll: nothing happens
    /// when the rectangle is visible, and when it is not, the page moves the
    /// least distance that makes it so.
    private func revealNote(_ id: UUID) {
        guard let marker = canvas.noteMarker(for: id) else { return }
        // A line of air around the mark, so a note arriving from off-screen
        // does not land flush against the edge of the window.
        canvas.scrollToVisible(marker.frame.insetBy(dx: 0, dy: -ScreenplayPageLayout.lineHeight))
        scrollView.layoutSubtreeIfNeeded()
    }

    // MARK: - Going to an element

    /// Brings an element into view and marks it.
    ///
    /// Two jobs, and the second is not optional: a script stops scrolling when
    /// its last page reaches the bottom, so a target near the end never reaches
    /// the top and one already in view does not move the page at all. See
    /// `RevealMark`.
    @discardableResult
    public func reveal(_ id: UUID, reduceMotion: Bool = false) -> Bool {
        if let editor, editor.revision != renderedRevision {
            renderIfNeeded(editor)
        }
        guard let mapped = ranges.first(where: { $0.id == id }),
              let rect = ScriptLayout.boundingRect(of: mapped.range, in: textView)
        else { return false }

        textView.setSelectedRange(NSRange(location: mapped.range.location, length: 0))
        updateSelection()
        scroll(bringingToTop: rect)
        mark(rect, reduceMotion: reduceMotion)
        return true
    }

    /// Where the page rests, in the scroll view's own terms — measured against
    /// a layout that is current. See `layOut()`.
    public var scrollableRange: ClosedRange<CGFloat> {
        layOut()
        return PageScroll.range(
            contentHeight: canvas.frame.height,
            viewportHeight: scrollView.contentView.bounds.height,
            topInset: scrollView.contentInsets.top,
            bottomInset: scrollView.contentInsets.bottom
        )
    }

    /// Moves the page so `rect` rests at the top of the readable area — as
    /// near as the document allows.
    public func scroll(bringingToTop rect: CGRect) {
        let range = scrollableRange
        guard PageScroll.canScroll(range) else { return }
        let y = PageScroll.offset(
            bringingContentY: canvasY(ofTextRect: rect), toTopOf: range
        )
        scrollView.contentView.scroll(to: NSPoint(x: max(0, canvas.pageView.frame.minX - canvas.canvasPadding), y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    /// A text-view rectangle, lifted into the canvas the scroll view actually
    /// moves. The page card sits around the text; without this, a reveal
    /// would scroll as if the paper's top margin were not there.
    /// `rect` is in the text view's coordinates already — `ScriptLayout.boundingRect`
    /// adds `textContainerOrigin`, which is the inset. Adding the inset here as
    /// well put every reveal one line low, because the inset *is* one line
    /// (`glyphOverflow`). Measured on screen, 2026-09-08.
    private func canvasY(ofTextRect rect: CGRect) -> CGFloat {
        rect.minY + textView.frame.minY
    }

    private func mark(_ rect: CGRect, reduceMotion: Bool) {
        var marked = rect
        if marked.width < 1, let container = textView.textContainer {
            marked.size.width = container.size.width
        }
        highlight.mark(marked, in: textView, reduceMotion: reduceMotion)
    }

    /// Whether a mark is currently on the page — the surface's own answer to
    /// "did that reveal say anything?", and what a test asks.
    public var isMarking: Bool {
        highlight.superview === textView && highlight.frame.height > 0
    }

    /// Which element the insertion point is in, if any.
    public func element(at location: Int) -> UUID? {
        elementRange(at: location)?.id
    }

    // MARK: - NSTextViewDelegate

    /// Tab is a kind cycle, never a character. `doCommandBy` is the AppKit
    /// path; there is no `NSTextView` subclass, so this is also the only path.
    /// Return and delete fall through to `shouldChangeTextIn`, which is the
    /// one place they are handled.
    public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            editor?.cycleActiveKind(backwards: false)
            return true
        }
        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            editor?.cycleActiveKind(backwards: true)
            return true
        }
        return false
    }

    /// Right-clicking the page offers a note on the line under the pointer.
    ///
    /// Added to the system's own menu rather than replacing it: Cut, Copy,
    /// Paste, Look Up, the writing tools and the spelling submenu are all
    /// still there, because a text view's context menu is the system's and a
    /// screenplay editor has no business shortening it.
    public func textView(
        _ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int
    ) -> NSMenu? {
        guard editor != nil else { return menu }
        // The line under the pointer, not the line the caret happens to be
        // on: a right-click does not move the caret, and a note that landed
        // somewhere else is a note in the wrong scene.
        rightClickedElement = elementRange(at: charIndex)?.id
        let item = NSMenuItem(
            title: "Add Note", action: #selector(addNoteFromMenu), keyEquivalent: ""
        )
        item.target = self
        menu.insertItem(item, at: 0)
        menu.insertItem(.separator(), at: 1)
        return menu
    }

    @objc private func addNoteFromMenu() {
        addNote(to: rightClickedElement)
        rightClickedElement = nil
    }

    public func undoManager(for view: NSTextView) -> UndoManager? {
        editingUndo
    }

    public func textView(
        _ textView: NSTextView,
        shouldChangeTextIn range: NSRange,
        replacementString replacement: String?
    ) -> Bool {
        guard let editor else { return true }
        guard let replacement else { return true }

        // The separator's escape hatch lives for exactly one keystroke:
        // the delete that immediately follows it. Consuming it here means
        // every other path clears it simply by not being that delete.
        let separatorEscape = pendingSeparatorEscape
        pendingSeparatorEscape = nil

        if textView.hasMarkedText() {
            pendingEdit = nil
            hideGhost()
            return true
        }

        let text = replacement
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        // A real Tab is consumed in `doCommandBy`. A pasted lone `\t` is not
        // a kind cycle — cycling here used to fire on paste and change the
        // line the writer did not ask to change. Refuse the character; a
        // screenplay has no tabs. A larger paste that happens to contain one
        // still goes through the planner.
        if text == "\t" {
            return false
        }

        let mapped = elementRange(at: range.location)
        let index = mapped.flatMap { mapped in
            editor.screenplay.elements.firstIndex(where: { $0.id == mapped.id })
        }

        if let mapped, let index,
           shouldAcceptPredictionWithSpace(
            editor: editor,
            mapped: mapped,
            elementIndex: index,
            range: range,
            replacement: text
           ) {
            acceptPrediction(appendingSpace: true)
            return false
        }

        if let mapped, let index {
            if text == "-", writeSceneSeparator(replacing: range, in: mapped, at: index) {
                return false
            }
            if text == " ", range.length == 0,
               absorbsSeparatorSpace(at: range, in: mapped, at: index) {
                return false
            }
            if text.isEmpty, range.length == 1, let separatorEscape,
               collapseSceneSeparator(
                replacing: range, in: mapped, at: index, escape: separatorEscape
               ) {
                return false
            }
        }

        let source = textView.string as NSString
        if ScreenplayEditPlanner.touchesParagraphBoundary(
            in: source,
            range: range,
            replacement: text
        ) {
            let deleted = range.location >= 0 && NSMaxRange(range) <= source.length
                ? source.substring(with: range)
                : ""
            let selected = textView.selectedRange()
            let isBoundaryDeletion = text.isEmpty
                && deleted == "\n"
                && selected.length == 0
                && (selected.location == range.location
                    || selected.location == NSMaxRange(range))

            // Return on a line with nothing on it changes what the line
            // is rather than making another one under it — the writer is
            // saying they are done with this kind, not asking for more of
            // it. What it becomes is the engine's to say: action out of a
            // speech, a cue out of action. See Choreography.emptyLineEscape.
            if text == "\n", range.length == 0, let index, let escaped = emptyLineEscape(at: index) {
                var elements = editor.screenplay.elements
                elements[index].type = escaped
                elements[index].text = ""
                applyModelEdit(
                    elements,
                    activeID: elements[index].id,
                    offset: 0,
                    selection: NSRange(location: mapped?.range.location ?? range.location, length: 0),
                    actionName: "Change Element"
                )
                return false
            }

            let intent: ScreenplayEditPlanner.Intent
            if isBoundaryDeletion {
                intent = selected.location == NSMaxRange(range)
                    ? .backspaceAtElementStart
                    : .boundaryDeletion
            } else if text == "\n" {
                intent = .returnKey
            } else if text.contains("\n") {
                intent = .multilinePaste
            } else {
                intent = .replacement
            }
            if applyStructuralReplacement(
                range: range,
                replacement: text,
                intent: intent,
                actionName: structuralActionName(replacement: text)
            ) {
                return false
            }
        }

        guard let mapped else {
            pendingEdit = nil
            return true
        }

        // Shout at the door, not after the fact.
        //
        // The page uppercases headings, cues, transitions and shots. Letting
        // the lowercase letter into the storage and rewriting the element
        // afterwards cannot work: replacing a range of an `NSTextView`'s
        // storage moves the insertion point to the end of what was replaced
        // (`ShoutedTypingTests.testReplacingAStorageRangeMovesTheInsertionPoint`),
        // so every letter typed anywhere but the end of the line threw the
        // caret to the end and the next letter landed there. `int` at the head
        // of LOCATION gave ILOCATIONNT.
        //
        // Inserting the shouted text instead means the wrong characters are
        // never in the document, AppKit places the caret itself, and undo sees
        // one insertion of what the writer meant. `insertText` re-enters this
        // method with text that already equals its own uppercase, so the
        // branch is not taken twice.
        if let index {
            let shouted = EditorState.normalizedText(
                text, for: editor.screenplay.elements[index].type
            )
            if shouted != text {
                textView.insertText(shouted, replacementRange: range)
                return false
            }
        }

        editor.prepareForNativeEdit()
        if !text.contains("\n"),
           range.location >= mapped.range.location,
           NSMaxRange(range) <= NSMaxRange(mapped.range) {
            pendingEdit = PendingEdit(
                elementID: mapped.id,
                replacedRange: range,
                insertedLength: (text as NSString).length
            )
        } else {
            pendingEdit = nil
        }
        return true
    }

    public func textDidBeginEditing(_ notification: Notification) {
        editor?.reportEditing(true)
    }

    public func textDidEndEditing(_ notification: Notification) {
        editor?.reportEditing(false)
        hideGhost()
        editor?.flushPendingWork()
    }

    public func textDidChange(_ notification: Notification) {
        guard !applyingModel, let editor else { return }
        
        let previousRevision = editor.revision
        if let pendingEdit, applyIncrementalEdit(pendingEdit) {
            self.pendingEdit = nil
        } else {
            self.pendingEdit = nil
            synchronizeModelFromNativeText()
        }
        
        if editor.revision != previousRevision {
            promoteToSceneHeadingIfTyped()
            renderedRevision = editor.revision
            lastLaidElements = editor.screenplay.elements
            updateTypingAttributes()
            reportNativeUndoAvailability()
            layOut()
            updateGhost()
        } else {
            render(editor.screenplay.elements) { [self] in
                restoreSelection(elementID: editor.activeElementID, offset: editor.selectionOffset)
            }
            updateGhost()
        }
    }

    public func textViewDidChangeSelection(_ notification: Notification) {
        guard !applyingModel else { return }
        updateSelection()
        formatBar.update(selection: textView.selectedRange(), in: textView, canvas: canvas)
        updateGhost()
    }

    // MARK: - Incremental edits

    private func applyIncrementalEdit(_ edit: PendingEdit) -> Bool {
        guard let editor,
              let rangeIndex = ranges.firstIndex(where: { $0.id == edit.elementID }) else {
            return false
        }

        let delta = edit.insertedLength - edit.replacedRange.length
        let newLength = ranges[rangeIndex].range.length + delta
        guard newLength >= 0 else { return false }

        adjustRange(at: rangeIndex, length: newLength, shiftLaterBy: delta)

        let updatedRange = ranges[rangeIndex].range
        let storage = textView.textStorage
        guard let storage, NSMaxRange(updatedRange) <= storage.length else { return false }
        // The text is already shouted if its kind shouts: that happens at the
        // input boundary in `shouldChangeTextIn`, before the characters reach
        // the storage. Nothing to repair here — and the old repair also had to
        // refuse expanding case mappings (ß → SS) to keep its range arithmetic,
        // which left the view lowercase while the model normalised to caps.
        let text = storage.attributedSubstring(from: updatedRange).string
        let selected = textView.selectedRange()
        let offset = max(
            0,
            min(updatedRange.length, selected.location - updatedRange.location)
        )
        // A glyph taller than the line has to be brought into it, because
        // TextKit clips drawing to the line fragment — see `fitTallGlyphs`.
        ScriptLayout.fitTallGlyphs(storage, range: updatedRange)
        editor.applyLiveText(id: edit.elementID, text: text, selectionOffset: offset)
        return true
    }

    private func synchronizeModelFromNativeText() {
        guard let editor else { return }
        let previousText = ScreenplayEditPlanner.flattenedText(editor.screenplay.elements)
        guard let difference = ScreenplayEditPlanner.replacementBetween(
            previousText,
            textView.string
        ) else { return }

        editor.prepareForNativeEdit()
        let source = previousText as NSString
        if !ScreenplayEditPlanner.touchesParagraphBoundary(
            in: source,
            range: difference.0,
            replacement: difference.1
        ),
           let mapped = elementRange(at: difference.0.location),
           difference.0.location >= mapped.range.location,
           NSMaxRange(difference.0) <= NSMaxRange(mapped.range) {
            let edit = PendingEdit(
                elementID: mapped.id,
                replacedRange: difference.0,
                insertedLength: (difference.1 as NSString).length
            )
            if applyIncrementalEdit(edit) { return }
        }

        let nativeSelection = textView.selectedRange()
        guard let plan = ScreenplayEditPlanner.plan(
            elements: editor.screenplay.elements,
            replacing: difference.0,
            with: difference.1,
            intent: .replacement,
            kindForNewElement: { previous, text in
                editor.kindForInsertedElement(after: previous, text: text)
            }
        ) else { return }
        editor.replaceAllElements(
            plan.elements,
            activeID: plan.activeElementID,
            offset: plan.activeOffset,
            structural: false,
            recordsUndo: false
        )
        render(plan.elements) { [self] in restoreSelection(nativeSelection) }
        renderedRevision = editor.revision
    }

    // MARK: - Structural edits

    private func applyStructuralReplacement(
        range: NSRange,
        replacement: String,
        intent: ScreenplayEditPlanner.Intent,
        actionName: String
    ) -> Bool {
        guard let editor,
              let plan = ScreenplayEditPlanner.plan(
                elements: editor.screenplay.elements,
                replacing: range,
                with: replacement,
                intent: intent,
                kindForNewElement: { previous, text in
                    editor.kindForInsertedElement(after: previous, text: text)
                }
              ) else { return false }
        applyModelEdit(
            plan.elements,
            activeID: plan.activeElementID,
            offset: plan.activeOffset,
            selection: plan.selection,
            actionName: actionName
        )
        return true
    }

    /// What the element at this index becomes when Return is pressed on
    /// it while it is empty, or nil when it is not empty — or when the
    /// escape would leave it exactly as it is, in which case Return has
    /// its ordinary meaning. `Choreography.emptyLineEscape` is the rule;
    /// the whitespace and no-op guards are the surface's, because they
    /// decide whether to ask at all.
    private func emptyLineEscape(at index: Int) -> ScreenplayKind? {
        guard let editor, editor.screenplay.elements.indices.contains(index) else { return nil }
        let element = editor.screenplay.elements[index]
        guard element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let escaped = ScreenplayKind(
            engineKind: Choreography.emptyLineEscape(from: element.type.engineKind)
        )
        return escaped == element.type ? nil : escaped
    }

    private func structuralActionName(replacement: String) -> String {
        if replacement == "\n" { return "Insert Paragraph" }
        if replacement.isEmpty { return "Delete" }
        if replacement.contains("\n") { return "Paste" }
        return "Edit"
    }

    private func applyModelEdit(
        _ elements: [ScriptElement],
        activeID: UUID,
        offset: Int,
        selection: NSRange,
        actionName: String
    ) {
        guard let editor else { return }
        editor.prepareForNativeEdit()
        let previousState = ModelUndoState(
            elements: editor.screenplay.elements,
            activeElementID: editor.activeElementID,
            selectionOffset: editor.selectionOffset,
            selection: textView.selectedRange()
        )
        editor.replaceAllElements(
            elements,
            activeID: activeID,
            offset: offset,
            structural: true,
            recordsUndo: false
        )
        registerModelUndo(previousState, actionName: actionName)
        render(elements) { [self] in restoreSelection(selection) }
        renderedRevision = editor.revision
        updateTypingAttributes()
        reportNativeUndoAvailability()
        updateGhost()
    }

    private func registerModelUndo(_ state: ModelUndoState, actionName: String) {
        editingUndo.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restoreModelUndoState(state, actionName: actionName)
            }
        }
        editingUndo.setActionName(actionName)
    }

    private func restoreModelUndoState(_ state: ModelUndoState, actionName: String) {
        guard let editor else { return }
        let inverse = ModelUndoState(
            elements: editor.screenplay.elements,
            activeElementID: editor.activeElementID,
            selectionOffset: editor.selectionOffset,
            selection: textView.selectedRange()
        )
        registerModelUndo(inverse, actionName: actionName)
        editor.replaceAllElements(
            state.elements,
            activeID: state.activeElementID,
            offset: state.selectionOffset,
            structural: true,
            recordsUndo: false
        )
        render(state.elements) { [self] in restoreSelection(state.selection) }
        renderedRevision = editor.revision
        updateTypingAttributes()
        reportNativeUndoAvailability()
        updateGhost()
    }

    // MARK: - Ghost

    /// Whether a completion is currently drawn on the page — what a test
    /// asks, rather than trusting the surface's bookkeeping alone.
    var isShowingGhost: Bool {
        !ghost.isHidden && ghost.frame.width > 0 && ghost.frame.height > 0
    }

    var presentedGhostSuffix: String? { ghost.presentedSuffix }
    var ghostFrame: NSRect { ghost.frame }
    var ghostHostLineRect: NSRect { ghost.hostLineRectForTests }
    var ghostForegroundColor: NSColor? { ghost.foregroundColorForTests }

    func updateGhost() {
        guard let editor else {
            hideGhost()
            return
        }
        // A surface with no window is the test harness, and is allowed to
        // draw. A real window without focus is not: the ghost is for the
        // writer who is typing, not for a page sitting in the background.
        let focused = textView.window == nil
            || textView.window?.firstResponder === textView
        guard focused,
              !scrollView.isFindBarVisible,
              !textView.hasMarkedText(),
              let suffix = editor.currentSuggestionSuffix,
              !suffix.isEmpty,
              textView.selectedRange().length == 0,
              let mapped = elementRange(at: textView.selectedRange().location),
              textView.selectedRange().location == NSMaxRange(mapped.range),
              editor.activeKind != .transition,
              editor.activeKind != .centered,
              let storage = textView.textStorage else {
            hideGhost()
            return
        }

        var suggestionAttributes = textView.typingAttributes
        suggestionAttributes[.foregroundColor] = editor.currentPrediction?.hint == true
            ? NSColor.screenplayHintInk
            : NSColor.screenplayGhostInk

        let isPresented = ghost.present(
            in: textView,
            base: NSAttributedString(attributedString: storage),
            suffix: suffix,
            insertionLocation: textView.selectedRange().location,
            paragraphRange: mapped.range,
            attributes: suggestionAttributes,
            revision: editor.revision
        )
        ghost.acceptsClicks = isPresented && editor.currentPrediction?.hint != true
        if isPresented, ghost.superview !== textView {
            textView.addSubview(ghost, positioned: .above, relativeTo: nil)
        }
    }

    private func hideGhost() {
        ghost.hide()
        ghost.acceptsClicks = false
    }

    /// Edit → Find. The system bar, with Replace disabled.
    public func showFind() {
        textFinder.performAction(.showFindInterface)
        updateGhost()
    }

    public func find(next: Bool) {
        textFinder.performAction(next ? .nextMatch : .previousMatch)
    }

    /// Whether the system find bar is currently up — what a test asks, and
    /// what hides the ghost.
    public var isFindBarVisible: Bool {
        scrollView.isFindBarVisible
    }

    private func shouldAcceptPredictionWithSpace(
        editor: EditorState,
        mapped: ScriptLayout.ElementRange,
        elementIndex: Int,
        range: NSRange,
        replacement: String
    ) -> Bool {
        let selected = textView.selectedRange()
        guard replacement == " ",
              range.length == 0,
              selected.length == 0,
              range.location == selected.location,
              range.location == NSMaxRange(mapped.range),
              mapped.id == editor.activeElementID,
              editor.activeElementIndex == elementIndex,
              editor.screenplay.elements[elementIndex].text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false,
              let prediction = editor.currentPrediction,
              prediction.hint != true,
              let suffix = editor.currentSuggestionSuffix,
              !suffix.isEmpty,
              // When the ghost itself begins with a space (e.g. " DAY"
              // after a scene-heading dash), the space the user is typing
              // is that leading space — not an accept. Insert it literally
              // so they can still type EVENING/NIGHT; a second space accepts.
              !suffix.hasPrefix(" "),
              ghost.isPresenting(
                suffix: suffix,
                insertionLocation: range.location,
                revision: editor.revision
              ) else { return false }
        return true
    }

    private func acceptPrediction(appendingSpace: Bool = false) {
        guard let editor,
              let prediction = editor.currentPrediction,
              prediction.hint != true,
              let index = editor.activeElementIndex,
              let suggestion = editor.currentSuggestionText else { return }

        hideGhost()
        var elements = editor.screenplay.elements
        if let becomes = prediction.becomes { elements[index].type = becomes }
        // Asked of the model, not decided here. A suggestion landing in a cue
        // shouts for the same reason a typed letter does, and there is one
        // sentence in the tree that says so.
        var completed = EditorState.normalizedText(suggestion, for: elements[index].type)
        if appendingSpace, !completed.hasSuffix(" ") {
            completed.append(" ")
        }
        elements[index].text = completed
        let id = elements[index].id
        let offset = (elements[index].text as NSString).length
        let location = ranges.first(where: { $0.id == id })?.range.location ?? 0
        applyModelEdit(
            elements,
            activeID: id,
            offset: offset,
            selection: NSRange(location: location + offset, length: 0),
            actionName: "Accept Suggestion"
        )
    }

    // MARK: - Kind, insert, apply

    private func promoteToSceneHeadingIfTyped() {
        guard let editor, let index = editor.activeElementIndex else { return }
        let element = editor.screenplay.elements[index]
        guard let promoted = ScenePromotion.kind(for: element.text, currently: element.type)
        else { return }
        changeKind(to: promoted)
    }

    private func changeKind(to kind: ScreenplayKind) {
        guard let editor, let index = editor.activeElementIndex else { return }
        var elements = editor.screenplay.elements
        // Screenplay convention re-cases on conversion: scene headings,
        // characters, transitions, and shots are caps; action and
        // dialogue keep the writer's own casing. The session memory
        // makes the re-case reversible — converting back restores
        // "Mara", not "MARA" — and any edit after the conversion wins
        // over the memory.
        let previousText = elements[index].text
        elements[index].text = editor.textForKindConversion(of: elements[index], to: kind)
        elements[index].type = kind
        let id = elements[index].id
        let offset = EditorState.caretAfterConversion(
            from: previousText,
            to: elements[index].text,
            caret: editor.selectionOffset,
            kind: kind
        )
        let location = ranges.first(where: { $0.id == id })?.range.location ?? 0
        applyModelEdit(
            elements,
            activeID: id,
            offset: offset,
            selection: NSRange(location: location + offset, length: 0),
            actionName: "Change Element"
        )
    }

    private func insertElements(_ pages: [ScriptElement]) {
        guard let editor, let last = pages.last else { return }
        var elements = editor.screenplay.elements
        let index = min(
            editor.activeElementIndex.map { $0 + 1 } ?? elements.count,
            elements.count
        )
        elements.insert(contentsOf: pages, at: index)
        let offset = (last.text as NSString).length
        let placed = index + pages.count - 1
        let location = ScreenplayEditPlanner.ranges(for: elements)[placed].range.location
        applyModelEdit(
            elements,
            activeID: last.id,
            offset: offset,
            selection: NSRange(location: location + offset, length: 0),
            actionName: "Add Pages"
        )
    }

    private func applyElements(_ elements: [ScriptElement], actionName: String) {
        guard let editor,
              let activeID = editor.activeElementID ?? elements.first?.id else { return }
        applyModelEdit(
            elements,
            activeID: activeID,
            offset: editor.selectionOffset,
            selection: textView.selectedRange(),
            actionName: actionName
        )
    }

    // MARK: - Scene heading separator

    /// A separator the dash key has just written, and where it left the
    /// caret. One delete against it collapses it back to a tight hyphen;
    /// any other keystroke lets it stand. See `SceneHeadingSeparator`.
    private struct SeparatorEscape {
        let elementID: UUID
        let caret: Int
    }

    private func writeSceneSeparator(
        replacing range: NSRange, in mapped: ScriptLayout.ElementRange, at index: Int
    ) -> Bool {
        guard let editor, editor.screenplay.elements[index].type == .scene else { return false }
        let element = editor.screenplay.elements[index]
        guard let local = elementRelative(range, in: mapped),
              let separated = SceneHeadingSeparator.spaced(
                in: element.text as NSString, replacing: local
              ) else { return false }

        write(separated, to: element, at: index, in: mapped, actionName: "Scene Heading")
        pendingSeparatorEscape = SeparatorEscape(elementID: element.id, caret: separated.caret)
        return true
    }

    /// A space typed against the one the separator already carries is dropped
    /// rather than doubled. `SceneHeadingSeparator` owns the judgement; this
    /// only locates the caret inside the element and refuses the keystroke.
    private func absorbsSeparatorSpace(
        at range: NSRange, in mapped: ScriptLayout.ElementRange, at index: Int
    ) -> Bool {
        guard let editor, editor.screenplay.elements[index].type == .scene,
              let local = elementRelative(range, in: mapped) else { return false }
        return SceneHeadingSeparator.absorbsSpace(
            in: editor.screenplay.elements[index].text as NSString, at: local.location
        )
    }

    private func collapseSceneSeparator(
        replacing range: NSRange,
        in mapped: ScriptLayout.ElementRange,
        at index: Int,
        escape: SeparatorEscape
    ) -> Bool {
        guard let editor, editor.screenplay.elements[index].type == .scene else { return false }
        let element = editor.screenplay.elements[index]
        guard element.id == escape.elementID,
              let local = elementRelative(range, in: mapped),
              NSMaxRange(local) == escape.caret,
              let collapsed = SceneHeadingSeparator.collapsed(
                in: element.text as NSString, endingAt: escape.caret
              ) else { return false }

        write(collapsed, to: element, at: index, in: mapped, actionName: "Scene Heading")
        return true
    }

    private func write(
        _ edit: (text: String, caret: Int),
        to element: ScriptElement,
        at index: Int,
        in mapped: ScriptLayout.ElementRange,
        actionName: String
    ) {
        guard let editor else { return }
        var elements = editor.screenplay.elements
        elements[index].text = edit.text
        applyModelEdit(
            elements,
            activeID: element.id,
            offset: edit.caret,
            selection: NSRange(location: mapped.range.location + edit.caret, length: 0),
            actionName: actionName
        )
    }

    private func elementRelative(
        _ range: NSRange, in mapped: ScriptLayout.ElementRange
    ) -> NSRange? {
        let start = range.location - mapped.range.location
        guard start >= 0, start + range.length <= mapped.range.length else { return nil }
        return NSRange(location: start, length: range.length)
    }

    // MARK: - Selection and typing attributes

    private func updateSelection() {
        guard let editor, let mapped = elementRange(at: textView.selectedRange().location) else {
            return
        }
        editor.selectionChanged(
            elementID: mapped.id,
            offset: min(
                mapped.range.length,
                max(0, textView.selectedRange().location - mapped.range.location)
            )
        )
        updateTypingAttributes()
    }

    /// Characters typed onto a fresh line inherit this, not whatever the last
    /// paragraph happened to wear. There is no software-keyboard trait on the
    /// Mac to fall back on, so a stale indent here is the indent the writer
    /// sees until the next full render.
    private func updateTypingAttributes() {
        guard let editor else { return }
        textView.typingAttributes = ScriptLayout.attributes(
            for: editor.activeKind, measure: measure, spacingAfter: 0
        )
    }

    private func restoreSelection(_ requestedRange: NSRange) {
        let length = (textView.string as NSString).length
        let location = min(max(0, requestedRange.location), length)
        let selectionLength = min(max(0, requestedRange.length), length - location)
        applyingModel = true
        textView.setSelectedRange(NSRange(location: location, length: selectionLength))
        applyingModel = false
        updateSelection()
    }

    private func restoreSelection(elementID: UUID?, offset: Int) {
        guard let elementID, let mapped = ranges.first(where: { $0.id == elementID }) else { return }
        let clamped = min(max(0, offset), mapped.range.length)
        restoreSelection(NSRange(location: mapped.range.location + clamped, length: 0))
    }

    private func placeCaretForEditing() {
        guard let editor else { return }
        restoreSelection(elementID: editor.activeElementID, offset: editor.selectionOffset)
    }

    // MARK: - Ranges

    /// The phone's lookup: an empty line is still a place (`length == 0` is
    /// not `NSLocationInRange`), and a caret sitting on the joining newline
    /// belongs to the element it just finished, not the one it is about to
    /// start.
    private func elementRange(at location: Int) -> ScriptLayout.ElementRange? {
        if let exact = ranges.first(where: {
            ($0.range.length == 0 && $0.range.location == location)
                || NSLocationInRange(location, $0.range)
        }) { return exact }
        if let preceding = ranges.last(where: { NSMaxRange($0.range) <= location }) {
            return preceding
        }
        return ranges.first
    }

    private func adjustRange(at index: Int, length: Int, shiftLaterBy delta: Int) {
        let current = ranges[index]
        ranges[index] = ScriptLayout.ElementRange(
            id: current.id,
            range: NSRange(location: current.range.location, length: length)
        )
        guard delta != 0, index + 1 < ranges.count else { return }
        for later in (index + 1)..<ranges.count {
            let moved = ranges[later]
            ranges[later] = ScriptLayout.ElementRange(
                id: moved.id,
                range: NSRange(
                    location: moved.range.location + delta, length: moved.range.length
                )
            )
        }
    }

    // MARK: - Viewport

    /// The caret's line, top to bottom, in the canvas's coordinates.
    private func caretContentLine() -> ClosedRange<CGFloat>? {
        let location = textView.selectedRange().location
        let probe = NSRange(location: location, length: 0)
        var caret = ScriptLayout.boundingRect(of: probe, in: textView)
        if caret == nil || caret?.height == 0 {
            let fallback = max(0, min(location, max(0, (textView.string as NSString).length - 1)))
            caret = ScriptLayout.boundingRect(
                of: NSRange(location: fallback, length: 0), in: textView
            )
        }
        guard let rect = caret else { return nil }
        let top = canvasY(ofTextRect: rect)
        return top...(top + max(rect.height, 1))
    }

    /// Where the page rests after the storage has been replaced.
    private func restoreViewport(preserved: NSPoint) {
        let range = scrollableRange
        let offset = scrollView.contentView.bounds.origin.y

        // Hold the page where the writer left it. `settled` with no caret is
        // exactly that, clamped to what the document allows.
        let held = PageScroll.settled(
            caretWas: nil, caretIs: nil,
            preserved: preserved.y, offset: offset, in: range
        )

        // Then move only if the line being written has gone out of sight.
        //
        // Following the caret unconditionally — which is what `settled` does
        // when it is given one — keeps the insertion point at a fixed height on
        // screen, and that is a typewriter, not a page. On a script that
        // already fits, every Return and every scene-heading dash slid the
        // whole page by a line. `correction` is the rule this path always
        // wanted; its own comment says so.
        var target = held
        if let caret = caretContentLine() {
            let viewport = scrollView.contentView.bounds.height
            let margin = caret.upperBound - caret.lowerBound
            if let corrected = PageScroll.correction(
                revealing: caret,
                within: held...(held + viewport),
                margin: margin,
                from: held,
                in: range
            ) {
                target = corrected
            }
        }

        if abs(offset - target) > 0.5 {
            scrollView.contentView.scroll(to: NSPoint(x: preserved.x, y: target))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
    }

    // MARK: - Native undo

    private func performNativeUndo() -> Bool {
        guard editingUndo.canUndo else {
            reportNativeUndoAvailability()
            return false
        }
        editingUndo.undo()
        reportNativeUndoAvailability()
        return true
    }

    private func performNativeRedo() -> Bool {
        guard editingUndo.canRedo else {
            reportNativeUndoAvailability()
            return false
        }
        editingUndo.redo()
        reportNativeUndoAvailability()
        return true
    }

    private func clearNativeUndoHistory() {
        editingUndo.removeAllActions()
        editor?.reportNativeUndoAvailability(canUndo: false, canRedo: false)
    }

    private func reportNativeUndoAvailability() {
        editor?.reportNativeUndoAvailability(
            canUndo: editingUndo.canUndo,
            canRedo: editingUndo.canRedo
        )
    }

    // MARK: - Types

    private struct PendingEdit {
        let elementID: UUID
        let replacedRange: NSRange
        let insertedLength: Int
    }

    private struct ModelUndoState {
        let elements: [ScriptElement]
        let activeElementID: UUID?
        let selectionOffset: Int
        let selection: NSRange
    }


}
