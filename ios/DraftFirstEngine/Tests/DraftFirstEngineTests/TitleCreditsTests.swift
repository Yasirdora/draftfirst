import Foundation
import Testing
import DraftFirstEngine

/// The title-page credit model: flat `Author:` strings parse into
/// structured writers and render back byte-identically, and the credit
/// picker's phrase matching is case-insensitive.
@Suite("Title credits")
struct TitleCreditsTests {

    @Test("solo writer round-trips")
    func solo() {
        let writers = TitleCredits.parseAuthors("Jane Smith")
        #expect(writers == [WriterCredit(name: "Jane Smith")])
        #expect(TitleCredits.renderAuthors(writers) == "Jane Smith")
    }

    @Test("team joins with ampersand")
    func team() {
        let writers = TitleCredits.parseAuthors("Jane Smith & John Smith")
        #expect(writers.map(\.name) == ["Jane Smith", "John Smith"])
        #expect(writers[1].joiner == .team)
        #expect(TitleCredits.renderAuthors(writers) == "Jane Smith & John Smith")
    }

    @Test("separate writers join with and")
    func separate() {
        let writers = TitleCredits.parseAuthors("Jane Smith and John Smith")
        #expect(writers[1].joiner == .separate)
        #expect(TitleCredits.renderAuthors(writers) == "Jane Smith and John Smith")
    }

    @Test("mixed team and separate keep their joiners positionally")
    func mixed() {
        let writers = TitleCredits.parseAuthors("A & B and C & D")
        #expect(writers.map(\.joiner) == [.team, .team, .separate, .team])
        #expect(TitleCredits.renderAuthors(writers) == "A & B and C & D")
    }

    @Test("and inside a name never splits")
    func nameContainingAnd() {
        #expect(TitleCredits.parseAuthors("Sandy Smith").count == 1)
    }

    @Test("joiners match case-insensitively and normalize on render")
    func caseInsensitive() {
        let writers = TitleCredits.parseAuthors("Jane Smith AND John Smith")
        #expect(writers[1].joiner == .separate)
        #expect(TitleCredits.renderAuthors(writers) == "Jane Smith and John Smith")
    }

    @Test("messy whitespace trims and empty renders empty")
    func whitespace() {
        let writers = TitleCredits.parseAuthors("  Jane Smith   &   John Smith  ")
        #expect(writers.map(\.name) == ["Jane Smith", "John Smith"])
        #expect(TitleCredits.parseAuthors("").isEmpty)
        #expect(TitleCredits.renderAuthors([]) == "")
    }

    @Test("blank names drop out of the render")
    func blankNames() {
        let writers = [
            WriterCredit(name: "Jane Smith"),
            WriterCredit(name: "  ", joiner: .separate),
            WriterCredit(name: "John Smith", joiner: .separate)
        ]
        #expect(TitleCredits.renderAuthors(writers) == "Jane Smith and John Smith")
    }

    @Test("standard credit matching is case-insensitive")
    func standardCredit() {
        #expect(TitleCredits.StandardCredit.matching("Written by") == .writtenBy)
        #expect(TitleCredits.StandardCredit.matching("  SCREENPLAY BY ") == .screenplayBy)
        #expect(TitleCredits.StandardCredit.matching("words by nobody") == nil)
        #expect(TitleCredits.StandardCredit.writtenBy.displayTitle == "Written by")
    }

    @Test("a full title page survives the Fountain round trip")
    func fountainRoundTrip() throws {
        let source = """
        Title: The Last Station
        Credit: written by
        Author: Jane Smith & John Smith
        Source: the novel by Mary Jones
        Contact: Jane Smith
           jane@example.com

        INT. LAB - NIGHT

        The room hums.
        """
        let parsed = try Fountain.parse(source)
        #expect(parsed.titlePage.first { $0.key == "Author" }?.values == ["Jane Smith & John Smith"])
        #expect(parsed.titlePage.first { $0.key == "Contact" }?.values == ["Jane Smith", "jane@example.com"])
        let reparsed = try Fountain.parse(Fountain.serialise(parsed))
        #expect(reparsed.titlePage == parsed.titlePage)
        #expect(reparsed.elements == parsed.elements)
    }
}
