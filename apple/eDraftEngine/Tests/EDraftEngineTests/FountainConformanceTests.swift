import Foundation
import Testing
import EDraftEngine

/// Conformance of `Fountain.parse` against `Fixtures/parse.json`: eight
/// scripts (sample, edge headings, edge dialogue, structural, title page,
/// empty, whitespace chaos, 871-element feature) parsed by the TypeScript
/// engine, compared element-for-element.
@Suite("Fountain parse conformance")
struct FountainParseConformanceTests {

    private static let corpus: [ParseCorpus.Case] = {
        do { return try FixtureStore.load("parse.json") }
        catch {
            Issue.record("Failed to load parse.json: \(error)")
            return []
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.count == 9)
    }

    @Test("parse", arguments: Self.corpus)
    func parse(_ case_: ParseCorpus.Case) throws {
        let parsed = try Fountain.parse(case_.source)
        #expect(parsed == case_.expected,
                "\(case_.name): parsed screenplay differs from the TypeScript engine")
    }
}

/// Conformance of `Fountain.serialise` against `Fixtures/serialise.json`.
@Suite("Fountain serialise conformance")
struct FountainSerialiseConformanceTests {

    private static let corpus: [SerialiseCorpus.Case] = {
        do { return try FixtureStore.load("serialise.json") }
        catch {
            Issue.record("Failed to load serialise.json: \(error)")
            return []
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.count == 9)
    }

    @Test("serialise", arguments: Self.corpus)
    func serialise(_ case_: SerialiseCorpus.Case) {
        #expect(Fountain.serialise(case_.screenplay) == case_.expected,
                "\(case_.name): serialised Fountain differs from the TypeScript engine")
    }

    /// Semantic round-trip: parsing each serialised corpus output must
    /// reproduce an equal screenplay (the TS engine's stability guarantee).
    @Test("round-trip stability", arguments: Self.corpus)
    func roundTrip(_ case_: SerialiseCorpus.Case) throws {
        let reparsed = try Fountain.parse(case_.expected)
        #expect(reparsed == case_.screenplay,
                "\(case_.name): serialise → parse round-trip is not stable")
    }
}
