import Foundation
import Observation
import EDraftEngine

@MainActor
@Observable
public final class EditorState {
    /// What the page sets.
    ///
    /// Not the whole document: everything that does not print is lifted out
    /// of it at open and put back at save — see `asides` and `ScriptAsides`.
    /// Everything that measures the script reads this, so a note or an act
    /// heading neither prints, nor paginates, nor shifts the element indices
    /// the Navigator and the prediction engine are keyed by.
    public var screenplay: Screenplay {
        didSet { synchronizeDraftIdentity(previous: oldValue) }
    }
    @ObservationIgnored private var documentIdentity = DocumentIdentity()
    @ObservationIgnored private var synchronizingIdentity = false
    /// What sits beside the page, in document order: the writer's notes and
    /// their outline.
    ///
    /// All of it is in the document — it saves, it exports, it round-trips
    /// through Final Draft — and none of it is on the page. Reading a private
    /// aside as though it were a stage direction, and counting an act heading
    /// toward the page number, is what putting them in the text stream did.
    public private(set) var asides: [ScriptAside] = [] {
        didSet { synchronizeDraftIdentity(previousAsides: oldValue) }
    }

    /// The notes among them.
    public var notes: [ScriptAside] { asides.filter { $0.kind == .note } }

    /// The notes a Final Draft file carried, when the document was opened from
    /// one — see `ImportedNote`.
    ///
    /// Apart from `asides` on purpose: asides are the document and save into
    /// it, and these are a reading of the file that must never be written a
    /// second time. Nothing here edits them.
    public private(set) var importedNotes: [ImportedNote] = []

    /// The name this writer signs notes with, and whether they sign at all.
    ///
    /// App-level state, like the assistance mode above it: read once at open
    /// and written on every change, so a Settings row survives relaunch.
    public private(set) var noteSignature = ""
    /// The role beside the name, optional (RFC-NOTES-SYSTEM D4).
    public private(set) var noteRole = ""
    public private(set) var signsNotes = false

    /// The names this document is prepared to attribute a note to.
    ///
    /// Derived, never stored — the notes themselves are the record. Walked on
    /// demand rather than cached beside `scenes` and `cast`: those two are
    /// read on every keystroke, and this only while notes are being looked at.
    /// Every writer a Final Draft file names is in it too, so one person is
    /// one colour whichever app their note was left in.
    public var noteRoster: Set<String> {
        ImportedNotes.roster(
            NoteAttribution.roster(of: notes.map(\.text), signature: signature),
            adding: importedNotes
        )
    }

    /// Reads the notes of the Final Draft file this document was opened from.
    ///
    /// Called by the document once the editor holds that file's script — at
    /// open, and again after Revert — because a note is placed on a line by
    /// where the file's own reading puts it, and that only holds while the
    /// lines are the ones the file was read into. `nil` is a document that
    /// did not come from Final Draft, and carries none.
    public func attachImportedNotes(from origin: String?) {
        /* Whatever the writer omitted or restored belonged to the text this
           replaces; from here the file says what is omitted again. */
        omissionsEdited = false
        publishedOmissions = nil
        finalDraftPageLockCount = origin.map(FinalDraftPageLocks.count(inOrigin:)) ?? 0
        guard let origin else {
            importedNotes = []
            omittedScenes = OmittedScenes()
            omissionsAvailability = .notFinalDraft
            return
        }
        let file = Fdx.parse(origin)
        let document = ScriptAsides.merge(page: screenplay.elements, asides: asides)
        importedNotes = ImportedNotes.resolve(
            file.scriptNotes,
            imported: file.script.elements,
            document: document
        )
        /* The omitted scenes come off the same parse, on the same seam and
           for the same reason: both are readings of the file the document
           was opened from, and both are placed on the lines that file was
           read into, before any edit has moved them. The name says notes
           because the document target calls it and is not this lock's to
           change; what it means is "attach what only the origin knows". */
        omittedScenes = Omissions.resolve(
            file.script.omissions ?? [],
            imported: file.script.elements,
            document: document,
            /* The file's own measure of each cut scene when it has one, and
               the paginator's when it does not. */
            recorded: Omissions.recordedEighths(inOrigin: origin),
            measuring: { span in
                ScreenplayExporter.pages(of: Array(document[span]))
            }
        )
        /* The lines and the file agree index for index, or no omission could
           be placed — and then none can be kept either. */
        omissionsAvailability = file.script.elements.count == document.count ? .available : .unplaced
    }

    /// The scenes this document's file says are omitted (§7.3), by
    /// `DraftElementID`, so an edit that moves elements cannot mis-mark one.
    /// Empty for a document that did not come from a Final Draft file with
    /// an `<OmittedScene>` in it.
    public private(set) var omittedScenes = OmittedScenes()

    /// Whether this element is inside an omitted span — the one question the
    /// surface, the Navigator and the paginator all ask.
    public func isOmitted(_ element: ScriptElement) -> Bool {
        omittedScenes.contains(element)
    }

    // MARK: - Final Draft page locks (IL-0090)

    /// How many page locks the Final Draft file this document came from
    /// carries — read once, when the file is attached (`FinalDraftPageLocks`).
    @ObservationIgnored private var finalDraftPageLockCount = 0
    /// Whether this session has told the writer already. Never reset — not by
    /// a dismissal, not by Revert: once per document per session.
    @ObservationIgnored private var pageLockNoticeRaised = false

    /// What the window says about this file's Final Draft page locks, while
    /// it is saying it; nil otherwise.
    ///
    /// Raised by the writer's first edit of a file that has locks: Final
    /// Draft moves a lock with the text, and eDraft's save does not yet, so
    /// from that edit on the locks in the saved file may point at the wrong
    /// text in Final Draft (RFC-DRAFT-PRODUCTION §7.2). Never at open, and
    /// never for a file that is only read and saved as it was. When the Help
    /// Center has an article on it, the notice gains a Learn More link.
    public private(set) var pageLockNotice: String?

    public static let pageLockNoticeText = "This script has Final Draft page locks. eDraft doesn't move them with your edits yet, so in Final Draft some locked pages may start in the wrong place."

    /// The writer has read it.
    public func dismissPageLockNotice() {
        pageLockNotice = nil
    }

    /// Every edit the writer makes passes here — typing, a structural edit,
    /// an undo or a redo. One flag test; nothing about the document is read.
    private func noteWritersEdit() {
        guard finalDraftPageLockCount > 0, !pageLockNoticeRaised else { return }
        pageLockNoticeRaised = true
        pageLockNotice = Self.pageLockNoticeText
    }

    // MARK: - Omitting a scene (§7.3, IL-0087)

    private enum OmissionsAvailability { case notFinalDraft, unplaced, available }
    @ObservationIgnored private var omissionsAvailability = OmissionsAvailability.notFinalDraft
    /// Whether the writer has omitted or restored a scene since the file was
    /// read. Until then the file's own structure decides what a save keeps
    /// omitted, exactly as it always has.
    @ObservationIgnored private var omissionsEdited = false

    /// Whether an omission made here would survive a save.
    ///
    /// Only a Final Draft file can keep one: Fountain — and so a `.fountain`
    /// or `.edraft` document — has no spelling for an omission, and a cut
    /// that silently came back on reopen would be worse than a cut never
    /// offered. So the command is off there, and says why.
    public var keepsOmissions: Bool { omissionsAvailability == .available }

    /// Why Omit Scene is off for this document, as the dimmed menu bar item
    /// says it; nil when it is on. The row and the context menu offer
    /// nothing there rather than a dead control.
    public var omissionUnavailableReason: String? {
        switch omissionsAvailability {
        case .available: return nil
        case .notFinalDraft: return "Omissions are kept in Final Draft (.fdx) files."
        case .unplaced: return "This file's omitted scenes could not be placed, so omitting is off for it."
        }
    }

    /// What the save should write as omitted, published with each source —
    /// nil until the writer has omitted or restored anything, so an ordinary
    /// edit saves exactly as it did before this existed.
    @ObservationIgnored public private(set) var publishedOmissions: OmissionSpans?

    /// The production actions a Navigator row offers, in the order it shows
    /// them. Empty where the scene allows none — or where this document could
    /// not keep the result.
    public func sceneActions(for row: SceneRow) -> [SceneAction] {
        guard keepsOmissions, screenplay.elements.indices.contains(row.elementIndex) else { return [] }
        let element = screenplay.elements[row.elementIndex]
        guard element.id == row.id, element.type == .scene else { return [] }
        if omittedScenes.isCard(element) { return [.restore] }
        guard !omittedScenes.contains(element), !Omissions.isCardText(element.text),
              !element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return [.omit]
    }

    /// What Omit Scene does where the caret is: omit the scene it is in, or
    /// restore the one whose card it is on. Nil above the first heading, and
    /// wherever this document cannot keep an omission.
    public var caretSceneAction: (action: SceneAction, sceneID: UUID)? {
        guard keepsOmissions, let id = activeSceneID,
              let row = scenes.first(where: { $0.id == id }),
              let action = sceneActions(for: row).first else { return nil }
        return (action, row.id)
    }

    /// Carries a scene action out. The surface that owns the window's undo
    /// performs it (`onSceneAction`), so every door — row, context menu,
    /// menu bar — lands on one undoable path; without one, it is done here
    /// on the editor's own undo stack.
    public func perform(_ action: SceneAction, on sceneID: UUID) {
        if let onSceneAction {
            onSceneAction(action, sceneID)
            return
        }
        switch action {
        case .omit: omitScene(sceneID)
        case .restore: restoreScene(sceneID)
        }
    }
    @ObservationIgnored public var onSceneAction: ((SceneAction, UUID) -> Void)?

