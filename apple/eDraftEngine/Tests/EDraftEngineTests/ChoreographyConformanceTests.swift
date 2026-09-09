import Foundation
import Testing
import EDraftEngine

/// Conformance of `Choreography` against the TypeScript engine's exported
/// corpus (`Fixtures/choreography.json`). Every row was produced by the TS
/// implementation; the Swift port must match it exactly.
@Suite("Choreography conformance")
struct ChoreographyConformanceTests {

    private static let corpus: ChoreographyCorpus.Root = {
        do { return try FixtureStore.load("choreography.json") }
        catch {
            Issue.record("Failed to load choreography.json: \(error)")
            return .init(tabNext: [], tabSetFor: [], tabCycle: [], nextElement: [])
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.tabNext.count == 28)
        #expect(Self.corpus.tabSetFor.count == 15)
        #expect(Self.corpus.tabCycle.count == 420)
        #expect(Self.corpus.nextElement.count == 112)
    }

    @Test("tabRingCycle", arguments: Self.corpus.tabNext)
    func tabNext(_ case_: ChoreographyCorpus.TabNext) {
        let current = ElementKind(rawValue: case_.current)!
        let expected = ElementKind(rawValue: case_.result)!
        #expect(Choreography.tabRingCycle(current: current, backwards: case_.reverse) == expected)
    }

    @Test("tabSetFor", arguments: Self.corpus.tabSetFor)
    func tabSetFor(_ case_: ChoreographyCorpus.TabSetFor) {
        let prev = case_.prev.flatMap(ElementKind.init(rawValue:))
        let expected = case_.result.map { ElementKind(rawValue: $0)! }
        #expect(Choreography.tabSetFor(previous: prev) == expected)
    }

    @Test("tabCycle", arguments: Self.corpus.tabCycle)
    func tabCycle(_ case_: ChoreographyCorpus.TabCycle) {
        let current = ElementKind(rawValue: case_.current)!
        let prev = case_.prev.flatMap(ElementKind.init(rawValue:))
        let expected = ElementKind(rawValue: case_.result)!
        let set = Choreography.tabSetFor(previous: prev)
        #expect(Choreography.tabCycle(current: current, within: set,
                                      backwards: case_.reverse) == expected)
    }

    @Test("nextElement", arguments: Self.corpus.nextElement)
    func nextElement(_ case_: ChoreographyCorpus.NextElement) {
        let current = ElementKind(rawValue: case_.current)!
        let key = Choreography.Key(rawValue: case_.key)!
        let expected = ElementKind(rawValue: case_.result)!
        #expect(Choreography.nextKind(after: current, key: key,
                                      currentText: case_.text) == expected)
    }
}
