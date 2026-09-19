import Foundation
import Testing
import EDraftEngine

/// Conformance of the .draft file (`DraftFile`, `Zip`, `CanonicalJSON`,
/// `SHA256Digest`) against `Fixtures/draft.json`, which the TypeScript engine
/// writes: the same bytes out for every write case, the same document and
/// diagnostics in for every read case (RFC-DRAFT-FORMAT §15, B4).
@Suite("Draft file conformance")
struct DraftFileConformanceTests {

    static let corpus: DraftCorpus.Root? = {
        do { return try FixtureStore.load("draft.json") }
        catch {
            Issue.record("Failed to load draft.json: \(error)")
            return nil
        }
    }()

    static let parseSources: [String: String] = {
        let cases = (try? FixtureStore.load("parse.json", as: [ParseCorpus.Case].self)) ?? []
        return Dictionary(cases.map { ($0.name, $0.source) }, uniquingKeysWith: { first, _ in first })
    }()

    @Test("corpus loads with every section")
    func corpusLoads() throws {
        let corpus = try #require(Self.corpus)
        #expect(!corpus.sha256.isEmpty && !corpus.write.isEmpty && !corpus.read.isEmpty && !corpus.bridges.isEmpty)
    }

    @Test("SHA-256 matches the TypeScript engine")
    func sha256() throws {
        for vector in try #require(Self.corpus).sha256 {
            #expect(SHA256Digest.hex(CRC32Corpus.bytes(fromHex: vector.hex)) == vector.sha256)
        }
    }

    @Test("the canonical form and RFC 8785 match, and invalid I-JSON is refused")
    func json() throws {
        let corpus = try #require(Self.corpus)
        for valid in corpus.json.valid {
            let tree = try CanonicalJSON.parse(valid.input)
            #expect(CanonicalJSON.canonical(tree) == valid.canonical, "canonical: \(valid.input)")
            #expect(CanonicalJSON.jcs(tree) == valid.jcs, "jcs: \(valid.input)")
        }
        for invalid in corpus.json.invalid {
            #expect(throws: CanonicalJSON.ParseError.self, "should refuse: \(invalid.debugDescription)") {
                try CanonicalJSON.parse(invalid)
            }
        }
    }

    @Test("anchor context")
    func contexts() throws {
        for context in try #require(Self.corpus).contexts {
            let (prefix, suffix) = DraftFile.anchorContext(context.text, start: context.start, end: context.end)
            #expect(prefix == context.prefix && suffix == context.suffix, "\(context.text)")
        }
    }

    @Test("recognising a file by its bytes")
    func detect() throws {
        for detect in try #require(Self.corpus).detect {
            #expect(DraftFile.detect(CRC32Corpus.bytes(fromHex: detect.hex)).rawValue == detect.format, "\(detect.name)")
        }
    }

    @Test("bridges to and from today's model")
    func bridges() throws {
        for bridge in try #require(Self.corpus).bridges {
            let source = try #require(bridge.source ?? bridge.corpus.flatMap { Self.parseSources[$0] }, "\(bridge.name)")
            let document = DraftFile.fromScreenplay(try Fountain.parse(source, emphasis: .runs))
            let back = DraftFile.toScreenplay(document)
            let rendition = Fountain.serialise(back.screenplay)
            let doc = DraftCorpus.doc(document)
            #expect(back.diagnostics == bridge.diagnostics, "\(bridge.name)")
            if let expected = bridge.document {
                #expect(doc.script == expected.script, "\(bridge.name): script")
                #expect(doc.notes == expected.notes, "\(bridge.name): notes")
                #expect(rendition == bridge.back, "\(bridge.name): back")
            } else {
                let digest = { (text: String) in SHA256Digest.hex(Array(text.utf8)) }
                #expect(digest(doc.script) == bridge.scriptSha256, "\(bridge.name): script")
                #expect(doc.notes.map(digest) == bridge.notesSha256, "\(bridge.name): notes")
                #expect(digest(rendition) == bridge.backSha256, "\(bridge.name): back")
            }
        }
    }

    @Test("writes the same bytes as the TypeScript engine")
    func write() throws {
        let corpus = try #require(Self.corpus)
        for write in corpus.write {
            let bytes = try DraftFile.write(
                DraftCorpus.document(write.document), writerName: corpus.writer.name, writerVersion: corpus.writer.version
            )
            #expect(DraftCorpus.hex(bytes) == write.bytes, "\(write.name)")
        }
    }

    @Test("reads every case to the same document and diagnostics, or refuses it the same way")
    func read() throws {
        for read in try #require(Self.corpus).read {
            let bytes = CRC32Corpus.bytes(fromHex: read.bytes)
            if let refused = read.refused {
                do {
                    _ = try DraftFile.read(bytes)
                    Issue.record("\(read.name): should be refused (\(refused))")
                } catch let error as DraftFormatError {
                    #expect(error.code == refused, "\(read.name)")
                }
                continue
            }
            let result = try DraftFile.read(bytes)
            let expected = try #require(read.document)
            let doc = DraftCorpus.doc(result.document)
            #expect(result.diagnostics == read.diagnostics, "\(read.name): diagnostics")
            #expect(result.readOnly == read.readOnly, "\(read.name): readOnly")
            #expect(doc.title == expected.title, "\(read.name): title")
            #expect(doc.script == expected.script, "\(read.name): script")
            #expect(doc.notes == expected.notes, "\(read.name): notes")
            #expect(doc.revisions == expected.revisions, "\(read.name): revisions")
            #expect(doc.production == expected.production, "\(read.name): production")
            #expect(doc.manifestExtra == expected.manifestExtra, "\(read.name): manifestExtra")
            #expect(doc.parts == expected.parts, "\(read.name): parts")
        }
    }
}
