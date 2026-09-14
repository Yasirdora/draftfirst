import Foundation
import Testing
import EDraftEngine

/// The title page as lines (docs/RFC-TITLE-PAGE.md): the keyed model's
/// migration into the classic renderer's template, the derivation that
/// answers keyed questions, and the splice the guided sheet writes through.
@Suite("Title page")
struct TitlePageTests {

    private let classicEntries = [
        TitlePage.LegacyEntry(key: "Title", values: ["The Last Station"]),
        TitlePage.LegacyEntry(key: "Credit", values: ["written by"]),
        TitlePage.LegacyEntry(key: "Author", values: ["Jane Smith & John Smith"]),
        TitlePage.LegacyEntry(key: "Source", values: ["the novel by Mary Jones"]),
        TitlePage.LegacyEntry(key: "Contact", values: ["Jane Smith", "jane@example.com"]),
    ]

    // MARK: Migration (D8)

    @Test("The keyed model migrates onto the renderer's own grid")
    func migrationGeometry() {
        let lines = TitlePage.lines(from: classicEntries)
        /* textTop 72 + 15 × 12 = 252 — the classic stack's 253.44 settling
           1.44pt onto the grid, once, here. */
        #expect(lines.count == TitlePage.contactLastLine + 1)
        #expect(lines[TitlePage.stackLeadingBlanks] == TitlePageLine(text: "THE LAST STATION", key: "Title"))
        #expect(lines[17] == TitlePageLine(text: "written by", key: "Credit"))
        #expect(lines[19] == TitlePageLine(text: "Jane Smith & John Smith", key: "Author"))
        /* Source prints no label line. */
        #expect(lines[21] == TitlePageLine(text: "the novel by Mary Jones", key: "Source"))
        /* Contact is grid-exact: its last line at 72 + 54 × 12 = 720 is the
           classic page-height − 72 anchor, so it does not move at all. */
        #expect(lines[53] == TitlePageLine(text: "Jane Smith", alignment: .left, key: "Contact"))
        #expect(lines[54] == TitlePageLine(text: "jane@example.com", alignment: .left, key: "Contact"))
        #expect(lines[..<15].allSatisfy { $0.text.isEmpty })
    }

