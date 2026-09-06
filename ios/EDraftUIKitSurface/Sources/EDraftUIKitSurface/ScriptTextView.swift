import EDraftCore
import EDraftEngine
import SwiftUI
import UIKit

/// A native UITextView screenplay surface. Ordinary typing is never intercepted:
/// UIKit owns composition, autocorrection, dictation, selection, and undo. Draft
/// First steps in only for screenplay-level actions such as Return and Tab.
/// The page, on a phone or an iPad — the app's one way in.
///
/// A wrapper rather than the representable itself, and deliberately. Making
/// `ScriptTextView` public would force `UIViewRepresentable`'s requirements
/// public with it, and those drag the whole `UITextViewDelegate` and
/// `UIGestureRecognizerDelegate` conformance along — twenty-odd methods
/// published to callers who must never call them. One public view keeps the
/// package's surface to what the app actually asks for; `@testable` still
/// reaches everything inside.
#if EDITOR_PREVIEW
/// Which launch arguments put the surface into a prediction fixture.
///
/// The QA-fixture programme is the only net that has ever caught a scroll or
/// typing regression, and it asserts with `precondition()` so a violation
/// crashes the app rather than being argued about. This predicate lives beside
/// the surface because it is the surface that behaves differently under it —
/// the app keeps the fixture's *screenplay*, which is the app's business, and
/// reads the answer from here so there is one list of argument names.
public enum EditorPreviewFixture {

    private static let predictionArguments = [
        "-prediction-fixture",
        "-character-prediction-fixture",
        "-parenthetical-prediction-fixture",
        "-scroll-prediction-fixture",
        "-qa-character-uppercase",
        "-qa-quicktype-scene"
    ]

    public static var usesPrediction: Bool {
        ProcessInfo.processInfo.arguments.contains { predictionArguments.contains($0) }
    }
}
#endif

public struct ScriptSurfaceView: View {
    private let editor: EditorState

    public init(editor: EditorState) {
        self.editor = editor
    }

    public var body: some View {
        ScriptTextView(editor: editor)
    }
}

struct ScriptTextView: UIViewRepresentable {
    let editor: EditorState

    func makeCoordinator() -> Coordinator {
        Coordinator(editor: editor)
    }

    func makeUIView(context: Context) -> ScreenplayTextView {
        let textView = ScreenplayTextView(usingTextLayoutManager: false)
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.keyboardDismissMode = .interactive
        textView.textContainerInset = UIEdgeInsets(top: 24, left: 22, bottom: 40, right: 22)
        textView.textContainer.lineFragmentPadding = 0
        textView.autocorrectionType = .yes
        textView.spellCheckingType = .yes
        // Autocapitalization is the keyboard's own job, switched per element
        // kind in updateTypingTraits (which runs before the keyboard first
        // appears and on every caret or kind change): .allCharacters for
        // scene headings, characters, transitions, and shots; .sentences for
        // everything else. The keyboard therefore types a scene heading in
        // capitals directly — the document is never rewritten mid-word, so
        // QuickType suggestion generation and acceptance stay fully native.
        // The model layer still normalizes casing as a backstop for paths the
        // trait cannot reach (paste, IME confirmation, import, tests).
        textView.autocapitalizationType = .sentences
        // Scene headings are dash-delimited ("INT. LAB - DAY"); UIKit's smart
        // dashes would rewrite " - " into an en/em dash and break both the
        // Fountain round-trip and the prediction engine's dash parsing.
        textView.smartDashesType = .no
        textView.smartQuotesType = .yes
        textView.smartInsertDeleteType = .yes
        textView.inlinePredictionType = .no
        textView.writingToolsBehavior = .limited
        textView.isFindInteractionEnabled = true
        textView.adjustsFontForContentSizeCategory = true
        // UITextView owns its standard inherited-tint caret, selection handles,
        // loupe, edit menu, and insertion-point animations without an overlay.
        textView.accessibilityLabel = "Screenplay editor"
        textView.accessibilityHint = "Return advances to the next screenplay element. Space accepts an actionable suggestion."

        context.coordinator.attach(to: textView)
        context.coordinator.renderModel(selecting: nil, offset: nil)
#if EDITOR_PREVIEW
        let isPredictionFixture = EditorPreviewFixture.usesPrediction
            || CommandLine.arguments.contains("-ordinary-space-fixture")
        let shouldExerciseSpaceAcceptance = CommandLine.arguments.contains("-qa-accept-with-space")
        let shouldExercisePredictionUndo = CommandLine.arguments.contains("-qa-undo-redo-prediction")
        let shouldExerciseOrdinarySpace = CommandLine.arguments.contains("-qa-ordinary-space")
        let shouldExerciseFirstCharacterBackspace = CommandLine.arguments.contains("-qa-first-character-backspace")
        let shouldExerciseLowercaseAction = CommandLine.arguments.contains("-qa-action-lowercase")
        let shouldExerciseUppercaseCharacter = CommandLine.arguments.contains("-qa-character-uppercase")
        let shouldExerciseQuickTypeScene = CommandLine.arguments.contains("-qa-quicktype-scene")
        let shouldExerciseSharpS = CommandLine.arguments.contains("-qa-sharp-s")
        // Visual-QA fixture: scroll content under the header so its blur
        // can be verified from a screenshot, not guessed from a rest state.
        if CommandLine.arguments.contains("-qa-header-scroll") {
            Task { @MainActor in
                await Task.yield()
                textView.setContentOffset(
                    CGPoint(x: 0, y: -textView.adjustedContentInset.top + 160),
                    animated: false
                )
            }
        }
        if CommandLine.arguments.contains("-show-keyboard")
            || shouldExerciseSpaceAcceptance
            || shouldExercisePredictionUndo
            || shouldExerciseOrdinarySpace
            || shouldExerciseFirstCharacterBackspace
            || shouldExerciseLowercaseAction
            || shouldExerciseUppercaseCharacter
            || shouldExerciseQuickTypeScene
            || shouldExerciseSharpS {
            let coordinator = context.coordinator
            Task { @MainActor in
                await Task.yield()
                if isPredictionFixture {
                    textView.selectedRange = NSRange(location: textView.textStorage.length, length: 0)
                }
                editor.beginEditing()
                if isPredictionFixture {
                    textView.scrollRangeToVisible(textView.selectedRange)
                }
                if shouldExerciseSpaceAcceptance || shouldExercisePredictionUndo {
                    for _ in 0..<400 where !coordinator.isActionableGhostReady() {
                        try? await Task.sleep(for: .milliseconds(25))
                    }
                    precondition(
                        coordinator.isActionableGhostReady(),
                        "Prediction fixture did not produce an actionable inline suggestion."
                    )
                    let range = textView.selectedRange
                    let shouldInsertNormally = coordinator.textView(
                        textView,
                        shouldChangeTextIn: range,
                        replacementText: " "
                    )
                    precondition(!shouldInsertNormally, "Space did not accept the inline suggestion.")
                    precondition(
                        textView.text == "INT. " && editor.activeKind == .scene,
                        "Space acceptance did not complete and promote the scene heading."
                    )
                    if shouldExercisePredictionUndo {
                        for _ in 0..<20 where !editor.canUndo {
                            try? await Task.sleep(for: .milliseconds(10))
                        }
                        precondition(editor.canUndo, "Accepted suggestion was not undoable.")
                        editor.undo()
                        precondition(
                            textView.text == "IN" && editor.activeKind == .action,
                            "Undo did not restore the typed prefix and element type."
                        )
                        for _ in 0..<20 where !editor.canRedo {
                            try? await Task.sleep(for: .milliseconds(10))
                        }
                        precondition(editor.canRedo, "Accepted suggestion was not redoable.")
                        editor.redo()
                        precondition(
                            textView.text == "INT. " && editor.activeKind == .scene,
                            "Redo did not restore the accepted suggestion."
                        )
                    }
                } else if shouldExerciseOrdinarySpace {
                    try? await Task.sleep(for: .milliseconds(100))
                    let shouldInsertNormally = coordinator.textView(
                        textView,
                        shouldChangeTextIn: textView.selectedRange,
                        replacementText: " "
                    )
                    precondition(shouldInsertNormally, "An ordinary Space was incorrectly intercepted.")
                } else if shouldExerciseFirstCharacterBackspace {
                    coordinator.exerciseFirstCharacterBackspaceRegression()
                } else if shouldExerciseLowercaseAction {
                    coordinator.exerciseLowercaseActionRegression()
                } else if shouldExerciseUppercaseCharacter {
                    coordinator.exerciseUppercaseCharacterRegression()
                } else if shouldExerciseQuickTypeScene {
                    await coordinator.exerciseQuickTypeSceneRegression()
                } else if shouldExerciseSharpS {
                    coordinator.exerciseSharpSRegression()
                }
            }
        }
        if CommandLine.arguments.contains("-qa-scroll-stability") {
            let coordinator = context.coordinator
            Task { @MainActor in
                await coordinator.exerciseScrollStabilityRegression()
            }
        }
#endif
        return textView
    }

