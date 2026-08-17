import Foundation

/// A ranked contextual suggestion (TypeScript `Prediction`).
public struct Prediction: Codable, Equatable, Sendable {
    /// The full candidate text (e.g. `MARA`, `KITCHEN`, `(V.O.)`).
    public var text: String
    /// Human-readable explanation for the ranking.
    public var why: String
    /// Accepting this converts the block to a different element type.
    public var becomes: ElementKind?
    /// A shape hint teaches the form of an element; it is never committed.
    public var hint: Bool?

    public init(text: String, why: String, becomes: ElementKind? = nil, hint: Bool? = nil) {
        self.text = text
        self.why = why
        self.becomes = becomes
        self.hint = hint
    }
}

/// Contextual predictions — the ghost-text engine. Ranks deterministic
/// suggestions from scene participants, recent dialogue, document
/// vocabulary, scene transitions, and open screenplay structures. Ported
/// line-for-line from the TypeScript engine's `predict.ts`; behaviour is
/// pinned by `Fixtures/predict.json` and `Fixtures/ghostSuffix.json`.
public enum PredictionEngine {

    private static let scenePrefixes = ["INT. ", "EXT. ", "INT./EXT. ", "EST. ", "I/E "]

    private static let times = SmartType.sceneTimeValues

    /// Heading modifiers accepted after a scene time.
    private static let slugModifiers = ["ESTABLISHING", "STOCK", "AERIAL", "ARCHIVE"]

    private static let commonTransitions = [
        "CUT TO:", "HARD CUT TO:", "SMASH CUT TO:", "MATCH CUT TO:", "JUMP CUT TO:", "FLIP CUT TO:",
        "DISSOLVE TO:", "CROSS DISSOLVE TO:",
        "FADE IN:", "FADE OUT.", "FADE TO BLACK.", "FADE TO WHITE.",
        "PRE-LAP", "SOUND CUT", "AUDIO DISSOLVE",
        "WIPE TO:", "IRIS OUT", "IRIS IN",
        "INTERCUT:", "INTERCUT WITH:",
    ]

    /// Conventional cue extensions in display order. `(CONT'D)` is derived
    /// from scene context and is therefore excluded from this static list.
    private static let commonExtensions = [
        "(V.O.)", "(O.S.)", "(O.C.)", "(SUBTITLE)", "(PRE-LAP)", "(FILTERED)",
    ]

    /// Default parenthetical suggestions.
    private static let commonWrylies = [
        "(beat)", "(quietly)", "(then)", "(under her breath)", "(to himself)",
        "(whispering)", "(sarcastic)", "(off that)", "(re: the note)",
    ]

    private static let commonShots = [
        "ANGLE ON", "CLOSE ON", "POV", "INSERT", "WIDE SHOT", "TWO SHOT",
        "TRACKING SHOT", "AERIAL SHOT", "CRANE SHOT",
    ]

    /// Recognized structure-opening and structure-closing pairs.
    private static let structurePairs: [(open: String, close: String)] = [
        ("MONTAGE", "END OF MONTAGE"),
        ("SERIES OF SHOTS", "END OF SERIES OF SHOTS"),
        ("FLASHBACK", "END FLASHBACK"),
        ("DREAM SEQUENCE", "END OF DREAM SEQUENCE"),
        ("INTERCUT", "END INTERCUT"),
        ("PRELAP", "END PRELAP"),
    ]

    /// Standalone slug/structure lines offered in scene position.
    private static let specialSlugs = [
        "MONTAGE", "SERIES OF SHOTS", "FLASHBACK", "DREAM SEQUENCE", "INTERCUT",
        "FADE IN:", "SUPER:", "TITLE CARD:", "SMASH TO BLACK.",
    ]

    // MARK: - Small shared helpers

    private static func pushUnique(_ list: inout [String], _ value: String) {
        if !value.isEmpty && !list.contains(value) { list.append(value) }
    }

    private static func pushUniquePredictions(_ list: inout [Prediction], _ prediction: Prediction) {
        if !prediction.text.isEmpty && !list.contains(where: { $0.text == prediction.text }) {
            list.append(prediction)
        }
    }

    private static func clampIndex(_ elements: [ScreenplayElement], _ beforeIndex: Int) -> Int {
        max(0, min(beforeIndex, elements.count))
    }

    private static func prefixHits(_ pool: [String], _ prefix: String, cap: Int = 8) -> [String] {
        if prefix.isEmpty { return [] }
        return Array(pool.filter { $0.hasPrefix(prefix) && $0 != prefix }.prefix(cap))
    }

