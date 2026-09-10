import Foundation
import Testing
import EDraftEngine

/// Conformance of `Emphasis` against the TypeScript engine's golden masters:
/// `emphasis.json` (parse), `emphasis-synthesise.json` (canonical emission,
/// including the recorded losses for AllCaps/HiddenText, boundary whitespace
/// and crossing coverage), and `emphasis-roundtrip.json` (the fixed point).
/// Plus direct unit tests of the normalisation invariants — the logic is
/// pure, so it is tested directly (the zoom-drift lesson).
@Suite("Emphasis conformance")
struct EmphasisConformanceTests {

    private static let parseCorpus: [EmphasisCorpus.ParseCase] = {
        do { return try FixtureStore.load("emphasis.json") }
        catch {
            Issue.record("Failed to load emphasis.json: \(error)")
            return []
        }
    }()

    private static let synthesiseCorpus: [EmphasisCorpus.SynthesiseCase] = {
        do { return try FixtureStore.load("emphasis-synthesise.json") }
        catch {
            Issue.record("Failed to load emphasis-synthesise.json: \(error)")
            return []
        }
    }()

    private static let roundTripCorpus: [EmphasisCorpus.RoundTripCase] = {
        do { return try FixtureStore.load("emphasis-roundtrip.json") }
        catch {
            Issue.record("Failed to load emphasis-roundtrip.json: \(error)")
            return []
        }
    }()

    @Test("corpora load non-empty")
    func corporaLoad() {
        #expect(Self.parseCorpus.count == 30)
        #expect(Self.synthesiseCorpus.count == 15)
        #expect(Self.roundTripCorpus.count == 6)
    }

    @Test("parse", arguments: Self.parseCorpus)
    func parse(_ case_: EmphasisCorpus.ParseCase) {
        let result = Emphasis.parse(case_.input)
        #expect(
            result.text == case_.expected.text && result.runs == case_.expected.runs,
            "\(case_.input.debugDescription): got \(result)"
        )
    }

    @Test("synthesise", arguments: Self.synthesiseCorpus)
    func synthesise(_ case_: EmphasisCorpus.SynthesiseCase) {
        let result = Emphasis.synthesise(case_.input.text, case_.input.runs)
        #expect(
            result == case_.expected,
            "\(case_.input.text.debugDescription): got \(result.debugDescription), expected \(case_.expected.debugDescription)"
        )
    }

    @Test("round trip", arguments: Self.roundTripCorpus)
    func roundTrip(_ case_: EmphasisCorpus.RoundTripCase) {
        let parsed = Emphasis.parse(case_.source)
        #expect(
            parsed.text == case_.expected.text && parsed.runs == case_.expected.runs,
            "\(case_.source.debugDescription): parse differs from the TypeScript engine"
        )
        let synthesised = Emphasis.synthesise(parsed.text, parsed.runs)
        #expect(
            synthesised == case_.expected.synthesised,
            "\(case_.source.debugDescription): synthesised \(synthesised.debugDescription)"
        )
        let fixedPoint = Emphasis.parse(synthesised)
        #expect(
            fixedPoint.text == case_.expected.fixedPoint.text
                && fixedPoint.runs == case_.expected.fixedPoint.runs,
            "\(case_.source.debugDescription): re-parse left the fixed point"
        )
    }
}

/// The canonical-form invariants, exercised directly (TypeScript
/// `normaliseRuns`): clamp, drop-empty, split-and-union overlaps,
/// earliest-start revision ownership, merge only when every property matches.
@Suite("Emphasis normalisation")
struct EmphasisNormalisationTests {

    @Test("clamps to the text and drops empty runs")
    func clampAndDrop() {
        let result = Emphasis.normalise([
            StyleRun(start: -3, end: 2, styles: .bold),
            StyleRun(start: 5, end: 5, styles: .italic),
            StyleRun(start: 8, end: 99, styles: .underline)
        ], textLength: 10)
        #expect(result == [
            StyleRun(start: 0, end: 2, styles: .bold),
            StyleRun(start: 8, end: 10, styles: .underline)
        ])
    }

    @Test("splits overlaps into union segments")
    func splitOverlaps() {
        let result = Emphasis.normalise([
            StyleRun(start: 0, end: 4, styles: .bold),
            StyleRun(start: 2, end: 6, styles: .italic)
        ], textLength: 10)
        #expect(result == [
            StyleRun(start: 0, end: 2, styles: .bold),
            StyleRun(start: 2, end: 4, styles: [.bold, .italic]),
            StyleRun(start: 4, end: 6, styles: .italic)
        ])
    }

    @Test("merges adjacent runs only when every property is equal")
    func mergeRule() {
        #expect(Emphasis.normalise([
            StyleRun(start: 0, end: 2, styles: .bold, revisionID: 1),
            StyleRun(start: 2, end: 4, styles: .bold, revisionID: 1)
        ], textLength: 10) == [
            StyleRun(start: 0, end: 4, styles: .bold, revisionID: 1)
        ])

        #expect(Emphasis.normalise([
            StyleRun(start: 0, end: 2, styles: .bold, revisionID: 1),
            StyleRun(start: 2, end: 4, styles: .bold, revisionID: 2)
        ], textLength: 10) == [
            StyleRun(start: 0, end: 2, styles: .bold, revisionID: 1),
            StyleRun(start: 2, end: 4, styles: .bold, revisionID: 2)
        ])
    }

    @Test("unions tagNumbers; the earliest run owns a revision conflict")
    func conflictRule() {
        #expect(Emphasis.normalise([
            StyleRun(start: 0, end: 4, styles: [], revisionID: 7, tagNumbers: [3, 1]),
            StyleRun(start: 2, end: 6, styles: [], revisionID: 9, tagNumbers: [2])
        ], textLength: 10) == [
            StyleRun(start: 0, end: 2, styles: [], revisionID: 7, tagNumbers: [1, 3]),
            StyleRun(start: 2, end: 4, styles: [], revisionID: 7, tagNumbers: [1, 2, 3]),
            StyleRun(start: 4, end: 6, styles: [], revisionID: 9, tagNumbers: [2])
        ])
    }

    @Test("drops runs carrying no information at all")
    func dropEmpty() {
        #expect(Emphasis.normalise([StyleRun(start: 0, end: 4, styles: [])], textLength: 10) == [])
    }

    @Test("StyleSet wire format is the canonical token array")
    func styleSetWireFormat() throws {
        let encoded = try JSONEncoder().encode(StyleSet([.italic, .bold, .strikeout]))
        #expect(String(data: encoded, encoding: .utf8) == #"["Bold","Italic","Strikeout"]"#)
        let decoded = try JSONDecoder().decode(StyleSet.self, from: Data(#"["Underline","AllCaps"]"#.utf8))
        #expect(decoded == [.underline, .allCaps])
        /* Unknown tokens from a newer Final Draft drop, never fail. */
        let tolerated = try JSONDecoder().decode(StyleSet.self, from: Data(#"["Bold","Shimmer"]"#.utf8))
        #expect(tolerated == .bold)
    }
}
