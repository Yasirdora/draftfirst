/// Notes pinned to words — RFC-NOTES-SYSTEM §5 (stage 4).
///
/// The Swift half of TypeScript `noteanchor.ts`, unit for unit: every offset
/// here is a UTF-16 index, the same coordinate space as `ContentIndex`, an
/// `NSRange` and the TypeScript engine's string offsets, so the two ports
/// agree on every case in the shared conformance fixture.
///
/// WHY NOT ATTRIBUTES. The Final Draft 13.4.0 probe measured every unknown
/// attribute stripped by Final Draft's first save (RFC §3, fact 1). Anchors
/// therefore live in text Final Draft preserves — the Range in FDX, the
/// header line in Fountain — and this engine writes no `EDraft:` attribute
/// for them anywhere.

/// A note pinned to words inside its paragraph. `on` is the words exactly as
/// they stand in the paragraph the note is about; `nth` selects which
/// occurrence, and is present exactly when the words occur more than once
/// (§5.3). Absent means the note is about its whole paragraph, which is
/// every note before stage 4 (TypeScript `NoteAnchor`).
public struct NoteAnchor: Codable, Equatable, Sendable {
    public var on: String
    public var nth: Int?

    public init(on: String, nth: Int? = nil) {
        self.on = on
        self.nth = nth
    }
}

extension NoteAnchor {
    /// Where an anchor lands: a half-open span in UTF-16 units of the
    /// paragraph's own text (TypeScript `AnchorSpan`).
    public struct Span: Equatable, Sendable {
        public let start: Int
        public let end: Int

        public init(start: Int, end: Int) {
            self.start = start
            self.end = end
        }
    }

    /// Every position where `words` occurs in `paragraph`, in order.
    ///
    /// Overlapping occurrences each count: in `aaa`, the word `aa` occurs at
    /// 0 and at 1. Writer and reader share this, so an ordinal always means
    /// the position it meant when it was written (TypeScript `occurrencesOf`).
    static func occurrences(of words: [UInt16], in paragraph: [UInt16]) -> [Int] {
        guard !words.isEmpty, words.count <= paragraph.count else { return [] }
        var out: [Int] = []
        for at in 0...(paragraph.count - words.count) {
            var matched = true
            for offset in 0..<words.count where paragraph[at + offset] != words[offset] {
                matched = false
                break
            }
            if matched { out.append(at) }
        }
        return out
    }

    /// The anchor's span in its paragraph — §5.3, rules 1 to 5.
    ///
    /// Only this paragraph is searched, from its start; the first occurrence
    /// unless `nth` selects another; exact on UTF-16 units, casing included.
    /// Words gone, or fewer than `nth`: `nil` — the caller anchors to the
    /// whole paragraph and says "words changed", never moving the note to
    /// another paragraph and never guessing (TypeScript `resolveAnchor`).
    public static func resolve(_ paragraph: String, _ anchor: NoteAnchor) -> Span? {
        let nth = anchor.nth ?? 1
        guard nth >= 1 else { return nil }
        let places = occurrences(of: Array(anchor.on.utf16), in: Array(paragraph.utf16))
        guard nth <= places.count else { return nil }
        let at = places[nth - 1]
        return Span(start: at, end: at + anchor.on.utf16.count)
    }

    /// The anchor for a span of a paragraph — the inverse of `resolve`.
    ///
    /// `nil` when the span is the whole paragraph or is empty: a note about
    /// its whole paragraph carries no anchor at all. §5.3 rule 3: `nth` is
    /// written exactly when the words occur more than once at the time of
    /// writing (TypeScript `anchorFor`).
    public static func forSpan(_ paragraph: String, start: Int, end: Int) -> NoteAnchor? {
        let units = Array(paragraph.utf16)
        guard start >= 0, end <= units.count, end > start else { return nil }
        guard !(start == 0 && end == units.count) else { return nil }
        let on = Array(units[start..<end])
        let places = occurrences(of: on, in: units)
        guard let ordinal = places.firstIndex(of: start) else { return nil }
        let words = String(decoding: on, as: UTF16.self)
        return places.count > 1 ? NoteAnchor(on: words, nth: ordinal + 1) : NoteAnchor(on: words)
    }
}

// MARK: - The Fountain header line (§4.1, the `on`/`nth` fields)

