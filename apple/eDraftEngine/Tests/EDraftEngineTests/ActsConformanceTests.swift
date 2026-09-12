import Foundation
import Testing
import EDraftEngine

/// Conformance of `Acts` against `Fixtures/acts.json`.
@Suite("Acts conformance")
struct ActsConformanceTests {

    private static let corpus: ActsCorpus.Root = {
        do { return try FixtureStore.load("acts.json") }
        catch {
            Issue.record("Failed to load acts.json: \(error)")
            return .init(ordinals: [], canonical: [], renumber: [])
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.ordinals.count == 8)
        #expect(Self.corpus.canonical.count == 14)
        #expect(Self.corpus.renumber.count == 7)
    }

    @Test("ordinal", arguments: Self.corpus.ordinals)
    func ordinal(_ case_: ActsCorpus.OrdinalCase) {
        #expect(Acts.ordinal(case_.n) == case_.result)
    }

    @Test("isCanonicalActCard", arguments: Self.corpus.canonical)
    func canonical(_ case_: ActsCorpus.CanonicalCase) {
        #expect(Acts.isCanonicalActCard(case_.text) == case_.result)
    }

    @Test("renumber", arguments: Self.corpus.renumber)
    func renumber(_ case_: ActsCorpus.RenumberCase) {
        #expect(Acts.renumber(case_.input).map(\.text) == case_.result)
    }
}