    /// Omits the scene whose heading this is (§7.3).
    ///
    /// The shape Final Draft gives an omission: an OMITTED card, carrying the
    /// scene's number, in front of the heading, and the scene behind it —
    /// heading through its last line — recorded as omitted. Nothing is
    /// deleted: every line keeps its identity and its words, so a restore
    /// puts back exactly what was here. Asides that stood in front of the
    /// heading now stand in front of the card, where they still are.
    /// Returns the scene as omitted, or nil when this heading cannot be.
    @discardableResult
    public func omitScene(_ headingID: UUID, recordsUndo: Bool = true) -> OmittedScene? {
        guard let index = screenplay.elements.firstIndex(where: { $0.id == headingID }),
              let row = scenes.first(where: { $0.id == headingID }),
              sceneActions(for: row).contains(.omit) else { return nil }
        let card = ScriptElement(type: .scene, text: "OMITTED", sceneNumber: screenplay.elements[index].sceneNumber)
        var page = screenplay.elements
        page.insert(card, at: index)
        let moved = asides.map { $0.anchor == headingID ? ScriptAside(element: $0.element, anchor: card.id) : $0 }
        var result: OmittedScene?
        /* The caret goes to the card's start: its end is where the hidden
           body's lines sit, and a caret there would stand in a cut line. */
        let applied = applyOmissionEdit(
            page: page, asides: moved, activeID: card.id, offset: 0, recordsUndo: recordsUndo
        ) { document in
            guard let heading = document.firstIndex(where: { $0.id == headingID }),
                  heading > 0, document[heading - 1].id == card.id else { return nil }
            let span = Omissions.sceneSpan(at: heading, in: document)
            let body = document[span]
            let scene = OmittedScene(
                card: document[heading - 1].draftID,
                elements: body.compactMap(\.draftID),
                sceneNumber: card.sceneNumber,
                eighths: nil,
                pages: ScreenplayExporter.pages(of: Array(body))
            )
            result = scene
            return Self.inScriptOrder(omittedScenes.scenes + [scene], in: document)
        }
        return applied ? result : nil
    }

    /// Restores the scene whose OMITTED card this is (§7.3): the card goes,
    /// the scene is live again, every line as it was.
    ///
    /// Final Draft moves a scene's number onto its card; a heading that
    /// came back with no number of its own takes the card's, so scene 21 is
    /// restored as scene 21. Returns the scene that was restored.
    @discardableResult
    public func restoreScene(_ cardID: UUID, recordsUndo: Bool = true) -> OmittedScene? {
        guard keepsOmissions,
              let index = screenplay.elements.firstIndex(where: { $0.id == cardID }),
              omittedScenes.isCard(screenplay.elements[index]),
              let scene = omittedScenes.scene(for: screenplay.elements[index]) else { return nil }
        var page = screenplay.elements
        page.remove(at: index)
        guard let heading = page.firstIndex(where: { $0.draftID.map(scene.elements.contains) ?? false }) else { return nil }
        if page[heading].sceneNumber == nil, let number = scene.sceneNumber {
            page[heading].sceneNumber = number
        }
        let headingID = page[heading].id
        let moved = asides.map { $0.anchor == cardID ? ScriptAside(element: $0.element, anchor: headingID) : $0 }
        let remaining = OmittedScenes(scenes: omittedScenes.scenes.filter { $0.key != scene.key })
        let applied = applyOmissionEdit(
            page: page, asides: moved, activeID: headingID, offset: 0, recordsUndo: recordsUndo
        ) { _ in remaining }
        return applied ? scene : nil
    }

    /// What an omit or a restore changes beyond the page's lines: the asides
    /// (one may have moved to or from a card) and the omitted scenes. The
    /// surface keeps this beside the lines in its undo record, so one ⌘Z puts
    /// all of it back.
    public struct OmissionState: Equatable, Sendable {
        public let asides: [ScriptAside]
        public let omitted: OmittedScenes
    }
    public var omissionState: OmissionState { OmissionState(asides: asides, omitted: omittedScenes) }

    /// Puts lines and omissions back together, recording no undo — the caller
    /// owns it (the surface's undo of an omit or a restore).
    @discardableResult
    public func replaceAllElements(
        _ elements: [ScriptElement], restoring state: OmissionState, activeID: UUID?, offset: Int
    ) -> Bool {
        applyOmissionEdit(
            page: elements, asides: state.asides,
            activeID: activeID ?? elements.first?.id, offset: offset, recordsUndo: false
        ) { _ in state.omitted }
    }

    /// One structural change to lines, asides and omissions, committed once:
    /// identities are settled first, so the omission can be built from the
    /// document as it will stand, and the source published after carries
    /// the omission with it.
    private func applyOmissionEdit(
        page incoming: [ScriptElement],
        asides incomingAsides: [ScriptAside],
        activeID: UUID?,
        offset: Int,
        recordsUndo: Bool,
        omitted build: ([ScriptElement]) -> OmittedScenes?
    ) -> Bool {
        var candidate = documentIdentity
        let adopted: [ScriptElement]
        do { adopted = try candidate.reconcile(incoming + incomingAsides.map(\.element)) }
        catch {
            showBanner("This document cannot allocate another element identity")
            return false
        }
        let page = Array(adopted.prefix(incoming.count))
        var settled = incomingAsides
        for i in settled.indices { settled[i].element = adopted[incoming.count + i] }
        guard let omitted = build(ScriptAsides.merge(page: page, asides: settled)) else { return false }
        if recordsUndo { recordSnapshot(structural: true) }
        documentIdentity = candidate
        synchronizingIdentity = true
        screenplay.elements = page
        asides = settled
        screenplay.nextId = documentIdentity.allocator.nextId
        synchronizingIdentity = false
        omittedScenes = omitted
        omissionsEdited = true
        caseMemory.prune(toAlive: Set(screenplay.elements.map(\.id)))
        activeElementID = activeID ?? screenplay.elements.first?.id
        selectionOffset = max(0, offset)
        commitChange()
        return true
    }

    /// Omitted scenes in the order they fall in the document.
    private static func inScriptOrder(_ scenes: [OmittedScene], in document: [ScriptElement]) -> OmittedScenes {
        var position: [DraftElementID: Int] = [:]
        for (at, element) in document.enumerated() {
            if let id = element.draftID { position[id] = at }
        }
        return OmittedScenes(scenes: scenes.sorted {
            (position[$0.key] ?? .max) < (position[$1.key] ?? .max)
        })
    }

    /// The writer's structure among them: acts, sequences and beats, each
    /// with the prose under it. In document order, so a reader can walk it.
    public var outline: [ScriptAside] {
        asides.filter { $0.kind == .section || $0.kind == .synopsis }
    }
    public var activeElementID: UUID?
    public var selectionOffset = 0
    public var predictions: [EnginePrediction] = []
    public var predictionIndex = 0
    public var predictionMode: PredictionMode = .smart
    public var stats = ScreenplayStats()
    public var revision = 0
    public var canUndo = false
    public var canRedo = false

    @ObservationIgnored public var onSourceChange: ((String) -> Void)?
    @ObservationIgnored public var onPredictionChange: (() -> Void)?
    @ObservationIgnored public var onAcceptPrediction: (() -> Void)?
    @ObservationIgnored public var onChangeElementKind: ((ScreenplayKind) -> Void)?
    /// Places finished elements after the caret's own. Implemented by the text
    /// view, because an edit that skips its undo registration leaves the Undo
    /// button and the model disagreeing about what the document contains.
    @ObservationIgnored public var onInsertElements: (([ScriptElement]) -> Void)?
    /// Inserts an act break after the caret's element, card canonical, caret
    /// in the action line that follows (RFC-ACT-BREAK §6). Same reasoning as
    /// `onInsertElements`: the text view owns undo registration.
    @ObservationIgnored public var onInsertActBreak: (() -> Void)?
    /// Replaces the whole element list as one undoable step, named for the
    /// Undo menu. Same reasoning as `onInsertElements`: the text view owns
    /// registration, so nothing may write the model behind its back.
    @ObservationIgnored public var onApplyElements: (([ScriptElement], String) -> Void)?
    @ObservationIgnored public var onJumpToElement: ((UUID) -> Void)?
    @ObservationIgnored public var onNativeUndo: (() -> Bool)?
    @ObservationIgnored public var onNativeRedo: (() -> Bool)?
    @ObservationIgnored public var onClearNativeUndo: (() -> Void)?
    /// Puts the writer into the script, or takes them out of it. The text
    /// surface owns first-responder status, so asking is the only honest way
    /// to change it: see `isEditing`.
    @ObservationIgnored public var onSetEditing: ((Bool) -> Void)?
    /// How large the page is drawn, and the way to change it. The surface owns
    /// the magnification — asking is the only honest way to change it, the same
    /// arrangement as `onSetEditing`.
    @ObservationIgnored public var onZoom: ((PageZoom.Command) -> Void)?
    /// A size the writer chose by name from the percentage menu — the same
    /// arrangement as `onZoom`: the surface owns the magnification.
    @ObservationIgnored public var onZoomTo: ((CGFloat) -> Void)?
    /// A column that borrows the page's room opened or closed beside it — the
    /// Mac's character thread. The surface owns the magnification, so the
    /// lend-and-return lives there too, the same arrangement as `onZoom`.
    /// `true` opens, `false` closes.
    @ObservationIgnored public var onThreadColumn: ((Bool) -> Void)?

    /// Leaves a note on the caret's element and opens its card.
    ///
    /// The surface's, not the model's, because the card points at a mark in
    /// the margin and the mark does not exist until the page has been laid
    /// out with the new note in it. `addNote` is the model half; this is the
    /// two halves in the order that works.
    @ObservationIgnored public var onAddNote: (() -> Void)?

    /// Shows the system find bar. The surface owns the `NSTextFinder`.
    @ObservationIgnored public var onShowFind: (() -> Void)?
    /// Writing a file is the app's business and the format list is the
    /// core's, so the surface can offer the choice without knowing what a
    /// save panel is.
    @ObservationIgnored public var onExport: ((ScreenplayExportFormat) -> Void)?
    @ObservationIgnored public var onFindNext: (() -> Void)?
    @ObservationIgnored public var onFindPrevious: (() -> Void)?
    /// Find Scene (⌘L): the window reveals the Navigator's Scenes tab and
    /// focuses the filter. Not a second text search.
    @ObservationIgnored public var onFindScene: (() -> Void)?
    /// Opens every page break if any are closed, closes them all otherwise.
    /// The surface preserves the viewport so a long document does not jump.
    @ObservationIgnored public var onSetLayoutMode: ((PageLayoutMode) -> Void)?
    @ObservationIgnored public var onSetArrangement: ((PageArrangement) -> Void)?

