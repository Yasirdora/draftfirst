import Testing
@testable import EDraftEngine

/// What `canonicalCasing` does with letters whose capitals are not a simple
/// one-to-one swap.
///
/// The TypeScript engine — the source of truth — writes this as
/// `toLocaleUpperCase()`, which asks the runtime's locale. Swift's
/// `uppercased()` does not. On every input below they agree, and these tests
/// pin that. They agree because none of these is the case where locale
/// matters: in Turkish, `i` uppercases to `İ`, so a Turkish reader of the web
/// app would see `İSTANBUL` where the iOS app writes `ISTANBUL`.
///
/// That is a live question about the document format rather than a bug with an
/// obvious side: casing by locale is typographically right for the writer and
/// wrong for a file that must read the same to everyone who opens it. It is
/// recorded here, unanswered, so that whoever answers it finds the evidence
/// rather than the surprise.
@Suite("Casing that is not a one-to-one swap")
struct LocaleCasingTests {

    /// ß expands to two letters. German sets caps this way, and the editor
    /// depends on it: `EditorState.normalizedText` asks this function, and a
    /// surface redraws when the answer is not the length that was typed.
    @Test func sharpSExpandsToTwoLetters() {
        #expect(Normalize.canonicalCasing(kind: .character, text: "straße") == "STRASSE")
        #expect(Normalize.canonicalCasing(kind: .scene, text: "int. straße") == "INT. STRASSE")
    }

    /// A ligature expands the same way, and must not be left alone either.
    @Test func ligaturesExpand() {
        #expect(Normalize.canonicalCasing(kind: .transition, text: "\u{FB01}nale") == "FINALE")
    }

    /// The Turkish dotless pair, in the locale-independent reading this engine
    /// gives it. If this test ever fails, someone has made casing
    /// locale-sensitive, and the question above has been answered — the answer
    /// belongs in SHARED-ARCHITECTURE, not only in a diff.
    @Test func turkishDottedIIsNotProduced() {
        #expect(Normalize.canonicalCasing(kind: .scene, text: "istanbul") == "ISTANBUL")
        #expect(Normalize.canonicalCasing(kind: .character, text: "i") == "I")
    }

    /// Kinds that do not shout are untouched, whatever their letters.
    @Test func kindsThatDoNotShoutAreLeftAlone() {
        #expect(Normalize.canonicalCasing(kind: .action, text: "straße") == "straße")
        #expect(Normalize.canonicalCasing(kind: .dialogue, text: "istanbul") == "istanbul")
    }
}
