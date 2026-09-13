import Foundation

/// Vocabulary extraction — character names, locations, scene times,
/// transitions, and heading prefixes — ported from the TypeScript engine's
/// `smarttype.ts`. Pinned by the predict corpus (which exercises these
/// through every candidate generator).
public enum SmartType {

    /// Canonical scene-time tokens shared by parsing and prediction.
    public static let sceneTimeValues: [String] = [
        "DAY", "NIGHT", "MORNING", "AFTERNOON", "EVENING", "DAWN", "DUSK",
        "SUNRISE", "SUNSET", "MAGIC HOUR", "MIDNIGHT", "LATER", "CONTINUOUS",
        "MOMENTS LATER", "SAME", "SAME TIME", "THE NEXT DAY", "DAYS LATER",
        "WEEKS LATER", "MONTHS LATER", "YEARS LATER", "FLASHBACK",
        "PRESENT DAY", "FUTURE",
    ]

    private static let sceneTimeSet = Set(sceneTimeValues)

    public struct Data: Equatable, Sendable {
        /// Character names with extensions stripped — MOLLY, not MOLLY (V.O.).
        public var characters: [String] = []
        /// Location parts of scene headings — POLICE STATION.
        public var locations: [String] = []
        /// Time-of-day parts of scene headings — DAY, NIGHT, LATER.
        public var times: [String] = []
        /// Transitions used — CUT TO:, SMASH CUT TO:.
        public var transitions: [String] = []
        /// Scene heading prefixes seen — INT., EXT., INT./EXT.
        public var prefixes: [String] = []
    }

    public struct HeadingParts: Equatable, Sendable {
        public var prefix: String
        public var location: String
        public var time: String
    }

