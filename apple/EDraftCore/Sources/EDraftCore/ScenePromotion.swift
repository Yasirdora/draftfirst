import EDraftEngine
import Foundation

/// When a line becomes something because of what it says.
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
/// Beside the slug stand the cards (RFC-SECONDARY-SLUG §5): the OMITTED card
/// the production retires a scene with, the closing card `THE END`, and the
/// secondary slug that names somewhere inside the setup (`BASIN - DAY`,
/// `MINUTES LATER`). The writer types them; the line becomes what it says.
///
/// Where typing and paste disagree, they disagree on purpose (D6): paste
/// gates the whole grammar on uppercase, because a pasted mixed-case line is
/// prose until proven otherwise; typing is the writer's own hand, so the
/// whole-line cards (OMITTED, THE END, the quantity-LATER family) promote in
/// any case, while the dash-form secondary slug keeps the uppercase gate —
/// the convention that slugs are typed in caps is the writer's signal, not
/// our guess.
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
        if FountainDetect.isSceneHeading(trimmed) { return .scene }
        // The OMITTED card: the writer's hand spells it OMIT or OMITTED, one
        // period tolerated, any case. The text stays as typed — the model's
        // one spelling ("OMITTED") is the import boundary's normalisation
        // (SceneNumbering.parseNumberedHeading), not a rewriting of the
        // writer's hand. Scene-typed so the navigator shows it and the
        // numbering keeps its number.
        var card = trimmed
        if card.hasSuffix(".") { card = String(card.dropLast()) }
        let upperCard = card.uppercased()
        if upperCard == "OMIT" || upperCard == "OMITTED" { return .scene }
        // The closing card.
        if PasteHeuristics.isEndCard(trimmed) { return .centered }
        // The secondary slug: the dash form uppercase-gated, the LATER card
        // read in any case (D6).
        if PasteHeuristics.isSecondarySlug(trimmed)
            || PasteHeuristics.isLaterCard(trimmed.uppercased()) { return .scene }
        return nil
    }
}