extension NoteAnchor {
    /// A note's anchor in Fountain is a header line — the first line of the
    /// note's text, alone on its line (§4.1):
    ///
    ///     [[[eDraft on:"doesn't move"]
    ///     Dana Reyes (Director): Too still? She should flinch.]]
    ///
    /// §4.1's grammar also carries `thread`, `status`, `by`, `at`,
    /// `reply-to` and `from` — stage 2 and stage 3's carrier, which the RFC
    /// says is not built. A header is read here only when every field in it
    /// is one stage 4 owns. A header carrying anything else stays exactly
    /// where it is, as the note's own first line of text, byte for byte.
    public struct HeaderReading: Equatable, Sendable {
        public let anchor: NoteAnchor
        /// The note's words, with the header line taken off.
        public let body: String
    }

    private static let headerMark = Array("[edraft".utf16)

    private static func isKeyChar(_ unit: UInt16) -> Bool {
        (unit >= 97 && unit <= 122) || (unit >= 65 && unit <= 90) || unit == 45  // a-z A-Z -
    }

    private static func lowercasedASCII(_ units: ArraySlice<UInt16>) -> [UInt16] {
        units.map { $0 >= 65 && $0 <= 90 ? $0 + 32 : $0 }
    }

    /// The anchor a note's first line carries, and the words left after it —
    /// `nil` when the note has no header this stage owns.
    ///
    /// Hand-scanned, one pass, no backtracking: a header is
    /// attacker-controlled text in any file eDraft opens, and this grammar
    /// needs nested quantifiers as a regular expression (TypeScript
    /// `readNoteHeader`).
    public static func readHeader(_ text: String) -> HeaderReading? {
        let all = Array(text.utf16)
        let newline = all.firstIndex(of: 10)
        let first = newline.map { Array(all[..<$0]) } ?? all
        guard first.count > headerMark.count else { return nil }
        guard lowercasedASCII(first[..<headerMark.count]) == headerMark else { return nil }
        guard first.last == 93 else { return nil }  // ]

        let close = first.count - 1
        var at = headerMark.count
        var on: String?
        var nth: Int?

        while at < close {
            guard first[at] == 32 else { return nil }  // space
            at += 1
            let keyFrom = at
            while at < close, isKeyChar(first[at]) { at += 1 }
            guard at > keyFrom, at < close, first[at] == 58 else { return nil }  // :
            let key = String(decoding: lowercasedASCII(first[keyFrom..<at]), as: UTF16.self)
            at += 1

            var value: [UInt16] = []
            if at < close, first[at] == 34 {  // "
                at += 1
                while true {
                    guard at < close else { return nil }
                    if first[at] == 34 {
                        at += 1
                        break
                    }
                    if first[at] == 92 {  // backslash
                        at += 1
                        guard at < close else { return nil }
                    }
                    value.append(first[at])
                    at += 1
                }
            } else {
                let from = at
                while at < close, first[at] != 32, first[at] != 34, first[at] != 93 { at += 1 }
                value = Array(first[from..<at])
            }

            switch key {
            case "on":
                guard on == nil else { return nil }
                on = String(decoding: value, as: UTF16.self)
            case "nth":
                guard nth == nil, !value.isEmpty, value[0] != 48 else { return nil }  // no leading zero
                var number = 0
                for unit in value {
                    guard unit >= 48, unit <= 57 else { return nil }
                    number = number * 10 + Int(unit - 48)
                    guard number <= 1_000_000 else { return nil }
                }
                nth = number
            default:
                /* Stage 2's fields, or a key this build has never heard of:
                   not ours to read, and not ours to rewrite. */
                return nil
            }
        }

        guard let words = on, !words.isEmpty else { return nil }
        let body = newline.map { String(decoding: all[(all.index(after: $0))...], as: UTF16.self) } ?? ""
        return HeaderReading(anchor: nth == nil ? NoteAnchor(on: words) : NoteAnchor(on: words, nth: nth), body: body)
    }

    /// A value in the header's spelling. Used by a diagnostic naming the
    /// words too, so both ports read the same (TypeScript
    /// `quoteAnchorWords`).
    public static func quoteWords(_ value: String) -> String {
        var quoted = "\""
        for character in value {
            if character == "\\" || character == "\"" { quoted.append("\\") }
            quoted.append(character)
        }
        quoted.append("\"")
        return quoted
    }

    /// The header line for an anchor, written with lowercase keys (§4.1)
    /// (TypeScript `writeNoteHeader`).
    public static func writeHeader(_ anchor: NoteAnchor) -> String {
        let nth = anchor.nth.map { " nth:\($0)" } ?? ""
        return "[eDraft on:\(quoteWords(anchor.on))\(nth)]"
    }
}
