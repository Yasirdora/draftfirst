import Foundation
import Testing
import EDraftEngine

/// Notes pinned to words, against the TypeScript engine — RFC-NOTES-SYSTEM
/// §5 (stage 4).
///
/// Conformance against `Fixtures/noteanchor.json`: the disambiguation rule
/// case by case (§5.3), the header grammar this stage owns (§4.1), and the
/// Fountain round trip (§5.2). Every expectation in that file was computed
/// by the TypeScript engine, so a disagreement here is a disagreement
/// between the ports — which is the thing this suite exists to catch.
enum NoteAnchorCorpus {
    struct Root: Decodable {
        let fountain: [FountainCase]
        let rewrite: [RewriteCase]
        let read: [ReadCase]
        let resolve: [ResolveCase]
        let forSpan: [ForSpanCase]
        let header: [HeaderCase]
        let writeHeader: [WriteHeaderCase]
    }

    /// A preserving save of a file that holds an anchored note (§5.1).
    struct RewriteCase: Decodable {
        let name: String
        let source: String
        let screenplay: Screenplay
        let unedited: Screenplay
        let notes: NoteWritingSpec
        let expected: Expected

        struct Expected: Decodable {
            let xml: String
            let identical: Bool?
        }
    }

    /// The anchor derived from the Range a note comes back on (§5.4).
    struct ReadCase: Decodable {
        let name: String
        let source: String
        let expected: Expected

        struct Expected: Decodable {
            let script: Screenplay
            let scriptNotes: [Fdx.ScriptNote]
            let diagnostics: [Fdx.Diagnostic]
        }
    }

    struct FountainCase: Decodable {
        let source: String
        let expected: Screenplay
        let written: String
        let reparsed: Screenplay
    }

    struct ResolveCase: Decodable {
        let paragraph: String
        let anchor: NoteAnchor
        let expected: SpanValue?
    }

    struct ForSpanCase: Decodable {
        let paragraph: String
        let start: Int
        let end: Int
        let expected: NoteAnchor?
        let resolved: SpanValue?
    }

    struct HeaderCase: Decodable {
        let text: String
        let expected: HeaderValue?
    }

    struct HeaderValue: Decodable {
        let anchor: NoteAnchor
        let body: String
    }

    struct WriteHeaderCase: Decodable {
        let anchor: NoteAnchor
        let expected: String
    }

    struct SpanValue: Decodable, Equatable {
        let start: Int
        let end: Int
    }
}

@Suite("Note anchors conformance")
struct NoteAnchorConformanceTests {

    private static let corpus: NoteAnchorCorpus.Root = {
        do { return try FixtureStore.load("noteanchor.json") }
        catch {
            Issue.record("Failed to load noteanchor.json: \(error)")
            return NoteAnchorCorpus.Root(
                fountain: [], rewrite: [], read: [],
                resolve: [], forSpan: [], header: [], writeHeader: []
            )
        }
    }()

