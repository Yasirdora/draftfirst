import Foundation

/// The title page as lines: migration from the keyed model, derivation back
/// to keyed fields for the surfaces that ask by name (Fountain export, the
/// guided sheet), and the splice the sheet's writes go through.
/// docs/RFC-TITLE-PAGE.md — D1, D3, D7, D8. TypeScript `titlepage.ts`,
/// mirrored; the splice is the Swift half of D7 the web editor has not
/// grown yet.
///
/// The geometry is the 12pt Courier line grid every screenplay page already
/// obeys: textTop 72, lineHeight 12, US Letter height 792. The classic
/// keyed renderer anchored the stack at 0.32 × 792 = 253.44pt, which is not
/// a grid position; the template below anchors at line 15 (72 + 15 × 12 =
/// 252pt), so the top stack settles exactly 1.44pt onto the grid — once, at
/// migration, pinned by the identity tests. The contact block's classic
/// anchor (page height − 72 = 720) IS a grid position (line 54), so contact
/// does not move at all.
public enum TitlePage {

    /// Blank lines above the stack's first line: 72 + 15 × 12 = 252pt down.
    public static let stackLeadingBlanks = 15
    /// The grid line the contact block's last line sits on: 72 + 54 × 12 = 720.
    public static let contactLastLine = 54

    /// The keyed shape documents carried before the line model — migration
    /// input only (TypeScript `LegacyTitlePageEntry`).
    public struct LegacyEntry: Codable, Equatable, Sendable {
        public var key: String
        public var values: [String]

        public init(key: String, values: [String]) {
            self.key = key
            self.values = values
        }
    }

    /// One keyed field recovered from the lines — Fountain export and the
    /// guided sheet both ask by name, so derivation answers by name.
    public struct DerivedEntry: Equatable, Sendable {
        public var key: String
        public var values: [String]
    }

    /// Derivation's full answer: the entries, which entry owns each value
    /// line, and the label lines (the printed key above a group's values).
    /// Ownership is what the splice rewrites by — an edit touches only the
    /// lines its key owns.
    public struct Derivation: Equatable, Sendable {
        public var entries: [DerivedEntry]
        /// Line index → index into `entries`, for value lines.
        public var owners: [Int: Int]
        /// Line index → index into `entries`, for label lines: accounted
        /// for, carrying no value, exempt from the fold.
        public var labels: [Int: Int]

        public init(entries: [DerivedEntry], owners: [Int: Int], labels: [Int: Int]) {
            self.entries = entries
            self.owners = owners
            self.labels = labels
        }
    }

    private static func blank() -> TitlePageLine { TitlePageLine(text: "") }
    private static func centre(_ text: String, _ key: String) -> TitlePageLine {
        TitlePageLine(text: text, key: key)
    }
    private static func isBlank(_ line: TitlePageLine) -> Bool {
        line.text.jsTrimmed.isEmpty
    }
    private static func nonEmpty(_ values: [String]) -> [String] {
        values.filter { !$0.jsTrimmed.isEmpty }
    }
    private static func text(_ line: TitlePageLine) -> String { line.text.jsTrimmed }

    // MARK: - Migration (D8)

    /// The classic template, written as lines. Every line the keyed
    /// renderer would have drawn becomes a line here, at the grid position
    /// that renderer's arithmetic implies — including the key lines it
    /// printed ahead of every extra key except Source, and the title in the
    /// uppercase the renderer forced. Entries with no non-empty values
    /// rendered nothing and migrate to nothing.
    public static func lines(from entries: [LegacyEntry]) -> [TitlePageLine] {
        guard !entries.isEmpty else { return [] }
        func find(_ key: String) -> [String] {
            nonEmpty(entries.first { $0.key.lowercased() == key }?.values ?? [])
        }
        var lines: [TitlePageLine] = []
        for _ in 0..<stackLeadingBlanks { lines.append(blank()) }

        for value in find("title") { lines.append(centre(value.uppercased(), "Title")) }
        lines.append(blank())
        for value in find("credit") { lines.append(centre(value, "Credit")) }
        lines.append(blank())
        for value in find("author") { lines.append(centre(value, "Author")) }

        for entry in entries {
            let key = entry.key.lowercased()
            if key == "title" || key == "credit" || key == "author" || key == "contact" { continue }
            let values = nonEmpty(entry.values)
            if values.isEmpty { continue }
            lines.append(blank())
            if key != "source" { lines.append(centre(entry.key, entry.key)) }
            for value in values { lines.append(centre(value, entry.key)) }
        }

        let contact = find("contact")
        if !contact.isEmpty {
            let firstLine = contactLastLine - (contact.count - 1)
            while lines.count < firstLine { lines.append(blank()) }
            for value in contact {
                lines.append(TitlePageLine(text: value, alignment: .left, key: "Contact"))
            }
        }

        while let last = lines.last, isBlank(last) { lines.removeLast() }
        return lines
    }

