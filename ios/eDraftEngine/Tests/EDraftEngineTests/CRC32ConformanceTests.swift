import Foundation
import Testing
import EDraftEngine

/// Conformance of `CRC32` against `Fixtures/crc32.json`.
@Suite("CRC32 conformance")
struct CRC32ConformanceTests {

    private static let corpus: CRC32Corpus.Root = {
        do { return try FixtureStore.load("crc32.json") }
        catch {
            Issue.record("Failed to load crc32.json: \(error)")
            return .init(cases: [])
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(!Self.corpus.cases.isEmpty)
    }

    @Test("checksum", arguments: Self.corpus.cases)
    func checksum(_ case_: CRC32Corpus.Case) {
        let bytes = CRC32Corpus.bytes(fromHex: case_.hex)
        #expect(CRC32.checksum(bytes) == case_.result)
    }
}
