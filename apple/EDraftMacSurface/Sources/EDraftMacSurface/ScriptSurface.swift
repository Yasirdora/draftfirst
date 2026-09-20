import AppKit
import EDraftCore
import EDraftEngine
import Foundation
import QuartzCore
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
    /// The legacy column view only, detached while the flagged spread editor
    /// is active. Selection and character geometry resolve their owning sheet.
    public let textView: NSTextView
    public let textStorage: NSTextStorage
    public let layoutManager: NSLayoutManager
    public private(set) var sheets: [PageSheet] = []
    private let legacyContainer: PageGapContainer
    private var legacySelection: NSRange?
    private let multiContainerSpreadEnabled: Bool

    /// Opt-in for manual sheet editing; absent (and in Release) means OFF.
    static var debugMultiContainerSpreadEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["EDRAFT_MULTI_CONTAINER_SPREAD"] == "1"
        #else
        false
        #endif
    }

    var usesPageSheets: Bool { !sheets.isEmpty }

    /// Selection belongs to the shared layout manager, not page one. The
    /// legacy view remains a separate, explicitly selected architecture.
    var selectionTextView: NSTextView {
        guard usesPageSheets else { return textView }
        if let view = layoutManager.textViewForBeginningOfSelection,
           sheets.contains(where: { $0.textView === view }) { return view }
        return textView(atCharacter: legacySelection?.location ?? 0)
    }

    func textView(atCharacter requested: Int) -> NSTextView {
        guard usesPageSheets else { return textView }
        let location = min(max(0, requested), textStorage.length)
        // Engine starts are also valid during repagination, before TextKit
        // has finished laying out the replacement text, and at empty EOF.
        let index = sheets.lastIndex(where: { $0.startLocation <= location }) ?? 0
        return sheets[index].textView
    }

    private func sheetRect(for range: NSRange) -> (view: NSTextView, rect: CGRect)? {
        let view = textView(atCharacter: range.location)
        guard let rect = ScriptLayout.sheetBoundingRect(of: range, in: view) else { return nil }
        return (view, rect)
    }

    private func characterCanvasRect(_ location: Int) -> CGRect? {
        if usesPageSheets {
            let clamped = min(max(0, location), textStorage.length)
            guard let geometry = sheetRect(for: NSRange(location: clamped, length: 0)) else { return nil }
            return canvas.convert(geometry.rect, from: geometry.view)
        }
        return boundingRect(atCharacter: location).map { canvasRect(fromTextRect: $0) }
    }
    /// Bold, italic, underline and centre, over whatever is selected.
    private let formatBar = SelectionFormatBar()
    let canvas: PageCanvasView

    /// Parallel to the editor's elements: same order, same count, always.
    /// `render` builds it from the elements and `adjustRange` shifts it in
    /// place, so the pair can be zipped — walking one while looking the other
    /// up by id measured quadratic on a 6,652-element paste (290ms per
    /// selection change, reported as "the format bar hangs"). The invariant
    /// is pinned by `testRangesStayParallelToElements`.
    private var ranges: [ScriptLayout.ElementRange] = []

    /// The engine's reading of the text last laid out: its pages, and where
    /// each begins in the flattened text. Paginating a feature is not cheap
    /// — measured 1.2 seconds on a synthetic 910-page draft — and the breaks
    /// and the markers both need it, so it is computed once per version of
    /// the text rather than once per question asked of it.
    private struct Pagination {
        let elements: [ScriptElement]
        let format: PageFormat
        let pages: [EDraftEngine.ScriptPage]?
        let locations: [Int]
    }
    private var cachedPagination: Pagination?

    /// The breaks last measured onto the container, with the text and mode
    /// they belong to. A re-layout of the same words — a window resize, a
    /// second pass while the window opens — reuses them: clearing the
    /// exclusion paths to measure again invalidates the whole container,
    /// which buys a full TextKit layout with a single assignment.
    private struct BreaksPlacement {
        let elements: [ScriptElement]
        let format: PageFormat
        let mode: PageLayoutMode
        /// The page-start character locations the `starts` were measured
        /// from — the fixpoint check's half of "did any boundary move?".
        let locations: [Int]
        let starts: [CGFloat]
    }
    private var breaksPlacement: BreaksPlacement?
    /// How many times the bands have been torn down and rebuilt from a full
    /// measurement — what a test asks to prove a keystroke that moves no
    /// boundary pays no rebuild.
    private(set) var breakRecomputeCount = 0
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
    /// The act-break count the renumber rule (RFC-ACT-BREAK §4) last
    /// accounted for. The rule fires only when an edit changed that count —
    /// an act break arriving or leaving — never on an ordinary keystroke.
    /// Written in exactly two places: `bind`, so a document merely opened is
    /// not mistaken for one that gained acts, and the hook itself once it
    /// has compared — never in `render`, or the structural path's own draw
    /// would move the baseline before the comparison happened.
    private var lastActbreakCount = 0
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

    /// The selection the screen last painted a highlight for.
    ///
    /// TextKit's range-based display invalidation covers line fragment rects
    /// only, and the paragraph spacing between two elements belongs to no
    /// fragment — while the highlight of a selection that covers a
    /// paragraph's end paints straight into that spacing. Taking such a
    /// selection down dirtied the fragments and left the paint in the bands:
    /// the two faint rules above and below the line, visible until a scroll
    /// or a pinch forced a full redraw. Tracking what was painted is what
    /// lets its removal dirty what was actually painted.
    private var paintedSelection = NSRange(location: 0, length: 0)

    /// AppKit's text view takes its undo manager off the responder chain, which
    /// is the window — so a surface driven without one, as every test here is,
    /// would see `textView.undoManager == nil` and silently drop structural
    /// undo. Vend this instead, through `undoManager(for:)`.
    private let editingUndo = UndoManager()

    /// System find bar, Replace disabled. See `FindBarClient`.
    private let textFinder = NSTextFinder()
    private let findClient: FindBarClient
    private lazy var sheetFindClient = PageSheetFindBarClient(surface: self)

    /// The note whose card is open, and the popover showing it. One at a
    /// time, which is what a `.transient` popover enforces anyway — clicking
    /// the page closes the card, and clicking another mark opens that one.
    private var openNoteIDs: [UUID] = []
    private var notePopover: NSPopover?
    /// What each note in the open card currently reads, so closing it can
    /// write them to the model. The card reports every keystroke here; the
    /// model is written once, when the card goes away — see `NoteCard.onEdit`.
    private var openNoteDrafts: [UUID: String] = [:]
    /// The element the context menu was opened over, so "Add Note" leaves the
    /// note where the writer pointed.
    private var rightClickedElement: UUID?

    public init(measure: CGFloat = 640, multiContainerSpreadEnabled: Bool? = nil) {
        self.multiContainerSpreadEnabled = multiContainerSpreadEnabled
            ?? Self.debugMultiContainerSpreadEnabled
        let textWidth = ScriptLayout.pageMeasure
        self.measure = textWidth

        let container = PageGapContainer(
            size: CGSize(width: textWidth, height: .greatestFiniteMagnitude)
        )
        // The page is paper, not the window: tracking the clip view would
        // stretch a 60-character block across whatever the writer resized to.
        container.widthTracksTextView = false
        let layoutManager = NSLayoutManager()
        let storage = NSTextStorage()
        self.textStorage = storage
        self.layoutManager = layoutManager
        self.legacyContainer = container
        layoutManager.delegate = fixedLeading
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        let textView = ArrangedTextView(
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
        // The headroom a tall glyph gets is a constant (see
        // `PageCanvasView.layoutPages`), so set it once, here: assigning the
        // inset invalidates the whole container, and doing it after the
        // first layout bought a second full one on every open.
        textView.textContainerInset = NSSize(
            width: 0, height: ScreenplayPageLayout.glyphOverflow
        )
        self.canvas = canvas

        let scrollView = PageScrollView(frame: NSRect(x: 0, y: 0, width: measure, height: 480))
        scrollView.hasVerticalScroller = true
        scrollView.allowsMagnification = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        // The clip view centres a page smaller than the window, so the canvas
        // never has to be grown to the viewport and a pinch needs no
        // re-measure to stay centred.
        //
        // It is installed *before* the background is settled below, and the
        // order is not arbitrary: a scroll view's background is its clip
        // view's, so replacing the clip view afterwards throws that setting
        // away — it used to discard the desk colour, and now it would put the
        // filling clip view back.
        scrollView.contentView = CentringClipView()
        scrollView.documentView = canvas
        // The desk is not painted. What shows instead is the surface the
        // system already puts under a content column, which is what the
        // Navigator beside it is also showing; the dots are laid over it by
        // `DeskGridView`, below the clip view so they stay fixed to the
        // window. The clip view has to be told separately — a scroll view's
        // background is drawn by its clip view, so clearing only the scroll
        // view leaves the clip view still filling.
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        let grid = DeskGridView(frame: scrollView.bounds)
        grid.autoresizingMask = [.width, .height]
        scrollView.addSubview(grid, positioned: .below, relativeTo: scrollView.contentView)
        self.scrollView = scrollView

        // The bar floats in the scroll view's own space, above the clip
        // view — chrome, not content, so the magnification transform never
        // touches it. Placement is reasoned about in the canvas's
        // coordinates. See `SelectionFormatBar`.
        formatBar.attach(to: scrollView, canvas: canvas)

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
        // A window that goes away mid-pinch never sends didEnd: without a
        // reset, the surface would go on refusing to touch the magnification
        // as though the fingers were still down.
        canvas.onLeaveWindow = { [weak self] in
            self?.recoverFromInterruptedGesture()
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
        // The bar floats over the page, and the page moves under it on every
        // scroll tick, resize and pinch frame. One observer hears all three:
        // the clip view's bounds is the scroll view's name for all of them.
        scrollView.contentView.postsBoundsChangedNotifications = true
        clipBoundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.repositionFormatBar()
                self?.canvas.refreshVisibleGridPreviews()
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
                    if live {
                        // A new pinch takes the page back, mid-settle or
                        // otherwise: the drift stops where it is and the
                        // fingers own the size from there.
                        self.cancelSettle()
                        self.isLiveMagnifying = true
                        self.syncHorizontalCentring()
                    } else {
                        self.isLiveMagnifying = false
                        self.syncHorizontalCentring()
                        self.settleAfterGesture()
                    }
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
            MainActor.assumeIsolated {
                guard let self else { return }
                // A frame during the column's slide is the slide, not a new
                // preference: reschedule the drift and leave the fit for
                // when the room stops moving.
                if self.isLentTransitioning {
                    self.lentGeneration += 1
                    self.scheduleLentDrift()
                    return
                }
                self.applyZoomForCurrentSize()
            }
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
        // The renumber rule's baseline: what the document holds at bind is
        // not something arriving, so the tracker starts at the truth rather
        // than at zero — see `renumberActCardsIfNeeded`.
        lastActbreakCount = editor.screenplay.elements.count(where: { $0.type == .actbreak })
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
        editor.onInsertActBreak = { [weak self] in self?.insertActBreak() }
        editor.onApplyElements = { [weak self] elements, name in
            self?.applyElements(elements, actionName: name)
        }
        editor.onNativeUndo = { [weak self] in self?.performNativeUndo() ?? false }
        editor.onNativeRedo = { [weak self] in self?.performNativeRedo() ?? false }
        editor.onClearNativeUndo = { [weak self] in self?.clearNativeUndoHistory() }
        editor.onZoom = { [weak self] command in self?.applyZoom(command) }
        editor.onZoomTo = { [weak self] size in self?.applyChosenSize(size) }
        editor.onThreadColumn = { [weak self] opened in self?.threadColumn(opened: opened) }
        editor.onSetEditing = { [weak self] editing in
            guard let self else { return }
            if editing {
                self.placeCaretForEditing()
                self.scrollView.window?.makeFirstResponder(self.selectionTextView)
            } else if self.scrollView.window?.firstResponder === self.selectionTextView {
                self.scrollView.window?.makeFirstResponder(nil)
            }
        }
        editor.onSetLayoutMode = { [weak self] mode in self?.setLayoutMode(mode) }
        editor.onSetArrangement = { [weak self] mode in self?.setArrangement(mode) }
        editor.onAddNote = { [weak self] in self?.addNoteAtCaret() }
        // The writer's choice reaches the canvas here rather than being read
        // from a global when the view was built — see `layoutMode`.
        canvas.layoutMode = editor.layoutMode
        canvas.arrangement = editor.arrangement
        canvas.onPickPage = { [weak self] index in self?.showPage(index) }
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

        let sheetSelection = usesPageSheets ? selectionTextView.selectedRange() : nil
        applyingModel = true
        let script = ScriptLayout.attributedScript(elements, measure: measure)
        ranges = script.ranges
        lastLaidElements = elements
        textStorage.setAttributedString(script.text)
        if let saved = sheetSelection {
            let location = min(saved.location, textStorage.length)
            selectionTextView.setSelectedRange(NSRange(location: location,
                length: min(saved.length, textStorage.length - location)))
        }
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
    /// The window's page column, in document points.
    ///
    /// The clip's *frame* is screen points; its bounds are already divided
    /// by the magnification. Two-page and Grid size themselves to what is
    /// actually on screen, so the opening fits when the writer resizes and
    /// still answers a pinch: we divide the frame by the current
    /// magnification rather than reading bounds, which after a layout can
    /// be the document itself and then the scale never moves.
    private func visibleViewport() -> CGSize {
        let mag = max(scrollView.magnification, 0.001)
        let clip = scrollView.contentView.frame.size
        let raw = clip.width > 1 ? clip : scrollView.frame.size
        guard raw.width > 1 else { return CGSize(width: 800, height: 600) }
        return CGSize(width: raw.width / mag, height: max(raw.height, 1) / mag)
    }

    private func layOut() {
        var pageStarts: [CGFloat] = [0]
        let pagination = pagination(for: lastLaidElements)
        if multiContainerSpreadEnabled, canvas.layoutMode == .pages,
           canvas.arrangement == .spread {
            layOutPageSheets(pagination)
            return
        }
        restoreLegacyContainerIfNeeded()
        if let layoutManager = textView.layoutManager,
           let container = textView.textContainer as? PageGapContainer {
            container.size = CGSize(width: measure, height: .greatestFiniteMagnitude)
            pageStarts = applyPageBreaks(
                in: layoutManager, container: container,
                elements: lastLaidElements, pagination: pagination
            )
            // No ensureLayout of our own here: applyPageBreaks leaves the
            // container laid out, and `usedRect` below forces the end of it
            // anyway — a third ensure would only repeat the question.
            //
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
        canvas.layoutPages(
            pageStarts: pageStarts,
            textHeight: max(textView.frame.height, 1),
            viewport: visibleViewport()
        )
        // Only in `continuous`, where the rule is the one thing saying a page
        // ended. In `pages` the gap between the sheets and their own edges
        // already say it, and a rule as well is a third mark for one
        // boundary.
        canvas.showBreaks(at: canvas.layoutMode == .continuous ? pageBreakPositions(pagination) : [])
        (textView as? ArrangedTextView)?.fold =
            canvas.arrangement == .spread ? canvas.spreadFold : nil
        placeNoteMarkers()
        washNotedLines()
        scrollView.layoutSubtreeIfNeeded()
    }

    /// The array is reconciled by page index: a resize or a moved break keeps
    /// the existing views; a changed page count adds/removes only the tail.
    private func layOutPageSheets(_ pagination: Pagination) {
        let wasApplying = applyingModel
        let savedSelection = selectionTextView.selectedRange()
        let hadFocus = scrollView.window?.firstResponder is NSTextView
            && (scrollView.window?.firstResponder === textView
                || sheets.contains(where: { $0.textView === scrollView.window?.firstResponder }))
        applyingModel = true
        defer { applyingModel = wasApplying }
        if !usesPageSheets {
            legacySelection = selectionTextView.selectedRange()
            if scrollView.window?.firstResponder === textView {
                scrollView.window?.makeFirstResponder(nil)
            }
            textView.isHidden = true
            textView.isEditable = false
            textView.isSelectable = false
            (textView as? ArrangedTextView)?.fold = nil
            layoutManager.removeTextContainer(at: 0)
            // Retire chrome while its previous host leaves the hierarchy.
            formatBar.hostView.isHidden = true
            hideGhost()
            textFinder.performAction(.hideFindInterface)
            textFinder.client = sheetFindClient
            canvas.showNotes([], active: nil, onOpen: { _ in })
        }
        let starts = pagination.locations.isEmpty ? [0] : pagination.locations
        while sheets.count > starts.count {
            let removed = sheets.removeLast()
            removed.textView.removeFromSuperview()
            layoutManager.removeTextContainer(at: sheets.count)
        }
        for page in starts.indices {
            let end = page + 1 < starts.count ? starts[page + 1] : Int.max
            if page == sheets.count {
                sheets.append(PageSheet(
                    startLocation: starts[page], endLocation: end,
                    measure: measure, layoutManager: layoutManager
                ))
            } else {
                sheets[page].update(startLocation: starts[page], endLocation: end, measure: measure)
            }
        }
        for sheet in sheets {
            sheet.textView.delegate = self
            sheet.textView.isEditable = true
            sheet.textView.isSelectable = true
            sheet.textView.allowsUndo = true
            layoutManager.ensureLayout(for: sheet.textContainer)
        }
        canvas.layoutSheets(sheets, viewport: visibleViewport())
        hideGhost()
        canvas.showBreaks(at: [])
        let location = min(savedSelection.location, textStorage.length)
        let selection = NSRange(location: location,
            length: min(savedSelection.length, textStorage.length - location))
        let owner = textView(atCharacter: location)
        owner.setSelectedRange(selection)
        legacySelection = nil
        if hadFocus { scrollView.window?.makeFirstResponder(owner) }
        placeNoteMarkers()
        washNotedLines()
        updateTypingAttributes()
        scrollView.layoutSubtreeIfNeeded()
    }

    private func restoreLegacyContainerIfNeeded() {
        guard usesPageSheets else { return }
        legacySelection = selectionTextView.selectedRange()
        textFinder.performAction(.hideFindInterface)
        textFinder.client = findClient
        let hadFocus = sheets.contains { $0.textView === scrollView.window?.firstResponder }
        hideGhost()
        highlight.removeFromSuperview()
        let wasApplying = applyingModel
        applyingModel = true
        defer { applyingModel = wasApplying }
        for sheet in sheets.reversed() {
            sheet.textView.removeFromSuperview()
            layoutManager.removeTextContainer(at: layoutManager.textContainers.count - 1)
        }
        sheets.removeAll()
        layoutManager.addTextContainer(legacyContainer)
        breaksPlacement = nil
        textView.isHidden = canvas.arrangement == .grid
        textView.isEditable = canvas.arrangement != .grid
        textView.isSelectable = canvas.arrangement != .grid
        if let saved = legacySelection {
            let location = min(saved.location, textStorage.length)
            textView.setSelectedRange(NSRange(
                location: location, length: min(saved.length, textStorage.length - location)
            ))
            legacySelection = nil
        }
        if hadFocus { scrollView.window?.makeFirstResponder(textView) }
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
        if mode == .continuous, canvas.arrangement != .single {
            canvas.arrangement = .single
            canvas.highlightedPage = nil
            PageArrangement.store(.single)
            editor?.reportArrangement(.single)
            textView.isHidden = false
            textView.isEditable = true
            textView.isSelectable = true
        }
        layOut()
        scrollBack(to: anchor)
        updateGhost()
    }

    /// Single, two-page or the bird's-eye. Two-page and Grid are sheets;
    /// asking for them from Continuous switches to Pages first.
    func setArrangement(_ mode: PageArrangement) {
        if mode != .single, canvas.layoutMode == .continuous {
            setLayoutMode(.pages)
        }
        guard canvas.arrangement != mode else { return }
        let anchor = anchoredLine()
        if mode != .grid { canvas.highlightedPage = nil }
        canvas.arrangement = mode
        PageArrangement.store(mode)
        editor?.reportArrangement(mode)
        textView.isHidden = mode == .grid
        textView.isEditable = mode != .grid
        textView.isSelectable = mode != .grid
        layOut()
        if mode != .grid { scrollBack(to: anchor) }
        updateGhost()
    }

    /// Grid → Single on that sheet, with the caret on its first line.
    func showPage(_ index: Int) {
        setArrangement(.single)
        guard index < canvas.pageViews.count else { return }
        let frame = canvas.pageViews[index].frame
        let clip = scrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: max(0, frame.minY - 12)))
        scrollView.reflectScrolledClipView(clip)
        let locations = pagination(for: lastLaidElements).locations
        if index < locations.count {
            let location = locations[index]
            let range = NSRange(location: location, length: 0)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
        }
        scrollView.window?.makeFirstResponder(textView)
    }

    /// The line at the top of what the writer can see, and how far below the
    /// viewport's edge it sits.
    ///
    /// The edge does not always land on a line. In `pages` it can land on the
    /// desk between sheets — an exclusion band with no glyphs in it at all —
    /// and there the layout engine's answer to "what is here" is the
    /// *nearest* glyph, which can sit a whole margin pair above the window,
    /// invisible. That line cannot be the anchor: pinning it would hold
    /// something the writer cannot see while everything they *can* see jumps
    /// the height of the band the moment the band goes away. The anchor is
    /// the first line whose fragment reaches the edge — the first words
    /// actually on the glass.
    private func anchoredLine() -> (location: Int, offset: CGFloat)? {
        if usesPageSheets {
            let visible = scrollView.contentView.bounds
            guard let sheet = sheets.first(where: { $0.textView.frame.intersects(visible) }) else { return nil }
            let view = sheet.textView
            let point = view.convert(NSPoint(x: view.frame.minX, y: visible.minY), from: canvas)
            let location = view.characterIndexForInsertion(at: point)
            guard let rect = characterCanvasRect(location) else { return nil }
            return (location, rect.minY - visible.minY)
        }
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return nil }
        let visible = scrollView.contentView.bounds
        let inText = textPoint(fromCanvas: NSPoint(x: textView.frame.minX, y: visible.minY))
        // The layout engine reckons in the container's coordinates, which the
        // inset puts a few points above the view's own.
        let top = NSPoint(
            x: inText.x - textView.textContainerOrigin.x,
            y: inText.y - textView.textContainerOrigin.y
        )
        var glyph = layoutManager.glyphIndex(for: top, in: container)
        if glyph < layoutManager.numberOfGlyphs,
           layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).maxY <= top.y,
           let below = firstGlyph(reachingBelow: top.y, from: glyph, in: layoutManager) {
            glyph = below
        }
        let location = layoutManager.characterIndexForGlyph(at: glyph)
        guard let rect = boundingRect(atCharacter: location) else { return nil }
        return (location, canvasRect(fromTextRect: rect).minY - visible.minY)
    }

    /// The first glyph whose line fragment reaches at or below `top`,
    /// counting down from `glyph` — the far side of a desk band, never more
    /// than a margin pair away. Past the end of the text there is no such
    /// line, and the caller keeps the glyph it was given.
    private func firstGlyph(
        reachingBelow top: CGFloat,
        from glyph: Int,
        in layoutManager: NSLayoutManager
    ) -> Int? {
        var found: Int?
        layoutManager.enumerateLineFragments(
            forGlyphRange: NSRange(location: glyph, length: layoutManager.numberOfGlyphs - glyph)
        ) { rect, _, _, glyphRange, stop in
            if rect.maxY > top {
                found = glyphRange.location
                stop.pointee = true
            }
        }
        return found
    }

    private func scrollBack(to anchor: (location: Int, offset: CGFloat)?) {
        guard let anchor, let rect = characterCanvasRect(anchor.location) else { return }
        let y = rect.minY - anchor.offset
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
        let length = textStorage.length
        let clamped = min(max(0, location), length)
        let probe = NSRange(location: clamped, length: min(1, max(0, length - clamped)))
        return ScriptLayout.boundingRect(of: probe, in: textView)
    }

    /// A TextKit rectangle in the coordinates its ink actually lands in.
    ///
    /// The fold is a transform *inside* the text view, not a step in the view
    /// hierarchy: `ArrangedTextView.draw` paints every line fragment through
    /// it, `characterIndexForInsertion` unfolds a point arriving from it, and
    /// `firstRect` folds on the way out. The view's own space *is* the spread,
    /// so an overlay hosted by it — a subview, whose frame is read in its
    /// superview's coordinates — belongs there too. Give one the unfolded
    /// rectangle and it sits where the line would be in a single column,
    /// which on an open book is another page.
    private func spreadRect(fromTextRect rect: CGRect) -> CGRect {
        (textView as? ArrangedTextView)?.fold?.spreadRect(fromVertical: rect) ?? rect
    }

    /// The same rectangle again, lifted out to the canvas the scroll view moves.
    private func canvasRect(fromTextRect rect: CGRect) -> CGRect {
        textView.convert(spreadRect(fromTextRect: rect), to: canvas)
    }

    /// Convert a canvas point back into the vertical TextKit column.
    private func textPoint(fromCanvas point: NSPoint) -> NSPoint {
        let local = textView.convert(point, from: canvas)
        return (textView as? ArrangedTextView)?.fold?.verticalPoint(fromSpread: local) ?? local
    }

    /// What a layout pass can see of the text: everything but identity and
    /// style runs. Emphasis redraws the ink inside the lines — Courier's
    /// fixed advance means it cannot change how many lines there are — so a
    /// bold toggle must never buy a 1.2 s repagination of a feature draft,
    /// nor a re-placement of the breaks.
    private static func layoutEquivalent(_ a: [ScriptElement], _ b: [ScriptElement]) -> Bool {
        guard a.count == b.count else { return false }
        for (lhs, rhs) in zip(a, b) {
            guard lhs.type == rhs.type, lhs.text == rhs.text,
                  lhs.dual == rhs.dual, lhs.sceneNumber == rhs.sceneNumber,
                  lhs.depth == rhs.depth
            else { return false }
        }
        return true
    }

    /// The engine's reading of `elements`, computed once per version of the
    /// text. Everything else that needs it this pass — the breaks, the
    /// markers — takes it from here.
    private func pagination(for elements: [ScriptElement]) -> Pagination {
        let format = PageFormat.current
        if let cached = cachedPagination, cached.format == format {
            if Self.layoutEquivalent(cached.elements, elements) {
                return cached
            }
            // A changed region repaginates at its own cost: the engine
            // resumes at the block above the first dirty element and
            // splices the cached tail the moment a page provably matches.
            // Full-pass identical, fuzz-pinned in both engines.
            if let previousPages = cached.pages,
               let pages = ScreenplayExporter.paginateIncrementally(
                   Screenplay(elements: elements),
                   previous: Screenplay(elements: cached.elements),
                   previousPages: previousPages
               ) {
                let locations: [Int]
                if pages.count > 1 {
                    locations = ScreenplayPageLayout.pageStartLocations(elements: elements, pages: pages)
                } else {
                    locations = []
                }
                let fresh = Pagination(elements: elements, format: format, pages: pages, locations: locations)
                cachedPagination = fresh
                return fresh
            }
        }
        let pages = ScreenplayExporter.paginate(Screenplay(elements: elements))
        let locations: [Int]
        if let pages, pages.count > 1 {
            locations = ScreenplayPageLayout.pageStartLocations(elements: elements, pages: pages)
        } else {
            locations = []
        }
        let fresh = Pagination(elements: elements, format: format, pages: pages, locations: locations)
        cachedPagination = fresh
        return fresh
    }

    /// Where each page after the first actually begins, in canvas
    /// coordinates, measured after the layout rather than predicted from it.
    ///
    /// Both modes ask the same question of the same laid-out text, so a
    /// marker cannot land anywhere but on the line the engine says starts
    /// that page.
    private func pageBreakPositions(_ pagination: Pagination) -> [PageCanvasView.PageBreak] {
        guard let pages = pagination.pages, pages.count > 1 else { return [] }
        // Numbered from the pagination, before anything is dropped. The
        // engine says this location begins page four; whether its rectangle
        // resolves decides only whether a mark is drawn, never what the marks
        // below it are called.
        return pagination.locations.enumerated().dropFirst().compactMap { index, location in
            guard let rect = boundingRect(atCharacter: location) else { return nil }
            return PageCanvasView.PageBreak(
                page: index + 1, y: canvas.convert(rect, from: textView).minY
            )
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
    /// Opens the space between one page and the next, and says where each
    /// page's first line ended up.
    ///
    /// One fixed amount per boundary: the bottom margin the page closes with,
    /// the top margin the next one opens with, and the gap between two
    /// sheets. That is the whole of what `pages` adds and `continuous`
    /// removes, and it is why the two modes hold the same words in the same
    /// order.
    ///
    /// It replaces an arithmetic that tried to force each page's first line
    /// onto a fixed grid of sheets — `target - where it is now`. Where the
    /// text view had already flowed past that target, which happens whenever
    /// it lays out one more line than the paginator counted, the amount came
    /// out negative and the break was skipped altogether. The page then never
    /// broke, every later page inherited the deficit, and it accumulated:
    /// measured on a production draft, page 27 began thirty-five lines down
    /// its own sheet. Adding a fixed space cannot go negative and cannot
    /// accumulate.
    ///
    /// Inserted one at a time, measuring between, because an exclusion path
    /// moves everything after it — the position of the next boundary is not
    /// known until this one has been placed.
    @discardableResult
    private func applyPageBreaks(
        in layoutManager: NSLayoutManager,
        container: PageGapContainer,
        elements: [ScriptElement],
        pagination: Pagination
    ) -> [CGFloat] {
        // The same text in the same mode lands on the same breaks. Reuse
        // them: clearing the bands to measure again invalidates the whole
        // container — a full layout bought with one assignment.
        if let placed = breaksPlacement,
           Self.layoutEquivalent(placed.elements, elements), placed.format == pagination.format,
           placed.mode == canvas.layoutMode {
            return placed.starts
        }
        // The fixpoint skip: a keystroke that moves no page boundary needs
        // no new bands, and most keystrokes move none. Measuring with the
        // current bands in place is an incremental layout — TextKit lays
        // out only what the edit dirtied — while rebuilding clears them,
        // which invalidates the whole container, then assigning them does
        // it again: measured on a 6,652-element paste, 170–460ms of
        // full-document layout per keystroke for bands that came out
        // identical. If every boundary still sits where it was placed, the
        // The fixpoint skip: a keystroke that moves no page boundary needs
        // no new bands, and most keystrokes move none. Measuring with the
        // current bands in place is an incremental layout — TextKit lays
        // out only what the edit dirtied — while rebuilding clears them,
        // which invalidates the whole container, then assigning them does
        // it again: measured on a 6,652-element paste, 170–460ms of
        // full-document layout per keystroke for bands that came out
        // identical.
        //
        // Character locations are no witness — they shift by one for every
        // typed character. What must stay put is the *geometry*: the same
        // number of boundaries, the same element types feeding the widow
        // and orphan rules, and every boundary's line sitting at the same
        // height it was placed at. All three equal means the document is
        // already in the state a rebuild would produce.
        if let placed = breaksPlacement,
           placed.format == pagination.format, placed.mode == canvas.layoutMode,
           placed.locations.count == pagination.locations.count,
           !pagination.locations.isEmpty,
           placed.starts.count == pagination.locations.count,
           placed.elements.count == elements.count,
           zip(placed.elements, elements).allSatisfy({ $0.type == $1.type }) {
            layoutManager.ensureLayout(for: container)
            let current = pagination.locations.map { pageStartY($0, in: layoutManager) }
            if current == placed.starts { return placed.starts }
        }
        breakRecomputeCount += 1
        // Assigning the bands invalidates the container even when it holds
        // none, so clear only when there is something to clear.
        if !container.gapBands.isEmpty { container.gapBands = [] }
        layoutManager.ensureLayout(for: container)
        guard let pages = pagination.pages, pages.count > 1
        else {
            breaksPlacement = BreaksPlacement(
                elements: elements, format: pagination.format,
                mode: canvas.layoutMode, locations: pagination.locations, starts: [0]
            )
            return [0]
        }

        let locations = pagination.locations
        guard canvas.layoutMode == .pages else {
            // `continuous` opens nothing. The marks still need to know where
            // each page begins, which is wherever the text put it.
            let starts = locations.map { pageStartY($0, in: layoutManager) }
            breaksPlacement = BreaksPlacement(
                elements: elements, format: pagination.format,
                mode: canvas.layoutMode, locations: locations, starts: starts
            )
            return starts
        }

        let format = PageFormat.current
        // One sheet to the next: the whole page and the gap between sheets.
        let pitch = format.pageRect.height + PageCanvasView.pageGap
        let line = ScreenplayPageLayout.lineHeight

        // Every space computed from one layout, and the bands set once.
        //
        // What was here measured between each boundary and the next, which
        // reads well and is quadratic: assigning `exclusionPaths` invalidates
        // the whole container, so each measurement re-laid out the entire
        // script. Timed on a synthetic feature — 8 pages 42ms, 28 pages
        // 610ms, 82 pages 8.0 seconds, against 299ms for the same script in
        // `continuous`. A hundred-page draft stopped responding.
        //
        // Nothing needs measuring in between, because the text system's
        // answer turns out to be exact. A gap of height *h* placed at a
        // line's own top moves that line by *h plus one line* — measured at
        // 40, 100, 132 and 797 points, the surplus was 12.0 every time, which
        // is the leading the pushed line brings with it. Knowing that, where
        // each page will land is arithmetic: where it sits with no gaps at
        // all, plus everything inserted above it.
        //
        // The bands are the container's own (`PageGapContainer`), not
        // exclusion paths: AppKit checks every path against every line, which
        // measured 4.8 seconds against 0.3 for the same 910-page draft laid
        // out bare. The band lookup is a binary search, and the lines land
        // exactly where the paths put them — that equivalence is tested.
        let ungapped = locations.map { pageStartY($0, in: layoutManager) }
        let base = ungapped[0]

        var bands: [CGRect] = []
        var placed: CGFloat = 0
        var sheet = 0
        for index in 1..<ungapped.count {
            let here = ungapped[index] + placed
            sheet += 1
            var target = base + CGFloat(sheet) * pitch
            // A page the text view sets longer than a whole sheet takes the
            // next one rather than being crushed onto this. This is the case
            // the old arithmetic met with a negative space and answered by
            // skipping the break altogether, which is how a page came to
            // begin thirty-five lines down its own paper.
            while target - here < line {
                sheet += 1
                target += pitch
            }
            let space = target - here - line
            if space > 0.5 {
                bands.append(CGRect(
                    x: 0, y: here, width: container.size.width, height: space
                ))
            }
            placed += space + line
        }

        // The assignment is what invalidates the container, so spend it
        // only when the bands actually moved — a rebuild after a
        // layout-neutral edit would otherwise buy a full layout for no
        // change at all.
        if bands != container.gapBands { container.gapBands = bands }
        layoutManager.ensureLayout(for: container)
        // Where they actually landed. The sheets are laid under these, so a
        // line resting a fraction below its exclusion carries its paper with
        // it rather than being left off the top of it.
        let starts = locations.map { pageStartY($0, in: layoutManager) }
        breaksPlacement = BreaksPlacement(
            elements: elements, format: format, mode: .pages, locations: locations, starts: starts
        )
        return starts
    }

    /// Where the line beginning at `location` sits, in the text view's own
    /// coordinates.
    private func pageStartY(_ location: Int, in layoutManager: NSLayoutManager) -> CGFloat {
        let length = textStorage.length
        let clamped = min(max(0, location), length)
        let probe = clamped < length
            ? NSRange(location: clamped, length: 1)
            : NSRange(location: max(0, length - 1), length: 0)
        return (ScriptLayout.boundingRect(of: probe, in: textView)
            ?? layoutManager.extraLineFragmentUsedRect).minY
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
        // Never while the magnification is moving on its own: a pinch owns
        // it between willStart and didEnd, the settle until it lands on the
        // grid. Setting it from here is what made the page shrink and bounce.
        // Nor during the column's slide: the room and the borrow would be
        // read mid-change, and disagree. The debounced drift fits the room
        // the slide lands on.
        guard !isLiveMagnifying, !isAnimatingSettle, !isLentTransitioning,
              scrollView.contentView.frame.width > 1 else { return }
        if applyPreferredMagnification() {
            layOut()
            updateGhost()
        }
        pinOpeningViewportIfNeeded()
    }

    // MARK: - How large the page is drawn

    /// The size the writer is working at, as distinct from the size on screen.
    ///
    /// They are the same thing until the size is borrowed: the percentage
    /// button shows actual size *temporarily*, and a thread column beside the
    /// page fits whatever room is left while it is open. A borrowed size is
    /// always given back — pressing the button twice, or closing the column,
    /// returns the size that was there before rather than leaving the writer
    /// to find it again.
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

    /// Whether the thread column beside the page has borrowed the size.
    ///
    /// While it is open the page fits the room that is left; the writer's
    /// preference waits, untouched, and comes back when the column closes.
    /// Any size the writer asks for in the meantime — a pinch, ⌘+, the menu —
    /// ends the borrow on the spot: the last explicit choice is the one that
    /// stands.
    private var sizeLentToThread = false

    /// True between a thread column's open or close and the drift that
    /// answers it — the slide's duration, plus a breath. The frame
    /// observer's fits stand down for it: read then, the new room and the
    /// old borrow would disagree, and the page would snap.
    private var isLentTransitioning = false

    /// How many times the transition's geometry has moved. Every layout
    /// frame of the column's slide bumps it, and the drift is scheduled by
    /// the latest number — so only the settled room is ever fitted.
    private var lentGeneration = 0

    func applyZoom(_ command: PageZoom.Command) {
        // A command that arrives mid-settle means the writer has somewhere
        // else to be: stop the drift where it is and answer from there.
        cancelSettle()
        switch command {
        case .fit:
            // The menu's fit is the writer's own choice — it outlives the
            // column, so it ends the borrow rather than sitting under it.
            preference = .fit
            atActualSize = false
            sizeLentToThread = false
        case .zoomIn, .zoomOut:
            // An explicit size ends the thread's borrow: from here the
            // writer's own choice is the one that stands.
            preference = .fixed(PageZoom.stepped(from: scrollView.magnification, command))
            atActualSize = false
            sizeLentToThread = false
        case .actualSize:
            // Leaves the preference alone, so the percentage button still
            // knows where to go back to. ⌘0 and that button are the same
            // gesture reached two ways. The thread's borrow is left alone
            // too: actual size borrows the lent size, it does not end the
            // lend — pressing the button twice beside an open thread returns
            // to the fit it left in place, not to a size that fits no longer.
            atActualSize = true
        case .toggleActualSize:
            atActualSize.toggle()
        }
        layOut()
        if applyPreferredMagnification() { layOut() }
        updateGhost()
    }

    /// A size the writer chose by name from the percentage menu.
    ///
    /// An explicit choice, so it stands with a pinch or a keyed size: it
    /// ends the thread's borrow rather than sitting under it, and a window
    /// resize must not undo it.
    func applyChosenSize(_ size: CGFloat) {
        // A choice that arrives mid-settle means the writer has somewhere
        // else to be: stop the drift where it is and answer from there.
        cancelSettle()
        preference = .fixed(min(max(size, PageZoom.actualSize), PageZoom.maximum))
        atActualSize = false
        sizeLentToThread = false
        layOut()
        if applyPreferredMagnification() { layOut() }
        updateGhost()
    }

    /// The thread column beside the page opened, or closed.
    ///
    /// Open, the page lends the room: it fits whatever the column leaves,
    /// down to actual size and never below — the same floor as every fit.
    /// Closed, the writer's own size comes back. Both are drifts, never
    /// snaps: the column arriving is change enough without the page jumping
    /// to meet it.
    func threadColumn(opened: Bool) {
        if opened {
            guard !sizeLentToThread else { return }
            sizeLentToThread = true
        } else {
            guard sizeLentToThread else { return }
            sizeLentToThread = false
        }
        // A pinch owns the size until the fingers lift; the gesture's settle
        // is the next writer of it, and an explicit size ends the borrow
        // anyway.
        guard !isLiveMagnifying else { return }
        cancelSettle()
        // A windowless surface — the test harness — has no layout pass
        // coming: the room is what it is. With a window, the column slides
        // for a fifth of a second and every frame of the slide is a new
        // room, so the drift waits for the slide to fall quiet; until then
        // the frame observer's fits stand down.
        if scrollView.window == nil {
            driftToPreferredSize()
        } else {
            isLentTransitioning = true
            lentGeneration += 1
            scheduleLentDrift()
        }
    }

    /// Schedules the drift that ends a column's slide. A debounce, not a
    /// delay: every layout frame of the slide reschedules it, so it runs
    /// only once the room has been still for a breath — fitting the room
    /// the slide landed on, never a guess partway.
    private func scheduleLentDrift() {
        let generation = lentGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [weak self] in
            guard let self, self.isLentTransitioning, self.lentGeneration == generation else { return }
            self.isLentTransitioning = false
            self.driftToPreferredSize()
        }
    }

    /// Moves the page to the size the current preference and room ask for,
    /// as a drift rather than a snap. A size asked for mid-transition — the
    /// column's slide — is not lost: this reads the preference when it
    /// fires, so the last choice is the one it glides to.
    private func driftToPreferredSize() {
        let target = atActualSize ? PageZoom.actualSize : preferredMagnification()
        if abs(target - scrollView.magnification) > 0.001 {
            drift(to: target)
        } else {
            reportZoom(scrollView.magnification)
        }
        updateGhost()
    }

    /// Sets the magnification the current preference asks for, and says
    /// whether it moved — the caller re-centres the canvas when it did.
    ///
    /// Never while something else owns the magnification: a pinch owns it
    /// between willStart and didEnd, and the settle owns it until it lands
    /// on the grid. The guard lives here rather than at the callers because
    /// here is the one place every path passes through — a SwiftUI update
    /// arriving mid-gesture used to reach this point via `remeasure` and
    /// set the *old* preference back, snapping the page out from under the
    /// fingers. That is why a pinch used to take several attempts to stick.
    /// A thread column owns it for the turn its layout takes, too: read
    /// then, the new room and the old borrow would disagree, and the page
    /// would snap.
    @discardableResult
    private func applyPreferredMagnification() -> Bool {
        guard !isLiveMagnifying, !isAnimatingSettle, !isLentTransitioning else { return false }
        return magnify(to: atActualSize ? PageZoom.actualSize : preferredMagnification())
    }

    private func preferredMagnification() -> CGFloat {
        // A borrowed size always fits the room the column left; the writer's
        // own preference is not consulted until the column gives it back.
        if sizeLentToThread { return fitting(scrollView.contentView.frame.width) }
        switch preference {
        case .fixed(let value): return value
        case .fit: return fitting(scrollView.contentView.frame.width)
        }
    }

    /// As large as the room allows, within the same bounds as everything
    /// else — or the size the page already has, when the clip has not been
    /// laid out enough to say.
    ///
    /// The clip view's *frame* is the width in screen points; its bounds are
    /// already divided by the magnification, which is the number being solved
    /// for here.
    private func fitting(_ clipWidth: CGFloat) -> CGFloat {
        clipWidth > 1
            ? PageZoom.fitting(
                canvasWidth: clipWidth,
                pageWidth: PageFormat.current.pageRect.width,
                padding: canvas.canvasPadding
            )
            : scrollView.magnification
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
            reportZoom(value)
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
        reportZoom(value)
        // While the fingers are still down, the readout above is all that
        // moves. AppKit is mid-gesture and settling its own rubber-band;
        // anything else here is two hands on the same wheel. The settle's
        // frames arrive here too — each one writes the magnification, and
        // each looks like a fresh gesture unless it is named as ours.
        guard fromGesture, !isLiveMagnifying, !isAnimatingSettle else { return }
        settleAfterGesture()
    }

    /// Tells the model — and so the readout in the corner — how large the
    /// page is drawn. A pinch and a settle both move the size at frame
    /// rate, and the readout displays whole percentage points: reported at
    /// that granularity, the glass capsule re-renders only when the number
    /// it shows actually changes, rather than dozens of times a second.
    private func reportZoom(_ value: CGFloat) {
        if (isLiveMagnifying || isAnimatingSettle), let editor,
           PageZoom.displayedPercentage(editor.zoom) == PageZoom.displayedPercentage(value) {
            editor.reportHoldingActualSize(atActualSize)
            return
        }
        editor?.reportZoom(value)
        editor?.reportHoldingActualSize(atActualSize)
    }

    /// The size the gesture left behind becomes the writer's choice — the
    /// grid point it drifts to, not the raw landing — and the canvas is
    /// measured for it.
    private func settleAfterGesture() {
        let landed = scrollView.magnification
        let target = PageZoom.settled(landed)
        preference = .fixed(target)
        atActualSize = false
        // A pinch is an explicit size, and the last explicit choice stands:
        // the thread's borrow ends where the fingers finish.
        sizeLentToThread = false
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
        if abs(target - landed) > 0.001 {
            drift(to: target)
        } else {
            reportZoom(landed)
        }
        updateGhost()
    }

    // MARK: - The drift to the grid

    /// True while the drift is walking the magnification to the grid. Each
    /// of its frames changes the magnification, so everywhere the live
    /// pinch is guarded, this is too.
    private var isAnimatingSettle = false
    private var settleLink: CADisplayLink?
    private var settleFrom: CGFloat = 0
    private var settleTo: CGFloat = 0
    private var settleBegan: CFTimeInterval = 0
    private var settleDuration: CFTimeInterval = 0

    /// Walks the magnification from where the fingers left it to the stop
    /// they were nearest.
    ///
    /// Driven by a display link rather than handed to an animator proxy:
    /// the curve is the whole feature — a monotonic ease, explicitly *not*
    /// a bounce — and a link keeps the curve, the readout and interruption
    /// all explicit. The link is the scroll view's own, so it keeps time
    /// with the display the window is actually on and suspends itself when
    /// the window is off one. A new pinch or a zoom command cancels it
    /// mid-flight and takes the page from wherever the drift has reached;
    /// nothing jumps.
    private func drift(to target: CGFloat) {
        // A surface with no window is the test harness: land on the stop
        // directly — there is no screen to drift on.
        guard scrollView.window != nil else {
            magnify(to: target)
            return
        }
        cancelSettle()
        isAnimatingSettle = true
        syncHorizontalCentring()
        settleFrom = scrollView.magnification
        settleTo = target
        settleDuration = PageZoom.driftDuration(for: abs(target - settleFrom))
        settleBegan = CACurrentMediaTime()
        let link = scrollView.displayLink(
            target: SettleRelay(self), selector: #selector(SettleRelay.tick(_:))
        )
        link.add(to: .main, forMode: .common)
        settleLink = link
    }

    /// One frame of the drift: how far along we are comes from the link,
    /// which is only a clock; where that puts the page is `PageZoom.eased`,
    /// held in the core where a test can hold it.
    fileprivate func settleFrame() {
        let t = min(max((CACurrentMediaTime() - settleBegan) / settleDuration, 0), 1)
        guard t < 1 else {
            let target = settleTo
            // Magnify before standing down, so the last frame's bounds
            // proposal is still made under the drift's centring.
            magnify(to: target)
            cancelSettle()
            return
        }
        // Written directly rather than through `magnify`: each frame is
        // reported by the magnification observer like a gesture is, and
        // `isAnimatingSettle` is what tells the two apart.
        scrollView.magnification = PageZoom.eased(from: settleFrom, to: settleTo, progress: t)
    }

    /// Stops the drift wherever it has got to — never by jumping to the
    /// target. The page is already on its way there; what takes over (a
    /// pinch, a button, a keystroke) starts from the size on screen.
    private func cancelSettle() {
        guard isAnimatingSettle else { return }
        settleLink?.invalidate()
        settleLink = nil
        isAnimatingSettle = false
        syncHorizontalCentring()
    }

    /// Whether the clip view pins the page to the window's midline — true
    /// exactly while a pinch or its landing drift owns the size. Derived
    /// from the two flags rather than set on its own, so it can never
    /// disagree with them.
    private func syncHorizontalCentring() {
        (scrollView.contentView as? CentringClipView)?.centresHorizontally =
            isLiveMagnifying || isAnimatingSettle
    }

    /// A pinch whose didEnd never arrived — the window closed or was torn
    /// down mid-gesture. Without this the surface would go on believing the
    /// fingers are still down: every later attempt to set the magnification
    /// would be refused as "mid-pinch", and the corner buttons would go dead.
    private func recoverFromInterruptedGesture() {
        cancelSettle()
        isLiveMagnifying = false
        syncHorizontalCentring()
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
        // A paper flip restyles the text but never moves it, so the writer's
        // selection lives through the re-render verbatim. Restoring from the
        // model would bring back only the caret — the model tracks an
        // element and an offset, not a range — and a selected word would
        // come back unselected.
        let selection = selectionTextView.selectedRange()
        renderedRevision = -1
        render(editor.screenplay.elements) { [self] in
            restoreSelection(selection)
            refreshFormatBar(selection: selection)
        }
        renderedRevision = editor.revision
        updateTypingAttributes()
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
        window.makeFirstResponder(selectionTextView)
        pinOpeningViewportIfNeeded()
    }

    /// `NSScrollView` keeps the clip-view centre when magnification
    /// changes. The opening size is 1.25×, so a window that first lays
    /// out at 100% and then magnifies lands about a tenth of a screen
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
    public var breakMarkerPageNumbers: [Int] { canvas.breakMarkerPageNumbers }

    /// What is currently laid out, so a test can ask the engine whether the
    /// page boundaries moved rather than trusting that they did not.
    public var renderedElements: [ScriptElement] { lastLaidElements }

    /// The character at the top of what the writer can see. This is the thing
    /// a mode change has to preserve — not the scroll offset, which means
    /// something different once the document's height has changed.
    public var topmostVisibleCharacter: Int? { anchoredLine()?.location }

    /// The anchor line and its distance below the viewport's top edge — the
    /// pair a mode change holds still. The offset is the half of stillness
    /// the location alone cannot say: when the window's top sat on desk or
    /// a margin pair, the band's departure fills that space with earlier
    /// text, and the topmost *line* legitimately changes while the line the
    /// writer was reading keeps its place.
    public var anchoredLineForTesting: (location: Int, offset: CGFloat)? { anchoredLine() }

    /// How far below the viewport's top edge a character's line sits, so a
    /// stillness test can measure the writer's own line rather than
    /// whichever line happens to be first.
    public func screenOffsetForTesting(atCharacter location: Int) -> CGFloat? {
        if usesPageSheets {
            return characterCanvasRect(location).map { $0.minY - scrollView.contentView.bounds.minY }
        }
        guard let rect = boundingRect(atCharacter: location) else { return nil }
        return canvas.convert(rect, from: textView).minY - scrollView.contentView.bounds.minY
    }

    /// Six lines to the inch without cropping a tall glyph. Held here because
    /// `NSLayoutManager.delegate` is weak.
    private let fixedLeading = FixedLeading()
    /// True while this class is the one changing the magnification, so the
    /// observer can tell the writer's pinch from our own setting.
    private var isSettingMagnification = false
    private var magnificationObserver: NSKeyValueObservation?
    /// Scroll, resize and zoom, heard as one signal — the bar's cue to
    /// follow the selection. See `repositionFormatBar`.
    private var clipBoundsObserver: (any NSObjectProtocol)?
    /// True between `willStartLiveMagnify` and `didEndLiveMagnify`.
    ///
    /// A pinch is not one change of size, it is dozens a second, and AppKit
    /// rubber-bands past the limits and settles back on its own. Recording a
    /// preference and re-measuring the canvas on every one of those fights the
    /// gesture — the page shrinks, snaps and bounces under the fingers. So the
    /// readout follows live and nothing else moves until the fingers lift.
    /// The settle that follows owns the magnification the same way; see
    /// `isAnimatingSettle`.
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
        canvas.showNotes(notePlacements(), active: openNoteIDs.first) { [weak self] ids in
            self?.openNotes(ids)
        }
    }

    /// Every note the page marks, with the line it belongs to: the writer's
    /// own, then the ones a Final Draft file carried.
    ///
    /// A note of the writer's with no line trails the script, which is where
    /// it was left. An imported note with no line is one whose line could not
    /// be found in this draft; putting it beside the last line would say it
    /// is about that line, so it is left to the Navigator, which says why.
    private func notedLines(_ editor: EditorState) -> [(id: UUID, anchor: UUID?)] {
        editor.notes.map { ($0.id, $0.anchor) }
            + editor.importedNotes.compactMap { note in note.anchor.map { (note.id, $0) } }
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
        let layoutManager = self.layoutManager
        let whole = NSRange(location: 0, length: textStorage.length)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: whole)
        guard let editor else { return }
        let lines = notedLines(editor)
        guard !lines.isEmpty else { return }

        let byElement = Dictionary(ranges.map { ($0.id, $0.range) }) { first, _ in first }
        // Resolved for the page's own appearance, the way the ink is: a light
        // page in a dark app takes the wash meant for paper.
        var wash: NSColor = .screenplayNoteWash
        var open: NSColor = .screenplayOpenNoteWash
        textView.effectiveAppearance.performAsCurrentDrawingAppearance {
            wash = NSColor.screenplayNoteWash.usingColorSpace(.sRGB) ?? wash
            open = NSColor.screenplayOpenNoteWash.usingColorSpace(.sRGB) ?? open
        }

        for note in lines {
            guard let anchor = note.anchor, let range = byElement[anchor], range.length > 0,
                  NSMaxRange(range) <= whole.length else { continue }
            // The wash yields to the mark: a highlight is content in the
            // storage and the more specific claim on those words, so a noted
            // line is tinted everywhere *except* where one stands
            // (docs/RFC-HIGHLIGHTER.md §4).
            let color = openNoteIDs.contains(note.id) ? open : wash
            for unmarked in unhighlightedSubranges(of: range) {
                layoutManager.addTemporaryAttribute(
                    .backgroundColor,
                    value: color,
                    forCharacterRange: unmarked
                )
            }
        }
    }

    /// The pieces of `range` that carry no storage highlight — the gaps
    /// between highlighted spans, in order. The wash paints these; the mark
    /// keeps its own.
    private func unhighlightedSubranges(of range: NSRange) -> [NSRange] {
        guard range.length > 0 else { return [range] }
        let storage = textStorage
        var subranges: [NSRange] = []
        var cursor = range.location
        storage.enumerateAttribute(.backgroundColor, in: range) { value, subrange, _ in
            guard value != nil else { return }
            if subrange.location > cursor {
                subranges.append(NSRange(location: cursor, length: subrange.location - cursor))
            }
            cursor = NSMaxRange(subrange)
        }
        if cursor < NSMaxRange(range) {
            subranges.append(NSRange(location: cursor, length: NSMaxRange(range) - cursor))
        }
        return subranges
    }

    /// Where each note's mark goes, in canvas coordinates.
    ///
    /// Several notes may belong to one line — Final Draft allows it and the
    /// two production drafts use it — and they were all given that line's
    /// rectangle, so they landed on top of each other and read as one note.
    /// The card's "2 of 3" said otherwise, which is worse than either.
    /// `column` fans them across the margin; the canvas decides how far.
    /// The colour slot for each note, by id.
    ///
    /// The page's half of the reading the Navigator makes, taken from the same
    /// roster and the same palette, so one name is one colour in both places.
    func noteAuthorSlots() -> [UUID: Int] {
        guard let editor else { return [:] }
        let roster = editor.noteRoster
        let slots = NoteAttribution.slots(for: roster)
        var found: [UUID: Int] = [:]
        for note in editor.notes {
            guard let author = NoteAttribution.author(of: note.text, roster: roster),
                  let slot = slots[author.name] else { continue }
            found[note.id] = slot
        }
        // A note from Final Draft is whoever the file says wrote it; the
        // colour Final Draft gave it says what kind of note it is, not who.
        for note in editor.importedNotes {
            guard let author = ImportedNotes.author(of: note, in: roster),
                  let slot = slots[author] else { continue }
            found[note.id] = slot
        }
        return found
    }

    private func notePlacements() -> [PageCanvasView.NotePlacement] {
        guard let editor else { return [] }
        let byElement = Dictionary(ranges.map { ($0.id, $0.range) }) { first, _ in first }
        let slots = noteAuthorSlots()

        // Gathered by line rather than listed per note. Three notes on one
        // line used to be three marks side by side in the margin, walking
        // toward the edge of the sheet, and their words readable only one at
        // a time. The line is what the writer is looking at, so the line
        // carries one mark and its card holds everything left on it.
        var order: [String] = []
        var byLine: [String: (top: CGFloat, height: CGFloat, ids: [UUID], marginX: CGFloat?)] = [:]
        for note in notedLines(editor) {
            // A note anchored to nothing trails the script, and belongs
            // beside its last line — which is where the writer left it.
            let range = note.anchor.flatMap { byElement[$0] } ?? ranges.last?.range
            guard let range else { continue }
            let inCanvas: CGRect
            let marginX: CGFloat?
            let page: Int
            if usesPageSheets {
                guard let geometry = sheetRect(for: NSRange(location: range.location, length: 0)) else { continue }
                inCanvas = canvas.convert(geometry.rect, from: geometry.view)
                marginX = canvas.convert(geometry.view.bounds, from: geometry.view).maxX + PageCanvasView.noteMarkerGap
                page = pageIndex(containing: range.location)
            } else if canvas.arrangement == .grid {
                guard let rect = boundingRect(atCharacter: range.location) else { continue }
                page = pageIndex(containing: range.location)
                guard let mapped = canvas.gridNotePlacement(textRect: rect, page: page) else { continue }
                inCanvas = CGRect(
                    x: mapped.marginX, y: mapped.lineTop, width: 0, height: mapped.lineHeight
                )
                marginX = mapped.marginX
            } else {
                guard let rect = boundingRect(atCharacter: range.location) else { continue }
                let drawn = (textView as? ArrangedTextView)?.fold?.spreadRect(fromVertical: rect) ?? rect
                inCanvas = canvas.convert(drawn, from: textView)
                marginX = nil
                page = 0
            }
            let line = "\(page):\(Int(inCanvas.minY.rounded()))"
            if var existing = byLine[line] {
                existing.ids.append(note.id)
                byLine[line] = existing
            } else {
                order.append(line)
                byLine[line] = (inCanvas.minY, inCanvas.height, [note.id], marginX)
            }
        }
        return order.compactMap { line in
            guard let group = byLine[line] else { return nil }
            // Every note on the line has to agree, or the mark stays neutral:
            // one bubble in the margin cannot say two people's names.
            let agreed = Set(group.ids.compactMap { slots[$0] })
            let shared = agreed.count == 1 && group.ids.count == group.ids.compactMap {
                slots[$0]
            }.count ? agreed.first : nil
            return PageCanvasView.NotePlacement(
                noteIDs: group.ids, authorSlot: shared,
                lineTop: group.top, lineHeight: group.height, marginX: group.marginX
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

    /// How the writer is asked their name for notes. Nil presents
    /// `NoteNamePrompt` on the window; the tests answer it themselves.
    var askNoteName: ((@escaping (NoteNamePrompt.Answer?) -> Void) -> Void)?

    /// Runs `add` once the writer has a name for notes: at once when they
    /// have one, after "Your name for notes" when they do not (RFC-NOTES-SYSTEM
    /// §8), and not at all when they cancel.
    private func withNoteName(_ add: @escaping () -> Void) {
        guard let editor, editor.needsNoteName else {
            add()
            return
        }
        let finish: (NoteNamePrompt.Answer?) -> Void = { [weak self] answer in
            guard let self, let editor = self.editor, let answer else { return }
            editor.setNoteIdentity(name: answer.name, role: answer.role)
            add()
        }
        if let askNoteName {
            askNoteName(finish)
        } else {
            NoteNamePrompt.ask(on: textView.window, completion: finish)
        }
    }

    /// `nil` means the caret's own element — see `EditorState.addNote`.
    private func addNote(to anchor: UUID?) {
        // The line is settled before anything is asked.
        let line = anchor ?? editor?.activeElementID
        withNoteName { [weak self] in self?.placeNote(on: line) }
    }

    private func placeNote(on anchor: UUID?) {
        guard let editor, let note = editor.addNote(to: anchor) else { return }
        renderIfNeeded(editor)
        // Everything on that line, so a second note joins the first in one
        // card rather than replacing it — and joins any Final Draft left there.
        let line = notedLines(editor).filter { $0.anchor == note.anchor }.map(\.id)
        // The new one takes the caret, whether it is this line's first note
        // or its fourth.
        openNotes(line.isEmpty ? [note.id] : line, focusing: note.id)
    }

    /// Opens a note's card, pointing at its mark.
    ///
    /// An `NSPopover` rather than a card parked in the margin: the desk is
    /// a breath either side of the paper and a Pages comment card is 260,
    /// so a card that lived out there would either cover the script or
    /// push the page off centre every time a note existed. A popover is the
    /// same rounded, elevated card with an arrow to the mark it came from,
    /// and it is the system's own.
    /// Opens the card for a line's notes, pointing at its mark.
    ///
    /// An `NSPopover` rather than a card parked in the margin: the desk is
    /// 36 points wide either side of the paper and this card is 280, so a
    /// card that lived out there would either cover the script or push the
    /// page off centre every time a note existed. A popover is the same
    /// rounded, elevated card with an arrow to the mark it came from, and it
    /// is the system's own.
    public func openNotes(_ ids: [UUID], focusing focused: UUID? = nil) {
        guard let editor, let anchor = ids.first,
              let marker = canvas.noteMarker(for: anchor) else { return }

        commitOpenNotes()
        notePopover?.performClose(nil)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: NoteCard(
                notes: editor.notes.filter { ids.contains($0.id) },
                imported: editor.importedNotes.filter { ids.contains($0.id) },
                authorSlots: noteAuthorSlots(),
                focused: focused,
                onEdit: { [weak self] id, text in self?.openNoteDrafts[id] = text },
                onDone: { [weak self] in self?.commitOpenNotes() },
                onDelete: { [weak self] id in
                    guard let self else { return }
                    // Dropped before the model changes, so closing the card
                    // cannot write the deleted note's text back.
                    self.openNoteDrafts[id] = nil
                    let remaining = self.openNoteIDs.filter { $0 != id }
                    self.editor?.deleteNote(id: id)
                    // Nothing takes the caret: removing a note is not the
                    // same as wanting to write another one.
                    self.reopen(remaining, focusing: nil)
                },
                onAdd: { [weak self] in
                    guard let self, let editor = self.editor else { return }
                    // The same line the card belongs to, whatever the caret
                    // is doing elsewhere.
                    let line = self.notedLines(editor).first { $0.id == anchor }?.anchor
                    let open = self.openNoteIDs
                    self.withNoteName { [weak self] in
                        guard let self, let editor = self.editor,
                              let added = editor.addNote(to: line) else { return }
                        // The caret goes into the note just made — not back to
                        // the first one, which the writer has already written.
                        self.reopen(open + [added.id], focusing: added.id)
                    }
                }
            )
        )
        notePopover = popover
        openNoteIDs = ids
        openNoteDrafts = [:]
        placeNoteMarkers()
        washNotedLines()
        popover.show(relativeTo: marker.bounds, of: marker, preferredEdge: .maxX)

        // The card opens ready to be written in.
        //
        // `NSPopover` puts its content in a window of its own and does not
        // make it key, so the card opened with no caret and read as an empty
        // box — a keystroke went to the script's window instead and dismissed
        // the card. Scrolling the page afterwards made the caret appear,
        // which is the tell: the window became key by accident, later, and
        // only then did any of it mean anything.
        DispatchQueue.main.async { [weak popover] in
            guard let window = popover?.contentViewController?.view.window else { return }
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Lays the page out again and puts the card back, after adding a note to
    /// this line or removing one from it. The mark is placed by the layout,
    /// so the card has nothing to point at until that has happened.
    private func reopen(_ ids: [UUID], focusing focused: UUID?) {
        guard let editor else { return }
        notePopover?.performClose(nil)
        renderIfNeeded(editor)
        let alive = ids.filter { id in notedLines(editor).contains { $0.id == id } }
        guard !alive.isEmpty else { return }
        openNotes(alive, focusing: focused)
    }


    /// However the card ends — clicked away from, replaced, or closed with
    /// the window — this is where the writing lands.
    public func popoverDidClose(_ notification: Notification) {
        guard (notification.object as AnyObject?) === notePopover else { return }
        commitOpenNotes()
        openNoteIDs = []
        notePopover = nil
        placeNoteMarkers()
        washNotedLines()
    }

    /// Writes what the open card reads into the model, if it changed.
    ///
    /// The one place a note is written. Called when the card closes — by the
    /// writer clicking away, by the next note replacing it, or by the window
    /// going away — so the arrangement holds however the card ends.
    private func commitOpenNotes() {
        guard let editor, !openNoteIDs.isEmpty else { return }
        let drafts = openNoteDrafts
        openNoteDrafts = [:]
        // What to do with a blank one is the model's rule, not the card's —
        // the phone's surface will close a note too. See `finishNote`.
        for id in openNoteIDs {
            editor.finishNote(id: id, text: drafts[id])
        }
    }

    /// The text view SwiftUI's `TextEditor` is made of, wherever it has put
    /// it in the view tree.
    private static func firstTextView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        for child in view.subviews {
            if let found = firstTextView(in: child) { return found }
        }
        return nil
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
        guard let mapped = ranges.first(where: { $0.id == id }) else { return false }

        // Grid is a map: light the sheet that holds the line, do not pretend
        // to put a caret on a thumbnail.
        if canvas.arrangement == .grid {
            canvas.highlightGridPage(pageIndex(containing: mapped.range.location))
            return true
        }

        if usesPageSheets {
            guard let geometry = sheetRect(for: mapped.range) else { return false }
            geometry.view.setSelectedRange(NSRange(location: mapped.range.location, length: 0))
            updateSelection()
            geometry.view.scrollRangeToVisible(mapped.range)
            highlight.mark(geometry.rect, in: geometry.view, reduceMotion: reduceMotion)
            return true
        }
        guard let rect = ScriptLayout.boundingRect(of: mapped.range, in: textView)
        else { return false }

        textView.setSelectedRange(NSRange(location: mapped.range.location, length: 0))
        updateSelection()
        scroll(revealing: rect)
        mark(rect, reduceMotion: reduceMotion)
        return true
    }

    /// Which sheet holds this character, from the engine's page starts.
    private func pageIndex(containing location: Int) -> Int {
        let starts = pagination(for: lastLaidElements).locations
        guard starts.count > 1 else { return 0 }
        var index = 0
        while index + 1 < starts.count, starts[index + 1] <= location {
            index += 1
        }
        return index
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

    /// How far below the top of the readable area a reveal comes to rest, as
    /// a share of the visible height. A fifth: enough that the lines leading
    /// to the mark are on the glass with it — a cue is read in the exchange
    /// that prompted it — and little enough that the mark is plainly the
    /// place arrived at. Flush against the chrome was neither.
    private static let revealAir: CGFloat = 0.2

    /// Moves the page so `rect` comes to rest a little below the top of the
    /// readable area, the lines that led to it still on the glass — as near
    /// as the document allows.
    ///
    /// Vertically only. A reveal answers "where"; it is not a licence to
    /// move the page sideways. It once asked for x at the paper's own left
    /// edge — and `scroll(to:)` is not answered by `constrainBoundsRect`,
    /// so the request landed raw: a window wider than the paper pinned the
    /// sheet against the Navigator's side. The midline is stated here
    /// instead, the same arithmetic the clip view owns: paper narrower than
    /// the window stays centred, and paper wider keeps the writer's pan.
    public func scroll(revealing rect: CGRect) {
        let range = scrollableRange
        guard PageScroll.canScroll(range) else { return }
        let clip = scrollView.contentView
        let air = clip.bounds.height * Self.revealAir
        let y = PageScroll.offset(
            bringingContentY: canvasY(ofTextRect: rect), toTopOf: range, airAbove: air
        )
        let x = clip.bounds.width >= canvas.frame.width
            ? (canvas.frame.width - clip.bounds.width) / 2
            : clip.bounds.origin.x
        clip.scroll(to: NSPoint(x: x, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    /// A text-view rectangle, lifted into the canvas the scroll view actually
    /// moves. The page card sits around the text; without this, a reveal
    /// would scroll as if the paper's top margin were not there.
    /// `rect` is in the text view's coordinates already — `ScriptLayout.boundingRect`
    /// adds `textContainerOrigin`, which is the inset. Adding the inset here as
    /// well put every reveal one line low, because the inset *is* one line
    /// (`glyphOverflow`). Measured on screen, 2026-09-08.
    private func canvasY(ofTextRect rect: CGRect) -> CGFloat {
        canvasRect(fromTextRect: rect).minY
    }

    /// `rect` arrives in TextKit's own column, the way `ScriptLayout` hands it
    /// over. The mark is a subview of the text view, so the fold belongs here,
    /// at the boundary — and the widening belongs before it, because a
    /// container's width is a column's width and the fold is what scales it.
    private func mark(_ rect: CGRect, reduceMotion: Bool) {
        var marked = rect
        if marked.width < 1, let container = textView.textContainer {
            marked.size.width = container.size.width
        }
        highlight.mark(
            spreadRect(fromTextRect: marked), in: textView, reduceMotion: reduceMotion
        )
    }

    /// Whether a mark is currently on the page — the surface's own answer to
    /// "did that reveal say anything?", and what a test asks.
    public var isMarking: Bool {
        (highlight.superview === textView || sheets.contains { highlight.superview === $0.textView })
            && highlight.frame.height > 0
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

        // A typed `*`, `_` or `~` may complete a marker pair (RFC v2.1 §3.3 —
        // D6, an input transformation, never a display mode): the markers
        // collapse into a style run and cease to exist as text. A `\` before
        // the caret escapes the character instead — the backslash is consumed
        // and the marker arrives literal, never collapsing.
        if text == "*" || text == "_" || text == "~",
           range.length == 0, let mapped, let index {
            let element = editor.screenplay.elements[index]
            let nsText = element.text as NSString
            let p = max(0, min(range.location - mapped.range.location, nsText.length))
            if p > 0, nsText.substring(with: NSRange(location: p - 1, length: 1)) == "\\" {
                textView.insertText(
                    text,
                    replacementRange: NSRange(location: range.location - 1, length: 1)
                )
                return false
            }
            let typed = nsText.replacingCharacters(in: NSRange(location: p, length: 0), with: text)
            if let collapse = Emphasis.liveCollapse(typed, insertedAt: p) {
                // The pre-existing runs travel through the same three steps
                // the text just took: the typed character arrives, then the
                // marker spans leave — latest first, so the earlier offsets
                // stay true — then the collapsed span joins as one run.
                var length = (typed as NSString).length
                var runs = Emphasis.propagate(
                    element.runs ?? [], replacing: (p, p),
                    insertedLength: 1, newLength: length
                )
                for span in collapse.removed.sorted(by: { $0.start > $1.start }) {
                    length -= span.end - span.start
                    runs = Emphasis.propagate(
                        runs, replacing: (span.start, span.end),
                        insertedLength: 0, newLength: length
                    )
                }
                runs = Emphasis.normalise(
                    runs + [collapse.run], textLength: (collapse.text as NSString).length
                )

                var elements = editor.screenplay.elements
                elements[index].text = collapse.text
                elements[index].runs = runs.isEmpty ? nil : runs
                let caret = mapped.range.location + collapse.caret
                pendingEdit = nil
                applyModelEdit(
                    elements,
                    activeID: mapped.id,
                    offset: collapse.caret,
                    selection: NSRange(location: caret, length: 0),
                    actionName: Self.styleActionName(collapse.run.styles)
                )
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
            renumberActCardsIfNeeded()
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
        retireSelectionPaint()
        updateSelection()
        updateTypingAttributes()
        refreshFormatBar(selection: selectionTextView.selectedRange())
        updateGhost()
    }

    /// Dirties what the outgoing highlight painted, then records the
    /// incoming one.
    ///
    /// `selectionPaintRect` answers the region the highlight reached —
    /// fragments, spacing bands and descent overhang — which is a superset
    /// of what TextKit's own invalidation dirties, so the two are the
    /// difference between the paint coming down and most of it coming down.
    private func retireSelectionPaint() {
        if usesPageSheets {
            let incoming = selectionTextView.selectedRange()
            for (index, sheet) in sheets.enumerated() {
                let end = index + 1 < sheets.count ? sheets[index + 1].startLocation : textStorage.length
                let owned = NSRange(location: sheet.startLocation, length: max(0, end - sheet.startLocation))
                if NSIntersectionRange(owned, paintedSelection).length > 0
                    || NSIntersectionRange(owned, incoming).length > 0 {
                    sheet.textView.needsDisplay = true
                }
            }
            paintedSelection = incoming
            return
        }
        if paintedSelection.length > 0, let dirty = selectionPaintRect(for: paintedSelection) {
            textView.setNeedsDisplay(dirty)
        }
        paintedSelection = selectionTextView.selectedRange()
    }

    /// The rectangle a selection's highlight actually paints, in the text
    /// view's coordinates: the line fragments the range touches, opened out
    /// over the paragraph spacing beside them and the descent Courier draws
    /// past its used rect.
    ///
    /// The opening-out is the point. The spacing between two elements
    /// belongs to no line fragment, so range-based invalidation never
    /// dirties it — and a selection covering a paragraph's end highlights
    /// into it. Two lines is the widest spacing the page uses; the two
    /// points are the descent this file's `layOut` already knows the used
    /// rect undershoots.
    func selectionPaintRect(for range: NSRange) -> CGRect? {
        guard let layoutManager = textView.layoutManager,
              let container = textView.textContainer,
              range.length > 0
        else { return nil }
        // A render can shorten the text between the paint and its removal
        // (a centred line drops its markers); what is left of the range
        // still answers where the paint was.
        let length = textStorage.length
        let clamped = NSRange(
            location: min(range.location, length),
            length: min(range.length, max(0, length - min(range.location, length)))
        )
        guard clamped.length > 0 else { return nil }
        let glyphs = layoutManager.glyphRange(forCharacterRange: clamped, actualCharacterRange: nil)
        guard glyphs.length > 0, glyphs.location != NSNotFound else { return nil }
        var painted = CGRect.null
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
            painted = painted.union(rect)
        }
        guard !painted.isNull else { return nil }
        let air = ScreenplayPageLayout.lineHeight * 2 + 2
        let dirty = painted
            .insetBy(dx: -1, dy: -air)
            .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            .intersection(textView.bounds)
        return dirty.isEmpty ? nil : dirty
    }

    /// What is lit on the bar, and where it floats.
    private func refreshFormatBar(selection: NSRange) {
        formatBar.update(
            selection: selection, in: selectionTextView, active: styleCoverage(at: selection)
        )
    }

    /// Moves the bar to the selection's current screen position — the clip
    /// view's bounds changes are scroll, resize and zoom in one signal.
    private func repositionFormatBar() {
        formatBar.reposition(selection: selectionTextView.selectedRange(), in: selectionTextView)
    }

    /// The bar's frame in the scroll view's coordinates, for tests; nil
    /// while the bar is hidden.
    var formatBarFrame: CGRect? {
        formatBar.isVisible ? formatBar.frame : nil
    }

    /// The bar's view, for hit-testing and responder questions in tests.
    var formatBarHostView: NSView { formatBar.hostView }

    // MARK: - Incremental edits

    private func applyIncrementalEdit(_ edit: PendingEdit) -> Bool {
        guard let editor,
              let rangeIndex = ranges.firstIndex(where: { $0.id == edit.elementID }) else {
            return false
        }

        let elementOrigin = ranges[rangeIndex].range.location
        let delta = edit.insertedLength - edit.replacedRange.length
        let newLength = ranges[rangeIndex].range.length + delta
        guard newLength >= 0 else { return false }

        adjustRange(at: rangeIndex, length: newLength, shiftLaterBy: delta)

        let updatedRange = ranges[rangeIndex].range
        let storage = textStorage
        guard NSMaxRange(updatedRange) <= storage.length else { return false }
        // The text is already shouted if its kind shouts: that happens at the
        // input boundary in `shouldChangeTextIn`, before the characters reach
        // the storage. Nothing to repair here — and the old repair also had to
        // refuse expanding case mappings (ß → SS) to keep its range arithmetic,
        // which left the view lowercase while the model normalised to caps.
        let text = storage.attributedSubstring(from: updatedRange).string
        let selected = selectionTextView.selectedRange()
        let offset = max(
            0,
            min(updatedRange.length, selected.location - updatedRange.location)
        )
        // A glyph taller than the line has to be brought into it, because
        // TextKit clips drawing to the line fragment — see `fitTallGlyphs`.
        ScriptLayout.fitTallGlyphs(storage, range: updatedRange)
        editor.applyLiveText(
            id: edit.elementID,
            text: text,
            selectionOffset: offset,
            replaced: NSRange(
                location: edit.replacedRange.location - elementOrigin,
                length: edit.replacedRange.length
            ),
            insertedLength: edit.insertedLength
        )
        return true
    }

    private func synchronizeModelFromNativeText() {
        guard let editor else { return }
        let previousText = ScreenplayEditPlanner.flattenedText(editor.screenplay.elements)
        guard let difference = ScreenplayEditPlanner.replacementBetween(
            previousText,
            textStorage.string
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

        let nativeSelection = selectionTextView.selectedRange()
        guard let plan = ScreenplayEditPlanner.plan(
            elements: editor.screenplay.elements,
            replacing: difference.0,
            with: difference.1,
            intent: .replacement,
            kindForNewElement: { previous, text, depth, attached in
                editor.kindForInsertedElement(after: previous, text: text, pasteDepth: depth, attached: attached)
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
                kindForNewElement: { previous, text, depth, attached in
                    // A paste is not typing: a line no signal claims is
                    // prose, not the choreography's next guess (the writer
                    // never pressed those Returns).
                    editor.kindForInsertedElement(
                        after: previous, text: text, pasteDepth: depth,
                        attached: attached,
                        fallback: intent == .multilinePaste ? .action : nil
                    )
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
            selection: selectionTextView.selectedRange()
        )
        editor.replaceAllElements(
            elements,
            activeID: activeID,
            offset: offset,
            structural: true,
            recordsUndo: false
        )
        registerModelUndo(previousState, actionName: actionName)
        render(elements) { [self] in
            restoreSelection(selection)
            refreshFormatBar(selection: selection)
        }
        renderedRevision = editor.revision
        updateTypingAttributes()
        reportNativeUndoAvailability()
        updateGhost()
        // Last, and after the tracker compare, never inside `render`: every
        // structural road an act break can leave by ends here, and the hook
        // must read the count the page held *before* this edit drew. Its own
        // renumber re-enters this function once and no-ops there.
        renumberActCardsIfNeeded()
    }

    /// Toggles a style over the current selection — the format bar's verb.
    ///
    /// One decision for the whole selection — fully covered takes the style
    /// off, anything else puts it on — then applied element by element
    /// through the model, so undo, the file and the next writer of these
    /// paragraphs all see the same edit. The separator newlines inside a
    /// multi-element selection belong to no element and carry no style.
    func toggleStyle(_ style: StyleSet, named actionName: String) {
        guard let editor else { return }
        let selection = selectionTextView.selectedRange()
        guard selection.length > 0 else { return }

        var touched: [(index: Int, range: NSRange)] = []
        // `ranges` is parallel to the elements — one index serves both, and
        // looking ranges up by id instead measured quadratic on a
        // feature-length paste.
        for (index, mapped) in ranges.enumerated() {
            guard index < editor.screenplay.elements.count else { break }
            let intersection = NSIntersectionRange(selection, mapped.range)
            guard intersection.length > 0 else { continue }
            touched.append((index, NSRange(
                location: intersection.location - mapped.range.location,
                length: intersection.length
            )))
        }
        guard !touched.isEmpty else { return }

        // One decision for the whole selection: fully covered takes the
        // style off, anything else puts it on. Without it, a selection
        // spanning a bold paragraph and a plain one would strip the first
        // and embolden the second — the classic mixed-selection bug.
        let covered = touched.allSatisfy { index, range in
            Emphasis.isCovered(
                editor.screenplay.elements[index].runs ?? [],
                from: range.location, to: NSMaxRange(range), style: style
            )
        }
        var elements = editor.screenplay.elements
        for (index, range) in touched {
            let current = elements[index].runs ?? []
            if !covered,
               Emphasis.isCovered(current, from: range.location, to: NSMaxRange(range), style: style) {
                continue   // already wears it; adding elsewhere changes nothing here
            }
            let toggled = Emphasis.toggle(
                current,
                from: range.location, to: NSMaxRange(range),
                style: style, textLength: (elements[index].text as NSString).length
            )
            elements[index].runs = toggled.isEmpty ? nil : toggled
        }
        applyModelEdit(
            elements,
            activeID: editor.activeElementID ?? elements[touched[0].index].id,
            offset: editor.selectionOffset,
            selection: selection,
            actionName: actionName
        )
    }

    /// Marks the selection, or takes the mark off — the format bar's
    /// highlighter, the run's other property (`Emphasis.toggleHighlight`),
    /// toggled through the same model path as `toggleStyle` so undo, the
    /// file and the next writer of these paragraphs all see the same edit.
    ///
    /// One decision for the whole selection, the rule the styles set: every
    /// touched span already marked takes it off, anything else marks it
    /// all. One yellow — v1 has no other color to decide (RFC HIGHLIGHTER D1).
    func toggleHighlight(named actionName: String) {
        guard let editor else { return }
        let selection = selectionTextView.selectedRange()
        guard selection.length > 0 else { return }

        var touched: [(index: Int, range: NSRange)] = []
        for (index, mapped) in ranges.enumerated() {
            guard index < editor.screenplay.elements.count else { break }
            let intersection = NSIntersectionRange(selection, mapped.range)
            guard intersection.length > 0 else { continue }
            touched.append((index, NSRange(
                location: intersection.location - mapped.range.location,
                length: intersection.length
            )))
        }
        guard !touched.isEmpty else { return }

        let covered = touched.allSatisfy { index, range in
            Emphasis.highlightCovered(
                editor.screenplay.elements[index].runs ?? [],
                from: range.location, to: NSMaxRange(range)
            )
        }
        var elements = editor.screenplay.elements
        for (index, range) in touched {
            let current = elements[index].runs ?? []
            if !covered,
               Emphasis.highlightCovered(current, from: range.location, to: NSMaxRange(range)) {
                continue   // already wears it; marking elsewhere changes nothing here
            }
            let toggled = Emphasis.toggleHighlight(
                current,
                from: range.location, to: NSMaxRange(range),
                color: covered ? nil : .yellow,
                textLength: (elements[index].text as NSString).length
            )
            elements[index].runs = toggled.isEmpty ? nil : toggled
        }
        applyModelEdit(
            elements,
            activeID: editor.activeElementID ?? elements[touched[0].index].id,
            offset: editor.selectionOffset,
            selection: selection,
            actionName: actionName
        )
    }

    /// Centres every line the selection touches, or takes them all back to
    /// action — an element-level change of the same kind as `toggleStyle`.
    ///
    /// The element's type is the change, not the text around it: the model
    /// and both file formats already agree on what a centred line is
    /// (Fountain parses `> <` at the boundary, FDX stores
    /// `Alignment="Center"`), so the only thing a marker-inserting bar ever
    /// added was the marker. One decision for the whole selection, the rule
    /// the styles set: every touched line already centred undoes them all,
    /// anything else centres them all. Undo is one named step through
    /// `applyModelEdit`, exactly like a style.
    func toggleCentered(named actionName: String) {
        guard let editor else { return }
        let selection = selectionTextView.selectedRange()

        var touched: [Int] = []
        if selection.length == 0 {
            // A caret centres the line it sits in — `elementRange(at:)`
            // owns which element that is (an empty line is still a place,
            // and a caret on the joining newline belongs to the element it
            // just finished).
            if let mapped = elementRange(at: selection.location),
               let index = editor.screenplay.elements.firstIndex(where: { $0.id == mapped.id }) {
                touched.append(index)
            }
        } else {
            for (index, mapped) in ranges.enumerated() {
                guard index < editor.screenplay.elements.count else { break }
                guard NSIntersectionRange(selection, mapped.range).length > 0 else { continue }
                touched.append(index)
            }
        }
        guard !touched.isEmpty else { return }

        let unmark = touched.allSatisfy { editor.screenplay.elements[$0].type == .centered }
        var elements = editor.screenplay.elements
        for index in touched {
            elements[index].type = unmark ? .action : .centered
        }
        applyModelEdit(
            elements,
            activeID: editor.activeElementID ?? elements[touched[0]].id,
            offset: editor.selectionOffset,
            selection: selection,
            actionName: actionName
        )
    }

    /// The undo name for a collapsed marker pair, built from the run's
    /// styles in the bar's own order: "Bold", "Bold Italic", "Underline"…
    private static func styleActionName(_ styles: StyleSet) -> String {
        let names = FormatMark.allCases.compactMap { mark -> String? in
            guard let set = mark.styleSet, styles.contains(set) else { return nil }
            return mark.title
        }
        return names.isEmpty ? "Format" : names.joined(separator: " ")
    }

    /// The marks every character of the selection already wears — the bar's
    /// lit state. A caret answers for the next keystroke instead: the style
    /// it would inherit by the donor rule (§4). The highlighter lights the
    /// same way the styles do: when every touched span is marked, or when
    /// the caret's donor carries the mark.
    func styleCoverage(at selection: NSRange) -> Set<FormatMark> {
        guard let editor else { return [] }

        if selection.length == 0 {
            guard let mapped = elementRange(at: selection.location),
                  let element = editor.screenplay.elements.first(where: { $0.id == mapped.id })
            else { return [] }
            var lit: Set<FormatMark> = []
            let length = (element.text as NSString).length
            let caret = max(0, min(selection.location - mapped.range.location, length))
            let donor = caret > 0
                ? element.runs?.first(where: { $0.start <= caret - 1 && caret - 1 < $0.end })
                : element.runs?.first(where: { $0.start <= caret && caret < $0.end })
            if let donor {
                lit.formUnion(FormatMark.allCases.filter {
                    $0.styleSet.map { donor.styles.contains($0) } ?? false
                })
                if donor.highlight != nil { lit.insert(.highlight) }
            }
            return lit
        }

        var touched: [(element: ScriptElement, range: NSRange)] = []
        // `ranges` is parallel to the elements — one index serves both
        // (an id lookup per element measured 290ms per call on a
        // feature-length paste; the writer double-clicks and the app hangs).
        for (index, element) in editor.screenplay.elements.enumerated() {
            guard index < ranges.count else { break }
            let mapped = ranges[index]
            let intersection = NSIntersectionRange(selection, mapped.range)
            guard intersection.length > 0 else { continue }
            touched.append((element, NSRange(
                location: intersection.location - mapped.range.location,
                length: intersection.length
            )))
        }
        guard !touched.isEmpty else { return [] }
        var lit = Set(FormatMark.allCases.filter { mark in
            guard let style = mark.styleSet else { return false }
            return touched.allSatisfy { element, range in
                Emphasis.isCovered(
                    element.runs ?? [],
                    from: range.location, to: NSMaxRange(range), style: style
                )
            }
        })
        if touched.allSatisfy({ element, range in
            Emphasis.highlightCovered(element.runs ?? [], from: range.location, to: NSMaxRange(range))
        }) {
            lit.insert(.highlight)
        }
        return lit
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
            selection: selectionTextView.selectedRange()
        )
        registerModelUndo(inverse, actionName: actionName)
        editor.replaceAllElements(
            state.elements,
            activeID: state.activeElementID,
            offset: state.selectionOffset,
            structural: true,
            recordsUndo: false
        )
        render(state.elements) { [self] in
            restoreSelection(state.selection)
            refreshFormatBar(selection: state.selection)
        }
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
    /// The ghost's baseline in the text view's coordinates — laid against
    /// the host line's own baseline by the alignment test.
    var ghostBaseline: CGFloat? { ghost.baselineForTests }

    func updateGhost() {
        let textView = selectionTextView
        if ghost.superview !== textView { hideGhost() }
        guard let editor else {
            hideGhost()
            return
        }
        // A surface with no window is the test harness, and is allowed to
        // draw. A real window without focus is not: the ghost is for the
        // writer who is typing, not for a page sitting in the background.
        let focused = textView.window == nil
            || textView.window?.firstResponder === textView
        guard canvas.arrangement == .single || usesPageSheets,
              focused,
              !scrollView.isFindBarVisible,
              !textView.hasMarkedText(),
              let suffix = editor.currentSuggestionSuffix,
              !suffix.isEmpty,
              selectionTextView.selectedRange().length == 0,
              let mapped = elementRange(at: selectionTextView.selectedRange().location),
              selectionTextView.selectedRange().location == NSMaxRange(mapped.range),
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
            insertionLocation: selectionTextView.selectedRange().location,
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
        let selected = selectionTextView.selectedRange()
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

    /// The element menu's Act Break (RFC-ACT-BREAK §6): the break lands
    /// after the element the caret is in — never inside it, so nothing
    /// ends mid-sentence — with a canonical card and the caret in the
    /// action line that follows. The renumber runs inside the same edit,
    /// so an insert between two acts renumbers what follows as one undo
    /// step, and the tracker's refresh in `render` keeps the delete hook
    /// from mistaking this for an edit it must answer.
    private func insertActBreak() {
        guard let editor else { return }
        var elements = editor.screenplay.elements
        let card = ScreenplayEditPlanner.defaultActCard(forInsertionInto: elements)
        let actBreak = ScriptElement(type: .actbreak, text: card)
        let after = ScriptElement(type: .action, text: "")
        let index = min(
            editor.activeElementIndex.map { $0 + 1 } ?? elements.count,
            elements.count
        )
        elements.insert(contentsOf: [actBreak, after], at: index)
        for (changed, text) in ScreenplayEditPlanner.renumberedActCards(in: elements) {
            elements[changed].text = text
        }
        let location = ScreenplayEditPlanner.ranges(for: elements)[index + 1].range.location
        applyModelEdit(
            elements,
            activeID: after.id,
            offset: 0,
            selection: NSRange(location: location, length: 0),
            actionName: "Insert Act Break"
        )
    }

    /// The delete half of the renumber rule: an act break that left the
    /// document by any road — backspace, a selection delete, cut, undo —
    /// renumbers the cards that followed it. Fires only when the count the
    /// page last drew disagrees with the model's, so an ordinary keystroke
    /// costs one pass over the element types and nothing more; and applies
    /// only a non-empty delta, so an undo that restores the exact cards is
    /// not rewritten into a second undo step. The caret keeps its element
    /// and offset: renumbered cards shift text above it, so the selection
    /// is recomputed against the new ranges rather than carried across.
    private func renumberActCardsIfNeeded() {
        guard let editor else { return }
        let elements = editor.screenplay.elements
        let count = elements.count(where: { $0.type == .actbreak })
        guard count != lastActbreakCount else { return }
        lastActbreakCount = count
        let delta = ScreenplayEditPlanner.renumberedActCards(in: elements)
        guard !delta.isEmpty else { return }
        var updated = elements
        for (index, text) in delta { updated[index].text = text }
        guard let activeID = editor.activeElementID ?? updated.first?.id else { return }
        let offset = editor.selectionOffset
        let location = ScreenplayEditPlanner.ranges(for: updated)
            .first(where: { $0.id == activeID })?.range.location ?? 0
        applyModelEdit(
            updated,
            activeID: activeID,
            offset: offset,
            selection: NSRange(location: location + offset, length: 0),
            actionName: "Renumber Acts"
        )
    }

    private func applyElements(_ elements: [ScriptElement], actionName: String) {
        guard let editor,
              let activeID = editor.activeElementID ?? elements.first?.id else { return }
        applyModelEdit(
            elements,
            activeID: activeID,
            offset: editor.selectionOffset,
            selection: selectionTextView.selectedRange(),
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
        guard let editor, let mapped = elementRange(at: selectionTextView.selectedRange().location) else {
            return
        }
        editor.selectionChanged(
            elementID: mapped.id,
            offset: min(
                mapped.range.length,
                max(0, selectionTextView.selectedRange().location - mapped.range.location)
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
        var attributes = ScriptLayout.attributes(
            for: editor.activeKind, measure: measure, spacingAfter: 0
        )
        // The style under the caret travels with it by the platform's own
        // rule (§4): the character before, or — at the very start of the
        // element — the character after. Rebuilt from the base every time,
        // so leaving a bold run drops bold from the next keystroke.
        if let element = editor.screenplay.elements.first(where: { $0.id == editor.activeElementID }) {
            let length = (element.text as NSString).length
            let caret = max(0, min(editor.selectionOffset, length))
            let donor = caret > 0
                ? element.runs?.first(where: { $0.start <= caret - 1 && caret - 1 < $0.end })
                : element.runs?.first(where: { $0.start <= caret && caret < $0.end })
            if let donor {
                attributes.merge(ScriptLayout.styleAttributes(for: donor.styles)) { _, new in new }
            }
        }
        selectionTextView.typingAttributes = attributes
    }

    private func restoreSelection(_ requestedRange: NSRange) {
        let length = textStorage.length
        let location = min(max(0, requestedRange.location), length)
        let selectionLength = min(max(0, requestedRange.length), length - location)
        applyingModel = true
        textView(atCharacter: location).setSelectedRange(NSRange(location: location, length: selectionLength))
        applyingModel = false
        // The delegate is muted above, so the paint bookkeeping the writer's
        // own selection changes get must happen here by hand: a render may
        // have moved lines, and the old highlight's paint is dirtied against
        // the *new* layout — the padding in `selectionPaintRect` absorbs the
        // few points a same-length restyle can drift.
        retireSelectionPaint()
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
        let location = selectionTextView.selectedRange().location
        if usesPageSheets {
            guard let rect = characterCanvasRect(location) else { return nil }
            return rect.minY...max(rect.minY + 1, rect.maxY)
        }
        let probe = NSRange(location: location, length: 0)
        var caret = ScriptLayout.boundingRect(of: probe, in: textView)
        if caret == nil || caret?.height == 0 {
            let fallback = max(0, min(location, max(0, textStorage.length - 1)))
            caret = ScriptLayout.boundingRect(
                of: NSRange(location: fallback, length: 0), in: textView
            )
        }
        guard let rect = caret else { return nil }
        // Both ends off one rectangle in one space. A folded top over an
        // unscaled TextKit height made the band half a line too tall in
        // Two-page, and the band is what decides the caret has left the glass.
        let band = canvasRect(fromTextRect: rect)
        return band.minY...(band.minY + max(band.height, 1))
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

/// `CADisplayLink` retains its target; aimed at the surface, a running
/// drift would keep the whole editor — text storage, undo history and all
/// — alive. The relay is the weightless thing the link holds instead, and
/// it invalidates the link itself if the surface has already gone.
private final class SettleRelay: NSObject {
    private weak var surface: ScriptSurface?

    init(_ surface: ScriptSurface) { self.surface = surface }

    @objc func tick(_ link: CADisplayLink) {
        MainActor.assumeIsolated {
            guard let surface else {
                link.invalidate()
                return
            }
            surface.settleFrame()
        }
    }
}

/// The script, drawn as a column or as an open book.
///
/// TextKit still lays the type out as one stack — the same bands, the same
/// page starts — so a line that began a page in Single still begins it in
/// Two-page. Drawing and hit-testing fold that stack onto facing sheets.
private final class ArrangedTextView: NSTextView {
    var fold: SpreadFold? {
        didSet {
            if oldValue != fold { needsDisplay = true }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let fold, let layoutManager, let textContainer else {
            super.draw(dirtyRect)
            return
        }
        let origin = textContainerOrigin
        let glyphs = layoutManager.glyphRange(for: textContainer)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, glyphRange, _ in
            let vertical = NSPoint(x: origin.x + used.minX, y: origin.y + used.minY)
            let dest = fold.spreadPoint(fromVertical: vertical)
            NSGraphicsContext.saveGraphicsState()
            let xform = NSAffineTransform()
            xform.translateX(by: dest.x, yBy: dest.y)
            xform.scale(by: fold.scale)
            xform.translateX(by: -used.minX, yBy: -used.minY)
            xform.concat()
            layoutManager.drawBackground(forGlyphRange: glyphRange, at: .zero)
            layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: .zero)
            NSGraphicsContext.restoreGraphicsState()
        }
        if shouldDrawInsertionPoint, let color = insertionPointColor as NSColor? {
            let range = selectedRange()
            if range.length == 0 {
                var actual = NSRange()
                let screen = firstRect(forCharacterRange: range, actualRange: &actual)
                if let window, screen != .zero {
                    let inWindow = window.convertFromScreen(screen)
                    let inView = convert(inWindow, from: nil)
                    drawInsertionPoint(in: inView, color: color, turnedOn: true)
                }
            }
        }
    }

    override func characterIndexForInsertion(at point: NSPoint) -> Int {
        guard let fold else { return super.characterIndexForInsertion(at: point) }
        return super.characterIndexForInsertion(at: fold.verticalPoint(fromSpread: point))
    }

    override func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let rect = super.firstRect(forCharacterRange: range, actualRange: actualRange)
        guard let fold, let window, rect != .zero else { return rect }
        let inWindow = window.convertFromScreen(rect)
        let inView = convert(inWindow, from: nil)
        let mapped = fold.spreadRect(fromVertical: inView)
        let back = convert(mapped, to: nil)
        return window.convertToScreen(back)
    }

    override func setNeedsDisplay(_ invalidRect: NSRect) {
        if fold != nil {
            super.setNeedsDisplay(bounds)
        } else {
            super.setNeedsDisplay(invalidRect)
        }
    }
}