    // MARK: - Derivation (D3/D7)

    /// The inverse of the template, generalised to lines that came from
    /// anywhere. Annotation-first: a line carrying a key belongs to that
    /// key. Unannotated lines fall to the heuristics — the opening
    /// contiguous run is the title, a standard credit phrase opens the
    /// credit, the run under it is the authors, a trailing left-aligned
    /// block is the contact. Anything still unclaimed folds into the
    /// previous entry as a continuation value, because no surface may lose
    /// a line silently.
    public static func derive(_ lines: [TitlePageLine]) -> Derivation {
        var entries: [DerivedEntry] = []
        var byKey: [String: Int] = [:]
        var owners: [Int: Int] = [:]
        var labels: [Int: Int] = [:]
        func claim(_ index: Int, _ key: String) {
            let needle = key.lowercased()
            let entryIndex: Int
            if let existing = byKey[needle] {
                entryIndex = existing
            } else {
                entryIndex = entries.count
                entries.append(DerivedEntry(key: key, values: []))
                byKey[needle] = entryIndex
            }
            entries[entryIndex].values.append(text(lines[index]))
            owners[index] = entryIndex
        }

        /* Pass 1 — annotated lines group under their keys. A line whose
           text is its own key, standing first in a non-Source group, is the
           label the template prints above the values, not a value itself —
           without this the serialise → parse cycle would grow a copy of the
           key on every round trip. */
        var groups: [String: [Int]] = [:]
        var groupOrder: [String] = []
        var keyNames: [String: String] = [:]
        for (index, line) in lines.enumerated() {
            if isBlank(line) { continue }
            guard let rawKey = line.key?.jsTrimmed, !rawKey.isEmpty else { continue }
            let needle = rawKey.lowercased()
            if groups[needle] == nil {
                groups[needle] = []
                groupOrder.append(needle)
                keyNames[needle] = rawKey
            }
            groups[needle]?.append(index)
        }
        for needle in groupOrder {
            guard let indexes = groups[needle], let key = keyNames[needle],
                  let firstIndex = indexes.first else { continue }
            let labelled = needle != "source"
                && indexes.count > 1
                && text(lines[firstIndex]).lowercased() == needle
            for index in indexes.dropFirst(labelled ? 1 : 0) { claim(index, key) }
            /* The label is recorded only after the claims, so it points at
               an entry that exists — a labelled group always has at least
               one value line by construction. */
            if labelled { labels[firstIndex] = byKey[needle] }
        }

        /* Pass 2 — heuristics claim the lines no annotation did, only for
           keys the annotations did not already provide. */
        func free(_ index: Int) -> Bool {
            !isBlank(lines[index]) && owners[index] == nil
        }
        func has(_ key: String) -> Bool { byKey[key] != nil }
        func isCreditPhrase(_ line: TitlePageLine) -> Bool {
            TitleCredits.StandardCredit.matching(text(line)) != nil
        }
        func contiguousFrom(_ start: Int) -> [Int] {
            var claimed: [Int] = []
            var i = start
            while i < lines.count, free(i) { claimed.append(i); i += 1 }
            return claimed
        }

        if !has("title"), let start = lines.indices.first(where: { free($0) }) {
            for index in contiguousFrom(start) { claim(index, "Title") }
        }
        if !has("credit"), let at = lines.indices.first(where: { free($0) && isCreditPhrase(lines[$0]) }) {
            claim(at, "Credit")
        }
        if !has("author"), let creditEntry = byKey["credit"],
           let creditAt = lines.indices.first(where: {
               owners[$0] == creditEntry && isCreditPhrase(lines[$0])
           }) {
            for index in contiguousFrom(creditAt + 1) { claim(index, "Author") }
        }
        if !has("contact") {
            var trailing: [Int] = []
            var i = lines.count - 1
            while i >= 0 {
                let line = lines[i]
                if isBlank(line) {
                    if !trailing.isEmpty { break }
                } else if free(i), (line.alignment ?? .center) == .left {
                    /* The block must reach the page's end: a left line with
                       non-left content below it is not a contact block. */
                    trailing.insert(i, at: 0)
                } else {
                    break
                }
                i -= 1
            }
            for index in trailing { claim(index, "Contact") }
        }

        /* Pass 3 — nothing is lost: an unclaimed line continues the nearest
           entry above it. */
        var last: Int? = nil
        for (index, line) in lines.enumerated() {
            if isBlank(line) || labels[index] != nil { continue }
            if let owner = owners[index] {
                last = owner
                continue
            }
            if let last {
                entries[last].values.append(text(line))
                owners[index] = last
            } else {
                claim(index, "Title")
                last = byKey["title"]
            }
        }

        return Derivation(entries: entries, owners: owners, labels: labels)
    }

