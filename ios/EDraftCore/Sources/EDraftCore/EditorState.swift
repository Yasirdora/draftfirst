import Foundation
import Observation
import EDraftEngine

@MainActor
@Observable
public final class EditorState {
    public var screenplay: Screenplay
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

    /// Sheets or one column — see `PageLayoutMode`. Held here so a menu can
    /// show which one is on without asking the surface.
    public private(set) var layoutMode: PageLayoutMode = .stored

    /// The surface reporting the layout it settled on.
    public func reportLayoutMode(_ mode: PageLayoutMode) {
        guard layoutMode != mode else { return }
        layoutMode = mode
    }

    /// The surface reporting the size it settled on.
    public func reportZoom(_ value: CGFloat) {
        guard abs(zoom - value) > 0.0001 else { return }
        zoom = value
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

    private var currentEngineModel: EDraftEngine.Screenplay {
        if cachedEngineModelRevision == revision, let cachedEngineModel { return cachedEngineModel }
        let model = screenplay.engineModel
        cachedEngineModel = model
        cachedEngineModelRevision = revision
        return model
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

    public init(
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

    public func titlePageValue(for key: String) -> String? {
        screenplay.titlePage
            .first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?
            .values
            .joined(separator: "\n")
    }

    /// The entry's lines as stored (empty when the key is absent).
    public func titlePageValues(for key: String) -> [String] {
        screenplay.titlePage
            .first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?
            .values ?? []
    }

    /// Writes one title-page entry with a single undo snapshot — the same
    /// discipline as updateTitlePage, generalized to any key and any number
    /// of lines. Empty values remove the entry; unchanged values do nothing
    /// (no snapshot, no publish churn).
    public func setTitlePageEntry(_ key: String, values: [String]) {
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
        var number = 0
        return screenplay.elements.enumerated().compactMap { index, element in
            guard element.type == .scene, !element.text.isEmpty else { return nil }
            number += 1
            return SceneRow(
                id: element.id,
                number: number,
                page: stats.scenePages[index],
                sceneNumber: element.sceneNumber,
                title: element.text,
                elementIndex: index
            )
        }
    }

    public var cast: [CastRow] {
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
        return counts
            .compactMap { name, cues in
                firstCue[name].map { CastRow(id: name, name: name, cues: cues, firstCueID: $0) }
            }
            .sorted { $0.cues == $1.cues ? $0.name < $1.name : $0.cues > $1.cues }
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
                    stats.scenePages[index]
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
            elements[index].text = cueName + Self.cueExtension(elements[index].text)
            changed += 1
        }

        if includingMentions,
           let pattern = Self.mentionPattern(for: current),
           let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            let template = NSRegularExpression.escapedTemplate(for: typed)
            for index in elements.indices where elements[index].type != .character {
                let text = elements[index].text
                let range = NSRange(location: 0, length: (text as NSString).length)
                guard regex.firstMatch(in: text, range: range) != nil else { continue }
                elements[index].text = regex.stringByReplacingMatches(
                    in: text, range: range, withTemplate: template
                )
                changed += 1
            }
        }

        guard changed > 0 else { return 0 }
        apply(elements, "Rename Character")
        return changed
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
    public func applyLiveText(id: UUID, text: String, selectionOffset: Int) {
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
    public func replaceAllElements(
        _ elements: [ScriptElement],
        activeID: UUID?,
        offset: Int,
        structural: Bool,
        recordsUndo: Bool = true
    ) {
        if recordsUndo { recordSnapshot(structural: structural) }
        screenplay.elements = elements.isEmpty ? [ScriptElement(type: .action, text: "")] : elements
        caseMemory.prune(toAlive: Set(screenplay.elements.map(\.id)))
        activeElementID = activeID ?? screenplay.elements.first?.id
        selectionOffset = max(0, offset)
        commitChange(liveTyping: !structural)
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
        guard let parsed = try? Fountain.parse(source) else {
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
    public func kindForInsertedElement(after previous: ScriptElement?, text: String) -> ScreenplayKind {
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
    /// The page each scene opens on, keyed by element index.
    ///
    /// Read back out of the paginated pages rather than counted separately:
    /// a page number the Navigator computed its own way would drift from the
    /// one the export prints, and a writer would have no way to tell which
    /// was lying. A slug broken across a page break keeps the earlier page —
    /// the scene starts where its first line does.
    public nonisolated static func scenePages(
        in pages: [EDraftEngine.ScriptPage]
    ) -> [Int: Int] {
        var found: [Int: Int] = [:]
        for page in pages {
            for line in page.lines {
                guard case .element(.scene) = line.type, line.element >= 0,
                      found[line.element] == nil else { continue }
                found[line.element] = page.number
            }
        }
        return found
    }

    private nonisolated static func screenplayStats(
        for model: EDraftEngine.Screenplay,
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
            words: words,
            scenePages: scenePages(in: pages)
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