    /// Strip cue extensions — (V.O.), (O.S.), (O.C.), (CONT'D), (SUBTITLE)…
    /// Case-insensitive; accepts curly apostrophes, matching the JS regex.
    /// The one bare suffix the corpus witnesses is the transcript's V/O —
    /// "FRANK V/O" (pasted-26 ×299); O.S./O.C. stay parenthesised-only, the
    /// ambiguity the "MARA O.S." pin guards.
    public static func stripCueExtensions(_ cue: String) -> String {
        /* Every alternative sits inside a literal `\(...\)`, so a cue with
           no parenthesis and no V/O tail cannot match. Building the regex
           is the expensive part — it is not `Sendable`, so it cannot be
           shared — and the paginator asks this question of every dialogue
           block on every pass. Answer the common case without paying for
           it. */
        guard cue.contains("(") || cue.hasSuffix("V/O") else {
            return cue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var stripped = cue
        if cue.contains("(") {
            let pattern = #/(?i)\s*\((?:V\.?O\.?|O\.?S\.?|O\.?C\.?|CONT['’]?D|SUBTITLE|PRE-?LAP|FILTERED|INTO (?:PHONE|RADIO|COMMS?)[^)]*)\)\s*/#
            stripped = stripped.replacing(pattern, with: "")
        }
        // \s+V\/O$ — the bare transcript suffix
        if stripped.hasSuffix("V/O"),
           stripped.dropLast(3).last?.isWhitespace == true {
            stripped = String(stripped.dropLast(3))
        }
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Scene heading splitting

    /// Intro tokens in JS-regex alternation order (compound forms first so
    /// `INT./EXT.` is never clipped to `INT.`, and the reversed hand six
    /// corpus files write — EXT/INT. — reads the same way). Dots are part
    /// of the token; a separate optional `[. ]` and `\s*` run follows.
    private static let introTokens = [
        "INT./EXT.", "INT./EXT", "INT/EXT.", "INT/EXT",
        "EXT./INT.", "EXT./INT", "EXT/INT.", "EXT/INT",
        "I/E", "INT", "EXT", "EST",
    ]

    /// Matches `/^(INT\.?\/EXT\.?|INT\/EXT|I\/E|INT|EXT|EST)[. ]?\s*/i` and
    /// returns the raw prefix token plus the total characters consumed.
    static func matchIntro(_ heading: String) -> (raw: String, consumed: Int)? {
        for token in introTokens where heading.range(of: token, options: [.caseInsensitive, .anchored]) != nil {
            var index = heading.index(heading.startIndex, offsetBy: token.count)
            if index < heading.endIndex && (heading[index] == "." || heading[index] == " ") {
                index = heading.index(after: index)
            }
            while index < heading.endIndex && heading[index].isJSWhitespace {
                index = heading.index(after: index)
            }
            return (token, heading.distance(from: heading.startIndex, to: index))
        }
        return nil
    }

    /// Splits on `/\s+[-–—]\s+/` — spaced dashes (hyphen, en, em).
    private static func splitOnSpacedDashes(_ text: String) -> [String] {
        var parts: [String] = []
        var cursor = text.startIndex
        var scan = text.startIndex
        while scan < text.endIndex {
            if "-–—".contains(text[scan]),
               scan > text.startIndex {
                /* require whitespace before the dash */
                let before = text.index(before: scan)
                guard text[before].isJSWhitespace else {
                    scan = text.index(after: scan)
                    continue
                }
                /* require whitespace after the dash */
                var after = text.index(after: scan)
                guard after < text.endIndex, text[after].isJSWhitespace else {
                    scan = text.index(after: scan)
                    continue
                }
                /* find the extent of the preceding whitespace run */
                var left = before
                while left > text.startIndex {
                    let earlier = text.index(before: left)
                    if !text[earlier].isJSWhitespace { break }
                    left = earlier
                }
                while after < text.endIndex && text[after].isJSWhitespace {
                    after = text.index(after: after)
                }
                /* JS `split` matches never overlap: when this dash's
                   preceding whitespace run was already consumed by the
                   previous separator, the dash is literal text, not a
                   separator. (`INT. LAB - - DAY` → ["INT. LAB", "- DAY"].)
                   Clamping instead would append "" and diverge from JS. */
                guard left >= cursor else {
                    scan = text.index(after: scan)
                    continue
                }
                parts.append(String(text[cursor..<left]))
                cursor = after
                scan = after
                continue
            }
            scan = text.index(after: scan)
        }
        parts.append(String(text[cursor...]))
        return parts
    }

    /// Split a scene heading into prefix / location / time parts. Parts are
    /// canonical UPPERCASE — the model cannot be trusted to carry canonical
    /// case (blur without commit, paste, and mixed-case imports all leak).
    public static func splitSceneHeading(_ heading: String) -> HeadingParts {
        let trimmed = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        var rawPrefix = ""
        var rest = trimmed
        if let match = matchIntro(trimmed) {
            rawPrefix = match.raw.uppercased()
            if rawPrefix.hasSuffix(".") { rawPrefix.removeLast() }
            rest = String(trimmed.dropFirst(match.consumed))
        }
        let prefix = rawPrefix.isEmpty ? "" : rawPrefix == "I/E" ? "I/E" : rawPrefix + "."

        var time = ""
        let parts = splitOnSpacedDashes(rest).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var location = rest
        if parts.count > 1 {
            /* A heading may carry a modifier after time (`- DAY -
               ESTABLISHING`); locations may themselves contain spaced
               dashes (`54TH ST - UPTOWN - DAY`). */
            var timeAt = parts.indices.dropFirst().first(where: {
                sceneTimeSet.contains(parts[$0].uppercased())
            })
            if timeAt == nil { timeAt = parts.count - 1 }  // preserve custom times
            time = parts[timeAt!]
            location = parts[..<timeAt!].joined(separator: " - ")
        }
        return HeadingParts(
            prefix: prefix,
            location: location.uppercased(),
            time: time.uppercased()
        )
    }

    // MARK: - Collection

    private static func pushUnique(_ list: inout [String], _ seen: inout Set<String>, _ value: String) {
        if !value.isEmpty && !seen.contains(value) {
            seen.insert(value)
            list.append(value)
        }
    }

    /// Derive autocomplete/consistency vocabularies from the document.
    public static func collect(_ script: Screenplay) -> Data {
        var data = Data()
        var seenCharacters = Set<String>()
        var seenLocations = Set<String>()
        var seenTimes = Set<String>()
        var seenTransitions = Set<String>()
        var seenPrefixes = Set<String>()

        for element in script.elements {
            switch element.type {
            case .character:
                /* canonical case at the collection boundary */
                pushUnique(&data.characters, &seenCharacters,
                           stripCueExtensions(element.text).uppercased())
            case .scene:
                let parts = splitSceneHeading(element.text)
                pushUnique(&data.prefixes, &seenPrefixes, parts.prefix)
                pushUnique(&data.locations, &seenLocations, parts.location)
                pushUnique(&data.times, &seenTimes, parts.time)
            case .transition:
                pushUnique(&data.transitions, &seenTransitions,
                           element.text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
            default:
                continue
            }
        }
        return data
    }
}