    func updateUIView(_ textView: ScreenplayTextView, context: Context) {
        context.coordinator.rebindIfNeeded(to: editor)
        context.coordinator.renderExternalChangeIfNeeded()
        context.coordinator.updateGhost()
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        private weak var editor: EditorState?
        private weak var textView: ScreenplayTextView?
        private var renderedRevision = -1
        private var applyingModel = false
        private var ranges: [ElementRange] = []
        private var pendingSeparatorEscape: SeparatorEscape?
        private var acceptsFocus = false
        private var pendingEdit: PendingEdit?
        private var documentWidth: CGFloat = 0
        private var traitSignature = ""
        private var pendingLayoutRefresh = false
        /// The resume point is framed exactly once: the first layout with a
        /// real width. Later layouts must never yank the writer's scroll.
        private var didFrameInitialPosition = false
        private var acceptSuggestionAvailable = false
        private let ghostOverlay = GhostTextOverlay()
        /// The mark that says where a Navigator row landed.
        private let revealHighlight = RevealHighlightView()
        private let swipeHaptic = UISelectionFeedbackGenerator()
        private lazy var acceptSuggestionAccessibilityAction = UIAccessibilityCustomAction(
            name: "Accept suggestion",
            target: self,
            selector: #selector(acceptSuggestionFromAccessibility)
        )
        private lazy var nextElementAccessibilityAction = UIAccessibilityCustomAction(
            name: "Next element",
            target: self,
            selector: #selector(cycleElementKindFromAccessibilityNext)
        )
        private lazy var previousElementAccessibilityAction = UIAccessibilityCustomAction(
            name: "Previous element",
            target: self,
            selector: #selector(cycleElementKindFromAccessibilityPrevious)
        )

        init(editor: EditorState) {
            self.editor = editor
            super.init()
        }

        func attach(to textView: ScreenplayTextView) {
            self.textView = textView
            ghostOverlay.onAccept = { [weak self] in self?.acceptPrediction() }
            textView.addSubview(ghostOverlay)
            textView.onTab = { [weak self] backwards in
                self?.editor?.cycleActiveKind(backwards: backwards)
            }
            // ⌘1–9 set the element outright, through the same conversion
            // channel as the pill's menu — casing memory, bracket handling,
            // and undo grouping all come along for free.
            textView.onSelectElementKind = { [weak self] kind in
                self?.changeKind(to: kind)
            }
            textView.onAcceptPrediction = { [weak self] in
                self?.acceptPrediction()
            }
            textView.onLayout = { [weak self] width, traits in
                self?.layoutChanged(width: width, traits: traits)
            }

            // One list, wired in one place. `rebindIfNeeded` re-runs exactly
            // this set after an external document change, and a second copy
            // here could only drift out of step with it.
            if let editor { wireEditorCallbacks(for: editor) }

            installSwipeGestures(on: textView)
            updateAccessibilityActions()
        }

        /// Touch counterpart to the hardware Tab key — one fluid gesture where
        /// a phone has no Tab. Swipe right cycles to the next element, swipe
        /// left to the previous; both feed the exact same `cycleActiveKind`
        /// channel as Tab / ⇧Tab, so the mode order and its context rules are
        /// never duplicated. Gated to the text area while editing, so reading
        /// scrolls and screen-edge system gestures stay untouched.
        private func installSwipeGestures(on textView: ScreenplayTextView) {
            for direction: UISwipeGestureRecognizer.Direction in [.left, .right] {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swipeCycledElementKind(_:)))
                swipe.direction = direction
                swipe.delegate = self
                textView.addGestureRecognizer(swipe)
            }
            swipeHaptic.prepare()
        }

        @objc private func swipeCycledElementKind(_ recognizer: UISwipeGestureRecognizer) {
            editor?.cycleActiveKind(backwards: recognizer.direction == .left)
            swipeHaptic.selectionChanged()
        }

        /// A swipe counts only while editing, and only when it begins inside
        /// the text container — never in the margins where iOS owns the
        /// screen-edge gestures. Recognizers that are not ours pass through.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer is UISwipeGestureRecognizer else { return true }
            guard let textView, textView.isFirstResponder else { return false }
            let inset = textView.textContainerInset
            let textArea = textView.bounds.inset(by: UIEdgeInsets(
                top: 0, left: inset.left, bottom: 0, right: inset.right
            ))
            return textArea.contains(gestureRecognizer.location(in: textView))
        }

        /// EditorView swaps in a fresh EditorState after a genuinely external
        /// document change. The coordinator outlives that swap, so it must
        /// rebind: point at the new state, rewire its callbacks, and force a
        /// full re-render. Without this the surface stays bound to a
        /// deallocated state — the editor goes permanently dead.
        func rebindIfNeeded(to editor: EditorState) {
            guard self.editor !== editor else { return }
            self.editor = editor
            renderedRevision = -1
            wireEditorCallbacks(for: editor)
        }

        private func wireEditorCallbacks(for editor: EditorState) {
            editor.onAcceptPrediction = { [weak self] in self?.acceptPrediction() }
            editor.onPredictionChange = { [weak self] in self?.updateGhost() }
            editor.onChangeElementKind = { [weak self] kind in self?.changeKind(to: kind) }
            editor.onInsertElements = { [weak self] pages in self?.insertElements(pages) }
            editor.onApplyElements = { [weak self] elements, name in
                self?.applyElements(elements, actionName: name)
            }
            editor.onJumpToElement = { [weak self] id in self?.reveal(id) }
            editor.onNativeUndo = { [weak self] in self?.performNativeUndo() ?? false }
            editor.onNativeRedo = { [weak self] in self?.performNativeRedo() ?? false }
            editor.onClearNativeUndo = { [weak self] in self?.clearNativeUndoHistory() }
            editor.onSetEditing = { [weak self] editing in
                guard let textView = self?.textView else { return }
                // Focus is asked for here and nowhere else; `acceptsFocus`
                // is what makes a touch on the page unable to ask for it.
                if editing {
                    self?.acceptsFocus = true
                    // Where the caret belongs, decided before focus arrives.
                    // The surface carries no selection while reading, so
                    // taking focus first draws a caret at the top of the
                    // script and moves it a beat later — the jump a writer
                    // sees on pressing the pencil.
                    self?.placeCaretForEditing()
                    // A new document asks for the caret as it appears, which
                    // can be before the surface has joined a window — and a
                    // view with no window cannot take focus. Asking again on
                    // the next turn costs nothing and covers that ordering.
                    if !textView.becomeFirstResponder() {
                        DispatchQueue.main.async { [weak textView] in
                            textView?.becomeFirstResponder()
                        }
                    }
                } else {
                    textView.resignFirstResponder()
                    self?.acceptsFocus = false
                }
            }
        }

        func renderExternalChangeIfNeeded() {
            guard textView?.markedTextRange == nil,
                  let editor,
                  editor.revision != renderedRevision else { return }
            renderModel(selecting: editor.activeElementID, offset: editor.selectionOffset)
        }

        func renderModel(selecting elementID: UUID?, offset requestedOffset: Int?) {
            guard let editor, let textView else { return }
            let selectedID = elementID ?? editor.activeElementID
            let selectedOffset = requestedOffset ?? editor.selectionOffset
            let rendered = makeAttributedString(
                elements: editor.screenplay.elements,
                width: contentWidth(for: textView),
                traitCollection: textView.traitCollection
            )

            // Replacing the whole storage makes UITextView re-finalize its
            // text container size, and that pass can re-pin the scroll
            // offset to the top — the jump writers saw when typing at the
            // end of a long document. The invariant is that the PAGE stays
            // put; the caret itself moves legitimately on Return/Backspace,
            // so the guard only corrects a large upward jump (the reset's
            // signature) and never touches small or downward adjustments —
            // those are UIKit's own caret reveal and must keep working.
            let preservedOffset = textView.contentOffset
            // Where the caret sits on screen now, so the page can be put back
            // around it: a line inserted above it moves every line below down,
            // and the writer's eye should not have to follow.
            let caretBefore = caretScreenY(in: textView)

            applyingModel = true
            textView.textStorage.setAttributedString(rendered.string)
            ranges = rendered.ranges
            // Finalize the whole layout now: while layout stays unrealized,
            // UITextView re-sizes its container one beat after any
            // programmatic scroll and re-pins the offset to the top.
            // Measured at ~2.4 ms for a 32-scene script — cheap insurance,
            // and it makes every scroll deterministic.
            textView.layoutManager.ensureLayout(
                forGlyphRange: NSRange(location: 0, length: textView.textStorage.length)
            )
            if let selectedID, let mapped = ranges.first(where: { $0.id == selectedID }) {
                let offset = min(max(0, selectedOffset), mapped.range.length)
                textView.selectedRange = NSRange(location: mapped.range.location + offset, length: 0)
            }
            applyingModel = false
            restoreViewport(around: caretBefore, otherwise: preservedOffset, in: textView)
            renderedRevision = editor.revision
            updateTypingTraits()
            updateGhost()
        }

        /// The caret's vertical position on screen. caretRect reports in the
        /// view's own coordinate system (which for a scroll view is content
        /// coordinates), so a direct conversion is correct — no manual
        /// offset math.
        private func caretScreenY(in textView: UITextView) -> CGFloat? {
            guard let position = textView.selectedTextRange?.end, let window = textView.window else {
                return nil
            }
            // Same rule as `scrollableRange`: a caret rectangle is a result of
            // laying out, so ask for the layout before reading one.
            textView.layoutIfNeeded()
            let caret = textView.caretRect(for: position)
            guard !caret.isNull, !caret.isInfinite else { return nil }
            return textView.convert(caret, to: window).midY
        }

        /// The caret's screen position only when it is genuinely inside the
        /// visible window — between the top bar and the bottom edge of the
        /// view. The window's top is bounds.origin (the visible area's own
        /// origin), not CGPoint.zero — for a scroll view the zero point is
        /// the content origin, which is scrolled away.
        private func caretScreenYIfVisible(in textView: UITextView) -> CGFloat? {
            guard let y = caretScreenY(in: textView), let window = textView.window else { return nil }
            let viewTopOnScreen = textView.convert(textView.bounds.origin, to: window).y
            let top = viewTopOnScreen + textView.adjustedContentInset.top
            let bottom = viewTopOnScreen + textView.bounds.height - 8
            return (y > top && y < bottom) ? y : nil
        }

        /// Settles the page after a re-render, twice: now, and again once the
        /// text container has settled a beat later and may have moved it.
        private func restoreViewport(
            around caretBefore: CGFloat?, otherwise preserved: CGPoint, in textView: ScreenplayTextView
        ) {
            settleViewport(around: caretBefore, otherwise: preserved, in: textView)
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                self.settleViewport(around: caretBefore, otherwise: preserved, in: textView)
            }
        }

        /// Two rules, in order.
        ///
        /// The insertion point holds its place on the screen: rebuilding the
        /// text moves lines about, and the line being written should not
        /// wander because of it. This is about the text moving under the
        /// selection rather than about who owns the keyboard, so it applies
        /// whether or not the surface is focused — with no selection to
        /// follow at all, the page simply stays where it was.
        ///
        /// Then, whichever applied, the caret must still be visible. Holding
        /// it in place is right until the place itself is hidden — under the
        /// keyboard as it rises, or above the bar — and then the smallest
        /// correction that shows it wins. Doing only the first is how typing
        /// disappeared under the keyboard; doing only the second is how the
        /// page lurched on every keystroke.
        private func settleViewport(
            around caretBefore: CGFloat?, otherwise preserved: CGPoint, in textView: ScreenplayTextView
        ) {
            let range = scrollableRange(in: textView)
            let y = PageScroll.settled(
                caretWas: caretBefore,
                caretIs: caretScreenY(in: textView),
                preserved: preserved.y,
                offset: textView.contentOffset.y,
                in: range
            )
            if abs(textView.contentOffset.y - y) > 0.5 {
                textView.setContentOffset(CGPoint(x: preserved.x, y: y), animated: false)
            }
            revealCaretIfHidden(in: textView)
        }

        /// Restores the offset only when the viewport jumped significantly
        /// UPWARD — the re-pin reset's signature. Everything else (Return's
        /// one-line caret move, UIKit's reveal scroll) is left alone.
        /// The offsets this page may rest at: the top is minus the bar's
        /// clearance, not zero, because the content begins below the bar.
        /// The offsets the page may rest at, measured against a layout that is
        /// current.
        ///
        /// `contentSize` is a *result* of laying out, not a property of the
        /// text: replacing the storage invalidates it, and UIKit does not
        /// recompute it until its next layout pass. Measure in between and the
        /// page appears to be a single screen tall — so the arithmetic decides
        /// there is nowhere to scroll and quietly does nothing.
        ///
        /// That is exactly how a Navigator row came to work on the second tap
        /// and not the first: the tap arrived in the same turn as a render, the
        /// reveal measured a page that did not exist yet, and by the second tap
        /// the layout had caught up. Asking for the layout first costs nothing
        /// when it is already current, and is the difference between a row that
        /// works and a row that works sometimes.
        private func scrollableRange(in textView: UITextView) -> ClosedRange<CGFloat> {
            textView.layoutIfNeeded()
            return PageScroll.range(
                contentHeight: textView.contentSize.height,
                viewportHeight: textView.bounds.height,
                topInset: textView.adjustedContentInset.top,
                bottomInset: textView.adjustedContentInset.bottom
            )
        }

        /// Brings the caret back inside the readable band, moving the page as
        /// little as possible.
        ///
        /// The page holding still across a render is right until it hides what
        /// is being typed — a line pushed under the keyboard, or above the bar
        /// — and then the smallest correction that shows it again is the one
        /// the writer expects. Scrolling it to the top instead would be a jump
        /// of its own.
        private func revealCaretIfHidden(in textView: UITextView) {
            guard textView.isFirstResponder,
                  let position = textView.selectedTextRange?.end else { return }
            let caret = textView.caretRect(for: position)
            guard !caret.isNull, !caret.isInfinite else { return }

            let visibleTop = textView.contentOffset.y + textView.adjustedContentInset.top
            let visibleBottom = textView.contentOffset.y + textView.bounds.height
                - textView.adjustedContentInset.bottom
            guard visibleBottom > visibleTop,
                  let y = PageScroll.correction(
                      revealing: caret.minY...max(caret.minY, caret.maxY),
                      within: visibleTop...visibleBottom,
                      margin: 8,
                      from: textView.contentOffset.y,
                      in: scrollableRange(in: textView)
                  )
            else { return }
            textView.setContentOffset(
                CGPoint(x: textView.contentOffset.x, y: y), animated: false
            )
        }

        /// Puts the caret where the model says the writer is, before the
        /// surface takes focus.
        ///
        /// Reading leaves no selection behind — there is no caret to leave —
        /// so a surface that takes focus first shows one at offset zero and
        /// then corrects itself once the model is consulted. Deciding first
        /// means the caret only ever appears where it belongs.
        private func placeCaretForEditing() {
            guard let textView, let editor,
                  let id = editor.activeElementID,
                  let mapped = ranges.first(where: { $0.id == id }) else { return }
            let offset = min(max(0, editor.selectionOffset), mapped.range.length)
            textView.selectedRange = NSRange(
                location: mapped.range.location + offset, length: 0
            )
        }

        /// Whether a touch on the page may begin an edit. Reading mode says
        /// no, so the stray touches a reader makes — scrolling, lifting a
        /// line out — cannot start one; the pencil says yes by asking for
        /// editing outright.
        ///
        /// Refusing focus rather than clearing `isEditable`: taking
        /// editability away and giving it back re-lays the text container,
        /// and the page arrives under the writer's eyes shifted by about
        /// three lines. The QA scroll fixture catches it exactly there.
        func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
            acceptsFocus
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            editor?.reportEditing(true)
            updateSelection(from: textView)
            reportNativeUndoAvailability()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            editor?.reportEditing(false)
            hideGhost()
            editor?.flushPendingWork()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !applyingModel else { return }
            updateSelection(from: textView)
            updateTypingTraits()
            updateGhost()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !applyingModel, let editor else { return }
            guard textView.markedTextRange == nil else {
                hideGhost()
                return
            }

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
                updateTypingTraits()
                updateGhost()
                reportNativeUndoAvailability()
                applyDeferredLayoutIfNeeded()
            } else {
                renderModel(selecting: editor.activeElementID, offset: editor.selectionOffset)
            }
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard let editor else { return true }

            // The separator's escape hatch lives for exactly one keystroke:
            // the delete that immediately follows it. Consuming it here means
            // every other path clears it simply by not being that delete.
            let separatorEscape = pendingSeparatorEscape
            pendingSeparatorEscape = nil

            if textView.markedTextRange != nil {
                pendingEdit = nil
                hideGhost()
                return true
            }

            if text == "\t" {
                editor.cycleActiveKind(backwards: false)
                return false
            }

            let mapped = elementRange(at: range.location)
            let index = mapped.flatMap { mapped in
                editor.screenplay.elements.firstIndex(where: { $0.id == mapped.id })
            }

            if let mapped, let index, shouldAcceptPredictionWithSpace(
                editor: editor,
                textView: textView,
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
                if text.isEmpty, range.length == 1, let separatorEscape,
                   collapseSceneSeparator(
                    replacing: range, in: mapped, at: index, escape: separatorEscape
                   ) {
                    return false
                }
            }

            let source = textView.text as NSString
            if ScreenplayEditPlanner.touchesParagraphBoundary(
                in: source,
                range: range,
                replacement: text
            ) {
                let deleted = range.location >= 0 && NSMaxRange(range) <= source.length
                    ? source.substring(with: range)
                    : ""
                let isBoundaryDeletion = text.isEmpty
                    && deleted == "\n"
                    && textView.selectedRange.length == 0
                    && (textView.selectedRange.location == range.location
                        || textView.selectedRange.location == NSMaxRange(range))

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
                    intent = textView.selectedRange.location == NSMaxRange(range)
                        ? .backspaceAtElementStart
                        : .boundaryDeletion
                } else if text == "\n" {
                    intent = .returnKey
                } else if text.contains("\n") || text.contains("\r") {
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

            // Ordinary letters—including the first character in a paragraph—
            // remain UIKit edits. Casing of uppercase kinds is produced by the
            // keyboard itself (see updateTypingTraits): the document is never
            // mutated behind UIKit's back mid-word, which is what broke
            // QuickType suggestion generation and acceptance in scene headings.
            // A boundary is recognized only by the actual newline character
            // handled above.
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

        func updateGhost() {
            guard let editor,
                  let textView,
                  textView.isFirstResponder,
                  textView.markedTextRange == nil,
                  let suffix = editor.currentSuggestionSuffix,
                  !suffix.isEmpty,
                  textView.selectedRange.length == 0,
                  let mapped = elementRange(at: textView.selectedRange.location),
                  textView.selectedRange.location == NSMaxRange(mapped.range),
                  editor.activeKind != .transition,
                  editor.activeKind != .centered else {
                hideGhost()
                return
            }

            var suggestionAttributes = textView.typingAttributes
            suggestionAttributes[.foregroundColor] = editor.currentPrediction?.hint == true
                ? UIColor.tertiaryLabel
                : UIColor.secondaryLabel

            let isPresented = ghostOverlay.present(
                in: textView,
                base: textView.attributedText,
                suffix: suffix,
                insertionLocation: textView.selectedRange.location,
                paragraphRange: mapped.range,
                attributes: suggestionAttributes,
                revision: editor.revision
            )
            let isActionable = editor.currentPrediction?.hint != true
            ghostOverlay.isUserInteractionEnabled = isActionable
            setAcceptSuggestionAccessibilityAvailable(isPresented && isActionable)
            if isPresented {
                textView.bringSubviewToFront(ghostOverlay)
            }
        }

        private func hideGhost() {
            ghostOverlay.hide()
            setAcceptSuggestionAccessibilityAvailable(false)
        }

        private func setAcceptSuggestionAccessibilityAvailable(_ available: Bool) {
            acceptSuggestionAvailable = available
            updateAccessibilityActions()
        }

        /// VoiceOver gets the same structural controls as touch and hardware:
        /// element cycling is always present; accepting a suggestion only
        /// while a ghost is on screen.
        private func updateAccessibilityActions() {
            guard let textView else { return }
            var actions = [nextElementAccessibilityAction, previousElementAccessibilityAction]
            if acceptSuggestionAvailable {
                actions.append(acceptSuggestionAccessibilityAction)
            }
            textView.accessibilityCustomActions = actions
        }

        @objc private func cycleElementKindFromAccessibilityNext() -> Bool {
            editor?.cycleActiveKind(backwards: false)
            return true
        }

        @objc private func cycleElementKindFromAccessibilityPrevious() -> Bool {
            editor?.cycleActiveKind(backwards: true)
            return true
        }

        @objc private func acceptSuggestionFromAccessibility() -> Bool {
            guard !ghostOverlay.isHidden else { return false }
            acceptPrediction()
            return true
        }

#if EDITOR_PREVIEW
        func isActionableGhostReady() -> Bool {
            guard let editor,
                  editor.currentPrediction?.hint != true,
                  let suffix = editor.currentSuggestionSuffix,
                  !suffix.isEmpty else { return false }
            return ghostOverlay.isPresenting(
                suffix: suffix,
                insertionLocation: textView?.selectedRange.location ?? NSNotFound,
                revision: editor.revision
            )
        }

        /// Typing into an Action element must never capitalize the writer's
        /// text. Regression cover for all-caps-everywhere reports.
        func exerciseLowercaseActionRegression() {
            guard let editor,
                  let textView,
                  let actionElement = editor.screenplay.elements.last,
                  actionElement.type == .action,
                  let mapped = ranges.first(where: { $0.id == actionElement.id }) else {
                preconditionFailure("Lowercase fixture expected a trailing Action element.")
            }

            textView.selectedRange = NSRange(location: NSMaxRange(mapped.range), length: 0)
            textView.insertText(" The basement stays quiet.")

            precondition(
                textView.text.contains("The basement stays quiet."),
                "Typing in an Action element was uppercased."
            )
            precondition(
                editor.screenplay.elements.last?.text.hasSuffix("The basement stays quiet.") == true,
                "The model did not mirror the typed Action text."
            )
        }

        /// Regression cover for the long-document scroll jump — the real
        /// user sequence: caret at the end of a 32-scene document, keyboard
        /// up, scroll to the caret, type one character. Typing there routes
        /// through the full planner + renderModel path (a new paragraph is
        /// structural), and the viewport must stay where the caret is.
        /// Asserted on the caret's on-screen drift, not raw offsets.
        func exerciseScrollStabilityRegression() async {
            guard let textView else { return }
            // Launch runs its own layout passes (initial render, resume
            // scroll); wait until the content size is stable first.
            var settledHeight: CGFloat = 0
            for _ in 0..<100 {
                let height = textView.contentSize.height
                if height > 2000, abs(height - settledHeight) < 0.5 { break }
                settledHeight = height
                try? await Task.sleep(for: .milliseconds(20))
            }
            // No keyboard in this harness: keyboard avoidance animates on
            // its own schedule and would pollute the measurement. insertText
            // exercises the identical delegate path without it.
            let length = textView.textStorage.length
            textView.selectedRange = NSRange(location: length, length: 0)
            // A zero-length range does not scroll UITextView; scroll to the
            // last real character instead — what a tap near the end does.
            textView.scrollRangeToVisible(NSRange(location: max(0, length - 1), length: 1))
            try? await Task.sleep(for: .milliseconds(300))
            let beforeY = caretScreenYIfVisible(in: textView)
            precondition(beforeY != nil, "The caret never came on screen before typing.")

            textView.insertText("K")
            try? await Task.sleep(for: .milliseconds(300))
            let afterY = caretScreenY(in: textView)
            precondition(afterY != nil, "No measurable caret after typing.")
            let drift = abs(afterY! - beforeY!)
            precondition(
                drift < 30,
                "Typing moved the caret on screen by \(drift) pt (offsetY=\(textView.contentOffset.y))."
            )

            // Return creates a new paragraph: the caret legitimately moves
            // down one line, and UIKit's reveal may nudge the viewport —
            // the budget is one line plus that adjustment. The bug being
            // guarded against moved the caret by thousands of points.
            let preReturnY = afterY!
            textView.insertText("\n")
            try? await Task.sleep(for: .milliseconds(300))
            let postReturnY = caretScreenY(in: textView)
            precondition(postReturnY != nil, "No measurable caret after Return.")
            let returnDrift = abs(postReturnY! - preReturnY)
            precondition(
                returnDrift < 80,
                "Return moved the caret on screen by \(returnDrift) pt (offsetY=\(textView.contentOffset.y))."
            )
            precondition(
                caretScreenYIfVisible(in: textView) != nil,
                "The caret is off screen after Return (offsetY=\(textView.contentOffset.y))."
            )

            // Backspace merges it back: one line up, page steady.
            textView.deleteBackward()
            try? await Task.sleep(for: .milliseconds(300))
            let postDeleteY = caretScreenY(in: textView)
            precondition(postDeleteY != nil, "No measurable caret after Backspace.")
            let deleteDrift = abs(postDeleteY! - postReturnY!)
            precondition(
                deleteDrift < 80,
                "Backspace moved the caret on screen by \(deleteDrift) pt (offsetY=\(textView.contentOffset.y))."
            )
            precondition(
                caretScreenYIfVisible(in: textView) != nil,
                "The caret is off screen after Backspace (offsetY=\(textView.contentOffset.y))."
            )
        }

        /// Lowercase characters typed into a Character element must become
        /// uppercase — on device through the keyboard's all-characters mode,
        /// and for programmatic input through the model's backstop. Regression
        /// cover for the stuck all-characters keyboard: the trait must follow
        /// the caret, and Action elements must never be capitalized by it.
        func exerciseUppercaseCharacterRegression() {
            guard let editor,
                  let textView,
                  let characterElement = editor.screenplay.elements.last,
                  characterElement.type == .character,
                  characterElement.text == "EL",
                  let mapped = ranges.first(where: { $0.id == characterElement.id }) else {
                preconditionFailure("Uppercase fixture expected a trailing Character element containing EL.")
            }

            precondition(
                textView.autocapitalizationType == .allCharacters,
                "The keyboard trait must follow the caret into a Character element."
            )

            textView.selectedRange = NSRange(location: NSMaxRange(mapped.range), length: 0)
            textView.insertText("na")

            precondition(
                textView.text.contains("ELNA"),
                "Typing into a Character element was not uppercased by the model."
            )
            precondition(
                editor.screenplay.elements.last?.text == "ELNA",
                "The model did not store the uppercased Character text."
            )
        }

        /// A cue shouts, and ß shouts as SS — one UTF-16 unit becoming two.
        ///
        /// Both the model and this surface used to decline that, so the letter
        /// stayed lowercase in a line that shouts; and once the Mac began
        /// capitalising at the input boundary, the same keystroke produced SS
        /// at a desk and ß on a phone. The rule is the model's now, and what
        /// this surface owes it is a redraw when the answer is not the length
        /// that was typed. The page and the file agreeing is the assertion
        /// that matters — the rest is arithmetic.
        func exerciseSharpSRegression() {
            guard let editor,
                  let textView,
                  let cue = editor.screenplay.elements.last,
                  cue.type == .character,
                  cue.text.isEmpty,
                  let mapped = ranges.first(where: { $0.id == cue.id }) else {
                preconditionFailure("Sharp-S fixture expected a trailing empty Character element.")
            }

            textView.selectedRange = NSRange(location: NSMaxRange(mapped.range), length: 0)
            textView.insertText("ß")

            precondition(
                editor.screenplay.elements.last?.text == "SS",
                "A cue did not shout ß as SS; the model declined an expanding case mapping."
            )
            precondition(
                textView.text.hasSuffix("SS"),
                "The model shouted SS but the page still shows what was typed."
            )
            precondition(
                textView.selectedRange.location == textView.textStorage.length,
                "The caret did not follow the expansion; it should sit after SS, not inside it."
            )
        }

        /// Inside a scene heading the keyboard itself must be in all-
        /// characters mode, a QuickType-style word replacement ("BEDR" →
        /// "bedroom") must land as "BEDROOM" atomically, and its trailing
        /// space must land natively. Regression cover for two keyboard-context
        /// failures: accepted suggestions dropping (storage was rewritten
        /// behind UIKit's back mid-word) and suggestion generation freezing
        /// (a re-entrant input operation from inside the delegate callback).
        /// Steps yield between edits so each lands in its own UndoManager
        /// event group, mirroring real typing.
        func exerciseQuickTypeSceneRegression() async {
            guard let editor,
                  let textView,
                  let scene = editor.screenplay.elements.first,
                  scene.type == .scene,
                  scene.text == "INT. BED",
                  let mapped = ranges.first(where: { $0.id == scene.id }) else {
                preconditionFailure("QuickType fixture expected a Scene element containing INT. BED.")
            }

            let flattened = { ScreenplayEditPlanner.flattenedText(editor.screenplay.elements) }
            precondition(flattened() == textView.text, "Fixture did not start mirrored.")

            // 1) With the caret inside a Scene element the keyboard trait is
            //    all-characters, so a real keyboard types capitals directly.
            //    Programmatic insertion bypasses the trait, which exercises
            //    the model's uppercase backstop instead.
            let end = NSMaxRange(mapped.range)
            textView.selectedRange = NSRange(location: end, length: 0)
            precondition(
                textView.autocapitalizationType == .allCharacters,
                "Scene headings must put the keyboard in all-characters mode."
            )
            textView.insertText("r")
            precondition(
                editor.screenplay.elements.first?.text == "INT. BEDR",
                "A typed letter did not land uppercased in the model."
            )
            precondition(flattened() == textView.text, "Model and surface diverged after typing.")
            precondition(
                textView.selectedRange.location == end + 1,
                "The caret did not advance past the typed letter."
            )
            try? await Task.sleep(for: .milliseconds(50))

            // 2) QuickType acceptance replaces the current word with the
            //    suggestion through the same input entry point UIKit uses.
            guard let remapped = ranges.first(where: { $0.id == scene.id }) else {
                preconditionFailure("The Scene element lost its range mapping after typing.")
            }
            let wordStart = NSMaxRange(remapped.range) - 4
            guard let wordBegin = textView.position(from: textView.beginningOfDocument, offset: wordStart),
                  let wordEnd = textView.position(from: wordBegin, offset: 4),
                  let wordRange = textView.textRange(from: wordBegin, to: wordEnd) else {
                preconditionFailure("Could not form the QuickType replacement range.")
            }
            textView.replace(wordRange, withText: "bedroom")
            precondition(
                editor.screenplay.elements.first?.text == "INT. BEDROOM",
                "The QuickType suggestion did not land uppercased in the model."
            )
            precondition(
                flattened() == textView.text,
                "Model and surface diverged after QuickType acceptance."
            )
            try? await Task.sleep(for: .milliseconds(50))

            // 3) The trailing space QuickType appends must land natively.
            precondition(
                !isActionableGhostReady(),
                "The QuickType fixture unexpectedly shows an inline suggestion."
            )
            textView.insertText(" ")
            precondition(
                editor.screenplay.elements.first?.text == "INT. BEDROOM ",
                "The trailing space after the suggestion did not land."
            )
            precondition(flattened() == textView.text, "Model and surface diverged after the space.")
            try? await Task.sleep(for: .milliseconds(50))

            // 4) Undo and redo must keep the model and the surface consistent
            //    and return to the exact final text, no matter how UIKit
            //    grouped the edits on its native timeline.
            guard let undoManager = textView.undoManager else {
                preconditionFailure("The text view has no undo manager.")
            }
            precondition(undoManager.canUndo, "Scene-heading edits were not undoable.")
            while undoManager.canUndo {
                undoManager.undo()
                precondition(
                    flattened() == textView.text,
                    "Model and surface diverged during undo: \(textView.text)"
                )
            }
            while undoManager.canRedo { undoManager.redo() }
            precondition(
                textView.text == "INT. BEDROOM " && flattened() == textView.text,
                "Redo did not restore the final text: \(textView.text)"
            )
            print("QA-QUICKTYPE ok: \(textView.text)")
        }

        func exerciseFirstCharacterBackspaceRegression() {
            guard let editor,
                  let textView,
                  let index = editor.screenplay.elements.firstIndex(where: {
                    $0.type == .character && $0.text == "ELENA"
                  }),
                  let mapped = ranges.first(where: {
                    $0.id == editor.screenplay.elements[index].id
                  }) else {
                preconditionFailure("Backspace fixture did not contain ELENA as a Character element.")
            }

            let before = editor.screenplay.elements
            let deletion = NSRange(location: mapped.range.location, length: 1)
            textView.selectedRange = NSRange(location: NSMaxRange(deletion), length: 0)
            textView.deleteBackward()

            let after = editor.screenplay.elements
            precondition(after.count == before.count, "Deleting E changed the screenplay structure.")
            precondition(after[index].id == before[index].id, "Deleting E replaced the Character identity.")
            precondition(after[index].type == .character, "Deleting E changed the Character element type.")
            precondition(after[index].text == "LENA", "Deleting E did not leave LENA.")
            if index + 1 < before.count {
                precondition(after[index + 1] == before[index + 1], "Deleting E changed the following element.")
            }
            precondition(textView.selectedRange == NSRange(location: deletion.location, length: 0))

            guard let undoManager = textView.undoManager, undoManager.canUndo else {
                preconditionFailure("The native Backspace edit was not undoable.")
            }
            undoManager.undo()
            precondition(editor.screenplay.elements == before, "Undo did not restore the exact screenplay model.")
            precondition(undoManager.canRedo, "The native Backspace edit was not redoable.")
            undoManager.redo()
            precondition(editor.screenplay.elements == after, "Redo did not restore the exact deletion.")
        }
#endif

        private func shouldAcceptPredictionWithSpace(
            editor: EditorState,
            textView: UITextView,
            mapped: ElementRange,
            elementIndex: Int,
            range: NSRange,
            replacement: String
        ) -> Bool {
            guard replacement == " ",
                  range.length == 0,
                  textView.selectedRange.length == 0,
                  range.location == textView.selectedRange.location,
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
                  ghostOverlay.isPresenting(
                    suffix: suffix,
                    insertionLocation: range.location,
                    revision: editor.revision
                  ) else { return false }
            return true
        }

        private func synchronizeModelFromNativeText() {
            guard let editor, let textView else { return }
            let previousText = ScreenplayEditPlanner.flattenedText(editor.screenplay.elements)
            guard let difference = ScreenplayEditPlanner.replacementBetween(
                previousText,
                textView.text
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

            // UIKit owns the transaction (IME, Writing Tools, or native undo),
            // while the planner mirrors its final range without re-registering
            // a second undo action or reassigning later elements by line number.
            let nativeSelection = textView.selectedRange
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
            renderModel(selecting: plan.activeElementID, offset: plan.activeOffset)
            restoreSelection(nativeSelection)
        }

        private func applyIncrementalEdit(_ edit: PendingEdit) -> Bool {
            guard let editor,
                  let textView,
                  let rangeIndex = ranges.firstIndex(where: { $0.id == edit.elementID }) else {
                return false
            }

            let delta = edit.insertedLength - edit.replacedRange.length
            let newLength = ranges[rangeIndex].range.length + delta
            guard newLength >= 0 else { return false }

            ranges[rangeIndex].range.length = newLength
            if delta != 0, rangeIndex + 1 < ranges.count {
                for index in (rangeIndex + 1)..<ranges.count {
                    ranges[index].range.location += delta
                }
            }

            let updatedRange = ranges[rangeIndex].range
            guard NSMaxRange(updatedRange) <= textView.textStorage.length,
                  let elementIndex = editor.screenplay.elements.firstIndex(where: {
                      $0.id == edit.elementID
                  })
            else { return false }

            let kind = editor.screenplay.elements[elementIndex].type
            var text = textView.textStorage.attributedSubstring(from: updatedRange).string

            if kind.uppercasesInput {
                let uppercased = text.uppercased()
                // Caps that keep their length are repaired in place, which
                // leaves UIKit's native undo range intact. This is the
                // ordinary road, and usually it does nothing at all: the
                // keyboard is asked for .allCharacters, so the letters arrive
                // shouting already. It earns its keep on the roads the
                // keyboard does not pave — a hardware keyboard, a paste.
                if uppercased != text,
                   (uppercased as NSString).length == (text as NSString).length {
                    applyingModel = true
                    textView.textStorage.replaceCharacters(in: updatedRange, with: uppercased)
                    applyingModel = false
                    text = uppercased
                }
            }

            // Where the caret lands is decided by the same rule as the text.
            // A case mapping that grows — ß to SS — carries the caret with it,
            // so the offset is measured on the shouted prefix rather than the
            // typed one. For kinds that do not shout, and for every mapping
            // that keeps its length, this is exactly the offset typed.
            let typed = text as NSString
            let offset = max(
                0,
                min(updatedRange.length, textView.selectedRange.location - updatedRange.location)
            )
            let prefix = typed.substring(to: min(offset, typed.length))
            let caret = (EditorState.normalizedText(prefix, for: kind) as NSString).length

            editor.applyLiveText(id: edit.elementID, text: text, selectionOffset: caret)

            // The core has the last word on what an element says, and its
            // answer can be a different length than what is on the page. No
            // in-place repair can express that without its range arithmetic
            // coming apart, so the page is redrawn from the model — the
            // authority this whole surface is built to defer to.
            if editor.screenplay.elements[elementIndex].text != text {
                renderModel(selecting: edit.elementID, offset: caret)
            }
            return true
        }

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
        /// its ordinary meaning.
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
            if replacement.contains("\n") || replacement.contains("\r") { return "Paste" }
            return "Edit"
        }

        // MARK: - Scene heading separator

        /// A separator the dash key has just written, and where it left the
        /// caret. One delete against it collapses it back to a tight hyphen;
        /// any other keystroke lets it stand. See `SceneHeadingSeparator`.
        private struct SeparatorEscape {
            let elementID: UUID
            let caret: Int
        }

        /// Writes the separator a scene heading needs, in place of the dash
        /// that was typed. Answers whether it took the keystroke.
        private func writeSceneSeparator(
            replacing range: NSRange, in mapped: ElementRange, at index: Int
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

        /// Takes the separator back, for the heading that meant a hyphen —
        /// DRIVE-IN. Answers whether it took the keystroke.
        private func collapseSceneSeparator(
            replacing range: NSRange, in mapped: ElementRange, at index: Int, escape: SeparatorEscape
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
            in mapped: ElementRange,
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

        /// A document range in the coordinates of the element that holds it,
        /// or nil when it reaches outside that element.
        private func elementRelative(_ range: NSRange, in mapped: ElementRange) -> NSRange? {
            let start = range.location - mapped.range.location
            guard start >= 0, start + range.length <= mapped.range.length else { return nil }
            return NSRange(location: start, length: range.length)
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
            var completed = elements[index].type.uppercasesInput ? suggestion.uppercased() : suggestion
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                selection: textView?.selectedRange ?? NSRange(location: 0, length: 0)
            )
            if let undoManager = textView?.undoManager {
                editor.replaceAllElements(
                    elements,
                    activeID: activeID,
                    offset: offset,
                    structural: true,
                    recordsUndo: false
                )
                registerModelUndo(previousState, actionName: actionName, with: undoManager)
            } else {
                editor.replaceAllElements(
                    elements,
                    activeID: activeID,
                    offset: offset,
                    structural: true
                )
            }
            renderModel(selecting: activeID, offset: offset)
            restoreSelection(selection)
            reportNativeUndoAvailability(afterUIKitSettles: true)
        }

        private func registerModelUndo(
            _ state: ModelUndoState,
            actionName: String,
            with undoManager: UndoManager
        ) {
            undoManager.registerUndo(withTarget: self) { target in
                target.restoreModelUndoState(state, actionName: actionName)
            }
            undoManager.setActionName(actionName)
        }

        private func restoreModelUndoState(_ state: ModelUndoState, actionName: String) {
            guard let editor, let undoManager = textView?.undoManager else { return }
            let inverse = ModelUndoState(
                elements: editor.screenplay.elements,
                activeElementID: editor.activeElementID,
                selectionOffset: editor.selectionOffset,
                selection: textView?.selectedRange ?? NSRange(location: 0, length: 0)
            )
            registerModelUndo(inverse, actionName: actionName, with: undoManager)
            editor.replaceAllElements(
                state.elements,
                activeID: state.activeElementID,
                offset: state.selectionOffset,
                structural: true,
                recordsUndo: false
            )
            renderModel(selecting: state.activeElementID, offset: state.selectionOffset)
            restoreSelection(state.selection)
            reportNativeUndoAvailability(afterUIKitSettles: true)
        }

        /// Makes a line a scene heading the moment it says it is one.
        ///
        /// Fountain defines a line beginning INT./EXT./EST./I/E. as a slug, and
        /// until this the editor disagreed with its own parser: you could type
        /// `INT. KITCHEN - DAY`, watch it stay action, save, reopen, and find it
        /// had been a heading all along. It also switches on the help that is
        /// scoped to headings — the time-of-day ghost, and the dash that writes
        /// a spaced separator — which previously waited for the writer to say
        /// what they were already writing.
        ///
        /// Through `changeKind`, not by setting the type, so the conversion
        /// carries what every other conversion carries: the caps a heading
        /// wears, the casing memory that makes it reversible, and one undo step.
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

        /// Places scanned or imported elements after the one holding the
        /// caret, through the same path as every other structural edit — so
        /// the pages arrive as one undoable step on the writer's own timeline
        /// and the view renders them immediately.
        private func insertElements(_ pages: [ScriptElement]) {
            guard let editor, let last = pages.last else { return }
            var elements = editor.screenplay.elements
            let index = min(
                editor.activeElementIndex.map { $0 + 1 } ?? elements.count,
                elements.count
            )
            elements.insert(contentsOf: pages, at: index)

            // Ranges of the document as it will be, not as it was: the caret
            // belongs at the end of what arrived, and everything after the
            // insertion point has moved.
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

        /// Replaces every element without moving the writer.
        ///
        /// Used by edits that change what an element *is* rather than what it
        /// says — scene numbering writes metadata the flattened text does not
        /// contain — so the caret and selection are carried across untouched.
        private func applyElements(_ elements: [ScriptElement], actionName: String) {
            guard let editor, let textView,
                  let activeID = editor.activeElementID ?? elements.first?.id else { return }
            applyModelEdit(
                elements,
                activeID: activeID,
                offset: editor.selectionOffset,
                selection: textView.selectedRange,
                actionName: actionName
            )
        }

        /// Brings an element into view and shows which one it is.
        ///
        /// A Navigator row has two jobs and only the first was being done.
        /// The page has to move, and the reader has to see where they landed.
        /// A script stops scrolling once its last page reaches the bottom, so
        /// a target within a screen of the end never reaches the top however
        /// hard this scrolls; a target already on screen does not move the
        /// page at all; and while reading there is no caret to mark the
        /// arrival either. All three read as a dead row. The mark is what
        /// answers them — see `RevealHighlightView`.
        private func reveal(_ id: UUID) {
            guard let textView else { return }
            // The row named an element in the model. These ranges are this
            // surface's picture of that model, and a picture taken before the
            // last change would fail the lookup below and do nothing at all —
            // so bring it up to date first rather than miss silently.
            if let editor, editor.revision != renderedRevision {
                renderModel(selecting: nil, offset: nil)
            }
            guard let mapped = ranges.first(where: { $0.id == id }) else {
                assertionFailure("asked to reveal an element the surface does not have")
                return
            }

            textView.selectedRange = NSRange(location: mapped.range.location, length: 0)
            scroll(to: mapped.range, in: textView)
            // UITextView re-pins the offset one layout beat after a
            // programmatic scroll into unrealized layout — the same
            // container-settling quirk renderModel guards against. The mark
            // goes on after that, on the page where it comes to rest.
            let target = textView.contentOffset
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                textView.setContentOffset(target, animated: false)
                self.markRevealed(mapped.range, in: textView)
            }
            updateSelection(from: textView)
        }

        /// Draws the mark over an element's own lines.
        private func markRevealed(_ range: NSRange, in textView: UITextView) {
            let layout = textView.layoutManager
            let container = textView.textContainer
            // The whole container, not just this range's glyphs: the extra line
            // fragment an empty last line lives in does not exist until the text
            // system has finished laying out.
            layout.ensureLayout(for: container)
            let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)

            // An element with no text encloses no glyphs, so it measures no
            // *width* — but it has a height and a place, and it is still
            // somewhere a reader can be sent: the blank line they are about to
            // type into. Testing `isEmpty` here would discard it, because a
            // rectangle is empty when either dimension is zero. A blank line in
            // the body borrows the fragment it sits in; a blank line at the very
            // end has none of its own and lives in the extra fragment.
            var rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
            if rect.height <= 0 {
                let length = layout.numberOfGlyphs
                rect = glyphs.location >= length
                    ? layout.extraLineFragmentUsedRect
                    : layout.lineFragmentUsedRect(
                        forGlyphAt: min(glyphs.location, max(0, length - 1)), effectiveRange: nil
                    )
            }
            guard !rect.isNull, rect.height > 0 else { return }

            // Marked across the measure rather than as an invisible sliver.
            if rect.width < 1 { rect.size.width = container.size.width }
            rect.origin.x += textView.textContainerInset.left
            rect.origin.y += textView.textContainerInset.top
            revealHighlight.mark(rect, in: textView)
        }

        /// Brings a range to rest just under the navigation bar.
        ///
        /// Not `scrollRangeToVisible`. The page deliberately runs under a
        /// transparent bar, so its top inset is contributed by the system
        /// rather than owned by the text view — `contentInset.top` is 0 while
        /// `adjustedContentInset.top` is the bar's height — and UITextView's
        /// own scroll-to-range does nothing at all in that configuration.
        /// Measured on a 4776pt document parked at its end: a heading laid
        /// out at y=2960 left the offset at 3936, unmoved. Every Navigator
        /// row looked dead because of it — the caret arrived on the right
        /// line and the page stayed where it was — and the re-pin below,
        /// reading an offset that had not changed, then nailed it there.
        ///
        /// The layout manager knows where the line is, so ask it and set the
        /// offset. The range lands at the top of the page rather than at the
        /// minimum scroll that would reveal it: a writer who asks for a scene
        /// wants to read down from it.
        private func scroll(to range: NSRange, in textView: UITextView) {
            let layout = textView.layoutManager
            // A zero-length range encloses no glyphs and so has no rectangle
            // to aim at — the caret's own range is exactly that. Measure the
            // character it sits against instead, which is the line it is on.
            let length = textView.textStorage.length
            var measured = range
            if measured.length == 0, length > 0 {
                let anchor = min(max(measured.location, 0), length - 1)
                measured = NSRange(location: anchor, length: 1)
            }
            let glyphs = layout.glyphRange(forCharacterRange: measured, actualCharacterRange: nil)
            layout.ensureLayout(forGlyphRange: glyphs)
            let rect = layout.boundingRect(forGlyphRange: glyphs, in: textView.textContainer)
            // Content space: the container's own inset, then the offset that
            // corresponds to "resting at the top" under the system's inset.
            // A page that fits on the screen has nowhere to go, and pinning it
            // anyway puts a short script under the navigation bar: the resting
            // offset of an inset scroll view is not zero, and this ran before
            // the bar's clearance had been measured.
            let range = scrollableRange(in: textView)
            guard PageScroll.canScroll(range) else { return }
            let y = PageScroll.offset(
                bringingContentY: rect.minY + textView.textContainerInset.top, toTopOf: range
            )
            textView.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        }

        private func performNativeUndo() -> Bool {
            guard let undoManager = textView?.undoManager, undoManager.canUndo else {
                reportNativeUndoAvailability()
                return false
            }
            undoManager.undo()
            reportNativeUndoAvailability(afterUIKitSettles: true)
            return true
        }

        private func performNativeRedo() -> Bool {
            guard let undoManager = textView?.undoManager, undoManager.canRedo else {
                reportNativeUndoAvailability()
                return false
            }
            undoManager.redo()
            reportNativeUndoAvailability(afterUIKitSettles: true)
            return true
        }

        private func clearNativeUndoHistory() {
            textView?.undoManager?.removeAllActions()
            editor?.reportNativeUndoAvailability(canUndo: false, canRedo: false)
        }

        private func reportNativeUndoAvailability(afterUIKitSettles: Bool = false) {
            if afterUIKitSettles {
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.reportNativeUndoAvailability()
                }
                return
            }

            let undoManager = textView?.undoManager
            editor?.reportNativeUndoAvailability(
                canUndo: undoManager?.canUndo == true,
                canRedo: undoManager?.canRedo == true
            )
        }

        private func updateSelection(from textView: UITextView) {
            guard let mapped = elementRange(at: textView.selectedRange.location) else { return }
            editor?.selectionChanged(
                elementID: mapped.id,
                offset: min(mapped.range.length, max(0, textView.selectedRange.location - mapped.range.location))
            )
        }

        private func restoreSelection(_ requestedRange: NSRange) {
            guard let textView else { return }
            let length = textView.textStorage.length
            let location = min(max(0, requestedRange.location), length)
            let selectionLength = min(max(0, requestedRange.length), length - location)
            applyingModel = true
            textView.selectedRange = NSRange(location: location, length: selectionLength)
            applyingModel = false
            updateSelection(from: textView)
            updateTypingTraits()
            updateGhost()
        }

        private func updateTypingTraits() {
            guard let editor, let textView else { return }
            textView.typingAttributes = attributes(
                for: editor.activeKind,
                width: contentWidth(for: textView),
                traitCollection: textView.traitCollection,
                spacingAfter: 0
            )

            // The keyboard uppercases scene headings, characters, transitions,
            // and shots itself; everywhere else it applies ordinary sentence
            // capitalization. Assigning the trait alone does not reach an
            // already-visible keyboard — that unreliability is what produced
            // the original stuck-in-caps report — so a real change is followed
            // by reloadInputViews(), Apple's documented mechanism for making a
            // live keyboard re-read its input traits. The value comparison
            // keeps that reload to genuine transitions only.
            //
            // A cue is the one kind where the keyboard's guesses are worse
            // than no guesses: the app already predicts cast names itself, so
            // autocorrect adds nothing, and a name it "fixes" — MARA to MARE
            // — does not misspell a word, it invents a second character and
            // splits her dialogue between the two. Everywhere else, headings
            // included, the writer keeps their own system setting.
            let cue = editor.activeKind == .character
            let desiredCase: UITextAutocapitalizationType = editor.activeKind.uppercasesInput
                ? .allCharacters
                : .sentences
            let desiredCorrection: UITextAutocorrectionType = cue ? .no : .yes
            let desiredSpelling: UITextSpellCheckingType = cue ? .no : .yes
            var traitsChanged = false
            if textView.autocapitalizationType != desiredCase {
                textView.autocapitalizationType = desiredCase
                traitsChanged = true
            }
            if textView.autocorrectionType != desiredCorrection {
                textView.autocorrectionType = desiredCorrection
                traitsChanged = true
            }
            if textView.spellCheckingType != desiredSpelling {
                textView.spellCheckingType = desiredSpelling
                traitsChanged = true
            }
            if traitsChanged, textView.isFirstResponder {
                textView.reloadInputViews()
            }
        }

        private func layoutChanged(width: CGFloat, traits: UITraitCollection) {
            let nextTraitSignature = [
                traits.preferredContentSizeCategory.rawValue,
                String(traits.userInterfaceStyle.rawValue),
                String(traits.accessibilityContrast.rawValue),
                String(traits.legibilityWeight.rawValue),
                String(traits.layoutDirection.rawValue)
            ].joined(separator: "|")
            guard abs(width - documentWidth) > 1 || nextTraitSignature != traitSignature else { return }
            guard let textView else { return }
            if textView.markedTextRange != nil {
                pendingLayoutRefresh = true
                return
            }
            let nativeSelection = textView.selectedRange
            pendingLayoutRefresh = false
            documentWidth = width
            traitSignature = nextTraitSignature
            guard renderedRevision >= 0 else { return }
            renderModel(selecting: editor?.activeElementID, offset: editor?.selectionOffset)
            restoreSelection(nativeSelection)
            if !didFrameInitialPosition, editor?.opensAtEnd == true {
                didFrameInitialPosition = true
                // Same reason as `scroll(to:in:)`: under a transparent bar,
                // scrollRangeToVisible leaves the page at the top and the
                // writer resumes at page one instead of where they stopped.
                scroll(to: textView.selectedRange, in: textView)
                // The same container-settling reset can yank the resume
                // scroll back to the top a beat later; re-apply it once.
                let target = textView.contentOffset
                DispatchQueue.main.async { [weak textView] in
                    textView?.setContentOffset(target, animated: false)
                }
            }
        }

        private func applyDeferredLayoutIfNeeded() {
            guard pendingLayoutRefresh,
                  let textView,
                  textView.markedTextRange == nil else { return }
            layoutChanged(width: textView.bounds.width, traits: textView.traitCollection)
        }

        private func elementRange(at location: Int) -> ElementRange? {
            if let exact = ranges.first(where: {
                ($0.range.length == 0 && $0.range.location == location) ||
                NSLocationInRange(location, $0.range)
            }) { return exact }
            if let preceding = ranges.last(where: { NSMaxRange($0.range) <= location }) { return preceding }
            return ranges.first
        }

        private func makeAttributedString(
            elements: [ScriptElement],
            width: CGFloat,
            traitCollection: UITraitCollection
        ) -> (string: NSAttributedString, ranges: [ElementRange]) {
            let result = NSMutableAttributedString()
            var mapped: [ElementRange] = []
            for (index, element) in elements.enumerated() {
                let location = result.length
                let nextSpacing = index + 1 < elements.count
                    ? spacing(before: elements[index + 1].type)
                    : 0
                let style = attributes(
                    for: element.type,
                    width: width,
                    traitCollection: traitCollection,
                    spacingAfter: nextSpacing
                )
                result.append(NSAttributedString(string: element.text, attributes: style))
                mapped.append(ElementRange(
                    id: element.id,
                    range: NSRange(location: location, length: (element.text as NSString).length)
                ))
                if index < elements.count - 1 {
                    result.append(NSAttributedString(string: "\n", attributes: style))
                }
            }
            return (result, mapped)
        }

        private func attributes(
            for kind: ScreenplayKind,
            width: CGFloat,
            traitCollection: UITraitCollection,
            spacingAfter: CGFloat
        ) -> [NSAttributedString.Key: Any] {
            let resolvedFont = font(for: kind, traits: traitCollection)
            let resolvedLineHeight = ScriptTypography.lineHeight(
                forFontLineHeight: resolvedFont.lineHeight
            )
            let paragraph = NSMutableParagraphStyle()
            paragraph.minimumLineHeight = resolvedLineHeight
            paragraph.maximumLineHeight = resolvedLineHeight
            // Paragraph space belongs to the preceding paragraph. UIKit can
            // then draw its standard insertion caret at the next baseline,
            // without stretching the caret through screenplay whitespace.
            paragraph.paragraphSpacing = UIFontMetrics(forTextStyle: .body).scaledValue(
                for: spacingAfter,
                compatibleWith: traitCollection
            )

            // The shape of the page is the same on every surface, so the
            // measurements come from one place: ScriptTypography.
            if let indents = ScriptTypography.indents(for: kind) {
                paragraph.firstLineHeadIndent = width * indents.head
                paragraph.headIndent = width * indents.head
                paragraph.tailIndent = -(width * indents.tail)
            }
            switch ScriptTypography.alignment(for: kind) {
            case .natural: break
            case .right: paragraph.alignment = .right
            case .centred: paragraph.alignment = .center
            }

            return [
                .font: resolvedFont,
                .foregroundColor: UIColor.label,
                .paragraphStyle: paragraph
            ]
        }

        private func font(for kind: ScreenplayKind, traits: UITraitCollection) -> UIFont {
            let weight: UIFont.Weight = ScriptTypography.isEmphasised(kind) ? .semibold : .regular
            let base = UIFont.monospacedSystemFont(ofSize: 16, weight: weight)
            return UIFontMetrics(forTextStyle: .body).scaledFont(for: base, compatibleWith: traits)
        }

        private func spacing(before kind: ScreenplayKind) -> CGFloat {
            ScriptTypography.spacing(before: kind)
        }

        private func contentWidth(for textView: UITextView) -> CGFloat {
            max(280, textView.bounds.width - textView.textContainerInset.left - textView.textContainerInset.right)
        }

        private struct ElementRange {
            let id: UUID
            var range: NSRange
        }

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
}

