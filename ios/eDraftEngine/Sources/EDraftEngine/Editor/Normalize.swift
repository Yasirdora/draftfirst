import Foundation

/// Text normalization rules for character cues and parentheticals, ported
/// from the TypeScript engine's `normalize.ts`. Behaviour is pinned by
/// `Fixtures/normalize.json` — including the deliberate ASCII-only regex
/// semantics (a curly apostrophe `'` in `CONT'D` does NOT key the canonical
/// extension table, exactly as in JS).
public enum Normalize {

    // MARK: - Character extensions

    /// Canonical spellings keyed by the stripped, uppercased tail
    /// (TypeScript `EXTENSION_CANONICAL`).
    private static let extensionCanonical: [String: String] = [
        "VO": "V.O.",
        "OS": "O.S.",
        "OC": "O.C.",
        "CONTD": "CONT'D",
        "PRELAP": "PRE-LAP",
        "SUBTITLE": "SUBTITLE",
        "FILTERED": "FILTERED",
    ]

    /// Strips `[.\s'-]` — ASCII apostrophe only, matching the JS character
    /// class exactly (a curly `'` is preserved). Built locally because
    /// `Regex` is not `Sendable` and cannot be a static under Swift 6
    /// concurrency checking.
    private static func canonicalExtension(_ raw: String) -> String? {
        let strip = #/[.\s'-]/#
        let key = raw.replacing(strip, with: "").uppercased()
        return extensionCanonical[key]
    }

    // MARK: - Public API

    /// TypeScript `normalizeParenthetical`: trim, strip ONE leading `(` and
    /// ONE trailing `)`, trim, then wrap in `()` when non-empty.
    public static func normalizeParenthetical(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("(") { s.removeFirst() }
        if s.hasSuffix(")") { s.removeLast() }
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "" : "(\(s))"
    }

    /// TypeScript `unwrapParenthetical`: the inverse, for conversion OUT of
    /// the parenthetical lane. Sheds exactly one outer wrapper — "(beat)" →
    /// "beat", "((beat))" → "(beat)". A text holding several directions,
    /// "(a) (b)", keeps them: only a first "(" that closes at the very end
    /// is a wrapper. Partial states shed one stray end bracket; anything
    /// unbalanced is left exactly as written.
    public static func unwrapParenthetical(_ text: String) -> String {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        let opens = s.contains("(")
        let closes = s.contains(")")
        if !opens && !closes { return s }
        if !opens {
            // One stray closer: "beat)" → "beat" (one layer only).
            guard let i = s.lastIndex(of: ")") else { return s }
            var t = s
            t.remove(at: i)
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !closes {
            // One stray opener: "(beat" → "beat" (one layer only).
            guard let i = s.firstIndex(of: "(") else { return s }
            var t = s
            t.remove(at: i)
            return t.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Both present: strip only a true outer wrapper.
        var depth = 0
        for (offset, ch) in s.enumerated() {
            if ch == "(" { depth += 1 }
            if ch == ")" {
                depth -= 1
                if depth < 0 { return s }
                if depth == 0 {
                    guard offset == s.count - 1 else { return s }
                    return String(s.dropFirst().dropLast())
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        return s
    }

    /// TypeScript `normalizeCue`: canonicalize the extension on a character
    /// cue — `MARA (V.O)`, `MARA VO`, `MARA (vo)` all become `MARA (V.O.)`.
    public static func normalizeCue(_ text: String) -> String {
        // Bare trailing extension detector (TypeScript `BARE_EXTENSION`,
        // JS `/i`). Local because `Regex` is not `Sendable`.
        let bareExtension = #/(?i)\s+(V\.?O\.?|O\.?S\.?|O\.?C\.?|CONT'?D\.?|PRE[\s-]?LAP|SUBTITLE|FILTERED)$/#
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasSuffix(")") { return s }                    // already bracketed
        guard let open = s.firstIndex(of: "(") else {
            // No bracket: detect a bare trailing extension.
            if let match = s.firstMatch(of: bareExtension) {
                let name = String(s[s.startIndex..<match.range.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return s }
                let tail = String(match.output.1)
                let canonical = canonicalExtension(tail) ?? tail.uppercased()
                return "\(name) (\(canonical))"
            }
            return s
        }
        let name = String(s[s.startIndex..<open])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(s[s.index(after: open)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if tail.isEmpty { return name }
        if name.isEmpty { return s }
        let canonical = canonicalExtension(tail) ?? tail
        return "\(name) (\(canonical))"
    }

    /// TypeScript `looksLikeCue`: trimmed, ≥2 chars, not starting with `(`,
    /// contains an ASCII letter, and equal to its uppercased form.
    public static func looksLikeCue(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 2, !t.hasPrefix("(") else { return false }
        // JS: /[A-Za-z]/ — ASCII letters only, deliberately.
        guard t.contains(where: { $0.isASCII && $0.isLetter }) else { return false }
        return t == t.uppercased()
    }

    /// TypeScript `normalizeElementText`: dispatch per element kind.
    public static func normalizeElementText(kind: ElementKind, text: String) -> String {
        switch kind {
        case .parenthetical: return normalizeParenthetical(text)
        case .character: return normalizeCue(text)
        default: return text
        }
    }
}
