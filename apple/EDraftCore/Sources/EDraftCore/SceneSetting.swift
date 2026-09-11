import EDraftEngine
import Foundation

/// Whether a scene plays inside, outside, or crosses between.
///
/// A writer types this half a dozen ways — `INT.`, `int`, `I/E`, `INT/EXT`,
/// `INT./EXT.` — and a filter that matched the letters would answer only for
/// the spelling it was taught. So the heading goes through the engine's
/// `splitSceneHeading`, which is the same parse Fountain uses to decide the
/// line is a heading at all, and this groups the canonical prefix it returns.
/// Nothing here re-decides what a scene heading is.
///
/// `EST.` counts as exterior. An establishing shot is a shot of the outside of
/// somewhere, and a schedule treats it that way; giving it a fourth case would
/// buy a distinction almost no script uses and cost every filter a column.
public nonisolated enum SceneSetting: String, CaseIterable, Sendable, Identifiable {
    case interior
    case exterior
    case both

    public var id: String { rawValue }

    /// What the menu calls it.
    ///
    /// Spelled out for the two a writer picks most, abbreviated for the third.
    /// The abbreviations were chosen so the filter would be named in the
    /// language on the page — but "Int." and "Ext." sitting alone in a menu
    /// read as truncations rather than as the words they stand for, and a menu
    /// is not the page. The crossing case keeps its short form: "Interior /
    /// Exterior" is a mouthful for a row, and `Int. / Ext.` is how a writer
    /// says it out loud anyway.
    public var title: String {
        switch self {
        case .interior: "Interior"
        case .exterior: "Exterior"
        case .both: "Int. / Ext."
        }
    }

    /// The same thing inside a sentence, where "no int. scenes" would read as
    /// a typo — an empty state, or a screen reader.
    public var phrase: String {
        switch self {
        case .interior: "interior"
        case .exterior: "exterior"
        case .both: "interior or exterior"
        }
    }

    public var symbol: String {
        switch self {
        case .interior: "house"
        case .exterior: "tree"
        case .both: "arrow.left.and.right"
        }
    }

    /// Nil when the line has no intro token the engine recognises — a
    /// sequence heading, or a slug a writer forced with a leading dot.
    ///
    /// `isSceneHeading` decides that, not `splitSceneHeading`. The splitter is
    /// built for completion, where the line is already known to be a heading,
    /// so it will take `INT` out of `INTO THE WOODS` and leave `O THE WOODS`
    /// behind. Fountain's own detector requires a separator after the token,
    /// which is what keeps a forced slug from being filed as an interior.
    public init?(heading: String) {
        let trimmed = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard FountainDetect.isSceneHeading(trimmed) else { return nil }
        switch SmartType.splitSceneHeading(trimmed).prefix {
        case "INT.": self = .interior
        case "EXT.", "EST.": self = .exterior
        case "I/E", "INT/EXT.", "INT./EXT.": self = .both
        default: return nil
        }
    }
}