/// Draws the completion with the same TextKit stack as the editor without ever
/// inserting prediction text into the real document. Matching containers and
/// paragraph attributes keep baselines, indents, and line wrapping identical.
@MainActor
private final class GhostTextOverlay: UIView {
    var onAccept: (() -> Void)?

    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: .zero)
    private var ghostGlyphRange = NSRange(location: 0, length: 0)
    private var ghostHitRect = CGRect.null
    private var drawingOrigin = CGPoint.zero
    /// The ghost line's rect in the host text view's content coordinates.
    /// The overlay's frame is this rect (plus a glyph overhang margin) — never
    /// the document: a plain `draw(_:)` view's backing store is sized to its
    /// bounds, so spanning a feature-length script would allocate hundreds of
    /// megabytes to draw a dozen glyphs.
    private var hostLineRect = CGRect.null
    private var renderedKey: RenderKey?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isHidden = true
        isAccessibilityElement = false

        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.allowsNonContiguousLayout = true

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(acceptTapped)))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(
        in host: UITextView,
        base: NSAttributedString,
        suffix: String,
        insertionLocation: Int,
        paragraphRange: NSRange,
        attributes: [NSAttributedString.Key: Any],
        revision: Int
    ) -> Bool {
        guard paragraphRange.location >= 0,
              NSMaxRange(paragraphRange) <= base.length,
              insertionLocation >= paragraphRange.location,
              insertionLocation <= NSMaxRange(paragraphRange),
              let selectedTextRange = host.selectedTextRange else {
            hide()
            return false
        }

        let scale = host.traitCollection.displayScale
        let width = host.bounds.width
        let containerWidth = host.textContainer.size.width
        let key = RenderKey(
            revision: revision,
            insertionLocation: insertionLocation,
            suffix: suffix,
            paragraphLocation: paragraphRange.location,
            paragraphLength: paragraphRange.length,
            pixelWidth: Int((width * scale).rounded()),
            pixelContainerWidth: Int((containerWidth * scale).rounded()),
            traitStyle: host.traitCollection.userInterfaceStyle.rawValue,
            contentSizeCategory: host.traitCollection.preferredContentSizeCategory.rawValue,
            attributeDescription: String(describing: attributes)
        )

        guard key != renderedKey else {
            return !isHidden
        }

        textContainer.lineFragmentPadding = host.textContainer.lineFragmentPadding
        textContainer.lineBreakMode = host.textContainer.lineBreakMode
        textContainer.maximumNumberOfLines = host.textContainer.maximumNumberOfLines
        textContainer.exclusionPaths = []
        textContainer.size = CGSize(width: containerWidth, height: .greatestFiniteMagnitude)
        layoutManager.usesFontLeading = host.layoutManager.usesFontLeading

        let localLocation = insertionLocation - paragraphRange.location
        // An empty screenplay element has no host glyph to anchor against.
        // Wait for the writer's first character instead of guessing a baseline.
        guard localLocation > 0 else {
            hide()
            return false
        }
        let paragraph = base.attributedSubstring(from: paragraphRange)
        storage.setAttributedString(paragraph)
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: storage.length))
        let originalLineY = lineOriginY(before: localLocation)

        let mirrored = NSMutableAttributedString(attributedString: paragraph)
        mirrored.insert(NSAttributedString(string: suffix, attributes: attributes), at: localLocation)
        storage.setAttributedString(mirrored)
        let ghostCharacterRange = NSRange(
            location: localLocation,
            length: (suffix as NSString).length
        )
        ghostGlyphRange = layoutManager.glyphRange(
            forCharacterRange: ghostCharacterRange,
            actualCharacterRange: nil
        )
        layoutManager.ensureLayout(forCharacterRange: ghostCharacterRange)

        let lineFragments = ghostLineFragments()
        let completedPrefixLineY = lineOriginY(before: localLocation)
        let prefixStayedOnLine: Bool
        if let originalLineY {
            prefixStayedOnLine = completedPrefixLineY.map {
                abs(originalLineY - $0) < 0.5
            } ?? false
        } else {
            prefixStayedOnLine = true
        }
        guard ghostGlyphRange.length > 0,
              lineFragments.count == 1,
              prefixStayedOnLine else {
            hide()
            return false
        }

        let ghostLine = lineFragments[0]
        let ghostStayedBesidePrefix = completedPrefixLineY.map {
            abs(ghostLine.usedRect.minY - $0) < 0.5
        } ?? (localLocation == 0)
        guard ghostStayedBesidePrefix else {
            hide()
            return false
        }

        guard let hostLineTop = hostLineTop(
            in: host,
            precedingCharacterAt: insertionLocation
        ) else {
            hide()
            return false
        }

        let caret = host.caretRect(for: selectedTextRange.end)
        let mirrorInsertionX = ghostLine.lineRect.minX
            + layoutManager.location(forGlyphAt: ghostGlyphRange.location).x
        let expectedCaretX = host.textContainerInset.left + mirrorInsertionX
        guard abs(expectedCaretX - caret.minX) < 1.5 else {
            // The completed candidate would reflow the already-typed prefix.
            // Hiding is safer than drawing a completion away from the caret.
            hide()
            return false
        }

        drawingOrigin = CGPoint(
            x: caret.minX - mirrorInsertionX,
            y: hostLineTop - ghostLine.usedRect.minY
        )
        // The frame hugs the ghost line (in host content coordinates, so the
        // overlay scrolls with the document), and drawing/hit-testing happen
        // in the overlay's local space. Glyphs can overhang their used rect —
        // the margin keeps ascenders and descenders from clipping.
        hostLineRect = ghostLine.lineRect
            .union(ghostLine.glyphRect)
            .offsetBy(dx: drawingOrigin.x, dy: drawingOrigin.y)
        updateFrame()
        let localVisibleRect = ghostLine.glyphRect
            .offsetBy(dx: drawingOrigin.x - frame.minX, dy: drawingOrigin.y - frame.minY)
        ghostHitRect = CGRect(
            x: localVisibleRect.minX,
            y: localVisibleRect.midY - 22,
            width: max(44, localVisibleRect.width),
            height: 44
        )
        renderedKey = key
        isHidden = false
        setNeedsDisplay()
        return true
    }

    func isPresenting(suffix: String, insertionLocation: Int, revision: Int) -> Bool {
        guard !isHidden, let renderedKey else { return false }
        return renderedKey.suffix == suffix
            && renderedKey.insertionLocation == insertionLocation
            && renderedKey.revision == revision
    }

    func hide() {
        guard !isHidden || renderedKey != nil else { return }
        isHidden = true
        renderedKey = nil
        ghostGlyphRange = NSRange(location: 0, length: 0)
        ghostHitRect = .null
        drawingOrigin = .zero
        hostLineRect = .null
        // Collapsing the frame releases the layer's backing store.
        frame = .zero
    }

    override func draw(_ rect: CGRect) {
        guard !isHidden, ghostGlyphRange.length > 0 else { return }
        layoutManager.drawGlyphs(
            forGlyphRange: ghostGlyphRange,
            at: CGPoint(x: drawingOrigin.x - frame.minX, y: drawingOrigin.y - frame.minY)
        )
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard !isHidden else { return false }
        return ghostHitRect.contains(point)
    }

    private static let lineOverhangMargin = CGFloat(8)

    private func updateFrame() {
        guard !hostLineRect.isNull else {
            frame = .zero
            return
        }
        frame = hostLineRect.insetBy(dx: -2, dy: -Self.lineOverhangMargin)
    }

    private func ghostLineFragments() -> [LineFragment] {
        var fragments: [LineFragment] = []
        layoutManager.enumerateLineFragments(forGlyphRange: ghostGlyphRange) {
            lineRect, usedRect, container, lineGlyphRange, _ in
            let intersection = NSIntersectionRange(lineGlyphRange, self.ghostGlyphRange)
            guard intersection.length > 0 else { return }
            fragments.append(LineFragment(
                lineRect: lineRect,
                usedRect: usedRect,
                glyphRect: self.layoutManager.boundingRect(forGlyphRange: intersection, in: container)
            ))
        }
        return fragments
    }

    /// Returns the real glyph line in the host text view's content coordinates.
    /// TextKit's used line rectangle is the source of truth for the screenplay
    /// baseline, so the completion shares the real glyph line at every scroll.
    private func hostLineTop(
        in host: UITextView,
        precedingCharacterAt insertionLocation: Int
    ) -> CGFloat? {
        guard insertionLocation > 0,
              insertionLocation <= host.textStorage.length,
              host.layoutManager.numberOfGlyphs > 0 else { return nil }

        let characterRange = NSRange(location: insertionLocation - 1, length: 1)
        host.layoutManager.ensureLayout(forCharacterRange: characterRange)
        let glyphIndex = host.layoutManager.glyphIndexForCharacter(at: characterRange.location)
        guard glyphIndex < host.layoutManager.numberOfGlyphs else { return nil }

        let usedRect = host.layoutManager.lineFragmentUsedRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil
        )
        return host.textContainerInset.top + usedRect.minY
    }

    private func lineOriginY(before characterLocation: Int) -> CGFloat? {
        guard characterLocation > 0, layoutManager.numberOfGlyphs > 0 else { return nil }
        let characterIndex = min(characterLocation - 1, max(0, storage.length - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        return layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil).minY
    }

    private struct LineFragment {
        let lineRect: CGRect
        let usedRect: CGRect
        let glyphRect: CGRect
    }

    @objc private func acceptTapped() {
        if !isHidden {
            onAccept?()
        }
    }

    private struct RenderKey: Equatable {
        let revision: Int
        let insertionLocation: Int
        let suffix: String
        let paragraphLocation: Int
        let paragraphLength: Int
        let pixelWidth: Int
        let pixelContainerWidth: Int
        let traitStyle: Int
        let contentSizeCategory: String
        let attributeDescription: String
    }
}

