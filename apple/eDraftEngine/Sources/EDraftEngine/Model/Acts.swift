import Foundation

/// The act derivation (RFC-ACT-BREAK §2, §4): ordinals, the canonical card
/// spelling, and the renumber rule — the one home of that arithmetic, so the
/// FDX boundary's generated End of Act cards, the selector's default card
/// text, and the renumber rule cannot disagree.
///
/// Ported call for call from the TypeScript engine's `acts.ts`; the port is
/// pinned to it by `Fixtures/acts.json`.
public enum Acts {

    /// The words an act card spells its ordinal with: ONE through TWENTY,
    /// then digits — some scripts run long (RFC-ACT-BREAK §4).
    public static let ordinalWords = [
        "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE",
        "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN",
        "SEVENTEEN", "EIGHTEEN", "NINETEEN", "TWENTY"
    ]

    /// The ordinal an act card spells, 1-based: a word through twenty, the
    /// digits beyond.
    public static func ordinal(_ n: Int) -> String {
        n >= 1 && n <= ordinalWords.count ? ordinalWords[n - 1] : String(n)
    }

    /// Whether a card speaks the canonical spelling (RFC-ACT-BREAK §4). A
    /// card in this shape means only "the act I am" and so follows the
    /// renumber rule; anything else — TEASER, ACT TWO: THE TURN, a lowercase
    /// act one — is the writer's text and is never rewritten. Answered
    /// without a regex so the port cannot drift from the TypeScript
    /// `[0-9]` character class on a non-ASCII digit.
    public static func isCanonicalActCard(_ text: String) -> Bool {
        guard text.hasPrefix("ACT ") else { return false }
        let tail = text.dropFirst(4)
        guard !tail.isEmpty else { return false }
        if ordinalWords.contains(String(tail)) { return true }
        return tail.allSatisfy { ("0"..."9").contains($0) }
    }

    /// The default card a freshly inserted act break carries: the canonical
    /// spelling of the ordinal it was inserted at. The renumber rule keeps
    /// it true afterwards, which is the point of starting canonical.
    public static func defaultCard(ordinal: Int) -> String {
        "ACT \(Self.ordinal(ordinal))"
    }

    /// The cards the paste route recognises as act breaks (RFC-ACT-BREAK §5):
    /// a canonical act card, or one of television's unnumbered openers. Both
    /// tests are exact and case-sensitive — a lowercase "teaser" is prose
    /// until the writer shouts it. The corpus witness is Breaking Bad:
    /// TEASER, then ACT ONE through ACT FOUR, and nothing else in fourteen
    /// scripts matches.
    public static func isActCard(_ text: String) -> Bool {
        isCanonicalActCard(text) || text == "TEASER" || text == "COLD OPEN"
    }

    /// The companion card that closes an act on the page (RFC-ACT-BREAK §5):
    /// "END ACT ONE", "END OF ACT ONE", or the teaser's own "END TEASER" —
    /// the exact set the corpus carries; "END OF 4M26 MI CAMINO" is a music
    /// cue and must not match, so ACT must end on a word boundary. These
    /// lines are dropped on import, never stored: an act ends where the next
    /// one begins, and the FDX boundary regenerates the card from the
    /// derivation.
    ///
    /// Answered without a regex, with the boundary read the way JavaScript's
    /// `\b` reads it: a word character is an ASCII letter, digit, or
    /// underscore — a Unicode letter like É is a boundary, matching the
    /// TypeScript engine's `[A-Za-z0-9_]` class exactly.
    public static func isEndActCard(_ text: String) -> Bool {
        if text == "END TEASER" { return true }
        var rest = Substring(text)
        if rest.hasPrefix("END OF ") {
            rest = rest.dropFirst(7)
        } else if rest.hasPrefix("END ") {
            rest = rest.dropFirst(4)
        } else {
            return false
        }
        guard rest.hasPrefix("ACT") else { return false }
        guard let next = rest.dropFirst(3).first else { return true }
        let isWordChar = next.isASCII && (next.isLetter || next.isNumber || next == "_")
        return !isWordChar
    }

    /// The renumber rule (RFC-ACT-BREAK §4): every card still speaking the
    /// canonical spelling is renumbered to the ordinal its position now
    /// carries; a card that doesn't match is the writer's text and is left
    /// alone. Every act break counts toward the ordinals, custom card or
    /// not — an act boundary is an act boundary however it is labelled.
    ///
    /// Idempotent: a second pass changes nothing. That is what lets a
    /// surface run it after any edit that touched the act count — insert,
    /// delete, undo — without asking which one happened.
    public static func renumber(_ elements: [ScreenplayElement]) -> [ScreenplayElement] {
        var ordinal = 0
        return elements.map { element in
            guard element.type == .actbreak else { return element }
            ordinal += 1
            let canonical = defaultCard(ordinal: ordinal)
            guard element.text != canonical, isCanonicalActCard(element.text) else { return element }
            var copy = element
            copy.text = canonical
            return copy
        }
    }
}