    /// `SCENE_HEAD_RE` = `/^\s*(INT|EXT|EST|INT\.?\/EXT|INT\/EXT|I\/E)[\.\s]/i`.
    /// Boolean-only, so any matching intro form suffices.
    static func matchesSceneHead(_ text: String) -> Bool {
        var rest = text[...]
        while rest.first?.isJSWhitespace == true { rest = rest.dropFirst() }
        for token in ["INT./EXT", "INT/EXT", "I/E", "INT", "EXT", "EST"]
        where rest.uppercased().hasPrefix(token) {
            let after = rest.dropFirst(token.count)
            guard let next = after.first else { return false }
            return next == "." || next.isJSWhitespace
        }
        return false
    }

    /// `EXT_RE`: a trailing cue extension, captured without its brackets.
    static func trailingExtension(_ text: String) -> String? {
        let pattern = #/(?i)\s*\(((?:V\.?O\.?|O\.?S\.?|O\.?C\.?|CONT['’]?D|SUBTITLE|PRE-?LAP|FILTERED))\)\s*$/#
        guard let match = text.firstMatch(of: pattern) else { return nil }
        return String(match.output.1)
    }

    // MARK: - Scene memory

    /// Characters who have spoken in the scene containing `beforeIndex`,
    /// first-appearance order, extensions stripped.
    public static func sceneCharacters(
        _ elements: [ScreenplayElement], before beforeIndex: Int
    ) -> [String] {
        let n = clampIndex(elements, beforeIndex)
        var start = 0
        for i in stride(from: n - 1, through: 0, by: -1) where elements[i].type == .scene {
            start = i
            break
        }
        var out: [String] = []
        for i in start..<n where elements[i].type == .character {
            pushUnique(&out, SmartType.stripCueExtensions(elements[i].text).uppercased())
        }
        return out
    }

    /// Characters in the current scene ranked by *recency of last speech*
    /// (most recent first) — the raw material of the ping-pong rule.
    public static func scenePartnersByRecency(
        _ elements: [ScreenplayElement], before beforeIndex: Int
    ) -> [String] {
        let n = clampIndex(elements, beforeIndex)
        var start = 0
        for i in stride(from: n - 1, through: 0, by: -1) where elements[i].type == .scene {
            start = i
            break
        }
        var out: [String] = []
        for i in stride(from: n - 1, through: start, by: -1) where elements[i].type == .character {
            pushUnique(&out, SmartType.stripCueExtensions(elements[i].text).uppercased())
        }
        return out
    }

    /// The character who spoke most recently before `beforeIndex`, or nil.
    public static func lastSpeakerBefore(
        _ elements: [ScreenplayElement], before beforeIndex: Int
    ) -> String? {
        let n = clampIndex(elements, beforeIndex)
        for i in stride(from: n - 1, through: 0, by: -1) {
            let element = elements[i]
            if element.type == .character {
                let name = SmartType.stripCueExtensions(element.text)
                    .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if !name.isEmpty { return name }
            }
            if element.type == .scene { return nil }
        }
        return nil
    }