@MainActor
final class ScreenplayTextView: UITextView {
    var onTab: ((Bool) -> Void)?
    var onAcceptPrediction: (() -> Void)?
    var onLayout: ((CGFloat, UITraitCollection) -> Void)?
    /// A hardware ⌘1–9 press, as an index into `ScreenplayKind.editorKinds`.
    var onSelectElementKind: ((ScreenplayKind) -> Void)?

    /// Every command carries a title, which is the whole of its
    /// discoverability: iPad draws the hold-⌘ overlay from these strings, and
    /// an untitled command is invisible there. ⌘1–9 mirror the web editor's
    /// element order exactly, so a writer's fingers work on either surface.
    override var keyCommands: [UIKeyCommand]? {
        var commands = [
            UIKeyCommand(
                title: "Next Element",
                action: #selector(tabForward),
                input: "\t",
                modifierFlags: []
            ),
            UIKeyCommand(
                title: "Previous Element",
                action: #selector(tabBackward),
                input: "\t",
                modifierFlags: [.shift]
            ),
            UIKeyCommand(
                title: "Accept Suggestion",
                action: #selector(acceptPrediction),
                input: UIKeyCommand.inputRightArrow,
                modifierFlags: [.command]
            ),
            // A hardware keyboard has no Done above it to reach for, and
            // Escape is what leaves an editing context everywhere else on
            // the platform. Resigning is the whole action: the chrome reads
            // focus, so the bar follows without being told.
            UIKeyCommand(
                title: "Done Editing",
                action: #selector(doneEditing),
                input: UIKeyCommand.inputEscape,
                modifierFlags: []
            )
        ]
        // One selector serves all nine: the digit the writer pressed is the
        // command's own input, so there is no parallel mapping to keep true.
        for (index, kind) in ScreenplayKind.editorKinds.prefix(9).enumerated() {
            commands.append(UIKeyCommand(
                title: kind.title,
                image: UIImage(systemName: kind.symbol),
                action: #selector(selectElementKind(_:)),
                input: String(index + 1),
                modifierFlags: [.command]
            ))
        }
        return commands
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateTopBarClearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateTopBarClearance()
        onLayout?(bounds.width, traitCollection)
    }

