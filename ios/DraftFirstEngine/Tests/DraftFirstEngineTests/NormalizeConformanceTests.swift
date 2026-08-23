import Foundation
import Testing
import DraftFirstEngine

/// Conformance of `Normalize` against `Fixtures/normalize.json`.
@Suite("Normalize conformance")
struct NormalizeConformanceTests {

    private static let corpus: NormalizeCorpus.Root = {
        do { return try FixtureStore.load("normalize.json") }
        catch {
            Issue.record("Failed to load normalize.json: \(error)")
            return .init(parenthetical: [], unwrapParenthetical: [], cue: [], looksLikeCue: [], elementText: [])
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.parenthetical.count == 12)
        #expect(Self.corpus.unwrapParenthetical.count == 12)
        #expect(Self.corpus.cue.count == 25)
        #expect(Self.corpus.looksLikeCue.count == 13)
        #expect(Self.corpus.elementText.count == 50)
    }

    @Test("normalizeParenthetical", arguments: Self.corpus.parenthetical)
    func parenthetical(_ case_: NormalizeCorpus.TextCase) {
        #expect(Normalize.normalizeParenthetical(case_.input) == case_.result)
    }

    @Test("unwrapParenthetical", arguments: Self.corpus.unwrapParenthetical)
    func unwrapParenthetical(_ case_: NormalizeCorpus.TextCase) {
        #expect(Normalize.unwrapParenthetical(case_.input) == case_.result)
    }

    @Test("normalizeCue", arguments: Self.corpus.cue)
    func cue(_ case_: NormalizeCorpus.TextCase) {
        #expect(Normalize.normalizeCue(case_.input) == case_.result)
    }

    @Test("looksLikeCue", arguments: Self.corpus.looksLikeCue)
    func looksLikeCue(_ case_: NormalizeCorpus.BoolCase) {
        #expect(Normalize.looksLikeCue(case_.input) == case_.result)
    }

    @Test("normalizeElementText", arguments: Self.corpus.elementText)
    func elementText(_ case_: NormalizeCorpus.ElementTextCase) {
        let kind = ElementKind(rawValue: case_.type)!
        #expect(Normalize.normalizeElementText(kind: kind, text: case_.input) == case_.result)
    }
}