    @Test("§5.3 · the rule lands on the same words as TypeScript, case for case")
    func resolveMatches() {
        #expect(!Self.corpus.resolve.isEmpty)
        for (index, testCase) in Self.corpus.resolve.enumerated() {
            let span = NoteAnchor.resolve(testCase.paragraph, testCase.anchor)
            let got = span.map { NoteAnchorCorpus.SpanValue(start: $0.start, end: $0.end) }
            #expect(
                got == testCase.expected,
                """
                resolve[\(index)] \(testCase.paragraph.debugDescription) \
                on:\(testCase.anchor.on.debugDescription) nth:\(String(describing: testCase.anchor.nth)) \
                — Swift \(String(describing: got)), TypeScript \(String(describing: testCase.expected))
                """
            )
        }
    }

    @Test("§5.3 · the anchor written for a span, and the span it resolves back to")
    func forSpanMatches() {
        #expect(!Self.corpus.forSpan.isEmpty)
        for (index, testCase) in Self.corpus.forSpan.enumerated() {
            let anchor = NoteAnchor.forSpan(testCase.paragraph, start: testCase.start, end: testCase.end)
            #expect(
                anchor == testCase.expected,
                """
                forSpan[\(index)] \(testCase.paragraph.debugDescription) \
                [\(testCase.start),\(testCase.end)) — Swift \(String(describing: anchor)), \
                TypeScript \(String(describing: testCase.expected))
                """
            )
            /* And the inverse holds in this port too, not just in that one. */
            let resolved = anchor.flatMap { NoteAnchor.resolve(testCase.paragraph, $0) }
                .map { NoteAnchorCorpus.SpanValue(start: $0.start, end: $0.end) }
            #expect(resolved == testCase.resolved, "forSpan[\(index)] does not resolve back")
        }
    }

    @Test("§4.1 · the header this stage owns, read the same way")
    func headerMatches() {
        #expect(!Self.corpus.header.isEmpty)
        for (index, testCase) in Self.corpus.header.enumerated() {
            let reading = NoteAnchor.readHeader(testCase.text)
            #expect(
                reading?.anchor == testCase.expected?.anchor,
                "header[\(index)] \(testCase.text.debugDescription) — anchor differs"
            )
            #expect(
                reading?.body == testCase.expected?.body,
                "header[\(index)] \(testCase.text.debugDescription) — body differs"
            )
        }
    }

    @Test("§4.1 · and written the same way")
    func writeHeaderMatches() {
        #expect(!Self.corpus.writeHeader.isEmpty)
        for (index, testCase) in Self.corpus.writeHeader.enumerated() {
            #expect(
                NoteAnchor.writeHeader(testCase.anchor) == testCase.expected,
                "writeHeader[\(index)] differs from TypeScript"
            )
        }
    }

    @Test("§5.1 · FDX: a save writes the anchored Range byte for byte as TypeScript does")
    func rewriteMatches() {
        #expect(!Self.corpus.rewrite.isEmpty)
        for testCase in Self.corpus.rewrite {
            let xml = Fdx.open(testCase.source).rewrite(
                testCase.screenplay,
                unedited: testCase.unedited,
                notes: testCase.notes.writing()
            )
            #expect(xml == testCase.expected.xml, "rewrite \(testCase.name) differs from TypeScript")
            if testCase.expected.identical == true {
                #expect(xml == testCase.source, "rewrite \(testCase.name): a save with no edit changed the file")
            }
        }
    }

    @Test("§5.4 · FDX: the words come back off the Range, in both ports")
    func readMatches() {
        #expect(!Self.corpus.read.isEmpty)
        for testCase in Self.corpus.read {
            let result = Fdx.parse(testCase.source)
            #expect(result.script == testCase.expected.script, "read \(testCase.name): the screenplay differs")
            #expect(result.scriptNotes == testCase.expected.scriptNotes, "read \(testCase.name): the notes differ")
            #expect(result.diagnostics == testCase.expected.diagnostics, "read \(testCase.name): the diagnostics differ")
            /* The point of the case: the note carries the words, not the paragraph. */
            let anchors = result.script.elements.filter { $0.type == .note }.map(\.anchor)
            #expect(anchors.contains { $0 != nil }, "read \(testCase.name): no note came back anchored")
        }
    }

    @Test("§5.2 · Fountain: the same reading, the same bytes, and the anchor survives")
    func fountainRoundTrip() throws {
        #expect(!Self.corpus.fountain.isEmpty)
        for (index, testCase) in Self.corpus.fountain.enumerated() {
            let parsed = try Fountain.parse(testCase.source)
            #expect(parsed == testCase.expected, "fountain[\(index)] reads differently")
            let written = Fountain.serialise(parsed)
            #expect(written == testCase.written, "fountain[\(index)] writes different bytes")
            #expect(try Fountain.parse(written) == testCase.reparsed, "fountain[\(index)] does not round-trip")
        }
    }
}