    /// The page extends under the transparent navigation bar, so the resting
    /// first line must start exactly at the bar's bottom edge — measured, not
    /// assumed. SwiftUI's safe-area delivery differs between hosts (the QA
    /// preview's NavigationStack propagates it into UIKit's automatic inset
    /// adjustment; DocumentGroup's host does not), so any clearance derived
    /// from safeAreaInsets alone is wrong in one of them. The bar's own frame
    /// is the ground truth everywhere; whatever share the system's automatic
    /// adjustment already contributes is subtracted, so the two never
    /// double up. Rotation and bar show/hide both re-land here through
    /// layoutSubviews.
    private func updateTopBarClearance() {
        guard window != nil, let barBottom = measuredTopBarBottom() else { return }
        let systemContribution = adjustedContentInset.top - contentInset.top
        let top = max(barBottom - systemContribution, 0)
        guard abs(contentInset.top - top) > 0.5 else { return }
        contentInset.top = top
        verticalScrollIndicatorInsets.top = top
    }

    /// The navigation bar's bottom edge as clearance above this view's
    /// visible top, measured in WINDOW space. The view's own coordinate
    /// system is content space — it moves with the scroll offset, so
    /// converting the bar into `self` produced a clearance that grew as the
    /// writer scrolled, mutating the scroll geometry mid-gesture (the
    /// viewport jumps). Window space never moves.
    private func measuredTopBarBottom() -> CGFloat? {
        var responder: UIResponder? = next
        while let current = responder {
            if let navigationController = current as? UINavigationController {
                let bar = navigationController.navigationBar
                guard !bar.isHidden, bar.window != nil else { return nil }
                let barBottomInWindow = bar.convert(bar.bounds, to: nil).maxY
                let viewTopInWindow = convert(bounds.origin, to: nil).y
                return max(barBottomInWindow - viewTopInWindow, 0)
            }
            responder = current.next
        }
        return nil
    }

