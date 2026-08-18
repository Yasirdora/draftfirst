import Foundation
import Observation
import DraftFirstEngine

@MainActor
@Observable
final class EditorState {
    var screenplay: Screenplay
    var activeElementID: UUID?
    var selectionOffset = 0
    var predictions: [EnginePrediction] = []
    var predictionIndex = 0
    var predictionMode: PredictionMode = .smart
    var stats = ScreenplayStats()
    var revision = 0
    var canUndo = false
    var canRedo = false

    @ObservationIgnored var onSourceChange: ((String) -> Void)?
    @ObservationIgnored var onPredictionChange: (() -> Void)?
    @ObservationIgnored var onAcceptPrediction: (() -> Void)?
    @ObservationIgnored var onChangeElementKind: ((ScreenplayKind) -> Void)?
    @ObservationIgnored var onJumpToElement: ((UUID) -> Void)?
    @ObservationIgnored var onNativeUndo: (() -> Bool)?
    @ObservationIgnored var onNativeRedo: (() -> Bool)?
    @ObservationIgnored var onClearNativeUndo: (() -> Void)?

    /// A transient, non-modal notice ("Updated from iCloud", the swipe
    /// element toast). The view renders it as a capsule under the chrome.
    var banner: String?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?

    func showBanner(_ text: String) {
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
    @ObservationIgnored private(set) var lastKnownSource: String?
    /// True when this state opened with the caret at the end of the document.
    /// The text surface reads it once to scroll the resume point into view
    /// after the first real layout.
    @ObservationIgnored let opensAtEnd: Bool
    @ObservationIgnored private var predictionTask: Task<Void, Never>?
    @ObservationIgnored private var sourceTask: Task<Void, Never>?
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    /// The identity-free engine model costs one struct allocation per element
    /// to build, and prediction, persistence, and pagination all need it
    /// several times per second. Cached per revision: every content mutation
    /// bumps `revision`, so the cache is self-invalidating and never stale.
    @ObservationIgnored private var cachedEngineModel: DraftFirstEngine.Screenplay?
    @ObservationIgnored private var cachedEngineModelRevision = -1

    private var currentEngineModel: DraftFirstEngine.Screenplay {
        if cachedEngineModelRevision == revision, let cachedEngineModel { return cachedEngineModel }
        let model = screenplay.engineModel
        cachedEngineModel = model
        cachedEngineModelRevision = revision
        return model
    }
    @ObservationIgnored private var undoStack: [EditorSnapshot] = []
    @ObservationIgnored private var redoStack: [EditorSnapshot] = []
    @ObservationIgnored private var lastTypingSnapshotAt = Date.distantPast
    @ObservationIgnored private var predictionGeneration = 0
    @ObservationIgnored private var nativeCanUndo = false
    @ObservationIgnored private var nativeCanRedo = false

    var engineVersion: String? { EngineInfo.version }

    /// UserDefaults key for the writing-assistance mode (see init and
    /// setPredictionMode).
    private static let predictionModeKey = "writingAssistance"

    init(
        source: String,
        startsAtEnd: Bool = false
    ) {
        self.lastKnownSource = source
        self.opensAtEnd = startsAtEnd
        /* Native Fountain parse; the naive parser remains only as the
           guard-rail for sources beyond the engine's size limit. */
        self.screenplay = (try? Fountain.parse(source)).map(Screenplay.init(engineModel:))
            ?? Self.naiveParse(source)
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
        // Never paginate synchronously at open: a cheap estimate renders
        // immediately, the debounced pass refines it off the critical path.
        stats = Self.quickStats(for: screenplay)
        scheduleStatsRefresh()
        refreshPredictions()
    }

    deinit {
        predictionTask?.cancel()
        sourceTask?.cancel()
        statsTask?.cancel()
        bannerTask?.cancel()
    }

    func titlePageValue(for key: String) -> String? {
        screenplay.titlePage
            .first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?
            .values
            .joined(separator: "\n")
    }

    /// The entry's lines as stored (empty when the key is absent).
    func titlePageValues(for key: String) -> [String] {
        screenplay.titlePage
            .first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?
            .values ?? []
    }

    /// Writes one title-page entry with a single undo snapshot — the same
    /// discipline as updateTitlePage, generalized to any key and any number
    /// of lines. Empty values remove the entry; unchanged values do nothing
    /// (no snapshot, no publish churn).
    func setTitlePageEntry(_ key: String, values: [String]) {
        let normalized = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard titlePageValues(for: key) != normalized else { return }

        clearNativeUndoHistory()
        recordSnapshot(structural: true)
        if let index = screenplay.titlePage.firstIndex(where: {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        }) {
            if normalized.isEmpty {
                screenplay.titlePage.remove(at: index)
            } else {
                screenplay.titlePage[index].values = normalized
            }
        } else if !normalized.isEmpty {
            screenplay.titlePage.append(TitlePageEntry(key: key, values: normalized))
        }
        commitChange()
    }

    var activeElementIndex: Int? {
        guard let activeElementID else { return nil }
        return screenplay.elements.firstIndex(where: { $0.id == activeElementID })
    }

    var activeKind: ScreenplayKind {
        guard let index = activeElementIndex else { return .action }
        return screenplay.elements[index].type
    }

    var contextualKinds: [ScreenplayKind] {
        guard let index = activeElementIndex else {
            return Choreography.tabSetFor(previous: nil).map(ScreenplayKind.init(engineKind:))
        }
        let previous = index > 0 ? screenplay.elements[index - 1].type : nil
        return Choreography.tabSetFor(previous: previous?.engineKind)
            .map(ScreenplayKind.init(engineKind:))
    }

    var currentPrediction: EnginePrediction? {
        guard predictions.indices.contains(predictionIndex) else { return nil }
        return predictions[predictionIndex]
    }

    var currentSuggestionText: String? {
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

    var currentSuggestionSuffix: String? {
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

    var scenes: [SceneRow] {
        var number = 0
        return screenplay.elements.enumerated().compactMap { index, element in
            guard element.type == .scene, !element.text.isEmpty else { return nil }
            number += 1
            return SceneRow(id: element.id, number: number, title: element.text, elementIndex: index)
        }
    }

    var cast: [CastRow] {
        var counts: [String: Int] = [:]
        for element in screenplay.elements where element.type == .character {
            let name = Self.canonicalCharacterName(element.text)
            if !name.isEmpty { counts[name, default: 0] += 1 }
        }
        return counts
            .map { CastRow(id: $0.key, name: $0.key, cues: $0.value) }
            .sorted { $0.cues == $1.cues ? $0.name < $1.name : $0.cues > $1.cues }
    }

    /// A cue's identity ignores its extensions: "(CONT'D)", "(V.O.)" and any
    /// other trailing parenthetical modify the delivery, never the character.
    /// Trailing whitespace or a non-breaking space — left behind when a
    /// ghosted extension is accepted — must not defeat the match.
    static func canonicalCharacterName(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"(?:\s*\([^)]*\))+\s*$"#,
                with: "",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    func selectionChanged(elementID: UUID, offset: Int) {
        let moved = elementID != activeElementID
        activeElementID = elementID
        selectionOffset = max(0, offset)
        if moved { predictionIndex = 0 }
        refreshPredictions()
    }

    func replaceElementText(id: UUID, text: String, structural: Bool = false) {
        guard let index = screenplay.elements.firstIndex(where: { $0.id == id }) else { return }
        recordSnapshot(structural: structural)
        screenplay.elements[index].text = Self.normalizedText(
            text,
            for: screenplay.elements[index].type
        )
        activeElementID = id
        selectionOffset = screenplay.elements[index].text.utf16.count
        commitChange(liveTyping: !structural)
    }

    /// Mirrors a native UITextView edit without asking the surface to render
    /// back into itself. Persistence, pagination, and prediction are debounced.
    func applyLiveText(id: UUID, text: String, selectionOffset: Int) {
        guard let index = screenplay.elements.firstIndex(where: { $0.id == id }) else { return }
        screenplay.elements[index].text = Self.normalizedText(
            text,
            for: screenplay.elements[index].type
        )
        activeElementID = id
        self.selectionOffset = max(0, selectionOffset)
        revision += 1
        scheduleSourcePublish()
        scheduleStatsRefresh()
        refreshPredictions()
    }

    /// Replaces the screenplay model. Native surfaces may disable snapshot
    /// recording when they register the same atomic edit with UndoManager.
    func replaceAllElements(
        _ elements: [ScriptElement],
        activeID: UUID?,
        offset: Int,
        structural: Bool,
        recordsUndo: Bool = true
    ) {
        if recordsUndo { recordSnapshot(structural: structural) }
        screenplay.elements = elements.isEmpty ? [ScriptElement(type: .action, text: "")] : elements
        activeElementID = activeID ?? screenplay.elements.first?.id
        selectionOffset = max(0, offset)
        commitChange(liveTyping: !structural)
    }

    func cycleActiveKind(backwards: Bool) {
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
    func applyExternalSource(_ source: String) {
        // No flush: publishing now would clobber the incoming sync with our
        // stale model. Cancel the debounced write instead — last-writer-wins
        // is the document store's semantics, and the sync is the newer write.
        sourceTask?.cancel()
        guard let parsed = try? Fountain.parse(source) else { return }
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
        activeElementID = caretID
        selectionOffset = max(0, caretOffset)
        revision += 1
        updateUndoAvailability()
        lastKnownSource = serializedSource()
        scheduleStatsRefresh()
        refreshPredictions()
        showBanner("Updated from iCloud")
    }

    private static func identityKey(for element: ScriptElement) -> String {
        "\(element.type.rawValue)\u{1F}\(element.text)"
    }

    func nextKind(after kind: ScreenplayKind, text: String) -> ScreenplayKind {
        ScreenplayKind(engineKind: Choreography.nextElement(after: kind.engineKind, currentText: text))
    }

    /// Classifies paragraphs created by a structural paste or replacement.
    /// Return choreography still comes from the shared engine; the small set of
    /// lexical checks lets pasted Fountain retain its obvious screenplay shape.
    func kindForInsertedElement(after previous: ScriptElement?, text: String) -> ScreenplayKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let uppercase = trimmed.uppercased()

        if Self.looksLikeSceneHeading(uppercase) { return .scene }
        if trimmed.hasPrefix("(") { return .parenthetical }
        if Self.looksLikeTransition(uppercase) { return .transition }
        if previous?.type == .character || previous?.type == .parenthetical { return .dialogue }
        if Self.looksLikeCharacterCue(trimmed, uppercase: uppercase) { return .character }
        guard let previous else { return .action }
        return nextKind(after: previous.type, text: previous.text)
    }

    func acceptPrediction() {
        guard currentPrediction != nil else { return }
        onAcceptPrediction?()
    }

    func setPredictionMode(_ mode: PredictionMode) {
        predictionMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: Self.predictionModeKey)
        predictionIndex = 0
        refreshPredictions()
    }

    func updateTitlePage(title: String, writer: String, credit: String) {
        let changes = [
            (key: "Title", value: title),
            (key: "Credit", value: credit),
            (key: "Author", value: writer)
        ]
        let changed = changes.contains { change in
            (titlePageValue(for: change.key) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                != change.value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard changed else { return }

        clearNativeUndoHistory()
        recordSnapshot(structural: true)
        for change in changes {
            setTitlePageValue(change.value, for: change.key)
        }
        commitChange()
    }

    func flushPendingWork() {
        sourceTask?.cancel()
        publishSource()
        scheduleStatsRefresh()
    }

    func jump(to id: UUID) {
        activeElementID = id
        onJumpToElement?(id)
        refreshPredictions()
    }

    /// Captures the start of a native typing group without taking UIKit out of
    /// the input path. UIKit remains the sole character-level undo timeline.
    func prepareForNativeEdit() {
        if !redoStack.isEmpty {
            redoStack.removeAll()
            updateUndoAvailability()
        }
    }

    func reportNativeUndoAvailability(canUndo: Bool, canRedo: Bool) {
        nativeCanUndo = canUndo
        nativeCanRedo = canRedo
        updateUndoAvailability()
    }

    func undo() {
        if nativeCanUndo, onNativeUndo?() == true { return }
        guard let snapshot = undoStack.popLast() else { return }
        clearNativeUndoHistory()
        redoStack.append(snapshotNow())
        restore(snapshot)
    }

    func redo() {
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

    private func setTitlePageValue(_ value: String, for key: String) {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = screenplay.titlePage.firstIndex(where: {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        }) {
            if normalized.isEmpty {
                screenplay.titlePage.remove(at: index)
            } else {
                screenplay.titlePage[index].values = [normalized]
            }
        } else if !normalized.isEmpty {
            screenplay.titlePage.append(TitlePageEntry(key: key, values: [normalized]))
        }
    }

    /// The single casing rule for the whole model: uppercase kinds store
    /// uppercase text, everything else stores the writer's text verbatim.
    /// Case mappings that change the UTF-16 length (ß→SS) are left untouched
    /// so the model can never drift out of sync with the text storage that
    /// delivered the edit.
    static func normalizedText(_ text: String, for kind: ScreenplayKind) -> String {
        guard kind.uppercasesInput else { return text }
        let uppercased = text.uppercased()
        return uppercased.utf16.count == text.utf16.count ? uppercased : text
    }

    private static func looksLikeSceneHeading(_ text: String) -> Bool {
        ["INT.", "EXT.", "EST.", "INT/EXT.", "I/E."].contains { prefix in
            text.hasPrefix(prefix)
        }
    }

    private static func looksLikeTransition(_ text: String) -> Bool {
        text == "FADE IN:" || text == "FADE OUT."
            || text.hasSuffix(" TO:") || text.hasSuffix(" OUT:")
    }

    private static func looksLikeCharacterCue(_ text: String, uppercase: String) -> Bool {
        guard !text.isEmpty,
              text == uppercase,
              text.utf16.count <= 48,
              text.rangeOfCharacter(from: .letters) != nil else { return false }
        return !text.hasSuffix(".") && !text.hasSuffix(":")
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
            activeElementID: activeElementID,
            selectionOffset: selectionOffset
        )
    }

    private func restore(_ snapshot: EditorSnapshot) {
        screenplay = snapshot.screenplay
        activeElementID = snapshot.activeElementID
        selectionOffset = snapshot.selectionOffset
        revision += 1
        updateUndoAvailability()
        publishSource()
        scheduleStatsRefresh()
        refreshPredictions()
    }

    private func commitChange(liveTyping: Bool = false) {
        revision += 1
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
            let model = self.currentEngineModel
            let scheduledRevision = self.revision
            let linesPerPage = PageFormat.current.linesPerPage
            // Pagination walks and wraps every element — off the main actor,
            // so page math on a feature script never hitches the keystroke
            // that triggered it.
            let computed = await Task.detached(priority: .utility) {
                Self.screenplayStats(for: model, linesPerPage: linesPerPage)
            }.value
            guard !Task.isCancelled, self.revision == scheduledRevision else { return }
            self.stats = computed
        }
    }

    private func publishSource() {
        let source = serializedSource()
        lastKnownSource = source
        onSourceChange?(source)
    }

    private func serializedSource() -> String {
        Fountain.serialise(currentEngineModel)
    }

    /// Precise stats from the native paginator over the cached engine model,
    /// with the line-count estimate as the unreachable-in-practice guard.
    /// `nonisolated`: pure function of its inputs, called from detached tasks.
    private nonisolated static func screenplayStats(
        for model: DraftFirstEngine.Screenplay,
        linesPerPage: Int
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
            words: words
        )
    }

    /// A Swift-only estimate that never touches the JavaScript bridge. Used
    /// at editor open and around structural edits: precise pagination is
    /// always refreshed by the debounced pass, never on the critical path.
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
        var titlePage: [TitlePageEntry] = []
        if let first = blocks.first, first.contains(":") {
            titlePage = first.components(separatedBy: "\n").compactMap { line in
                guard let colon = line.firstIndex(of: ":") else { return nil }
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                return key.isEmpty ? nil : TitlePageEntry(key: key, values: [value])
            }
            if !titlePage.isEmpty { blocks.removeFirst() }
        }
        let elements = blocks.map { block -> ScriptElement in
            let text = block.trimmingCharacters(in: .newlines)
            let upper = text.uppercased()
            if looksLikeSceneHeading(upper) { return ScriptElement(type: .scene, text: upper) }
            if looksLikeTransition(upper) { return ScriptElement(type: .transition, text: upper) }
            return ScriptElement(type: .action, text: text)
        }
        return Screenplay(titlePage: titlePage, elements: elements)
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
        let activeElementID: UUID?
        let selectionOffset: Int
    }
}
