import Testing
@testable import EDraftEngine

@Suite
struct WrapLinesTests {

    @Test("wrapText is wrapLines without the offsets")
    func wrapTextDelegates() {
        let text = "The action on this beat is long enough that it must wrap across the sixty-character text block rather than sitting on a single line of the page."
        let lines = Paginator.wrapLines(text, width: Paginator.pageWidthChars)
        #expect(Paginator.wrapText(text, width: Paginator.pageWidthChars) == lines.map(\.text))
    }

    @Test("the second wrapped line names its start in the original")
    func secondLineOffset() {
        let text = "The action on this beat is long enough that it must wrap across the sixty-character text block."
        let lines = Paginator.wrapLines(text, width: Paginator.pageWidthChars)
        #expect(lines.count >= 2)
        let units = Array(text.utf16)
        let start = lines[1].utf16Start
        #expect(start > 0)
        #expect(start < units.count)
        let fromOriginal = String(decoding: units[start...], as: UTF16.self)
        #expect(fromOriginal.hasPrefix(lines[1].text.split(separator: " ").first.map(String.init) ?? "\u{0}"))
    }

    @Test("an empty string still yields one empty line at 0")
    func emptyString() {
        let lines = Paginator.wrapLines("", width: 60)
        #expect(lines == [Paginator.WrappedLine(text: "", utf16Start: 0)])
    }
}
