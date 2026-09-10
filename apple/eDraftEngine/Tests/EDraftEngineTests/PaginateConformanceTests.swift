import Foundation
import Testing
import EDraftEngine

/// Conformance of `Paginator` against `Fixtures/paginate.json`: eight
/// scripts (including the 871-element, 36-page synthetic feature) paginated
/// by the TypeScript engine, compared line-for-line — text, type, indent,
/// provenance, and scene-continuation margins.
@Suite("Paginate conformance")
struct PaginateConformanceTests {

    private static let corpus: [PaginateCorpus.Case] = {
        do { return try FixtureStore.load("paginate.json") }
        catch {
            Issue.record("Failed to load paginate.json: \(error)")
            return []
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.count == 10)
    }

    @Test("paginate", arguments: Self.corpus)
    func paginate(_ case_: PaginateCorpus.Case) throws {
        let pages = try Paginator.paginate(case_.screenplay)
        #expect(pages == case_.expected.pages,
                "\(case_.name): pages differ from the TypeScript engine")
        #expect(Paginator.estimateRuntime(pages) == case_.expected.runtime,
                "\(case_.name): runtime differs")
        #expect(Paginator.printedLineCount(pages) == case_.expected.printedLines,
                "\(case_.name): printed line count differs")
    }
}
