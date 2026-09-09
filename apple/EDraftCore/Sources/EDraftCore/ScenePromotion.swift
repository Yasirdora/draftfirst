import EDraftEngine
import Foundation

/// When a line becomes a scene heading because of what it says.
///
/// Fountain defines a line beginning INT./EXT./EST./I/E. as a slug — that is
/// the format's rule, not a guess — and until now the editor disagreed with its
/// own parser: you could type `INT. KITCHEN - DAY`, watch it stay action on the
/// page, save, reopen, and find it had been a scene heading all along.
///
/// Promoting as it is typed settles that, and it is what lets the Return ring
/// stay at two stops: a writer reaches action and a cue with the Return key,
/// because those are the two kinds you cannot type your way into, and reaches a
/// slug by typing one.
///
/// It only ever promotes, and only from the kinds that mean "I have not said
/// what this is". A writer who has deliberately made a line a cue or a
/// transition is not second-guessed because their words happen to begin with
/// three letters and a full stop.
public nonisolated enum ScenePromotion {

    /// The kinds that have not yet been claimed. Action is what a line is when
    /// nobody has said otherwise; general is its imported equivalent.
    private static let unclaimed: Set<ScreenplayKind> = [.action, .general]

    /// The kind this line should become, or nil to leave it alone.
    public static func kind(
        for text: String, currently kind: ScreenplayKind
    ) -> ScreenplayKind? {
        guard unclaimed.contains(kind) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard FountainDetect.isSceneHeading(trimmed) else { return nil }
        return .scene
    }
}
