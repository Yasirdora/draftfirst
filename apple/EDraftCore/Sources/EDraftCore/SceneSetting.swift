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

    /// What the menu calls it: the abbreviation the screenplay is written in.
    ///
    /// A writer scanning for exteriors is looking for `EXT.` on the page, not
    /// for the word "exterior" — the filter should be named in the language
    /// they are already reading.
    public var title: String {
        switch self {
        case .interior: "Int."
        case .exterior: "Ext."
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