    /// Whether the writer is editing the script or reading it.
    ///
    /// This is not a mode the app keeps. It is the text surface's own
    /// first-responder state, reported here so the chrome can follow it, and
    /// that single source of truth is the whole point: a bar that reads the
    /// keyboard's state cannot come to disagree with the keyboard. Tapping
    /// the page, dismissing it by swipe, presenting a sheet over it — every
    /// one of those already moves focus, and the chrome simply follows.
    public private(set) var isEditing = false

    /// What the page is currently drawn at, reported by the surface so a menu
    /// can grey out a command that would do nothing. Not a stored preference:
    /// the default follows the window, and this follows the default.
    public private(set) var zoom: CGFloat = PageZoom.actualSize

    /// Whether the percentage button is holding actual size, so the next
    /// press gives back the size the writer had. Reported with the zoom
    /// because the control needs both to decide whether it is a toggle or
    /// a menu — at 100% after a toggle, a menu would swallow the way back.
    public private(set) var holdingActualSize = false

    /// Sheets or one column — see `PageLayoutMode`. Held here so a menu can
    /// show which one is on without asking the surface.
    public private(set) var layoutMode: PageLayoutMode = .stored

    /// Single, two-page or grid — see `PageArrangement`. Sheets only;
    /// Continuous has no facing pages to arrange.
    public private(set) var arrangement: PageArrangement = .stored

    /// The surface reporting the layout it settled on.
    public func reportLayoutMode(_ mode: PageLayoutMode) {
        guard layoutMode != mode else { return }
        layoutMode = mode
    }

    /// The surface reporting the arrangement it settled on.
    public func reportArrangement(_ mode: PageArrangement) {
        guard arrangement != mode else { return }
        arrangement = mode
    }

    /// The surface reporting the size it settled on.
    public func reportZoom(_ value: CGFloat) {
        guard abs(zoom - value) > 0.0001 else { return }
        zoom = value
    }

    /// The surface reporting whether the percentage button is holding 100%.
    public func reportHoldingActualSize(_ holding: Bool) {
        guard holdingActualSize != holding else { return }
        holdingActualSize = holding
    }

    /// The surface reporting what focus did.
    public func reportEditing(_ editing: Bool) {
        guard isEditing != editing else { return }
        isEditing = editing
    }

    /// The chrome asking for focus to move.
    public func beginEditing() { onSetEditing?(true) }
    public func endEditing() { onSetEditing?(false) }

    /// A transient, non-modal notice ("Updated elsewhere", the swipe
    /// element toast). The view renders it as a capsule under the chrome.
    public var banner: String?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?