    /// What the guided surfaces ask most: the values under one key, derived.
    public static func values(_ lines: [TitlePageLine], for key: String) -> [String] {
        let needle = key.lowercased()
        return derive(lines).entries.first { $0.key.lowercased() == needle }?.values ?? []
    }

    // MARK: - The splice (D7)

    /// The sheet's write path: an edit rewrites only the lines its key
    /// owns — every other line stays exactly where it is, with one
    /// exception: the blank padding above the contact block is expendable,
    /// and it grows or shrinks so the block keeps the grid anchor the
    /// classic renderer pinned it to. `values` arrives normalised by the
    /// caller (trimmed, empties dropped); empty removes the key's lines.
    /// The replacement keeps the group's own key spelling and its label
    /// shape (a label the group had is reprinted; one it lacked is not
    /// invented). Title values store their printed form — the uppercase
    /// the classic renderer forced — so the page a write produces is the
    /// page the template would have drawn. A new group lands where the
    /// template would have put it: the stack on top, extras after the
    /// last claimed group, contact anchored bottom-left at the grid line.
    ///
    /// Pure and total: comparing the result against the input IS the
    /// change detection, so callers never duplicate the transform rules.
    public static func spliced(
        _ lines: [TitlePageLine], key: String, values: [String]
    ) -> [TitlePageLine] {
        let derivation = derive(lines)
        let needle = key.lowercased()
        let special: Set<String> = ["title", "credit", "author", "source", "contact"]
        let canonical: [String: String] = [
            "title": "Title", "credit": "Credit", "author": "Author",
            "source": "Source", "contact": "Contact",
        ]

        let entryIndex = derivation.entries.firstIndex { $0.key.lowercased() == needle }
        /* The group's own lines, in page order: its label (if any) and its
           value lines. */
        var owned: [Int] = []
        var labelIndex: Int? = nil
        if let entryIndex {
            owned = derivation.owners
                .filter { $0.value == entryIndex }
                .map(\.key)
                .sorted()
            labelIndex = derivation.labels.first { $0.value == entryIndex }?.key
        }
        let spelling: String = {
            if let first = owned.first, let existing = lines[first].key, !existing.jsTrimmed.isEmpty {
                return existing
            }
            return canonical[needle] ?? key
        }()

        /* The replacement lines. Title stores its printed (uppercase) form;
           contact is left-aligned; a custom group reprints its label only
           if it had one — or if it is brand new, which is the template's
           shape. */
        let wantsLabel = !values.isEmpty
            && !special.contains(needle)
            && (entryIndex == nil || labelIndex != nil)
        var replacement: [TitlePageLine] = []
        if wantsLabel { replacement.append(centre(spelling, spelling)) }
        for value in values {
            switch needle {
            case "title":
                replacement.append(TitlePageLine(text: value.uppercased(), key: spelling))
            case "contact":
                replacement.append(TitlePageLine(text: value, alignment: .left, key: spelling))
            default:
                replacement.append(centre(value, spelling))
            }
        }

        if entryIndex != nil, let first = owned.first, let last = owned.last {
            /* Replace in place. Contact is anchored by its bottom line —
               the classic renderer pinned it to the grid and the padding
               above absorbed every size change. */
            let rangeStart = labelIndex.map { min($0, first) } ?? first
            if needle == "contact" {
                var start = max(0, last - (replacement.count - 1))
                while start < rangeStart, !isBlank(lines[start]) { start += 1 }
                if start >= rangeStart {
                    /* Shrink, same size, or no absorbable padding: the
                       block's bottom line stays put and the gap the old
                       lines leave refills with blanks. */
                    return lines[..<rangeStart]
                        + (0..<(start - rangeStart)).map { _ in blank() }
                        + replacement
                        + lines[(last + 1)...]
                }
                /* Growth that absorbs blank padding directly above the
                   block — never another group's line. */
                return lines[..<start] + replacement + lines[(last + 1)...]
            }
            let result = Array(lines[..<rangeStart]) + replacement + lines[(last + 1)...]
            /* A stack edit above the contact block keeps contact's anchor. */
            if let contactFirst = contactFirstLine(of: derivation), contactFirst > last {
                return balancingContact(result, original: lines, contactFirst: contactFirst)
            }
            return result
        }

        guard !replacement.isEmpty else { return lines }

        /* A new group. Title tops the stack; credit follows the title and
           author the credit, one blank between; extras follow the last
           claimed group; contact pads to its grid anchor. Anything appended
           below existing content leads with one blank, the template's
           separator. */
        func insertAtTop() -> [TitlePageLine] {
            let at = lines.firstIndex { !isBlank($0) } ?? 0
            return lines[..<at] + replacement + lines[at...]
        }
        func afterGroup(_ group: String) -> [TitlePageLine]? {
            guard let groupEntry = derivation.entries.firstIndex(where: {
                $0.key.lowercased() == group
            }) else { return nil }
            guard let groupLast = derivation.owners
                .filter({ $0.value == groupEntry })
                .map(\.key)
                .max() else { return nil }
            return lines[...(groupLast)] + [blank()] + replacement + lines[(groupLast + 1)...]
        }
        /* Insertions above the contact block keep its anchor too. */
        func balanced(_ result: [TitlePageLine]) -> [TitlePageLine] {
            if let contactFirst = contactFirstLine(of: derivation) {
                return balancingContact(result, original: lines, contactFirst: contactFirst)
            }
            return result
        }

        switch needle {
        case "title":
            return balanced(insertAtTop())
        case "credit":
            return balanced(afterGroup("title") ?? insertAtTop())
        case "author":
            return balanced(afterGroup("credit") ?? afterGroup("title") ?? insertAtTop())
        case "contact":
            let firstLine = contactLastLine - (replacement.count - 1)
            var out = lines
            if out.count < firstLine {
                while out.count < firstLine { out.append(blank()) }
            } else if let last = out.last, !isBlank(last) {
                out.append(blank())
            }
            return out + replacement
        default:
            /* Extras sit after the last claimed group, ahead of the contact
               block's padding, so contact keeps its anchor. */
            if let contactFirst = contactFirstLine(of: derivation) {
                var at = contactFirst
                while at > 0, isBlank(lines[at - 1]) { at -= 1 }
                return balanced(lines[..<at] + [blank()] + replacement + lines[at...])
            }
            if let lastClaim = derivation.owners.keys.max() {
                return lines[...(lastClaim)] + [blank()] + replacement + lines[(lastClaim + 1)...]
            }
            var out = lines
            if let last = out.last, !isBlank(last) { out.append(blank()) }
            return out + replacement
        }
    }

