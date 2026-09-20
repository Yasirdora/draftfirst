import EDraftEngine
import Foundation

/// The scenes a production has omitted, as the surface needs them —
/// RFC-DRAFT-PRODUCTION §7.3.
///
/// The engine reads an FDX `<OmittedScene>` into `Screenplay.omissions`, a
/// span of element *indices* (IL-0071). Indices are fine inside one reading
/// of one file and useless afterwards: the writer types a line above the
/// span and every index below it is wrong. So the span is converted here,
/// once, into the `DraftElementID`s of the elements it covers (M1,
/// IL-0073), and the surface asks about elements, never about positions.
///
/// Nothing here decides what is omitted. That is the file's to say, and
/// §7.3 blocks omitting from the app in `development` anyway. This is a
/// reading of the document that was opened.
public nonisolated struct OmittedScenes: Equatable, Sendable {

    /// Every element inside an omitted span: the scene heading the span
    /// starts at, and its body down to the last element of the span.
    public private(set) var elements: Set<DraftElementID>
    /// The OMITTED card each span hangs under — the Scene Heading Final
    /// Draft nests the block inside, which still prints and still holds the
    /// scene number. A card is *not* omitted: it is what the omission looks
    /// like on the page (§7.3, "the span prints as an OMITTED card").
    public private(set) var cards: Set<DraftElementID>

    public init(elements: Set<DraftElementID> = [], cards: Set<DraftElementID> = []) {
        self.elements = elements
        self.cards = cards
    }

    public var isEmpty: Bool { elements.isEmpty }

    /// Whether this element is inside an omitted span — muted, struck, and
    /// closed to the caret.
    public func contains(_ element: ScriptElement) -> Bool {
        guard let id = element.draftID else { return false }
        return elements.contains(id)
    }

    /// Whether this element is the OMITTED card in front of a span.
    public func isCard(_ element: ScriptElement) -> Bool {
        guard let id = element.draftID else { return false }
        return cards.contains(id)
    }
}

public nonisolated enum Omissions {

    /// The omitted spans of a Final Draft file, placed on the document as it
    /// stands at open.
    ///
    /// The engine says which elements of *its* reading are omitted; the
    /// editor's lines are the same file carried through Fountain, with
    /// identities of their own. The two agree index for index — the same
    /// correspondence `ImportedNotes.resolve` relies on, and the reason both
    /// are attached at open, from the same parse, before any edit has moved
    /// anything. A span that cannot be placed is dropped rather than guessed
    /// at: a mis-placed span would grey out a scene the writer is working in.
    public static func resolve(
        _ omissions: [EDraftEngine.Omission],
        imported: [EDraftEngine.ScreenplayElement],
        document: [ScriptElement]
    ) -> OmittedScenes {
        guard !omissions.isEmpty, imported.count == document.count else {
            return OmittedScenes()
        }
        var elements: Set<DraftElementID> = []
        var cards: Set<DraftElementID> = []
        for omission in omissions {
            guard omission.start > 0, omission.start < omission.end,
                  omission.end <= document.count else { continue }
            /* The card is the element the block is nested in — the one
               before the span (§7.3). Without it the span is still omitted;
               it just has no card to mark. */
            if let card = document[omission.start - 1].draftID { cards.insert(card) }
            for at in omission.start..<omission.end {
                if let id = document[at].draftID { elements.insert(id) }
            }
        }
        return OmittedScenes(elements: elements, cards: cards)
    }

    /// The same script with the omitted elements taken out, for the
    /// paginator.
    ///
    /// *Measured on `finaldraft-sample02.fdx`, the file Final Draft 13.4
    /// wrote:* the OMITTED card records `Length="0" Page="17"`, and the
    /// scene nested inside the block records `Page="1"` while the script's
    /// 35 live scenes run monotonically from page 1 to page 25. `Page="1"`
    /// is not a place in a 25-page script — that scene was never paginated
    /// in situ. So Final Draft does not count an omitted scene toward page
    /// numbers, the card holds its place at no measurable height, and this
    /// does the same.
    /// `kept` maps each index of the returned model back to its index in the
    /// script, so page numbers land on the right lines afterwards.
    public static func paginable(
        _ model: EDraftEngine.Screenplay,
        document: [ScriptElement],
        omitted: OmittedScenes
    ) -> (model: EDraftEngine.Screenplay, kept: [Int]) {
        guard !omitted.isEmpty, model.elements.count == document.count else {
            return (model, Array(model.elements.indices))
        }
        var elements: [EDraftEngine.ScreenplayElement] = []
        var kept: [Int] = []
        for (at, pair) in zip(model.elements, document).enumerated() where !omitted.contains(pair.1) {
            elements.append(pair.0)
            kept.append(at)
        }
        var paginable = model
        paginable.elements = elements
        return (paginable, kept)
    }

    /// Page numbers, keyed by the script's own element indices again.
    /// An omitted element is on no page and appears nowhere here.
    public static func restored(_ pages: [Int: Int], through kept: [Int]) -> [Int: Int] {
        var out: [Int: Int] = [:]
        out.reserveCapacity(pages.count)
        for (at, page) in pages where at >= 0 && at < kept.count { out[kept[at]] = page }
        return out
    }
}