    public func showBanner(_ text: String) {
        bannerTask?.cancel()
        banner = text
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard let self, !Task.isCancelled else { return }
            banner = nil
        }
    }

    /// The last source this state published or was created with, so the
    /// document binding can tell its own echoes — and unchanged redeliveries
    /// at launch — apart from genuinely external document changes.
    @ObservationIgnored public private(set) var lastKnownSource: String?
    /// True when this state opened with the caret at the end of the document.
    /// The text surface reads it once to scroll the resume point into view
    /// after the first real layout.
    @ObservationIgnored public let opensAtEnd: Bool
    @ObservationIgnored private var predictionTask: Task<Void, Never>?
    @ObservationIgnored private var sourceTask: Task<Void, Never>?
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    /// The identity-free engine model costs one struct allocation per element
    /// to build, and prediction, persistence, and pagination all need it
    /// several times per second. Cached per revision: every content mutation
    /// bumps `revision`, so the cache is self-invalidating and never stale.
    @ObservationIgnored private var cachedEngineModel: EDraftEngine.Screenplay?
    @ObservationIgnored private var cachedEngineModelRevision = -1

    /// The panel's lists walk the whole document, and a SwiftUI body asks
    /// for them on every invalidation — the cast's regex-per-cue pass
    /// measured 14ms on a 6,769-element paste, paid per keystroke. Both are
    /// pure functions of (revision) — and, for scene page numbers, the
    /// debounced stats — so they are cached by exactly those keys.
    @ObservationIgnored private var scenesCache: (revision: Int, stats: ScreenplayStats, rows: [SceneRow])?
    @ObservationIgnored private var actsCache: (revision: Int, stats: ScreenplayStats, rows: [ActRow])?
    @ObservationIgnored private var castCache: (revision: Int, rows: [CastRow])?

    private var currentEngineModel: EDraftEngine.Screenplay {
        if cachedEngineModelRevision == revision, let cachedEngineModel { return cachedEngineModel }
        let model = screenplay.engineModel
        cachedEngineModel = model
        cachedEngineModelRevision = revision
        return model
    }

    /// The whole document: the page with everything beside it put back.
    ///
    /// Only the writers-out use this — serialising to Fountain, and through
    /// that every export. Pagination, stats and prediction read
    /// `currentEngineModel` instead, which is the page: a note occupies no
    /// line, and the indices those answers are keyed by are the page's.
    /// Uncached on purpose — it is built when a file is written, not per
    /// keystroke, and a second cache keyed on a second revision is how the
    /// document and the page come to disagree about what is in the file.
    private var currentDocumentModel: EDraftEngine.Screenplay {
        guard !asides.isEmpty else { return currentEngineModel }
        var document = screenplay
        document.elements = ScriptAsides.merge(page: screenplay.elements, asides: asides)
        return document.engineModel
    }
    @ObservationIgnored private var undoStack: [EditorSnapshot] = []
    @ObservationIgnored private var redoStack: [EditorSnapshot] = []
    /// Remembers what re-cased elements looked like before conversion, so
    /// converting back restores the writer's own casing (see the type).
    @ObservationIgnored private var caseMemory = ElementCaseMemory()
    @ObservationIgnored private var lastTypingSnapshotAt = Date.distantPast
    @ObservationIgnored private var predictionGeneration = 0
    @ObservationIgnored private var nativeCanUndo = false
    @ObservationIgnored private var nativeCanRedo = false

    public var engineVersion: String? { EngineInfo.version }

    /// UserDefaults key for the writing-assistance mode (see init and
    /// setPredictionMode).
    private static let predictionModeKey = "writingAssistance"

    /// UserDefaults keys for the writer's own name and whether notes carry it
    /// (see init, `setNoteSignature` and `setSignsNotes`).
    private static let noteSignatureKey = NoteIdentity.nameKey
    private static let noteRoleKey = NoteIdentity.roleKey
    private static let signsNotesKey = "signsNotes"

    public init(
        source: String,
        startsAtEnd: Bool = false
    ) {
        self.lastKnownSource = source
        self.opensAtEnd = startsAtEnd
        /* Native Fountain parse; the naive parser remains only as the
           guard-rail for sources beyond the engine's size limit. Emphasis
           arrives as runs, never marker characters (RFC v2.1). */
        let parsed = (try? Fountain.parse(source, emphasis: .runs)).map(Screenplay.init(engineModel:))
            ?? Self.naiveParse(source)
        // A new Fountain session starts a new document-local counter.
        // A finite in-memory parse cannot exhaust the 64-digit ID space.
        let adopted: [ScriptElement]
        do { adopted = try documentIdentity.reconcile(parsed.elements) }
        catch { preconditionFailure("A fresh document exhausted its element identity space") }
        let split = ScriptAsides.split(adopted)
        self.screenplay = Screenplay(titlePage: parsed.titlePage, elements: split.page)
        self.asides = split.asides
        if screenplay.elements.isEmpty { screenplay.elements = Screenplay.blank.elements }
        let initialElement = startsAtEnd ? screenplay.elements.last : screenplay.elements.first
        activeElementID = initialElement?.id
        selectionOffset = startsAtEnd
            ? initialElement.map { ($0.text as NSString).length } ?? 0
            : 0
        // A Settings row must survive relaunch: the assistance mode is
        // app-level state, read once here and written on every change.
        if let stored = UserDefaults.standard.string(forKey: Self.predictionModeKey),
           let mode = PredictionMode(rawValue: stored) {
            predictionMode = mode
        }
        // The name the writer gave, or nothing — never the account's, the
        // computer's or a contact card's (RFC-NOTES-SYSTEM §8, D6). A writer
        // with none is asked at their first note.
        noteSignature = NoteIdentity.name
        noteRole = NoteIdentity.role
        signsNotes = UserDefaults.standard.bool(forKey: Self.signsNotesKey)
        // Never paginate synchronously at open: a cheap estimate renders
        // immediately, the debounced pass refines it off the critical path.
        synchronizeDraftIdentity()
        stats = Self.quickStats(for: screenplay)
        scheduleStatsRefresh()
        refreshPredictions()
    }

    /// Opens the durable document model. App .draft save wiring is a later milestone.
    public convenience init(identifiedScreenplay model: EDraftEngine.Screenplay) throws {
        var identity = DocumentIdentity()
        let restored = try identity.reopen(model)
        self.init(source: "")
        synchronizingIdentity = true
        documentIdentity = identity
        let split = ScriptAsides.split(restored.elements)
        screenplay = Screenplay(titlePage: restored.titlePage, elements: split.page, nextId: restored.nextId)
        asides = split.asides
        if screenplay.elements.isEmpty { screenplay.elements = [ScriptElement(type: .action, text: "")] }
        synchronizingIdentity = false
        synchronizeDraftIdentity()
        activeElementID = screenplay.elements.first?.id
        revision += 1
    }

    /// Complete durable model, including nonprinting script elements. Notes remain
    /// a legacy projection of their separate namespace; omissions remain indices.
    public var identifiedDocumentModel: EDraftEngine.Screenplay {
        var document = screenplay
        document.elements = ScriptAsides.merge(page: screenplay.elements, asides: asides)
        document.nextId = documentIdentity.allocator.nextId
        return document.identifiedEngineModel
    }

    private func synchronizeDraftIdentity(previous: Screenplay? = nil, previousAsides: [ScriptAside]? = nil) {
        guard !synchronizingIdentity else { return }
        synchronizingIdentity = true
        defer { synchronizingIdentity = false }
        do {
            let pageCount = screenplay.elements.count
            let normalized = try documentIdentity.reconcile(screenplay.elements + asides.map(\.element))
            screenplay.elements = Array(normalized.prefix(pageCount))
            for i in asides.indices { asides[i].element = normalized[pageCount + i] }
            screenplay.nextId = documentIdentity.allocator.nextId
        } catch {
            // Reject the edit atomically if the counter is exhausted. Never reuse
            // an ID or erase the text merely to make allocation succeed.
            if let previous { screenplay = previous }
            if let previousAsides { asides = previousAsides }
            showBanner("This document cannot allocate another element identity")
        }
    }

    deinit {
        predictionTask?.cancel()
        sourceTask?.cancel()
        statsTask?.cancel()
        bannerTask?.cancel()
    }

    public func titlePageValue(for key: String) -> String? {
        let values = TitlePage.values(screenplay.titlePage, for: key)
        return values.isEmpty ? nil : values.joined(separator: "\n")
    }

    /// The entry's lines as stored (empty when the key is absent).
    public func titlePageValues(for key: String) -> [String] {
        TitlePage.values(screenplay.titlePage, for: key)
    }

    /// Every keyed field the page currently answers — the sheet's rows.
    /// Derivation, never storage: the lines are the model (RFC-TITLE-PAGE
    /// D3), so a row can only show what the page itself says.
    public var titlePageEntries: [TitlePage.DerivedEntry] {
        TitlePage.derive(screenplay.titlePage).entries
    }

    /// Writes one title-page entry with a single undo snapshot — the same
    /// discipline as updateTitlePage, generalized to any key and any number
    /// of lines. Empty values remove the entry. The splice rewrites only
    /// the lines the key owns (RFC-TITLE-PAGE D7); comparing its result
    /// against the page IS the change detection, so an unchanged value
    /// costs nothing — no snapshot, no publish churn.
    public func setTitlePageEntry(_ key: String, values: [String]) {
        let normalized = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let next = TitlePage.spliced(screenplay.titlePage, key: key, values: normalized)
        guard next != screenplay.titlePage else { return }

        clearNativeUndoHistory()
        recordSnapshot(structural: true)
        screenplay.titlePage = next
        commitChange()
    }

    public var activeElementIndex: Int? {
        guard let activeElementID else { return nil }
        return screenplay.elements.firstIndex(where: { $0.id == activeElementID })
    }

    public var activeKind: ScreenplayKind {
        guard let index = activeElementIndex else { return .action }
        return screenplay.elements[index].type
    }

    public var contextualKinds: [ScreenplayKind] {
        guard let index = activeElementIndex else {
            return Choreography.tabSetFor(previous: nil).map(ScreenplayKind.init(engineKind:))
        }
        let previous = index > 0 ? screenplay.elements[index - 1].type : nil
        return Choreography.tabSetFor(previous: previous?.engineKind)
            .map(ScreenplayKind.init(engineKind:))
    }

    public var currentPrediction: EnginePrediction? {
        guard predictions.indices.contains(predictionIndex) else { return nil }
        return predictions[predictionIndex]
    }

    public var currentSuggestionText: String? {
        guard let prediction = currentPrediction,
              let index = activeElementIndex else { return nil }
        let typed = screenplay.elements[index].text
        guard let suffix = ghostSuffix(
            candidate: prediction.text,
            typed: typed,
            hint: prediction.hint ?? false
        ), !suffix.isEmpty else { return nil }
        return typed + suffix
    }

    public var currentSuggestionSuffix: String? {
        guard let prediction = currentPrediction,
              let index = activeElementIndex else { return nil }
        let typed = screenplay.elements[index].text
        return ghostSuffix(
            candidate: prediction.text,
            typed: typed,
            hint: prediction.hint ?? false
        )
    }

    private func ghostSuffix(candidate: String, typed: String, hint: Bool) -> String? {
        PredictionEngine.ghostSuffix(candidate: candidate, blockText: typed, hint: hint)
    }

    public var scenes: [SceneRow] {
        if let cache = scenesCache, cache.revision == revision, cache.stats == stats {
            return cache.rows
        }
        var number = 0
        let rows = screenplay.elements.enumerated().compactMap { index, element in
            guard element.type == .scene, !element.text.isEmpty else { return nil as SceneRow? }
            /* The heading inside an omitted span is not a scene of its own
               in the Navigator: its card, which prints, is the scene. Left
               in, a Final Draft file with one omission showed scene 21
               twice — the card and the scene behind it (§7.3). */
            guard !omittedScenes.contains(element) else { return nil as SceneRow? }
            number += 1
            return SceneRow(
                id: element.id,
                number: number,
                page: stats.elementPages[index],
                sceneNumber: element.sceneNumber,
                title: element.text,
                elementIndex: index,
                omitted: omittedScenes.isCard(element),
                cutPages: omittedScenes.scene(for: element).map(\.pillText)
            ) as SceneRow?
        }
        scenesCache = (revision, stats, rows)
        return rows
    }

    /// The scene the writer is in — the Navigator's "you are here" mark.
    ///
    /// A scene owns everything from its heading down to the next heading, so
    /// the answer is the last row whose heading sits at or before the active
    /// element — never the active element's own type, which is dialogue or
    /// action far more often than it is a slug. Nil above the first heading,
    /// where the script has a title page and a FADE IN but no scene yet.
    ///
    /// Derived here rather than in the list so the rule has one home: a row
    /// that jumps the caret into a scene lights up because the caret landed,
    /// and the mark follows the caret however it moves — click, keys, or a
    /// Navigator row.
    public var activeSceneID: UUID? {
        guard let activeIndex = activeElementIndex else { return nil }
        return scenes.last(where: { $0.elementIndex <= activeIndex })?.id
    }

    /// The acts, derived (RFC-ACT-BREAK §2): every `actbreak` opens one,
    /// and it runs to the next card or the document's end. Cached by
    /// revision like the scene list — a 300-page script recounts its
    /// cards only when the text actually moved.
    public var acts: [ActRow] {
        if let cache = actsCache, cache.revision == revision, cache.stats == stats {
            return cache.rows
        }
        var ordinal = 0
        var starts: [(id: UUID, ordinal: Int, title: String, index: Int, page: Int?)] = []
        for (index, element) in screenplay.elements.enumerated() where element.type == .actbreak {
            ordinal += 1
            starts.append((element.id, ordinal, element.text, index, stats.elementPages[index]))
        }
        let rows = starts.enumerated().map { position, start in
            let ceiling = position + 1 < starts.count
                ? starts[position + 1].page ?? stats.pages + 1
                : stats.pages + 1
            return ActRow(
                id: start.id,
                ordinal: start.ordinal,
                title: start.title,
                elementIndex: start.index,
                firstPage: start.page,
                lastPage: start.page.map { max($0, ceiling - 1) }
            )
        }
        actsCache = (revision, stats, rows)
        return rows
    }

    /// The act the writer is in — the same "you are here" rule as the
    /// scene mark: the last card at or before the caret. Nil above the
    /// first act break, which is every film script and most television
    /// cold opens.
    public var activeActID: UUID? {
        guard let activeIndex = activeElementIndex else { return nil }
        return acts.last(where: { $0.elementIndex <= activeIndex })?.id
    }

    public var cast: [CastRow] {
        if let cache = castCache, cache.revision == revision { return cache.rows }
        var counts: [String: Int] = [:]
        var firstCue: [String: UUID] = [:]
        for element in screenplay.elements where element.type == .character {
            let name = Self.canonicalCharacterName(element.text)
            guard !name.isEmpty else { continue }
            counts[name, default: 0] += 1
            // First appearance, not last: a writer opening a character is
            // looking for where they come in.
            if firstCue[name] == nil { firstCue[name] = element.id }
        }
        var rows: [CastRow] = []
        rows.reserveCapacity(counts.count)
        for (name, cues) in counts {
            guard let first = firstCue[name] else { continue }
            rows.append(CastRow(id: name, name: name, cues: cues, firstCueID: first))
        }
        rows.sort { $0.cues == $1.cues ? $0.name < $1.name : $0.cues > $1.cues }
        castCache = (revision, rows)
        return rows
    }

    /// A character's thread through the script: every scene they speak in,
    /// and what they say while they are there.
    ///
    /// One walk answers both questions a writer asks about a character. Read
    /// down the speeches and you hear whether they sound like one person.
    /// Read down the headings and you see where they appear, how often, and
    /// the stretches where they vanish — which is their shape in the story.
    ///
    /// Every row carries the id of a real element, so the view navigates to
    /// places rather than to guesses.
    public func appearances(of character: String) -> [CharacterAppearance] {
        let elements = screenplay.elements
        var appearances: [CharacterAppearance] = []
        var scene: (id: UUID, label: String, heading: String, page: Int?)?
        var ordinal = 0
        var lines: [SpokenLine] = []

        /// Closes the scene being read, keeping it only if the character
        /// actually spoke in it.
        func closeScene() {
            guard !lines.isEmpty else { return }
            let place = scene ?? (
                id: lines[0].id, label: "—", heading: "Before the first scene", page: nil
            )
            appearances.append(CharacterAppearance(
                id: place.id, label: place.label, heading: place.heading,
                page: place.page, lines: lines
            ))
            lines = []
        }

        var index = 0
        while index < elements.count {
            let element = elements[index]

            switch element.type {
            case .scene:
                closeScene()
                ordinal += 1
                scene = (
                    element.id,
                    element.sceneNumber ?? String(ordinal),
                    element.text,
                    stats.elementPages[index]
                )
                index += 1

            case .character where Self.canonicalCharacterName(element.text) == character:
                // A cue owns everything spoken under it until the block ends.
                index += 1
                var direction: String?
                block: while index < elements.count {
                    switch elements[index].type {
                    case .parenthetical:
                        direction = elements[index].text
                    case .dialogue:
                        lines.append(SpokenLine(
                            id: elements[index].id,
                            parenthetical: direction,
                            text: elements[index].text
                        ))
                        direction = nil
                    default:
                        break block
                    }
                    index += 1
                }

            default:
                index += 1
            }
        }
        closeScene()
        return appearances
    }

    /// The Navigator's context numbers, derived from the same scenes and
    /// cast the panel lists — headings are split by the engine's own
    /// conformance-pinned parser, so the footnote can never disagree with
    /// the rows above it.
    public var storyStats: StoryStats {
        var stats = StoryStats()
        var locations = Set<String>()
        for scene in scenes {
            stats.scenes += 1
            let parts = SmartType.splitSceneHeading(scene.title)
            if !parts.location.isEmpty { locations.insert(parts.location) }
            // Interior unless purely exterior: INT./EXT. and I/E both carry
            // interior work, which is what schedules around.
            if parts.prefix.hasPrefix("EXT") { stats.exterior += 1 }
            else if !parts.prefix.isEmpty { stats.interior += 1 }
        }
        stats.locations = locations.count

        let rows = cast
        stats.characters = rows.count
        stats.cues = rows.reduce(0) { $0 + $1.cues }
        if let lead = rows.first, stats.cues > 0 {
            stats.leadingCharacter = lead.name
            stats.leadingShare = Double(lead.cues) / Double(stats.cues)
        }
        return stats
    }

    /// A cue's identity ignores its extensions: "(CONT'D)", "(V.O.)" and any
    /// other trailing parenthetical modify the delivery, never the character.
    /// Trailing whitespace or a non-breaking space — left behind when a
    /// ghosted extension is accepted — must not defeat the match.
    public static func canonicalCharacterName(_ text: String) -> String {
        // The regex this replaces — `(?:\s*\([^)]*\))+\s*$` — cost a regex
        // engine per cue per panel render (14ms a pass on a feature paste).
        // The rule by hand: trailing "(extension)" groups and whitespace come
        // off the end; nothing else is touched.
        var rest = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while rest.hasSuffix(")") {
            guard let open = rest.lastIndex(of: "(") else { break }
            /* The regex allowed exactly one close per group: an unbalanced
               tail ("TYLER)", "NAME (A) B)") strips nothing at all. */
            guard rest[open...].filter({ $0 == ")" }).count == 1 else { break }
            rest = rest[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return rest.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    /// Whatever follows a cue's name — " (V.O.)", " (CONT'D)".
    ///
    /// An extension is production information about *how* the line is heard,
    /// not part of who says it, so a rename keeps it exactly as written. The
    /// pattern is the one `canonicalCharacterName` strips, read from the other
    /// end: what it removes is what this returns.
    public static func cueExtension(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(
            of: #"(?:\s*\([^)]*\))+\s*$"#, options: .regularExpression
        ) else { return "" }
        return String(trimmed[range])
    }

    /// Matches a name only where it stands as a whole word.
    ///
    /// Lookarounds rather than `\b`, so a name ending in punctuation — "DR."
    /// — still anchors correctly, and the pattern is escaped because a cue
    /// may legitimately contain regex characters: "MR. O'BRIEN (V.O.)".
    ///
    /// Whole-word matching is what stops MARAUDER becoming ELENAUDER. It does
    /// not stop a character called WILL from matching "will you come" — no
    /// pattern can — which is why the count is shown before anything changes.
    private static func mentionPattern(for name: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(
            for: name.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !escaped.isEmpty else { return nil }
        return "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
    }

    /// How often the character is named outside their own cues — in action,
    /// in other characters' dialogue, in a slug like INT. MARA'S FLAT.
    public func characterMentions(_ name: String) -> Int {
        guard let pattern = Self.mentionPattern(for: name),
              let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { return 0 }

        return screenplay.elements.reduce(0) { total, element in
            guard element.type != .character else { return total }
            let length = (element.text as NSString).length
            return total + regex.numberOfMatches(
                in: element.text, range: NSRange(location: 0, length: length)
            )
        }
    }

    /// Renames a character and reports how many elements it touched.
    ///
    /// Cues always. Mentions in prose only when asked, because the safety of
    /// that depends entirely on the name: renaming MARA is unambiguous, while
    /// renaming WILL would rewrite half the action. The caller shows both
    /// counts first and lets the writer decide, which is the part Final Draft
    /// and WriterDuet leave to a global replace.
    ///
    /// Cues take the name uppercased, as their lane requires; prose takes it
    /// exactly as the writer typed it, so "Elena crosses to the window" reads
    /// as prose rather than as shouting.
    @discardableResult
    public func renameCharacter(
        _ current: String, to proposed: String, includingMentions: Bool = false
    ) -> Int {
        guard let apply = onApplyElements else { return 0 }
        let typed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        let cueName = Self.canonicalCharacterName(typed)
        guard !cueName.isEmpty, cueName != current else { return 0 }

        var elements = screenplay.elements
        var changed = 0

        for index in elements.indices where elements[index].type == .character {
            guard Self.canonicalCharacterName(elements[index].text) == current else { continue }
            let previous = elements[index]
            let renamed = cueName + Self.cueExtension(previous.text)
            elements[index].text = renamed
            elements[index].runs = runsThroughRename(
                previous.runs, from: previous.text, to: renamed
            )
            changed += 1
        }

        if includingMentions,
           let pattern = Self.mentionPattern(for: current),
           let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let template = NSRegularExpression.escapedTemplate(for: typed)
            for index in elements.indices where elements[index].type != .character {
                let text = elements[index].text
                let range = NSRange(location: 0, length: (text as NSString).length)
                // One pass replaces every mention — and moves every run
                // after each of them. Runs travel one replacement at a time,
                // latest first, so the earlier offsets stay true.
                let matches = regex.matches(in: text, range: range)
                guard !matches.isEmpty else { continue }
                var newText = text as NSString
                var runs = elements[index].runs
                for match in matches.reversed() {
                    let inserted = typed.utf16.count
                    let delta = inserted - match.range.length
                    newText = newText.replacingCharacters(in: match.range, with: typed) as NSString
                    runs = runs.map { runs in runs.map { reseat($0, around: match.range, delta: delta, insertedLength: inserted) } }
                }
                elements[index].text = newText as String
                elements[index].runs = runs?.isEmpty == true ? nil : runs
                changed += 1
            }
        }

        guard changed > 0 else { return 0 }
        apply(elements, "Rename Character")
        return changed
    }

    /// The runs a name change carries with it: the diff re-seats them by
    /// exactly the edit the text just went through, so a bold cue — or a
    /// highlighted one — keeps its mark on the right words after a rename.
    private func runsThroughRename(
        _ runs: [StyleRun]?, from oldText: String, to newText: String
    ) -> [StyleRun]? {
        guard let runs,
              let (range, inserted) = ScreenplayEditPlanner.replacementBetween(oldText, newText)
        else { return runs }
        let delta = inserted.utf16.count - range.length
        let reseated = runs.map { reseat($0, around: range, delta: delta, insertedLength: inserted.utf16.count) }
        return reseated.isEmpty ? nil : reseated
    }

    /// Where a run lands when a name is replaced underneath it. A name is an
    /// atomic unit: a run that overlaps the replaced mention at all covers
    /// the new name whole — anything less would pin the mark to letters that
    /// merely kept their offsets, which is how a rename loses its styles.
    private func reseat(
        _ run: StyleRun, around range: NSRange, delta: Int, insertedLength: Int
    ) -> StyleRun {
        if run.end <= range.location { return run }
        if run.start >= NSMaxRange(range) {
            var shifted = run
            shifted.start += delta
            shifted.end += delta
            return shifted
        }
        var covered = run
        covered.start = min(run.start, range.location)
        covered.end = range.location + insertedLength + max(0, run.end - NSMaxRange(range))
        return covered
    }

    /// Whether a rename would fold this character into one that already
    /// speaks — worth saying out loud before it happens.
    public func characterExists(_ name: String) -> Bool {
        let canonical = Self.canonicalCharacterName(name)
        guard !canonical.isEmpty else { return false }
        return screenplay.elements.contains {
            $0.type == .character && Self.canonicalCharacterName($0.text) == canonical
        }
    }

    public func selectionChanged(elementID: UUID, offset: Int) {
        let moved = elementID != activeElementID
        activeElementID = elementID
        selectionOffset = max(0, offset)
        if moved { predictionIndex = 0 }
        refreshPredictions()
    }

    public func replaceElementText(id: UUID, text: String, structural: Bool = false) {
        guard let index = screenplay.elements.firstIndex(where: { $0.id == id }) else { return }
        recordSnapshot(structural: structural)
        let previous = screenplay.elements[index]
        let normalized = Self.normalizedText(text, for: previous.type)
        screenplay.elements[index].text = normalized
        if let runs = previous.runs,
           let (range, inserted) = ScreenplayEditPlanner.replacementBetween(previous.text, normalized) {
            // The diff is derived here, so the runs shift by exactly the
            // change the text just went through.
            let propagated = Emphasis.propagate(
                runs,
                replacing: (range.location, NSMaxRange(range)),
                insertedLength: inserted.utf16.count,
                newLength: normalized.utf16.count
            )
            screenplay.elements[index].runs = propagated.isEmpty ? nil : propagated
        }
        activeElementID = id
        selectionOffset = screenplay.elements[index].text.utf16.count
        commitChange(liveTyping: !structural)
    }

    /// Mirrors a native UITextView edit without asking the surface to render
    /// back into itself. Persistence, pagination, and prediction are debounced.
    ///
    /// `replaced` is the element-relative range the surface just replaced, and
    /// `insertedLength` the length of what it inserted — together they let the
    /// runs travel through the edit with the text.
    public func applyLiveText(
        id: UUID,
        text: String,
        selectionOffset: Int,
        replaced: NSRange,
        insertedLength: Int
    ) {
        guard let index = screenplay.elements.firstIndex(where: { $0.id == id }) else { return }
        let previous = screenplay.elements[index]
        let normalized = Self.normalizedText(text, for: previous.type)
        screenplay.elements[index].text = normalized
        if let runs = previous.runs {
            if normalized.utf16.count == text.utf16.count {
                let propagated = Emphasis.propagate(
                    runs,
                    replacing: (replaced.location, NSMaxRange(replaced)),
                    insertedLength: insertedLength,
                    newLength: normalized.utf16.count
                )
                screenplay.elements[index].runs = propagated.isEmpty ? nil : propagated
            } else {
                // Normalisation rewrote beyond the reported edit (ß→SS): no
                // offset can be trusted, so the style is let go rather than
                // pinned to the wrong words.
                screenplay.elements[index].runs = nil
            }
        }
        activeElementID = id
        self.selectionOffset = max(0, selectionOffset)
        revision += 1
        noteWritersEdit()
        scheduleSourcePublish()
        scheduleStatsRefresh()
        refreshPredictions()
    }

    /// Replaces the screenplay model. Native surfaces may disable snapshot
    /// recording when they register the same atomic edit with UndoManager.
    @discardableResult
    public func replaceAllElements(
        _ elements: [ScriptElement],
        activeID: UUID?,
        offset: Int,
        structural: Bool,
        recordsUndo: Bool = true
    ) -> Bool {
        let incoming = elements.isEmpty ? [ScriptElement(type: .action, text: "")] : elements
        var candidate = documentIdentity
        let adopted: [ScriptElement]
        do { adopted = try candidate.reconcile(incoming + asides.map(\.element)) }
        catch {
            showBanner("This document cannot allocate another element identity")
            return false
        }
        if recordsUndo { recordSnapshot(structural: structural) }
        documentIdentity = candidate
        synchronizingIdentity = true
        screenplay.elements = Array(adopted.prefix(incoming.count))
        for i in asides.indices { asides[i].element = adopted[incoming.count + i] }
        screenplay.nextId = documentIdentity.allocator.nextId
        synchronizingIdentity = false
        caseMemory.prune(toAlive: Set(screenplay.elements.map(\.id)))
        activeElementID = activeID ?? screenplay.elements.first?.id
        selectionOffset = max(0, offset)
        commitChange(liveTyping: !structural)
        return true
    }

    public func cycleActiveKind(backwards: Bool) {
        guard let index = activeElementIndex else { return }
        let previous = index > 0 ? screenplay.elements[index - 1].type : nil
        let current = screenplay.elements[index].type
        let kind = Choreography.tabCycle(
            current: current.engineKind,
            within: Choreography.tabSetFor(previous: previous?.engineKind),
            backwards: backwards
        )
        onChangeElementKind?(ScreenplayKind(engineKind: kind))
    }

    /// Applies a document changed outside this editor — iCloud delivery,
    /// conflict resolution, a Files.app move — without throwing the writer
    /// back to page 1 or discarding undo. Unchanged elements keep their
    /// identity, so the caret and the text surface's range map survive; both
    /// undo timelines stay intact; nothing is published back (a sync must
    /// never become a write-after-read).
    public func applyExternalSource(_ source: String) {
        // No flush: publishing now would clobber the incoming sync with our
        // stale model. Cancel the debounced write instead — last-writer-wins
        // is the document store's semantics, and the sync is the newer write.
        sourceTask?.cancel()
        guard let parsed = try? Fountain.parse(source, emphasis: .runs) else {
            // Keeping our own copy is right; keeping quiet is not. The writer
            // has a device or a file somewhere holding something this app
            // cannot read, and only they can go and look at it.
            showBanner("A change from elsewhere couldn't be read")
            return
        }
        let fresh = Screenplay(engineModel: parsed)

        // Monotonic alignment: each old element lends its identity to the
        // earliest unclaimed fresh element of the same type and text.
        var lists: [String: [Int]] = [:]
        for (index, element) in fresh.elements.enumerated() {
            lists[Self.identityKey(for: element), default: []].append(index)
        }
        var offsets: [String: Int] = [:]
        var merged = fresh.elements
        var lastUsed = -1
        for old in screenplay.elements {
            let key = Self.identityKey(for: old)
            guard let list = lists[key] else { continue }
            var cursor = offsets[key] ?? 0
            while cursor < list.count && list[cursor] <= lastUsed { cursor += 1 }
            guard cursor < list.count else { continue }
            merged[list[cursor]].id = old.id
            merged[list[cursor]].inheritDraftIdentity(from: old)
            lastUsed = list[cursor]
            offsets[key] = cursor + 1
        }

        // The caret keeps its element when the element survived; otherwise it
        // falls back to the nearest surviving predecessor, then the top.
        let survivingIDs = Set(merged.map(\.id))
        let caretID: UUID?
        let caretOffset: Int
        if let activeElementID, survivingIDs.contains(activeElementID),
           let element = merged.first(where: { $0.id == activeElementID }) {
            caretID = activeElementID
            caretOffset = min(selectionOffset, element.text.utf16.count)
        } else if let activeElementID,
                  let oldIndex = screenplay.elements.firstIndex(where: { $0.id == activeElementID }),
                  let predecessor = screenplay.elements[..<oldIndex]
                      .reversed()
                      .first(where: { survivingIDs.contains($0.id) }) {
            caretID = predecessor.id
            caretOffset = merged.first(where: { $0.id == predecessor.id })?.text.utf16.count ?? 0
        } else {
            caretID = merged.first?.id
            caretOffset = 0
        }

        // One undoable step in the snapshot timeline; UIKit's native timeline
        // is deliberately left alone — that history is the writer's.
        recordSnapshot(structural: true)
        screenplay.titlePage = fresh.titlePage
        screenplay.elements = merged.isEmpty ? [ScriptElement(type: .action, text: "")] : merged
        caseMemory.prune(toAlive: Set(screenplay.elements.map(\.id)))
        activeElementID = caretID
        selectionOffset = max(0, caretOffset)
        revision += 1
        updateUndoAvailability()
        lastKnownSource = serializedSource()
        scheduleStatsRefresh()
        refreshPredictions()
        // Not necessarily iCloud: this fires for anything that changed the
        // file outside this editor — another device, an edit made in Files,
        // a conflict resolved by the system. Naming one source was wrong
        // three times out of four.
        showBanner("Updated elsewhere")
    }

    private static func identityKey(for element: ScriptElement) -> String {
        "\(element.type.rawValue)\u{1F}\(element.text)"
    }

    public func nextKind(after kind: ScreenplayKind, text: String) -> ScreenplayKind {
        ScreenplayKind(engineKind: Choreography.nextElement(after: kind.engineKind, currentText: text))
    }

    /// Classifies paragraphs created by a structural paste or replacement.
    /// Return choreography still comes from the shared engine; the small set of
    /// lexical checks lets pasted Fountain retain its obvious screenplay shape.
    ///
    /// `pasteDepth` is the reassembled paste's witness (`PasteReassembly`):
    /// how far past the scheme's base column the paragraph sat. Once a
    /// hard-wrapped speech is joined, its words read exactly like narration,
    /// and the depth is the only honest thing left that says dialogue from
    /// action. It decides nothing else — the lexical checks above stay the
    /// authority on headings, parentheticals, transitions and cues.
    ///
    /// `fallback` answers the line no signal claims. Typing has no use for
    /// it: the choreography's guess after the writer's own Return is the
    /// right one. A paste is not typing — the writer never pressed those
    /// Returns, so a signal-less pasted line is prose, not the next thing
    /// the choreography expects. The breaking-bad paste made the failure
    /// concrete: "1148. So my records show I paid" arrived after a speech,
    /// and nextKind(after: .dialogue) adopted it as a cue named
    /// "1148. SO MY RECORDS SHOW I PAID".
    ///
    /// `attached` is the raw paste route's witness that no blank line
    /// separates this line from the one above (`ScreenplayEditPlanner`,
    /// mirroring plaintext.ts). A wrapped speech continuation reads exactly
    /// like prose once it stands alone; attachment is what keeps it speech.
    /// The TypeScript engine types the same line from the same flag
    /// (classify.ts, arm 7), so the two paste paths agree.
    public func kindForInsertedElement(
        after previous: ScriptElement?,
        text: String,
        pasteDepth: Int? = nil,
        attached: Bool = false,
        fallback: ScreenplayKind? = nil
    ) -> ScreenplayKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let uppercase = trimmed.uppercased()

        if Self.looksLikeSceneHeading(trimmed) { return .scene }
        // The card is structural, never a speaker (RFC-ACT-BREAK §5) —
        // without this arm the cue check below adopts ACT ONE, and speech
        // position would read it as dialogue under a cue.
        if Acts.isActCard(trimmed) { return .actbreak }
        if trimmed.hasPrefix("(") { return .parenthetical }
        if Self.looksLikeTransition(uppercase) { return .transition }
        // Uppercase camera framing is a shot designation, never a speaker —
        // classify.ts rule 5, and it fires before speech position for the
        // same reason: a "VIEW ON …" under a cue is the shot, not the speech.
        if PasteHeuristics.looksLikeCameraShot(trimmed) { return .shot }
        // The closing card (RFC-SECONDARY-SLUG §4) and the secondary slug
        // (§2) answer before speech position on the camera arm's doctrine:
        // under a cue, "THE END" is the card and "BASIN - DAY" is the slug,
        // never the speech.
        if PasteHeuristics.isEndCard(trimmed) { return .centered }
        if PasteHeuristics.isSecondarySlug(trimmed) { return .scene }
        if previous?.type == .character || previous?.type == .parenthetical { return .dialogue }
        // An attached line under a speech continues it — unless it wears a
        // cue's shape, in which case a new speaker interrupts (pasted
        // streams carry no blank lines, so the cue check below adopts it).
        if attached, previous?.type == .dialogue,
           !Self.looksLikeCharacterCue(trimmed, uppercase: uppercase) { return .dialogue }
        if Self.looksLikeCharacterCue(trimmed, uppercase: uppercase) { return .character }
        if let depth = pasteDepth {
            // Eight columns past the action margin is where speeches live.
            return depth >= 8 ? .dialogue : .action
        }
        if let fallback { return fallback }
        guard let previous else { return .action }
        return nextKind(after: previous.type, text: previous.text)
    }

    // MARK: - Scene numbers

    public enum SceneNumberingMode { case all, newScenesOnly, clear }

    /// Whether the script has been addressed yet — what decides between
    /// adding numbers and renumbering over somebody's schedule.
    public var isSceneNumbered: Bool {
        SceneNumbering.isNumbered(screenplay.engineModel.elements)
    }


    /// Applies numbering and reports how many scenes it touched.
    ///
    /// The numbers are carried onto the existing elements rather than a fresh
    /// list: every element keeps its identity, so the caret, the undo timeline
    /// and the case memory all survive an operation that changed no text.
    @discardableResult
    public func applySceneNumbering(_ mode: SceneNumberingMode) -> Int {
        guard let apply = onApplyElements else { return 0 }

        let source = screenplay.engineModel.elements
        let numbered: [ScreenplayElement] = switch mode {
        case .all: SceneNumbering.numberingAll(source)
        case .newScenesOnly: SceneNumbering.numberingNewScenes(source)
        case .clear: SceneNumbering.cleared(source)
        }

        var elements = screenplay.elements
        guard numbered.count == elements.count else { return 0 }
        var changed = 0
        for index in elements.indices where elements[index].sceneNumber != numbered[index].sceneNumber {
            elements[index].sceneNumber = numbered[index].sceneNumber
            changed += 1
        }
        guard changed > 0 else { return 0 }

        apply(elements, mode == .clear ? "Remove Scene Numbers" : "Number Scenes")
        return changed
    }

    public func acceptPrediction() {
        guard currentPrediction != nil else { return }
        onAcceptPrediction?()
    }

    public func setNoteSignature(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard trimmed != noteSignature else { return }
        noteSignature = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.noteSignatureKey)
    }

    public func setSignsNotes(_ signs: Bool) {
        guard signs != signsNotes else { return }
        signsNotes = signs
        UserDefaults.standard.set(signs, forKey: Self.signsNotesKey)
    }

    /// How this writer signs a note: `Name (Role)`, or `Name` (D4) — empty
    /// while they have given no name.
    public var signature: String { NoteIdentity.signature(name: noteSignature, role: noteRole) }

    /// Whether the writer has yet to say who they are — asked once, the first
    /// time they leave a note (RFC-NOTES-SYSTEM §8).
    public var needsNoteName: Bool {
        noteSignature.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The writer's answer to "Your name for notes": kept on this device, and
    /// every note they leave from now on is signed with it.
    public func setNoteIdentity(name: String, role: String) {
        let role = role.trimmingCharacters(in: .whitespaces)
        setNoteSignature(name)
        if role != noteRole {
            noteRole = role
            UserDefaults.standard.set(role, forKey: Self.noteRoleKey)
        }
        setSignsNotes(!noteSignature.isEmpty)
    }

    public func setPredictionMode(_ mode: PredictionMode) {
        predictionMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.predictionModeKey)
        predictionIndex = 0
        refreshPredictions()
    }

    public func updateTitlePage(title: String, writer: String, credit: String) {
        let changes = [
            (key: "Title", value: title),
            (key: "Credit", value: credit),
            (key: "Author", value: writer)
        ]
        /* The three writes build against each other and land as one undo
           step; the splice's own equality is the change detection, so a
           re-typed same title — any casing — creates no revision. */
        var next = screenplay.titlePage
        for change in changes {
            let normalized = change.value.trimmingCharacters(in: .whitespacesAndNewlines)
            next = TitlePage.spliced(next, key: change.key, values: normalized.isEmpty ? [] : [normalized])
        }
        guard next != screenplay.titlePage else { return }

        clearNativeUndoHistory()
        recordSnapshot(structural: true)
        screenplay.titlePage = next
        commitChange()
    }

    // MARK: - Notes

    /// Leaves a note on the element the caret is in, and returns it.
    ///
    /// Anchored to an element rather than to a character range: Final Draft
    /// stores a note's position as an offset into the script and those offsets
    /// rot the moment anyone edits above them. An element id cannot.
    @discardableResult
    public func addNote(_ text: String = "", to anchor: UUID? = nil) -> ScriptAside? {
        let target = anchor ?? activeElementID
        guard target == nil || screenplay.elements.contains(where: { $0.id == target }) else {
            return nil
        }
        // Signed only when the writer asked for it, and never over a note
        // that already names somebody — see `NoteAttribution.signed`.
        let body = signsNotes ? NoteAttribution.signed(text, as: signature) : text
        let note = ScriptAside(
            element: ScriptElement(type: .note, text: body), anchor: target
        )
        applyAsides(inserting: note)
        return note
    }

    /// The bubble finished editing. Called once when the writer is done, not
    /// per keystroke — the same arrangement as the title-page sheet, and for
    /// the same reason: a model change re-lays the page, and the page must not
    /// be re-laid on every letter typed beside it.
    public func updateNote(id: UUID, text: String) {
        guard let index = asides.firstIndex(where: { $0.id == id }), asides[index].text != text
        else { return }
        var updated = asides
        updated[index].element.text = text
        // The card is a plain-text editor and the change it reports is the
        // whole string, not a range — no run offset survives it honestly.
        updated[index].element.runs = nil
        applyAsides(updated)
    }

    /// The writer has finished with this note — Done, or the card closing.
    ///
    /// `text` is what the card reads, or `nil` when it was never typed in.
    /// Either way a note with nothing written in it is not a note and goes:
    /// added and left blank, or emptied and closed, it should not reach the
    /// file as an empty `[[]]` for the next reader to wonder about. Pages
    /// drops a comment nobody typed into for the same reason.
    public func finishNote(id: UUID, text: String?) {
        guard let settled = text ?? asides.first(where: { $0.id == id })?.text else { return }
        if settled.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            deleteNote(id: id)
        } else if text != nil {
            updateNote(id: id, text: settled)
        }
    }

    public func deleteNote(id: UUID) {
        guard asides.contains(where: { $0.id == id }) else { return }
        applyAsides(asides.filter { $0.id != id })
    }

    /// Puts a new note where it belongs: in front of the element it is
    /// anchored to, after any notes already there. Document order, so the
    /// bubbles beside a line read top to bottom in the order they were left.
    private func applyAsides(inserting aside: ScriptAside) {
        var updated = asides
        let anchorIndex = aside.anchor.flatMap { anchor in
            screenplay.elements.firstIndex { $0.id == anchor }
        }
        let position = updated.lastIndex { existing in
            guard let existingAnchor = existing.anchor else { return anchorIndex == nil }
            guard let anchorIndex else { return true }
            let index = screenplay.elements.firstIndex { $0.id == existingAnchor }
            return (index ?? .max) <= anchorIndex
        }
        updated.insert(aside, at: position.map { $0 + 1 } ?? 0)
        applyAsides(updated)
    }

    private func applyAsides(_ updated: [ScriptAside]) {
        // The text view's undo stack knows nothing about a change made beside
        // the page, and a ⌘Z that skipped back past it would undo the wrong
        // thing. Same reasoning as `updateTitlePage`.
        clearNativeUndoHistory()
        recordSnapshot(structural: true)
        asides = updated
        commitChange()
    }

    public func flushPendingWork() {
        sourceTask?.cancel()
        publishSource()
        scheduleStatsRefresh()
    }

    public func jump(to id: UUID) {
        activeElementID = id
        onJumpToElement?(id)
        refreshPredictions()
    }

    /// Captures the start of a native typing group without taking UIKit out of
    /// the input path. UIKit remains the sole character-level undo timeline.
    public func prepareForNativeEdit() {
        if !redoStack.isEmpty {
            redoStack.removeAll()
            updateUndoAvailability()
        }
    }

    public func reportNativeUndoAvailability(canUndo: Bool, canRedo: Bool) {
        nativeCanUndo = canUndo
        nativeCanRedo = canRedo
        updateUndoAvailability()
    }

    public func undo() {
        if nativeCanUndo, onNativeUndo?() == true { return }
        guard let snapshot = undoStack.popLast() else { return }
        clearNativeUndoHistory()
        redoStack.append(snapshotNow())
        restore(snapshot)
    }

    public func redo() {
        if nativeCanRedo, onNativeRedo?() == true { return }
        guard let snapshot = redoStack.popLast() else { return }
        clearNativeUndoHistory()
        undoStack.append(snapshotNow())
        restore(snapshot)
    }

    private func refreshPredictions() {
        predictionTask?.cancel()
        predictionGeneration += 1
        let generation = predictionGeneration
        guard predictionMode != .off,
              let index = activeElementIndex else {
            predictions = []
            predictionIndex = 0
            onPredictionChange?()
            return
        }

        let element = screenplay.elements[index]
        let mode = predictionMode
        guard selectionOffset == element.text.utf16.count else {
            predictions = []
            predictionIndex = 0
            onPredictionChange?()
            return
        }

        predictionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(65))
            guard let self, !Task.isCancelled else { return }
            let model = self.currentEngineModel
            let kind = element.type.engineKind
            let text = element.text
            // The engine is pure Foundation and Sendable — prediction runs
            // off the main actor so a feature-length vocabulary never stalls
            // the caret. The generation and identity guards below discard a
            // result that arrives after the writer moved on.
            let enginePredictions = await Task.detached(priority: .userInitiated) {
                PredictionEngine.predict(model, type: kind, text: text, index: index)
            }.value
            guard !Task.isCancelled,
                  generation == predictionGeneration,
                  activeElementID == element.id,
                  activeElementIndex == index,
                  screenplay.elements.indices.contains(index),
                  screenplay.elements[index].text == element.text else { return }
            let result = enginePredictions.map {
                EnginePrediction(
                    text: $0.text,
                    why: $0.why,
                    becomes: $0.becomes.map(ScreenplayKind.init(engineKind:)),
                    hint: $0.hint
                )
            }
            let filtered = mode == .formatOnly
                ? result.filter { ($0.hint ?? false) || $0.becomes != nil }
                : result
            predictions = filtered
            predictionIndex = min(predictionIndex, max(0, filtered.count - 1))
            onPredictionChange?()
        }
    }

    /// The text an element should carry after a kind conversion. Uppercase
    /// kinds get caps, as screenplay convention demands; converting back to
    /// action or dialogue restores the writer's own casing for the session —
    /// unless the writer edited the re-cased text, in which case their edit
    /// wins (see ElementCaseMemory). The parenthetical lane owns its
    /// brackets: converting in wraps the text in exactly one pair,
    /// converting out sheds the outer wrapper — the same convergence the
    /// commit-time normalization guarantees. The wrapper sheds FIRST, so
    /// the casing memory memorizes the writer's words, never their brackets.
    public func textForKindConversion(of element: ScriptElement, to kind: ScreenplayKind) -> String {
        var input = element
        if element.type == .parenthetical, kind != .parenthetical {
            input.text = Normalize.unwrapParenthetical(element.text)
        }
        var text = caseMemory.text(for: input, convertedTo: kind)
        if kind == .parenthetical {
            text = Normalize.normalizeParenthetical(text)
        }
        return text
    }

    /// Where the caret belongs after an element changes lane.
    ///
    /// Wrapping text in brackets shifts every character right by the opener
    /// that was added, so carrying the old offset across unchanged strands the
    /// caret one character behind the letter the writer left it on. Unwrapping
    /// shifts the other way.
    ///
    /// Inside a parenthetical the caret then belongs *between* the brackets.
    /// Outside the closer looks tidier and is worse: the next thing typed
    /// lands after the direction — "(whispering)softly" — which is the very
    /// bracket damage the position was meant to avoid.
    public static func caretAfterConversion(
        from old: String, to new: String, caret: Int, kind: ScreenplayKind
    ) -> Int {
        let length = (new as NSString).length
        var offset = caret + (new.hasPrefix("(") ? 1 : 0) - (old.hasPrefix("(") ? 1 : 0)
        if kind == .parenthetical, new.hasPrefix("("), new.hasSuffix(")"), length >= 2 {
            offset = min(max(offset, 1), length - 1)
        }
        return min(max(offset, 0), length)
    }

    /// The casing rule for INPUT paths — typing, paste, import: uppercase
    /// kinds store uppercase text, everything else stores the writer's text
    /// verbatim. Element CONVERSION applies the same rule through
    /// ElementCaseMemory, which remembers the verbatim text so converting
    /// back can restore it. Case mappings that change the UTF-16 length
    /// (ß→SS) are left untouched so the model can never drift out of sync
    /// with the text storage that delivered the edit.
    /// What an element of `kind` says, once the convention has had its way.
    ///
    /// This used to decline case mappings that change the UTF-16 length — ß
    /// becoming SS — so that a surface repairing text in place could keep its
    /// range arithmetic. That was a text view's problem wearing a model's
    /// clothes, and it cost more than it saved: the TypeScript engine, which
    /// this file is pinned to, capitalises unconditionally, and once the Mac
    /// began shouting at the input boundary the two surfaces stored different
    /// files for the same keystroke.
    ///
    /// The rule is the craft's, so it is asked of the engine rather than
    /// answered here — the same way `ScreenplayKind.uppercasesInput` already
    /// asks which kinds shout. Two copies of one formula is how the editor's
    /// live casing, the conversion rule and the Final Draft importer come to
    /// different conclusions about what a cue looks like.
    ///
    /// The surfaces deal with the consequences of a length change where such
    /// consequences belong. Conversions remain reversible: `ElementCaseMemory`
    /// keeps the writer's verbatim text, not a re-derived guess at it.
    public static func normalizedText(_ text: String, for kind: ScreenplayKind) -> String {
        Normalize.canonicalCasing(kind: kind.engineKind, text: text)
    }

    /* The rules live in PasteHeuristics: the reassembly breaks paragraphs
       on them and this classifier types the results — two readers, one rule. */
    private static func looksLikeSceneHeading(_ text: String) -> Bool {
        PasteHeuristics.looksLikeSceneHeading(text)
    }

    private static func looksLikeTransition(_ text: String) -> Bool {
        PasteHeuristics.looksLikeTransition(text)
    }

    private static func looksLikeCharacterCue(_ text: String, uppercase: String) -> Bool {
        PasteHeuristics.looksLikeCharacterCue(text, uppercase: uppercase)
    }

    private func recordSnapshot(structural: Bool) {
        let now = Date()
        if structural || now.timeIntervalSince(lastTypingSnapshotAt) > 0.8 {
            undoStack.append(snapshotNow())
            if undoStack.count > 160 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        lastTypingSnapshotAt = now
        updateUndoAvailability()
    }

    private func snapshotNow() -> EditorSnapshot {
        EditorSnapshot(
            screenplay: screenplay,
            asides: asides,
            omitted: omittedScenes,
            activeElementID: activeElementID,
            selectionOffset: selectionOffset
        )
    }

    private func restore(_ snapshot: EditorSnapshot) {
        synchronizingIdentity = true
        screenplay = snapshot.screenplay
        asides = snapshot.asides
        synchronizingIdentity = false
        if omittedScenes != snapshot.omitted {
            omittedScenes = snapshot.omitted
            omissionsEdited = true
        }
        synchronizeDraftIdentity()
        activeElementID = snapshot.activeElementID
        selectionOffset = snapshot.selectionOffset
        revision += 1
        noteWritersEdit()
        updateUndoAvailability()
        publishSource()
        scheduleStatsRefresh()
        refreshPredictions()
    }

    private func commitChange(liveTyping: Bool = false) {
        revision += 1
        noteWritersEdit()
        updateUndoAvailability()
        if liveTyping {
            scheduleSourcePublish()
        } else {
            sourceTask?.cancel()
            publishSource()
        }
        scheduleStatsRefresh()
        refreshPredictions()
    }

    private func scheduleSourcePublish() {
        sourceTask?.cancel()
        sourceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard let self, !Task.isCancelled else { return }
            publishSource()
        }
    }

    private func scheduleStatsRefresh() {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled else { return }
            /* An omitted scene is not on a page: Final Draft does not count
               one, and neither do we (Omissions.paginable). The page numbers
               come back keyed by the script's own indices. */
            let paginable = Omissions.paginable(
                self.currentEngineModel, document: self.screenplay.elements, omitted: self.omittedScenes
            )
            let model = paginable.model
            let kept = paginable.kept
            let scheduledRevision = self.revision
            let linesPerPage = PageFormat.current.linesPerPage
            // Pagination walks and wraps every element — off the main actor,
            // so page math on a feature script never hitches the keystroke
            // that triggered it.
            let computed = await Task.detached(priority: .utility) {
                Self.screenplayStats(for: model, linesPerPage: linesPerPage, kept: kept)
            }.value
            guard !Task.isCancelled, self.revision == scheduledRevision else { return }
            self.stats = computed
        }
    }

    private func publishSource() {
        let source = serializedSource()
        lastKnownSource = source
        /* From the same model, at the same moment, as the source itself — so
           the spans and the text they index cannot describe two documents. */
        if omissionsEdited {
            let document = ScriptAsides.merge(page: screenplay.elements, asides: asides)
            publishedOmissions = OmissionSpans(
                spans: Omissions.spans(of: omittedScenes, in: document),
                elementCount: document.count
            )
        }
        onSourceChange?(source)
    }

    private func serializedSource() -> String {
        Fountain.serialise(currentDocumentModel)
    }

    /// Precise stats from the native paginator over the cached engine model,
    /// with the line-count estimate as the unreachable-in-practice guard.
    /// `nonisolated`: pure function of its inputs, called from detached tasks.
    /// The page each scene opens on, keyed by element index.
    ///
    /// Read back out of the paginated pages rather than counted separately:
    /// a page number the Navigator computed its own way would drift from the
    /// one the export prints, and a writer would have no way to tell which
    /// was lying. A slug broken across a page break keeps the earlier page —
    /// the scene starts where its first line does.
    public nonisolated static func elementPages(
        in pages: [EDraftEngine.ScriptPage]
    ) -> [Int: Int] {
        var found: [Int: Int] = [:]
        for page in pages {
            for line in page.lines {
                guard case .element = line.type, line.element >= 0,
                      found[line.element] == nil else { continue }
                found[line.element] = page.number
            }
        }
        return found
    }

    private nonisolated static func screenplayStats(
        for model: EDraftEngine.Screenplay,
        linesPerPage: Int,
        kept: [Int]
    ) -> ScreenplayStats {
        let words = model.elements.reduce(0) {
            $0 + $1.text.split(whereSeparator: \.isWhitespace).count
        }
        guard let pages = try? Paginator.paginate(model, linesPerPage: linesPerPage) else {
            let lines = model.elements.reduce(0) { $0 + max(1, $1.text.count / 60) }
            let estimated = max(1, Int(ceil(Double(lines) / Double(linesPerPage))))
            return ScreenplayStats(
                pages: estimated,
                runtime: estimated <= 1 ? "~1 minute" : "~\(estimated) minutes",
                words: words
            )
        }
        return ScreenplayStats(
            pages: max(1, pages.count),
            runtime: Paginator.estimateRuntime(pages),
            words: words,
            elementPages: Omissions.restored(elementPages(in: pages), through: kept)
        )
    }

    /// A line-count estimate, not a measurement. Used at editor open and
    /// around structural edits: precise pagination (the Swift engine, off the
    /// main actor) is always refreshed by the debounced pass, never on the
    /// critical path.
    private static func quickStats(for screenplay: Screenplay) -> ScreenplayStats {
        let words = screenplay.elements.reduce(0) {
            $0 + $1.text.split(whereSeparator: \.isWhitespace).count
        }
        let lines = screenplay.elements.reduce(0) { $0 + max(1, $1.text.count / 60) }
        let pages = max(1, Int(ceil(Double(lines) / Double(PageFormat.current.linesPerPage))))
        return ScreenplayStats(
            pages: pages,
            runtime: pages <= 1 ? "~1 minute" : "~\(pages) minutes",
            words: words
        )
    }

    /// Engine-free parser: title-page "Key: value" lines, then one element
    /// per block, recognizing only scene headings and transitions.
    private static func naiveParse(_ source: String) -> Screenplay {
        var blocks = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
        var entries: [TitlePage.LegacyEntry] = []
        if let first = blocks.first, first.contains(":") {
            entries = first.components(separatedBy: "\n").compactMap { line in
                guard let colon = line.firstIndex(of: ":") else { return nil }
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                return key.isEmpty ? nil : TitlePage.LegacyEntry(key: key, values: [value])
            }
            if !entries.isEmpty { blocks.removeFirst() }
        }
        let elements = blocks.map { block -> ScriptElement in
            let text = block.trimmingCharacters(in: .newlines)
            let upper = text.uppercased()
            if looksLikeSceneHeading(text) { return ScriptElement(type: .scene, text: upper) }
            if looksLikeTransition(upper) { return ScriptElement(type: .transition, text: upper) }
            return ScriptElement(type: .action, text: text)
        }
        return Screenplay(titlePage: TitlePage.lines(from: entries), elements: elements)
    }

    private func updateUndoAvailability() {
        canUndo = nativeCanUndo || !undoStack.isEmpty
        canRedo = nativeCanRedo || !redoStack.isEmpty
    }

    private func clearNativeUndoHistory() {
        onClearNativeUndo?()
        nativeCanUndo = false
        nativeCanRedo = false
    }

    private struct EditorSnapshot {
        let screenplay: Screenplay
        let asides: [ScriptAside]
        /// Omissions are part of the document: an undo that brings a card back
        /// brings back the scene it stands for.
        let omitted: OmittedScenes
        let activeElementID: UUID?
        let selectionOffset: Int
    }
}
