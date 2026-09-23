import Foundation

/// Final Draft's page locks, as far as eDraft reads them today: whether a
/// file has any (RFC-DRAFT-PRODUCTION §7.2).
///
/// **A layering compromise, taken deliberately**, as `Omissions.recordedEighths`
/// is. The engine does not model `<LockedPages>` yet — a save keeps the block
/// byte for byte — while Final Draft moves each lock's `Position` with the
/// text (measured 2026-09-22: four paragraphs inserted, every later lock +46).
/// So an edit made here leaves those locks pointing at the wrong text in
/// Final Draft, and until the engine carries them the one thing the app needs
/// is to know that there are some, so it can say so (IL-0090). The scan is
/// narrow — the file's `<LockedPages>` block and nothing else — and it retires
/// the day the engine reads locks into the model.
public nonisolated enum FinalDraftPageLocks {

    /// How many `<LockedPage>` entries the file's `<LockedPages>` block holds.
    ///
    /// Text inside the script is entity-encoded, so the block's own tags are
    /// the only place these spellings occur; an empty or self-closing block
    /// holds none.
    public static func count(inOrigin origin: String) -> Int {
        guard let open = origin.range(of: "<LockedPages>"),
              let close = origin.range(of: "</LockedPages>", range: open.upperBound..<origin.endIndex)
        else { return 0 }
        var found = 0
        var rest = origin[open.upperBound..<close.lowerBound]
        while let tag = rest.range(of: "<LockedPage") {
            /* `<LockedPage ` or `<LockedPage/>` — never the block's own name. */
            if tag.upperBound < rest.endIndex, rest[tag.upperBound] != "s" { found += 1 }
            rest = rest[tag.upperBound...]
        }
        return found
    }
}