    /// The contact block's first value line in this page, when one exists.
    private static func contactFirstLine(of derivation: Derivation) -> Int? {
        guard let entry = derivation.entries.firstIndex(where: {
            $0.key.lowercased() == "contact"
        }) else { return nil }
        return derivation.owners.filter { $0.value == entry }.map(\.key).min()
    }

    /// The classic renderer anchored contact at its grid line no matter
    /// how the stack above it grew or shrank. The splice keeps that
    /// invariant: an edit above the contact block is balanced by the blank
    /// padding directly above it — padding is expendable by definition.
    /// More growth than the padding can absorb shifts the block, the
    /// honest answer for a genuinely full page.
    private static func balancingContact(
        _ result: [TitlePageLine], original: [TitlePageLine], contactFirst: Int
    ) -> [TitlePageLine] {
        let delta = result.count - original.count
        guard delta != 0 else { return result }
        var out = Array(result)
        let blockStart = contactFirst + delta
        guard blockStart >= 0, blockStart <= out.count else { return result }
        if delta > 0 {
            var runStart = blockStart
            while runStart > 0, isBlank(out[runStart - 1]) { runStart -= 1 }
            let removable = min(delta, blockStart - runStart)
            out.removeSubrange((blockStart - removable)..<blockStart)
        } else {
            out.insert(contentsOf: repeatElement(blank(), count: -delta), at: blockStart)
        }
        return out
    }
}
