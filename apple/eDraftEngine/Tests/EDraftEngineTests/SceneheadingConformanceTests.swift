import Foundation
import Testing
import EDraftEngine

/// Conformance of `SceneNumbering.parseNumberedHeading` against
/// `Fixtures/sceneheading.json` — the numbered heading grammar the corpus
/// carries, ported from the TypeScript engine's `sceneheading.ts`.
@Suite("Scene heading conformance")
struct SceneheadingConformanceTests {

    private static let corpus: SceneheadingCorpus.Root = {
        do { return try FixtureStore.load("sceneheading.json") }
        catch {
            Issue.record("Failed to load sceneheading.json: \(error)")
            return .init(cases: [])
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.cases.count == 24)
    }

    @Test("parseNumberedHeading", arguments: Self.corpus.cases)
    func parse(_ case_: SceneheadingCorpus.Case) {
        let parsed = SceneNumbering.parseNumberedHeading(case_.text)
        if let expected = case_.result {
            #expect(parsed?.number == expected.number)
            #expect(parsed?.text == expected.text)
        } else {
            #expect(parsed == nil)
        }
    }
}
