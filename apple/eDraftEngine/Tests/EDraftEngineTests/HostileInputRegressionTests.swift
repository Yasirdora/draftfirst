import Foundation
import Testing
import EDraftEngine

/// Regression: hostile real-world text that took the port down or silently
/// diverged from the TypeScript engine. The conformance corpus's torture
/// script pins the end-to-end behaviour; these cases pin the individual
/// fixes so a future refactor cannot reintroduce one hazard quietly.
@Suite("Hostile input regression")
struct HostileInputRegressionTests {

    /// `INT. LAB - - DAY` trapped `splitOnSpacedDashes` (`cursor > left`).
    /// JS `/\s+[-–—]\s+/` matches never overlap: the second dash is literal.
    /// Device crash, 2026-08-15 — EXC_BREAKPOINT "Range with upperBound < lowerBound".
    @Test("spaced double dash keeps the second dash literal")
    func spacedDoubleDash() {
        let parts = SmartType.splitSceneHeading("INT. LAB - - DAY")
        #expect(parts.prefix == "INT.")
        #expect(parts.location == "LAB")
        #expect(parts.time == "- DAY")
    }

    /// `"\r\n"` is ONE Character in Swift, so a Character-level split never
    /// fires and a Windows file collapses into a single bogus element.
    /// JS `split("\n")` is code-unit based; `components(separatedBy:)` matches it.
    @Test("CRLF files split into real lines")
    func crlfParse() throws {
        let screenplay = try Fountain.parse("INT. A - DAY\r\n\r\nHello.\r\n")
        #expect(screenplay.elements.count == 2)
        #expect(screenplay.elements[0].type == .scene)
        #expect(screenplay.elements[0].text == "INT. A - DAY")
        #expect(screenplay.elements[1].text == "Hello.")
    }

    /// The JS boneyard regex needs a closing delimiter to match at all, so an
    /// unclosed `/*` stays verbatim. The port used to delete the tail — silent
    /// data loss on any file with an open boneyard.
    @Test("unclosed boneyard stays verbatim")
    func unclosedBoneyard() throws {
        let screenplay = try Fountain.parse("INT. A - DAY\n\n/* never closed\nMore text.")
        #expect(screenplay.elements.count == 3)
        #expect(screenplay.elements[1].text == "/* never closed")
        #expect(screenplay.elements[2].text == "More text.")
    }

    /// JS `\s` excludes U+0085 and includes U+FEFF; Unicode White_Space is the
    /// reverse. Word wrapping must split on exactly the JS set.
    @Test("paginate wraps on the JS whitespace set")
    func jsWhitespaceWrap() throws {
        let nel = "hums\u{0085}steadily"  // one word to JS, two to White_Space
        let screenplay = Screenplay(elements: [
            ScreenplayElement(type: .action, text: "The generator \(nel) " + String(repeating: "x", count: 50))
        ])
        let pages = try Paginator.paginate(screenplay)
        let texts = pages.flatMap(\.lines).map(\.text)
        #expect(texts.contains { $0.contains("hums\u{0085}steadily") })
    }

