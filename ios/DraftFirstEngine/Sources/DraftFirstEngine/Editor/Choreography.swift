import Foundation

/// Keyboard-driven element choreography — the typed contract behind Tab,
/// Enter, and the iOS swipe gestures. Ported line-for-line from the
/// TypeScript engine's `choreography.ts`; behaviour is pinned by
/// `Fixtures/choreography.json`.
public enum Choreography {

    /// Keys that drive choreography decisions. iOS swipe gestures resolve to
    /// `.tab` before calling in (forward) or use `backwards` (reverse).
    public enum Key: String, Codable, Sendable {
        case enter
        case tab
    }

    // MARK: - Maps (mirror of the TS tables)

    /// Where ENTER leads from each element (TypeScript `ENTER_FLOW`).
    private static let enterFlow: [ElementKind: ElementKind] = [
        .scene: .action,
        .action: .action,
        .character: .dialogue,
        .parenthetical: .dialogue,
        .dialogue: .character,
        .transition: .scene,
        .shot: .action,
        .general: .action,
        .centered: .action,
        .lyrics: .lyrics,
    ]

    /// Ring order used for free cycling (TypeScript `TAB_RING`).
    private static let tabRing: [ElementKind] = [
        .character, .dialogue, .parenthetical, .transition, .scene, .action,
    ]

    /// The "fresh line" set (TypeScript `TAB_SET_FRESH`).
    private static let tabSetFresh: [ElementKind] = [
        .scene, .action, .character, .transition,
    ]

    /// Context sets per current element (TypeScript `TAB_SETS`). After
    /// action the set includes action itself: a cycle that cannot return
    /// to what the line was traps the writer — one swipe from action lands
    /// on character, and no amount of cycling brings action back. Closing
    /// the loop keeps the first stop identical (action still enters at
    /// character) while making every gesture reversible.
    private static let tabSets: [ElementKind: [ElementKind]] = [
        .scene: [.action, .character, .transition],
        .action: [.action, .character, .transition],
        .character: [.dialogue, .parenthetical],
        .parenthetical: [.dialogue],
        // After a speech the writer is choosing between five real
        // destinations, in the order a script actually goes: keep speaking,
        // cut away, open a new scene, describe, or cue the next voice. Enter
        // lands the new line on a character cue, so one Tab forward wraps to
        // dialogue — the speech continues — and one Tab back reaches action.
        // A parenthetical is not in the set: a direction belongs under the
        // cue that introduces the speech, not between two lines of one.
        //
        // The fresh set was wrong here for the same reason it was wrong
        // after action, and worse: with dialogue missing from it, no gesture
        // could turn that new line back into the speech it was meant to
        // continue. The block was a one-way door.
        .dialogue: [.dialogue, .transition, .scene, .action, .character],
        .transition: tabSetFresh,
    ]

    // MARK: - Queries

    /// The ordered set TAB should cycle through given the element before the
    /// caret (TypeScript `tabSetFor`). Empty lines at the document start and
    /// lines after dialogue/transition use the fresh set.
    public static func tabSetFor(previous: ElementKind?) -> [ElementKind] {
        guard let previous else { return tabSetFresh }
        return tabSets[previous] ?? tabSetFresh
    }

    /// Next kind within a context set with wraparound (TypeScript `tabCycle`).
    /// If `current` is outside the set, forward enters at the head and
    /// reverse enters at the tail.
    public static func tabCycle(current: ElementKind, within set: [ElementKind],
                                backwards: Bool = false) -> ElementKind {
        guard let index = set.firstIndex(of: current) else {
            return backwards ? (set.last ?? current) : (set.first ?? current)
        }
        let next = backwards
            ? (index - 1 + set.count) % set.count
            : (index + 1) % set.count
        return set[next]
    }

    /// Free-cycle order for lines with no context (TypeScript `tabRingCycle`).
    /// Off-ring kinds join the ring at `.action` and cycle from there —
    /// forward yields `.character`, reverse yields `.scene`.
    public static func tabRingCycle(current: ElementKind, backwards: Bool = false) -> ElementKind {
        let base = tabRing.contains(current) ? current : .action
        return tabCycle(current: base, within: tabRing, backwards: backwards)
    }

    /// The element ENTER creates after `current`, with the engine's
    /// empty-text guard (TypeScript `nextElement`).
    public static func nextElement(after current: ElementKind,
                                   currentText: String) -> ElementKind {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && current != .action {
            return .action
        }
        return enterFlow[current] ?? .action
    }

    /// The element a key press creates after `previous` (TypeScript
    /// `nextElement`). Tab uses the free ring (context-set cycling is a
    /// separate API — `tabCycle` with `tabSetFor`); Enter uses `ENTER_FLOW`
    /// with the empty-text guard.
    public static func nextKind(after previous: ElementKind?,
                                key: Key,
                                currentText: String) -> ElementKind {
        switch key {
        case .tab:
            guard let previous else { return .scene }
            return tabRingCycle(current: previous)
        case .enter:
            return nextElement(after: previous ?? .action, currentText: currentText)
        }
    }
}
