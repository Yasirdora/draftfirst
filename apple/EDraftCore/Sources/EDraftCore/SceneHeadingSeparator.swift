import Foundation

/// The dash that divides a scene heading.
///
/// `INT. BASEMENT - MORNING` is three parts, and the dash between them is a
/// separator rather than punctuation. The engine draws that distinction by
/// spacing — a *spaced* dash divides a heading, a *tight* one is a hyphen
/// inside it — which is what keeps DRIVE-IN whole in `INT. DRIVE-IN THEATER -
/// NIGHT`, and it is exact in both directions.
///
/// It is also the distinction a phone keyboard destroys. Completing a word
/// from the suggestion bar leaves a trailing space, and typing punctuation
/// after that space deletes it: `BASEMENT-`. The engine then reads one long
/// location and answers with silence — no times offered, no ghost — and the
/// writer is left deleting the dash, typing a space, and typing the dash
/// again, on every scene heading they write.
///
/// So in a heading the dash key writes the separator rather than the
/// character. Whatever spacing arrives — none, one space, several, or the
/// keyboard's deletion of one — the result is a single `" - "`, which is the
/// one shape the engine reads. The writer who did mean a hyphen takes it back
/// with a single press of delete: see `collapsed(in:endingAt:)`.
///
/// The rules are pure and live apart from the text surface deliberately: what
/// a heading should read is a question about screenplays, and answering it
/// here keeps it out of the delegate callbacks and under test.
public enum SceneHeadingSeparator {

    /// What the engine reads as a division, and what this writes.
    public nonisolated static let separator = " - "

    /// The heading that results from typing a dash into `text` over `range`,
    /// with the caret offset that follows it.
    ///
    /// `nil` when the dash is not dividing anything and should simply be
    /// typed: at the start of a heading, where there is nothing to divide,
    /// and directly after an existing dash, where the writer is reaching for
    /// something else and a second separator would only be in the way.
    public nonisolated static func spaced(
        in text: NSString, replacing range: NSRange
    ) -> (text: String, caret: Int)? {
        guard range.location != NSNotFound,
              range.location >= 0,
              NSMaxRange(range) <= text.length else { return nil }

        let lead = trimmingTrailingSpaces(text.substring(to: range.location))
        guard !lead.isEmpty, !lead.hasSuffix("-") else { return nil }

        let rest = trimmingLeadingSpaces(text.substring(from: NSMaxRange(range)))
        return (lead + separator + rest, (lead as NSString).length + (separator as NSString).length)
    }

    /// Whether a space typed at `caret` would only repeat the one the
    /// separator already carries.
    ///
    /// Typing the dash writes `" - "` and leaves the caret after it, so a
    /// writer typing a slug straight through — `INT. KITCHEN - DAY`, spaces
    /// and all, which is how the muscle memory of every other screenwriting
    /// app produces one — adds a second space against the first and gets
    /// `INT. KITCHEN -  DAY`. Fountain still reads it, and so does
    /// `splitSceneHeading`; the damage is that it reaches the page, the PDF
    /// and the file, where a double space in a slug line is the kind of thing
    /// a professional notices.
    ///
    /// Absorbing it is the same judgement this type already makes twice:
    /// `spaced(in:replacing:)` trims whatever spacing surrounds the dash on
    /// the way in, and `collapsed(in:endingAt:)` gives the writer the tight
    /// hyphen back for one press of delete. A space in that position is noise
    /// by the same reasoning, and stated as a function of the text rather than
    /// of the last keystroke, so clicking into an existing heading behaves the
    /// same as typing one.
    public nonisolated static func absorbsSpace(in text: NSString, at caret: Int) -> Bool {
        let width = (separator as NSString).length
        guard caret >= width, caret <= text.length else { return false }
        return text.substring(with: NSRange(location: caret - width, length: width)) == separator
    }

    /// The tight hyphen a writer meant when the separator was not what they
    /// wanted — DRIVE-IN — reached by pressing delete once against a
    /// separator this type has just written.
    ///
    /// `nil` when the caret does not sit against such a separator, which
    /// leaves every other deletion in the heading to behave as it always has.
    public nonisolated static func collapsed(
        in text: NSString, endingAt caret: Int
    ) -> (text: String, caret: Int)? {
        let width = (separator as NSString).length
        guard caret >= width, caret <= text.length,
              text.substring(with: NSRange(location: caret - width, length: width)) == separator
        else { return nil }

        let head = text.substring(to: caret - width)
        return (head + "-" + text.substring(from: caret), (head as NSString).length + 1)
    }

    // MARK: - Spacing

    // Spaces only, and not `.whitespaces`: a heading is one line, and a tab or
    // a newline inside one is a structural accident that trimming would hide.

    nonisolated private static func trimmingTrailingSpaces(_ text: String) -> String {
        var trimmed = text
        while trimmed.hasSuffix(" ") { trimmed.removeLast() }
        return trimmed
    }

    nonisolated private static func trimmingLeadingSpaces(_ text: String) -> String {
        var trimmed = text
        while trimmed.hasPrefix(" ") { trimmed.removeFirst() }
        return trimmed
    }
}
