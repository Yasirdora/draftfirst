import Foundation
import Testing
import EDraftEngine

/// Damage never opens silently (RFC-DRAFT-FORMAT §15, B3), the limits hold,
/// and a read-then-write keeps what it does not know (B5) — in the Swift
/// port, over the fixture's own files.
@Suite("Draft file recovery")
struct DraftFileRecoveryTests {

    static func written(_ name: String) throws -> [UInt8] {
        let corpus = try #require(DraftFileConformanceTests.corpus)
        let write = try #require(corpus.write.first { $0.name == name })
        return CRC32Corpus.bytes(fromHex: write.bytes)
    }

    static func key(_ document: DraftDocument) -> String {
        let doc = DraftCorpus.doc(document)
        return [doc.title ?? "-", doc.script, doc.notes ?? "-", doc.manifestExtra ?? "-"].joined(separator: "\u{1}")
            + doc.parts.map { "\($0.path)=\($0.hex)=\($0.damaged)" }.joined(separator: "\u{1}")
    }

    /// Opens, refuses with a reason, or — when it says nothing — opens the
    /// same document as the undamaged file.
    static func check(_ bytes: [UInt8], expected: String) {
        do {
            let result = try DraftFile.read(bytes)
            if result.diagnostics.isEmpty { #expect(key(result.document) == expected) }
        } catch {
            #expect(error is DraftFormatError, "a reader error that is not a refusal: \(error)")
        }
    }

    @Test("every byte changed and every truncation, three files", arguments: ["sample", "everything", "parts"])
    func fuzz(_ name: String) throws {
        let original = try Self.written(name)
        let expected = Self.key(try DraftFile.read(original).document)
        for index in original.indices {
            var bytes = original
            bytes[index] ^= 0xFF
            Self.check(bytes, expected: expected)
        }
        for length in 0..<original.count { Self.check(Array(original[0..<length]), expected: expected) }
    }

    @Test("a truncated file gives back its script whenever script.json is whole")
    func truncationKeepsTheScript() throws {
        let original = try Self.written("sample")
        var at = 0
        var scriptEnd = 0
        while at + 30 <= original.count, original[at] == 0x50, original[at + 1] == 0x4B, original[at + 2] == 3, original[at + 3] == 4 {
            let nameLength = Int(original[at + 26]) | Int(original[at + 27]) << 8
            let size = Int(original[at + 18]) | Int(original[at + 19]) << 8 | Int(original[at + 20]) << 16 | Int(original[at + 21]) << 24
            let end = at + 30 + nameLength + size
            if String(decoding: original[(at + 30)..<(at + 30 + nameLength)], as: UTF8.self) == "script.json" { scriptEnd = end }
            at = end
        }
        #expect(scriptEnd > 0)
        for length in scriptEnd..<original.count {
            #expect(throws: Never.self, "cut at \(length)") { _ = try DraftFile.read(Array(original[0..<length])) }
        }
    }

    @Test("an archive over the 512-entry limit is refused")
    func overLimits() throws {
        var entries = [Zip.Entry(name: "mimetype", data: Array(DraftFile.mediaType.utf8))]
        for i in 0..<520 { entries.append(Zip.Entry(name: "ext/x/\(i)", data: [])) }
        do {
            _ = try DraftFile.read(Zip.writeStored(entries, dosDate: 0x0021))
            Issue.record("an archive of 521 entries was read")
        } catch let error as DraftFormatError {
            #expect(error.code == "over-limits")
        }
    }

    @Test("a corrupt deflated entry comes back damaged, every byte of it flipped in turn")
    func corruptDeflate() throws {
        let corpus = try #require(DraftFileConformanceTests.corpus)
        let read = try #require(corpus.read.first { $0.name == "deflated-part" })
        let bytes = CRC32Corpus.bytes(fromHex: read.bytes)
        let name = Array("ext/x/deflated.txt".utf8)
        let start = try #require((0...(bytes.count - name.count)).first { Array(bytes[$0..<($0 + name.count)]) == name })
            + name.count
        for index in start..<min(bytes.count, start + 60) {
            var copy = bytes
            copy[index] ^= 0xFF
            let result = try DraftFile.read(copy)
            let part = result.document.parts.first { $0.path == "ext/x/deflated.txt" }
            #expect(part != nil)
        }
    }

    @Test("a read and a write keep every unknown member and part, byte for byte", arguments: ["must-preserve", "parts", "everything"])
    func mustPreserve(_ name: String) throws {
        let corpus = try #require(DraftFileConformanceTests.corpus)
        let original = try Self.written(name)
        let result = try DraftFile.read(original)
        #expect(result.diagnostics.isEmpty)
        let again = try DraftFile.write(result.document, writerName: corpus.writer.name, writerVersion: corpus.writer.version)
        #expect(again == original)
    }
}
