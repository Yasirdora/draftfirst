import Foundation

/// What it means to send a reader somewhere.
///
/// A Navigator row has two jobs: move the page, and say where it landed.
/// Scrolling alone cannot do the second — a script stops scrolling once its
/// last page reaches the bottom, so a target within a screen of the end never
/// reaches the top, and one already in view never moves the page at all. While
/// reading there is not even a caret to mark the arrival. All three read as a
/// dead row, which is exactly how the cast list was reported: its lines are
/// usually already on screen.
///
/// So a reveal is a scroll *and* a mark, on every platform. The drawing
/// belongs to whichever framework is at hand — `RevealHighlightView` on iOS,
/// its AppKit counterpart on the Mac — but the timing does not: a mark that
/// appears and fades differently on a desk than in a hand is the same feature
/// behaving like two, and nothing in a compiler would notice.
public nonisolated enum RevealMark {

    /// The mark waits before appearing. The Navigator is still sliding away
    /// when the reveal is asked for, and a mark that fades in behind a
    /// dismissing sheet is a mark the reader never sees.
    public static let wait: TimeInterval = 0.25
    public static let fadeIn: TimeInterval = 0.15
    /// Long enough to be found by an eye that was looking at the sheet.
    public static let hold: TimeInterval = 1.0
    public static let fadeOut: TimeInterval = 0.5

    /// How far the mark is drawn outside the text it marks, so a highlight
    /// reads as a band across the line rather than a box around the glyphs.
    public static let horizontalPadding = 6.0
    public static let verticalPadding = 2.0
    public static let cornerRadius = 6.0

    /// A mark that fades is motion; a reader who has asked for less of it
    /// still needs to see where they landed, so it simply appears and goes.
    public static func timing(reduceMotion: Bool)
    -> (wait: TimeInterval, fadeIn: TimeInterval, hold: TimeInterval, fadeOut: TimeInterval) {
        reduceMotion
            ? (wait: wait, fadeIn: 0, hold: hold, fadeOut: 0)
            : (wait: wait, fadeIn: fadeIn, hold: hold, fadeOut: fadeOut)
    }
}