    @objc private func doneEditing() { resignFirstResponder() }
    @objc private func tabForward() { onTab?(false) }
    @objc private func tabBackward() { onTab?(true) }
    @objc private func acceptPrediction() { onAcceptPrediction?() }

    @objc private func selectElementKind(_ sender: UIKeyCommand) {
        guard let digit = sender.input.flatMap(Int.init) else { return }
        let index = digit - 1
        guard ScreenplayKind.editorKinds.indices.contains(index) else { return }
        onSelectElementKind?(ScreenplayKind.editorKinds[index])
    }

    /// A caret belongs to exactly one line: the line fragment of the glyph at
    /// the insertion point. UIKit's default rect can stretch through
    /// `paragraphSpacing` when the caret sits at a paragraph edge, rendering
    /// inside the gap below the text; and any approach that reverse-matches a
    /// y-coordinate against line rectangles breaks as soon as the view is
    /// scrolled (content offset) or a fragment contains padding. Instead the
    /// caret line is resolved from the character index itself — the same
    /// lookup TextKit performs — while the horizontal placement stays UIKit's
    /// own (indents, alignment, and wrapping included). Every line then shows
    /// the same uniform caret, always on its own line.
    override func caretRect(for position: UITextPosition) -> CGRect {
        let rect = super.caretRect(for: position)
        let font = typingAttributes[.font] as? UIFont
            ?? UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
        let lineHeight = max(22, ceil(font.lineHeight * 1.1))
        let normalized = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: lineHeight)

