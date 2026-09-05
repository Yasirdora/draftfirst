import Foundation
import Testing
import EDraftEngine

/// Conformance of `PredictionEngine.predict` against `Fixtures/predict.json`:
/// eleven contexts over the sample and feature-120 scripts — scene intros,
/// character memory, cue extensions, transitions, and empty blocks —
/// compared candidate-for-candidate including `why`, `becomes`, and `hint`.
@Suite("Predict conformance")
struct PredictConformanceTests {

    private static let corpus: [PredictCorpus.Case] = {
        do { return try FixtureStore.load("predict.json") }
        catch {
            Issue.record("Failed to load predict.json: \(error)")
            return []
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.count == 15)
    }

    @Test("predict", arguments: Self.corpus)
    func predict(_ case_: PredictCorpus.Case) {
        let type = ElementKind(rawValue: case_.context.type)!
        let actual = PredictionEngine.predict(
            case_.screenplay,
            type: type,
            text: case_.context.text,
            index: case_.context.index
        )
        #expect(actual == case_.expected,
                "\(case_.name): predictions differ from the TypeScript engine")
    }
}

/// Conformance of `PredictionEngine.ghostSuffix` against
/// `Fixtures/ghostSuffix.json` — 112 candidate/typed/hint combinations.
@Suite("Ghost suffix conformance")
struct GhostSuffixConformanceTests {

    private static let corpus: [GhostSuffixCorpus.Case] = {
        do { return try FixtureStore.load("ghostSuffix.json") }
        catch {
            Issue.record("Failed to load ghostSuffix.json: \(error)")
            return []
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.count == 112)
    }

    @Test("ghostSuffix", arguments: Self.corpus)
    func ghostSuffix(_ case_: GhostSuffixCorpus.Case) {
        let actual = PredictionEngine.ghostSuffix(
            candidate: case_.candidate,
            blockText: case_.text,
            hint: case_.hint
        )
        #expect(actual == case_.expected,
                "candidate \(case_.candidate.debugDescription) against \(case_.text.debugDescription): expected \(case_.expected.debugDescription)")
    }
}