    /// `wrapText` must separate on UTF-16 code units, not grapheme clusters.
    /// `" " + U+0301` is ONE cluster, so a Character-level split refuses to
    /// break there and hard-splits the 72-unit run at the 60-column boundary
    /// instead — no line then begins with the combining mark. JS breaks on the
    /// space and carries the mark into the next word.
    @Test("wrap breaks on a space that carries a combining mark")
    func wrapSplitsClusterBoundary() throws {
        let text = String(repeating: "a", count: 50) + " \u{0301}" + String(repeating: "b", count: 20)
        let pages = try Paginator.paginate(
            Screenplay(elements: [ScreenplayElement(type: .action, text: text)])
        )
        let texts = pages.flatMap(\.lines).map(\.text)
        #expect(texts.contains { $0.utf16.first == 0x0301 },
                "the wrapped line should start at the combining mark")
    }

    /// `/[a-z]/` scans UTF-16 code units, so a DECOMPOSED `é` matches through
    /// its base `e` and the line is not an all-caps cue. Testing
    /// `Character.isASCII` misses it — the cluster is not ASCII — which turned
    /// `RENé` into a character cue and its dialogue into speech.
    @Test("decomposed lowercase base is not a character cue")
    func decomposedLowercaseIsNotACue() throws {
        let screenplay = try Fountain.parse("INT. LAB - DAY\n\nRENe\u{0301}\nWhere were you?")
        #expect(!screenplay.elements.contains { $0.type == .character })
    }

    /// Control for the case above: a COMPOSED uppercase `É` has no `[a-z]`
    /// match in either engine, so this one really is a cue. Guards against
    /// "fixing" the detector by disabling it.
    @Test("composed uppercase accent is still a character cue")
    func composedUppercaseIsACue() throws {
        let screenplay = try Fountain.parse("INT. LAB - DAY\n\nREN\u{00C9}\nWhere were you?")
        #expect(screenplay.elements.contains { $0.type == .character })
    }

    /// ECMAScript `/i` without `/u` never folds a non-ASCII code point onto an
    /// ASCII one, so U+0131 (dotless i) does not open a scene heading.
    /// `uppercased()` maps it to `I` and would accept the line.
    @Test("dotless i does not open a scene heading")
    func dotlessINotASceneHeading() throws {
        let screenplay = try Fountain.parse("\u{0131}nt. house - day\n\nSomething happens.")
        #expect(!screenplay.elements.contains { $0.type == .scene })
    }

    /// `/#([^#]+)#\s*$/` — the interior can never hold a `#`, so only the
    /// nearest preceding `#` can open the number. Walking further left
    /// captured "1#" where JS matches nothing at all.
    @Test("adjacent hashes are not a scene number")
    func adjacentHashesAreNotASceneNumber() throws {
        let screenplay = try Fountain.parse("INT. HOUSE #1##\n\nAction.")
        #expect(screenplay.elements.first?.sceneNumber == nil)
        #expect(screenplay.elements.first?.text == "INT. HOUSE #1##")
    }

    /// A blank interior trims to `""`, which is falsy in JS, so the key is
    /// absent rather than empty — otherwise the serializer re-emits ` ##` and
    /// the document stops being a round-trip fixed point.
    @Test("blank scene number is absent, not empty")
    func blankSceneNumberIsAbsent() throws {
        let screenplay = try Fountain.parse(".SCENE #  #\n\nAction.")
        #expect(screenplay.elements.first?.sceneNumber == nil)
    }

    /// `/^>\s*(.+?)\s*<$/` on `>  <`: the greedy `\s*` backtracks one character
    /// so `.+?` can match, giving a single-space capture. Stripping leading
    /// whitespace before measuring made the all-whitespace branch unreachable
    /// and the line fell through to a forced transition.
    @Test("all-whitespace centered line stays centered")
    func allWhitespaceCentered() throws {
        let screenplay = try Fountain.parse("INT. A - DAY\n\n>  <")
        #expect(screenplay.elements.last?.type == .centered)
    }

    /// The lazy `.*?` picks the first `(` whose remainder holds no `)` — the
    /// first `(` after the last `)`. Anchoring on the first `(` outright
    /// silenced every cue that already carried a closed extension.
    @Test("a cue with a closed extension still offers more")
    func cueWithExistingExtensionStillPredicts() {
        let script = Screenplay(elements: [
            ScreenplayElement(type: .scene, text: "INT. LAB - DAY"),
            ScreenplayElement(type: .character, text: "MARA"),
            ScreenplayElement(type: .dialogue, text: "We are live."),
            ScreenplayElement(type: .action, text: "She checks the array."),
        ])
        let fresh = PredictionEngine.predict(
            script, type: .character, text: "MARA (", index: script.elements.count
        )
        let extended = PredictionEngine.predict(
            script, type: .character, text: "MARA (V.O.) (", index: script.elements.count
        )
        #expect(!fresh.isEmpty, "baseline: an open paren offers extensions")
        #expect(!extended.isEmpty,
                "a cue already carrying (V.O.) must still offer further extensions")
    }
}
