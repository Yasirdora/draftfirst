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
    @ObservationIgnored private var undoStack: [EditorSnapshot] = []
    @ObservationIgnored private var redoStack: [EditorSnapshot] = []
    @ObservationIgnored private var lastTypingSnapshotAt = Date.distantPast
    @ObservationIgnored private var predictionGeneration = 0
    @ObservationIgnored private var nativeCanUndo = false
    @ObservationIgnored private var nativeCanRedo = false

    var engineVersion: String? { EngineInfo.version }

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
    }

    func titlePageValue(for key: String) -> String? {
        screenplay.titlePage
            .first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?
            .values
            .joined(separator: "\n")
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
            let result = PredictionEngine.predict(
                screenplay.engineModel,
                type: element.type.engineKind,
                text: element.text,
                index: index
            ).map {
                EnginePrediction(
                    text: $0.text,
                    why: $0.why,
                    becomes: $0.becomes.map(ScreenplayKind.init(engineKind:)),
                    hint: $0.hint
                )
            }
            guard !Task.isCancelled,
                  generation == predictionGeneration,
                  activeElementID == element.id,
                  activeElementIndex == index,
                  screenplay.elements.indices.contains(index),
                  screenplay.elements[index].text == element.text else { return }
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
            stats = screenplayStats()
        }
    }

    private func publishSource() {
        let source = serializedSource()
        lastKnownSource = source
        onSourceChange?(source)
    }

    private func serializedSource() -> String {
        Fountain.serialise(screenplay.engineModel)
    }

    /// Precise stats from the native paginator. The Swift-only estimate
    /// remains as the unreachable-in-practice guard below it.
    private func screenplayStats() -> ScreenplayStats {
        guard let pages = try? Paginator.paginate(
            screenplay.engineModel,
            linesPerPage: PageFormat.current.linesPerPage
        ) else {
            return Self.quickStats(for: screenplay)
        }
        return ScreenplayStats(
            pages: max(1, pages.count),
            runtime: Paginator.estimateRuntime(pages),
            words: screenplay.elements.reduce(0) {
                $0 + $1.text.split(whereSeparator: \.isWhitespace).count
            }
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