    /// The (CONT'D) condition. True only when `name` spoke earlier in THIS
    /// scene and nothing but action or shots separates that speech from
    /// this block.
    private static func resumingAfterAction(
        _ elements: [ScreenplayElement], before beforeIndex: Int, name: String
    ) -> Bool {
        var interrupted = false
        var spoke = false
        for i in stride(from: clampIndex(elements, beforeIndex) - 1, through: 0, by: -1) {
            let element = elements[i]
            switch element.type {
            case .scene:
                return false
            case .character:
                return interrupted && spoke
                    && SmartType.stripCueExtensions(element.text)
                        .trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == name
            case .action, .shot:
                interrupted = true
            case .note, .section, .synopsis, .pagebreak:
                continue
            case .dialogue, .parenthetical:
                /* Dialogue seen before an interruption belongs to an
                   unbroken speech; after an interruption it leads us back
                   to the cue being resumed. */
                if !interrupted { return false }
                if element.type == .dialogue
                    && !element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    spoke = true
                }
            default:
                /* A transition, general/centered line, or lyric is a
                   semantic break. Ignoring it would manufacture a false
                   continuation. */
                return false
            }
        }
        return false
    }

    /// The Final Draft continuation. True when the most recent voice in
    /// THIS scene is `name` and that speech actually happened (non-empty
    /// dialogue). Looser than `resumingAfterAction` on purpose: an
    /// explicit extension gesture only needs the fact that the same
    /// voice continues.
    private static func continuingSameVoice(
        _ elements: [ScreenplayElement], before beforeIndex: Int, name: String
    ) -> Bool {
        var spoke = false
        for i in stride(from: clampIndex(elements, beforeIndex) - 1, through: 0, by: -1) {
            let element = elements[i]
            switch element.type {
            case .scene:
                return false
            case .character:
                return spoke
                    && SmartType.stripCueExtensions(element.text)
                        .trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == name
            case .dialogue, .parenthetical:
                if element.type == .dialogue
                    && !element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    spoke = true
                }
            case .action, .shot, .note, .section, .synopsis, .pagebreak:
                continue
            default:
                return false
            }
        }
        return false
    }

    // MARK: - Structure memory

    /// The most recently opened structure that has not been closed yet.
    public static func openStructure(
        _ elements: [ScreenplayElement], before beforeIndex: Int
    ) -> (open: String, close: String)? {
        var stack: [String] = []
        let n = clampIndex(elements, beforeIndex)
        for i in 0..<n {
            let element = elements[i]
            guard element.type == .scene || element.type == .shot
                    || element.type == .general || element.type == .action else { continue }
            let line = element.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            for pair in structurePairs {
                if line == pair.close || line.hasPrefix(pair.close) {
                    if let at = stack.lastIndex(of: pair.open) { stack.remove(at: at) }
                } else if line == pair.open
                            || line.hasPrefix(pair.open + " ")
                            || line.hasPrefix(pair.open + " - ")
                            || line.hasPrefix(pair.open + ":") {
                    stack.append(pair.open)
                }
            }
        }
        guard let open = stack.last,
              let pair = structurePairs.first(where: { $0.open == open }) else { return nil }
        return (pair.open, pair.close)
    }

    // MARK: - Time-of-day reasoning

    /// How many content lines the scene starting at `sceneIndex` holds.
    private static func sceneBodyLength(
        _ elements: [ScreenplayElement], sceneIndex: Int, before beforeIndex: Int
    ) -> Int {
        var count = 0
        guard sceneIndex + 1 < beforeIndex else { return 0 }
        for i in (sceneIndex + 1)..<beforeIndex {
            if elements[i].type == .scene { break }
            if !elements[i].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                count += 1
            }
        }
        return count
    }

    /// Infer the next scene time from the location's history, the
    /// preceding scene, and whether the preceding scene was short enough
    /// to imply continuity.
    public static func bestTimeFor(
        _ location: String, _ elements: [ScreenplayElement], before beforeIndex: Int
    ) -> String? {
        let n = clampIndex(elements, beforeIndex)

        /* per-location habit */
        var locationTimes: [String: Int] = [:]
        var timeOrder: [String] = []
        for i in 0..<n where elements[i].type == .scene {
            let parts = SmartType.splitSceneHeading(elements[i].text)
            guard parts.location == location, !parts.time.isEmpty else { continue }
            if locationTimes[parts.time] == nil { timeOrder.append(parts.time) }
            locationTimes[parts.time, default: 0] += 1
        }

        /* the previous real scene */
        var previousTime = ""
        var previousLocation = ""
        var previousSceneIndex = -1
        for i in stride(from: n - 1, through: 0, by: -1) where elements[i].type == .scene {
            let parts = SmartType.splitSceneHeading(elements[i].text)
            previousTime = parts.time
            previousLocation = parts.location
            previousSceneIndex = i
            break
        }

        if !previousTime.isEmpty, locationTimes[previousTime] != nil { return previousTime }
        if !locationTimes.isEmpty {
            /* JS sort is stable: ties keep first-seen order. */
            return timeOrder
                .map { ($0, locationTimes[$0]!) }
                .sorted { $0.1 > $1.1 }
                .first!.0
        }
        if previousSceneIndex >= 0
            && !previousLocation.isEmpty
            && previousLocation != location
            && sceneBodyLength(elements, sceneIndex: previousSceneIndex, before: n) <= 3 {
            return "CONTINUOUS"
        }
        if !previousTime.isEmpty { return previousTime }
        return nil
    }

    // MARK: - Document vocabularies

    /// Extensions this script already uses, first-seen order — house style.
    public static func usedExtensions(_ elements: [ScreenplayElement]) -> [String] {
        var out: [String] = []
        for element in elements where element.type == .character {
            let trimmed = element.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let ext = trailingExtension(trimmed) {
                pushUnique(&out, "(" + ext.uppercased().replacingOccurrences(of: "’", with: "'") + ")")
            }
        }
        return out
    }

    /// Parentheticals this script already uses.
    public static func usedWrylies(_ elements: [ScreenplayElement]) -> [String] {
        var out: [String] = []
        for element in elements where element.type == .parenthetical {
            pushUnique(&out, element.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        return out
    }

    /// Shots this script already uses.
    public static func usedShots(_ elements: [ScreenplayElement]) -> [String] {
        var out: [String] = []
        for element in elements where element.type == .shot {
            pushUnique(&out, element.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
        }
        return out
    }

    /// Where scenes tend to go next: previous location → following
    /// locations, most frequent first, ties in first-seen order
    /// (JS stable sort).
    private static func nextLocationCounts(
        _ elements: [ScreenplayElement], before beforeIndex: Int
    ) -> [String: [String]] {
        var sequence: [String] = []
        let n = clampIndex(elements, beforeIndex)
        for i in 0..<n where elements[i].type == .scene {
            let location = SmartType.splitSceneHeading(elements[i].text).location
            if !location.isEmpty { sequence.append(location) }
        }
        var counts: [String: [String: Int]] = [:]
        var order: [String: [String]] = [:]
        /* No prior location chain → no transitions to count. The range
           `1..<0` would be a runtime trap, so guard before iterating. */
        guard sequence.count > 1 else { return [:] }
        for i in 1..<sequence.count {
            let from = sequence[i - 1]
            let to = sequence[i]
            if counts[from] == nil {
                counts[from] = [:]
                order[from] = []
            }
            if counts[from]![to] == nil { order[from]!.append(to) }
            counts[from]![to, default: 0] += 1
        }
        var out: [String: [String]] = [:]
        for (from, _) in counts {
            out[from] = (order[from] ?? [])
                .map { ($0, counts[from]![$0]!) }
                .sorted { $0.1 > $1.1 }
                .map(\.0)
        }
        return out
    }

    // MARK: - Intro/location coherence

    private enum IntroKind: Equatable {
        case interior, exterior, both, unknown
    }

    private static func kindOfIntro(_ intro: String) -> IntroKind {
        let up = intro.uppercased()
        if up.contains("/") { return .both }
        if up.hasPrefix("EXT") { return .exterior }
        if up.hasPrefix("INT") { return .interior }
        return .unknown
    }

    /// Each location's observed intro kinds — a place knows which one it is.
    private static func locationKinds(_ elements: [ScreenplayElement]) -> [String: IntroKind] {
        var out: [String: IntroKind] = [:]
        for element in elements where element.type == .scene {
            let parts = SmartType.splitSceneHeading(element.text)
            guard !parts.location.isEmpty else { continue }
            let kind = kindOfIntro(parts.prefix.replacingOccurrences(of: ".", with: ""))
            guard kind != .unknown else { continue }
            if let previous = out[parts.location], previous != kind {
                out[parts.location] = .both
            } else {
                out[parts.location] = kind
            }
        }
        return out
    }

    // MARK: - Candidate generators

    /// Empty character block, ranked by certainty:
    ///   1. two-character scene → the other participant
    ///   2. one voice plus intervening action → the same voice with (CONT'D)
    ///   3. ensemble scene → participants by recency
    private static func emptyCharacterCandidates(
        _ script: Screenplay, index: Int
    ) -> [Prediction] {
        let elements = script.elements
        let smart = SmartType.collect(script)
        let recency = scenePartnersByRecency(elements, before: index)
        let last = recency.first
        let sceneCast = sceneCharacters(elements, before: index)

        var ranked: [Prediction] = []

        if sceneCast.count == 2, let last {
            if let other = sceneCast.first(where: { $0 != last }) {
                ranked.append(Prediction(text: other, why: "the other half of the conversation"))
            }
        } else if sceneCast.count == 1, let last,
                  resumingAfterAction(elements, before: index, name: last) {
            ranked.append(Prediction(
                text: "\(last) (CONT'D)", why: "same speaker resuming after action"
            ))
        }

        for partner in recency.dropFirst() {
            pushUniquePredictions(&ranked, Prediction(text: partner, why: "scene participant"))
        }
        for character in smart.characters where character != last {
            pushUniquePredictions(&ranked, Prediction(text: character, why: "character in this script"))
        }
        return Array(ranked.prefix(8))
    }

    /// Partial cue typed: case-insensitive prefix match over known characters.
    private static func typedCharacterCandidates(
        _ script: Screenplay, text: String
    ) -> [Prediction] {
        let prefix = SmartType.stripCueExtensions(text)
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if prefix.isEmpty { return [] }
        return prefixHits(SmartType.collect(script).characters, prefix).map {
            Prediction(text: $0, why: "character in this script")
        }
    }

    /// Cue extensions, only after explicit extension input. Document-specific
    /// extensions rank before defaults; `(CONT'D)` leads when the same voice
    /// continues in the current scene.
    private static func extensionCandidates(
        _ script: Screenplay, text: String, index: Int
    ) -> [Prediction] {
        /* `/^(.*?)\(([^)]*)$/` — a name, an open paren, and a typed tail.
           The LAZY `.*?` selects the first `(` whose remainder holds no `)`,
           which is the first `(` after the last `)`. Anchoring on the very
           first `(` instead loses every cue that already carries a closed
           extension: `MARA (V.O.) (` must still offer `(CONT'D)`, and
           `A (b (c` must yield the tail `b (c`, not `c`. */
        let afterLastClose = text.range(of: ")", options: .backwards)?.upperBound
            ?? text.startIndex
        guard let paren = text[afterLastClose...].firstIndex(of: "(") else { return [] }
        /* No `)` can follow by construction, so the regex's `[^)]*` holds. */
        let tail = text[text.index(after: paren)...]
        let name = text[..<paren]
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !name.isEmpty else { return [] }
        let known = SmartType.collect(script).characters.contains(name)

        let typed = tail.uppercased()
        var pool: [String] = []
        if continuingSameVoice(script.elements, before: index, name: name) {
            pushUnique(&pool, "(CONT'D)")
        }
        if known {
            for ext in usedExtensions(script.elements) {
                if ext == "(CONT'D)" { continue }  /* facts outrank habits */
                pushUnique(&pool, ext)
            }
        }
        for ext in commonExtensions { pushUnique(&pool, ext) }

        return pool
            .filter { String($0.dropFirst().dropLast()).hasPrefix(typed)
                        && String($0.dropFirst().dropLast()) != typed }
            .prefix(6)
            .map { Prediction(
                text: $0,
                why: $0 == "(CONT'D)" ? "same voice continuing" : "cue extension"
            ) }
    }

    /// Scene-heading assembly: intro → location → time, story-aware at
    /// every stage.
    private static func sceneCandidates(
        _ script: Screenplay, text: String, index: Int
    ) -> [Prediction] {
        let up = text.uppercased()

        /* Require two characters before completing a scene prefix so
           ordinary action text never matches. */
        let typed = up.trimmingCharacters(in: .whitespacesAndNewlines)
        guard typed.count >= 2 else { return [] }
        if let introHit = scenePrefixes.first(where: { $0.hasPrefix(typed) && $0 != typed }),
           !introHit.dropFirst(typed.count).trimmingCharacters(in: .whitespaces).isEmpty {
            return [Prediction(text: introHit, why: "scene intro")]
        }

        if !matchesSceneHead(up) {
            /* An open structure's closing line takes precedence. */
            if let open = openStructure(script.elements, before: index),
               open.close.hasPrefix(typed), open.close != typed {
                return [Prediction(text: open.close, why: "closes the \(open.open.lowercased())")]
            }

            var slugPool: [String] = []
            for element in script.elements
            where (element.type == .scene || element.type == .general)
                    && !matchesSceneHead(element.text) {
                pushUnique(&slugPool, element.text
                    .trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
            }
            for slug in specialSlugs { pushUnique(&slugPool, slug) }
            return prefixHits(slugPool, typed).map { Prediction(text: $0, why: "sequence heading") }
        }

        /* Complete a scene time or a modifier following an existing time. */
        if let timeMatch = trailingTimeMatch(up) {
            let prefix = String(timeMatch.typed.drop(while: { $0.isWhitespace }))
            let beforeDash = timeMatch.beforeDash
            /* Text after a second dash is a heading modifier. */
            if times.contains(SmartType.splitSceneHeading(beforeDash).time) {
                if prefix.isEmpty {
                    return slugModifiers.map { Prediction(text: $0, why: "heading modifier") }
                }
                return prefixHits(slugModifiers, prefix, cap: 6)
                    .map { Prediction(text: $0, why: "heading modifier") }
            }
            /* Do not replace a complete, recognized scene time. */
            if times.contains(prefix) { return [] }
            let location = SmartType.splitSceneHeading(beforeDash).location
            let best = location.isEmpty
                ? nil
                : bestTimeFor(location, script.elements, before: index)
            var out: [Prediction] = []
            if let best, best.hasPrefix(prefix), best != prefix {
                out.append(Prediction(text: best, why: "the day has not turned over"))
            }
            /* A bare separator requests the default scene-time candidates. */
            if prefix.isEmpty {
                for time in times {
                    pushUniquePredictions(&out, Prediction(text: time, why: "time of day"))
                }
                return Array(out.prefix(6))
            }
            for time in prefixHits(times, prefix, cap: 6) {
                pushUniquePredictions(&out, Prediction(text: time, why: "time of day"))
            }
            return Array(out.prefix(6))
        }

        /* With no location text, return a shape hint, not a location. */
        let locationText = headingLocationRemainder(up) ?? ""
        let prefix = String(locationText.drop(while: { $0.isWhitespace }))
        if prefix.isEmpty {
            return [Prediction(
                text: "LOCATION - TIME",
                why: "the shape of a scene heading",
                hint: true
            )]
        }

        /* Filter locations by their observed interior/exterior usage. */
        let introRaw = headingIntroToken(up) ?? "INT"
        let want = kindOfIntro(introRaw.replacingOccurrences(of: ".", with: ""))
        let kinds = locationKinds(script.elements)
        func fits(_ location: String) -> Bool {
            guard let kind = kinds[location] else { return true }
            return kind == .both || want == .both || kind == want
        }

        let smart = SmartType.collect(script)
        /* Do not replace a complete, recognized location. */
        if smart.locations.contains(prefix) { return [] }
        let nextMap = nextLocationCounts(script.elements, before: index)
        var previousHeading = ""
        for i in stride(from: clampIndex(script.elements, index) - 1, through: 0, by: -1)
        where script.elements[i].type == .scene {
            previousHeading = script.elements[i].text
            break
        }
        let previous = SmartType.splitSceneHeading(previousHeading).location
        var out: [Prediction] = []
        if !previous.isEmpty {
            for location in nextMap[previous] ?? []
            where location.hasPrefix(prefix) && location != prefix && fits(location) {
                pushUniquePredictions(&out, Prediction(
                    text: location,
                    why: "where \(previous.lowercased()) scenes go next"
                ))
            }
        }
        for location in prefixHits(smart.locations.filter(fits), prefix) {
            pushUniquePredictions(&out, Prediction(text: location, why: "location in this script"))
        }
        return Array(out.prefix(8))
    }

    /// `/\s-\s*([A-Z ]*)$/` on the uppercased text: the final spaced dash
    /// whose tail is only uppercase letters and spaces. Returns the raw
    /// text before the dash and the captured tail.
    private static func trailingTimeMatch(_ up: String) -> (beforeDash: String, typed: String)? {
        let characters = Array(up)
        for index in characters.indices where characters[index] == "-" {
            guard index > 0, characters[index - 1].isJSWhitespace else { continue }
            var tailStart = index + 1
            while tailStart < characters.count && characters[tailStart].isJSWhitespace {
                tailStart += 1
            }
            let tail = characters[tailStart...]
            guard tail.allSatisfy({ $0 == " " || ($0.isASCII && $0.isLetter && $0.isUppercase) })
            else { continue }
            /* JS `up.replace(/\s-\s*[A-Z ]*$/, '')` removes the whitespace
               before the dash as well. */
            return (String(characters[..<(index - 1)]), String(tail))
        }
        return nil
    }

    /// The remainder of a heading after its intro token — `locMatch[1]` in
    /// `/^\s*(?:INT\.?\/EXT\.?|INT\/EXT|I\/E|INT|EXT|EST)[\.\s]+(.*)$/`.
    private static func headingLocationRemainder(_ up: String) -> String? {
        var rest = Substring(up)
        while rest.first?.isJSWhitespace == true { rest = rest.dropFirst() }
        for token in ["INT./EXT.", "INT./EXT", "INT/EXT.", "INT/EXT", "I/E", "INT", "EXT", "EST"]
        where rest.hasPrefix(token) {
            var after = rest.dropFirst(token.count)
            /* one or more dot/whitespace separators are required */
            guard let first = after.first, first == "." || first.isJSWhitespace else { return nil }
            after = after.dropFirst()
            while let next = after.first, next == "." || next.isJSWhitespace {
                after = after.dropFirst()
            }
            return String(after)
        }
        return nil
    }

    /// The intro token of a heading — `match(/^\s*(INT…)/)[1]`.
    private static func headingIntroToken(_ up: String) -> String? {
        var rest = Substring(up)
        while rest.first?.isJSWhitespace == true { rest = rest.dropFirst() }
        for token in ["INT./EXT.", "INT./EXT", "INT/EXT.", "INT/EXT", "I/E", "INT", "EXT", "EST"]
        where rest.hasPrefix(token) {
            return token
        }
        return nil
    }

    /// Document-specific transitions before defaults.
    private static func transitionCandidates(_ script: Screenplay, text: String) -> [Prediction] {
        let prefix = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var pool: [String] = []
        for transition in SmartType.collect(script).transitions { pushUnique(&pool, transition) }
        for transition in commonTransitions { pushUnique(&pool, transition) }
        return prefixHits(pool, prefix, cap: 6).map { Prediction(text: $0, why: "transition") }
    }

    /// Document-specific parentheticals before defaults.
    private static func wrylyCandidates(_ script: Screenplay, text: String) -> [Prediction] {
        guard text.hasPrefix("(") else { return [] }
        var pool: [String] = []
        for wryly in usedWrylies(script.elements) { pushUnique(&pool, wryly) }
        for wryly in commonWrylies { pushUnique(&pool, wryly) }
        return prefixHits(pool, text.lowercased(), cap: 6).map { Prediction(text: $0, why: "wryly") }
    }

    /// Document-specific shots before defaults.
    private static func shotCandidates(_ script: Screenplay, text: String) -> [Prediction] {
        let prefix = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var pool: [String] = []
        for shot in usedShots(script.elements) { pushUnique(&pool, shot) }
        for shot in commonShots { pushUnique(&pool, shot) }
        return prefixHits(pool, prefix, cap: 6).map { Prediction(text: $0, why: "shot") }
    }

    // MARK: - Main entry

    /// Ranked predictions for the block being edited, best first
    /// (TypeScript `predict`).
    public static func predict(
        _ script: Screenplay,
        type: ElementKind,
        text: String,
        index: Int
    ) -> [Prediction] {
        let clamped = clampIndex(script.elements, index)
        switch type {
        case .character:
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return emptyCharacterCandidates(script, index: clamped)
            }
            /* Extension candidates require explicit extension input. */
            let extensions = extensionCandidates(script, text: text, index: clamped)
            if !extensions.isEmpty { return extensions }
            /* A trailing space may offer `(CONT'D)` when scene context
               supports it. */
            if text.last?.isJSWhitespace == true {
                /* JS: `/^(.*?)\s+$/` — the text minus its trailing run. */
                var base = text
                while base.last?.isJSWhitespace == true { base.removeLast() }
                if trailingExtension(base) != nil { return [] }  /* already extended */
                let name = SmartType.stripCueExtensions(base)
                    .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                if !name.isEmpty
                    && continuingSameVoice(script.elements, before: clamped, name: name) {
                    return [Prediction(text: "(CONT'D)", why: "same voice continuing")]
                }
                return []
            }
            return typedCharacterCandidates(script, text: text)

        case .scene:
            return sceneCandidates(script, text: text, index: clamped)
        case .transition:
            return transitionCandidates(script, text: text)
        case .parenthetical:
            return wrylyCandidates(script, text: text)
        case .shot:
            return shotCandidates(script, text: text)
        case .action:
            /* Promote an action block whose text clearly begins a scene
               heading or a transition — the two openings an action line
               can grow into. */
            let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard typed.count >= 2 else { return [] }
            let up = typed.uppercased()
            let couldBeSlug = scenePrefixes.contains(where: { $0.hasPrefix(up) })
                || matchesSceneHead(text)
            if couldBeSlug {
                return sceneCandidates(script, text: text, index: clamped).map {
                    Prediction(text: $0.text, why: $0.why, becomes: .scene, hint: $0.hint)
                }
            }
            return transitionCandidates(script, text: up).map {
                Prediction(text: $0.text, why: $0.why, becomes: .transition, hint: $0.hint)
            }
        default:
            return []
        }
    }

    // MARK: - Ghost text

    /// The suffix to render as ghost text for a candidate. Full candidate
    /// when the block is empty (or the candidate completes a structured
    /// line like a scene heading), otherwise the unmatched tail.
    public static func ghostSuffix(
        candidate: String, blockText: String, hint: Bool = false
    ) -> String {
        /* shape hints append whole, spaced, and are never committed */
        if hint {
            if blockText.isEmpty { return candidate }
            return (blockText.hasSuffix(" ") ? "" : " ") + candidate
        }

        let trimmed = blockText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return candidate }

        /* extensions attach to the name: 'MARA' → ' (V.O.)', 'MARA ' →
           '(V.O.)' (a wryly block already inside parens completes as one) */
        if candidate.hasPrefix("(")
            && !blockText.drop(while: { $0.isWhitespace }).hasPrefix("(") {
            /* unclosed paren mid-cue: 'MARA (V' + '(V.O.)' → '.O.)' */
            if let openAt = blockText.firstIndex(of: "(") {
                let typed = blockText[openAt...].uppercased()
                if candidate.hasPrefix(typed) && candidate.count > typed.count {
                    return String(candidate.dropFirst(typed.count))
                }
                return ""
            }
            return (blockText.hasSuffix(" ") ? "" : " ") + candidate
        }

        /* scene headings complete structurally against the raw upper text */
        let up = blockText.uppercased()
        if candidate.hasPrefix(up) {
            return String(candidate.dropFirst(up.count))
        }

        /* location stage: block "INT. KIT", candidate "KITCHEN" — the tail */
        if let remainder = headingLocationRemainder(up) {
            let typed = remainder.drop(while: { $0.isWhitespace })
            if !typed.isEmpty && candidate.hasPrefix(typed.uppercased()) {
                return String(candidate.dropFirst(typed.count))
            }
        }

        /* time stage: block "INT. LAB - NI", candidate "NIGHT".
           The ' - ' separator belongs to the heading, not the writer:
           '-' alone whispers ' NIGHT'; '- ' whispers 'NIGHT'; '- NI'
           whispers 'GHT'; '-NI' jammed against the dash — silence. */
        if let timeMatch = trailingTimeMatchRaw(up) {
            let typed = timeMatch.tail
            if typed.isEmpty {
                if up.hasSuffix(" ") { return candidate }
                return candidate.isEmpty ? "" : " " + candidate
            }
            /* require whitespace after the dash: `\s-\s+[A-Z ]*$` */
            guard timeMatch.whitespaceAfterDash else { return "" }
            if candidate.hasPrefix(typed) {
                return String(candidate.dropFirst(typed.count))
            }
            return ""
        }

        /* character prefixes: block "MAR", candidate "MARA" */
        let prefix = SmartType.stripCueExtensions(blockText)
            .trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !prefix.isEmpty && candidate.hasPrefix(prefix) {
            return String(candidate.dropFirst(prefix.count))
        }

        /* wrylies: block "(qu", candidate "(quietly)" */
        if blockText.hasPrefix("(") && candidate.hasPrefix(blockText.lowercased()) {
            return String(candidate.dropFirst(blockText.count))
        }

        return ""
    }

    /// Like `trailingTimeMatch` but also reports whether whitespace
    /// followed the dash (the ghost-suffix path distinguishes them).
    private static func trailingTimeMatchRaw(
        _ up: String
    ) -> (beforeDash: String, tail: String, whitespaceAfterDash: Bool)? {
        let characters = Array(up)
        for index in characters.indices where characters[index] == "-" {
            guard index > 0, characters[index - 1].isJSWhitespace else { continue }
            var tailStart = index + 1
            while tailStart < characters.count && characters[tailStart].isJSWhitespace {
                tailStart += 1
            }
            let tail = characters[tailStart...]
            guard tail.allSatisfy({ $0 == " " || ($0.isASCII && $0.isLetter && $0.isUppercase) })
            else { continue }
            return (
                String(characters[..<index]),
                String(tail),
                tailStart > index + 1
            )
        }
        return nil
    }

    /// The next word of a suggestion (with trailing space) — partial accept.
    public static func nextWord(_ text: String) -> String {
        let pattern = #/^\s*\S+\s*/#
        guard let match = text.firstMatch(of: pattern) else { return text }
        return String(match.output)
    }

    /// Accept a prediction with Tab only after the user has entered text.
    public static func ghostTabBehavior(_ blockText: String) -> GhostTabBehavior {
        blockText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .jump : .accept
    }

    public enum GhostTabBehavior: String, Codable, Sendable {
        case accept
        case jump
    }
}