    @Test("Extra keys print their label; empty entries migrate to nothing")
    func extrasAndEmpties() {
        let lines = TitlePage.lines(from: [
            TitlePage.LegacyEntry(key: "Title", values: ["My Script"]),
            TitlePage.LegacyEntry(key: "Notes", values: ["First note.", "Second note."]),
            TitlePage.LegacyEntry(key: "Draft", values: []),
        ])
        #expect(lines[15] == TitlePageLine(text: "MY SCRIPT", key: "Title"))
        #expect(lines[19] == TitlePageLine(text: "Notes", key: "Notes"))
        #expect(lines[20] == TitlePageLine(text: "First note.", key: "Notes"))
        #expect(lines[21] == TitlePageLine(text: "Second note.", key: "Notes"))
        #expect(TitlePage.lines(from: [
            TitlePage.LegacyEntry(key: "Title", values: []),
        ]) == [])
    }

    // MARK: Derivation (D3)

    @Test("Derivation recovers the keyed questions from migrated lines")
    func derivationRoundTrip() {
        let derived = TitlePage.derive(TitlePage.lines(from: classicEntries))
        #expect(TitlePage.values(TitlePage.lines(from: classicEntries), for: "Title") == ["THE LAST STATION"])
        #expect(derived.entries.map(\.key) == ["Title", "Credit", "Author", "Source", "Contact"])
        #expect(derived.entries.map(\.values) == [
            ["THE LAST STATION"], ["written by"], ["Jane Smith & John Smith"],
            ["the novel by Mary Jones"], ["Jane Smith", "jane@example.com"],
        ])
    }

    @Test("Unannotated lines fall to the heuristics, and nothing is lost")
    func heuristics() {
        /* A foreign page: a title run, the credit phrase with the writers
           directly under it (the convention the heuristic reads), one stray
           line nobody can name, and a trailing left block. */
        var lines = (0..<10).map { _ in TitlePageLine(text: "") }
        lines.append(TitlePageLine(text: "THE BIG SCRIPT"))
        lines.append(TitlePageLine(text: ""))
        lines.append(TitlePageLine(text: "written by"))
        lines.append(TitlePageLine(text: "First Writer"))
        lines.append(TitlePageLine(text: "Second Writer"))
        lines.append(TitlePageLine(text: ""))
        lines.append(TitlePageLine(text: "Based on nothing in particular"))
        for _ in 0..<30 { lines.append(TitlePageLine(text: "")) }
        lines.append(TitlePageLine(text: "123 Writer Lane", alignment: .left))
        lines.append(TitlePageLine(text: "Hollywood, CA", alignment: .left))

        let derived = TitlePage.derive(lines)
        #expect(TitlePage.values(lines, for: "Title") == ["THE BIG SCRIPT"])
        #expect(TitlePage.values(lines, for: "Credit") == ["written by"])
        /* The fold: the stray line continues the nearest entry above it. */
        #expect(derived.entries.first { $0.key == "Author" }?.values == [
            "First Writer", "Second Writer", "Based on nothing in particular",
        ])
        #expect(TitlePage.values(lines, for: "Contact") == ["123 Writer Lane", "Hollywood, CA"])
    }

    @Test("A line whose text is its own key is the label, not a value")
    func labelRule() {
        let lines = TitlePage.lines(from: [
            TitlePage.LegacyEntry(key: "Title", values: ["My Script"]),
            TitlePage.LegacyEntry(key: "Notes", values: ["First note."]),
        ])
        let derived = TitlePage.derive(lines)
        #expect(derived.entries.first { $0.key == "Notes" }?.values == ["First note."])
        #expect(derived.labels.count == 1)
        /* Without the rule the serialise → parse cycle grows a copy of the
           key on every round trip; with it the cycle is a fixed point. */
        let reparsed = TitlePage.lines(from: [
            TitlePage.LegacyEntry(key: "Title", values: ["MY SCRIPT"]),
            TitlePage.LegacyEntry(key: "Notes", values: ["First note."]),
        ])
        #expect(reparsed == lines)
    }

    // MARK: The splice (D7)

    @Test("A replacement rewrites only the lines its key owns")
    func spliceReplace() {
        let lines = TitlePage.lines(from: classicEntries)
        let result = TitlePage.spliced(lines, key: "Credit", values: ["screenplay by"])
        #expect(result.count == lines.count)
        #expect(result[17] == TitlePageLine(text: "screenplay by", key: "Credit"))
        #expect(Array(result[..<17]) == Array(lines[..<17]))
        #expect(Array(result[18...]) == Array(lines[18...]))
    }

    @Test("The title stores its printed form — the uppercase the renderer forced")
    func spliceTitlePrintedForm() {
        let lines = TitlePage.lines(from: classicEntries)
        let result = TitlePage.spliced(lines, key: "Title", values: ["The New Story"])
        #expect(result[15] == TitlePageLine(text: "THE NEW STORY", key: "Title"))
        /* …which means a same-words edit is no edit at all: comparing the
           result against the input IS the change detection. */
        #expect(TitlePage.spliced(result, key: "Title", values: ["THE NEW STORY"]) == result)
        #expect(TitlePage.spliced(result, key: "Title", values: ["The New Story"]) == result)
    }

    @Test("Removal takes the group's lines and its label, nothing else")
    func spliceRemove() {
        let lines = TitlePage.lines(from: classicEntries + [
            TitlePage.LegacyEntry(key: "Notes", values: ["First note."]),
        ])
        #expect(lines[23] == TitlePageLine(text: "Notes", key: "Notes"))
        #expect(lines[24] == TitlePageLine(text: "First note.", key: "Notes"))
        let result = TitlePage.spliced(lines, key: "Notes", values: [])
        #expect(!result.contains { $0.key == "Notes" })
        /* The group's two lines leave, and the padding above contact
           refills them — the separator blank ahead of the group is not the
           group's, and the contact block keeps its anchor through the
           edit, so the page neither grows nor shrinks. */
        #expect(result.count == lines.count)
        #expect(result[TitlePage.contactLastLine] == lines[TitlePage.contactLastLine])
    }

    @Test("A new extra lands ahead of the contact padding; the anchor holds")
    func spliceInsertExtra() {
        let lines = TitlePage.lines(from: classicEntries)
        let result = TitlePage.spliced(lines, key: "Based on", values: ["a true story"])
        #expect(result.count == lines.count)
        /* Template shape: separator, the label, the value. */
        #expect(result[23] == TitlePageLine(text: "Based on", key: "Based on"))
        #expect(result[24] == TitlePageLine(text: "a true story", key: "Based on"))
        #expect(result[TitlePage.contactLastLine] == lines[TitlePage.contactLastLine])
    }

    @Test("Contact grows and shrinks by its bottom line, never its top")
    func spliceContactAnchor() {
        let lines = TitlePage.lines(from: classicEntries)
        let grown = TitlePage.spliced(lines, key: "Contact", values: ["Jane Smith", "jane@example.com", "Representation"])
        #expect(grown.count == lines.count)
        #expect(grown[52] == TitlePageLine(text: "Jane Smith", alignment: .left, key: "Contact"))
        #expect(grown[54] == TitlePageLine(text: "Representation", alignment: .left, key: "Contact"))
        let shrunk = TitlePage.spliced(lines, key: "Contact", values: ["Jane Smith"])
        #expect(shrunk.count == lines.count)
        #expect(shrunk[53].text.isEmpty)
        #expect(shrunk[54] == TitlePageLine(text: "Jane Smith", alignment: .left, key: "Contact"))
    }

    @Test("Stack growth above contact never moves the block")
    func spliceGrowthKeepsContactAnchored() {
        let lines = TitlePage.lines(from: classicEntries)
        let result = TitlePage.spliced(lines, key: "Author", values: ["Jane Smith & John Smith", "and Mary Jones"])
        #expect(result.count == lines.count)
        #expect(result[19] == TitlePageLine(text: "Jane Smith & John Smith", key: "Author"))
        #expect(result[20] == TitlePageLine(text: "and Mary Jones", key: "Author"))
        #expect(result[TitlePage.contactLastLine] == lines[TitlePage.contactLastLine])
    }

    @Test("A group that had no label does not grow one")
    func spliceKeepsLabelShape() {
        /* Verbatim import: keyed lines with no printed label. */
        let lines = [
            TitlePageLine(text: "MY SCRIPT", key: "Title"),
            TitlePageLine(text: "a true story", key: "Based on"),
        ]
        let result = TitlePage.spliced(lines, key: "Based on", values: ["the novel"])
        #expect(result == [
            TitlePageLine(text: "MY SCRIPT", key: "Title"),
            TitlePageLine(text: "the novel", key: "Based on"),
        ])
        /* A brand-new group takes the template's shape, label included. */
        let added = TitlePage.spliced(lines, key: "Notes", values: ["First note."])
        #expect(added.contains(TitlePageLine(text: "Notes", key: "Notes")))
        #expect(added.contains(TitlePageLine(text: "First note.", key: "Notes")))
    }
}