        let length = textStorage.length
        guard length > 0, layoutManager.numberOfGlyphs > 0 else { return normalized }

        let characterIndex = offset(from: beginningOfDocument, to: position)
        guard characterIndex >= 0 else { return normalized }

        // Caret past the final newline: the virtual empty line, which UIKit
        // reports separately from the real fragments.
        if characterIndex >= length {
            if textStorage.string.hasSuffix("\n") || textStorage.string.hasSuffix("\r") {
                let extra = layoutManager.extraLineFragmentRect
                if !extra.isNull, !extra.isInfinite {
                    return CGRect(
                        x: rect.minX,
                        y: textContainerInset.top + extra.minY,
                        width: rect.width,
                        height: lineHeight
                    )
                }
            }
            let lastGlyph = layoutManager.numberOfGlyphs - 1
            let line = layoutManager.lineFragmentUsedRect(forGlyphAt: lastGlyph, effectiveRange: nil)
            return CGRect(
                x: rect.minX,
                y: textContainerInset.top + line.minY,
                width: rect.width,
                height: lineHeight
            )
        }

        layoutManager.ensureLayout(forCharacterRange: NSRange(location: characterIndex, length: 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return normalized }
        let line = layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        guard !line.isNull, !line.isInfinite else { return normalized }
        return CGRect(
            x: rect.minX,
            y: textContainerInset.top + line.minY,
            width: rect.width,
            height: lineHeight
        )
    }
}
