import Foundation
import Testing
import EDraftEngine

/// Conformance of `Fdx.parse` against `Fixtures/fdx.json`: real-world and
/// adversarial FDX files parsed by the TypeScript engine, compared
/// element-for-element and diagnostic-for-diagnostic.
@Suite("FDX import conformance")
struct FdxImportConformanceTests {

    private static let corpus: FdxCorpus.Root = {
        do { return try FixtureStore.load("fdx.json") }
        catch {
            Issue.record("Failed to load fdx.json: \(error)")
            return FdxCorpus.Root(importCases: [], exportCases: [])
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        /* 29 before the omitted-scene cases (§7.3). */
        #expect(Self.corpus.importCases.count == 33)
        #expect(Self.corpus.exportCases.count == 14)
    }

    @Test("import", arguments: Self.corpus.importCases)
    func `import`(_ case_: FdxCorpus.ImportCase) {
        let result = Fdx.parse(case_.source, options: case_.importOptions)
        #expect(result.script == case_.expected.script,
                "\(case_.name): imported screenplay differs from the TypeScript engine")
        #expect(result.diagnostics == case_.expected.diagnostics,
                "\(case_.name): diagnostics differ from the TypeScript engine")
        #expect(result.warnings == case_.expected.diagnostics.map(\.message),
                "\(case_.name): warnings must be the diagnostic messages")
    }

    /// fdx → model → fdx is a byte-level fixed point. A foreign file's
    /// first import canonicalises once — a title line's absent alignment
    /// prints as Center and comes back recorded, exactly as the emphasis
    /// flip's first pass did — so the gate is set on our own export: what
    /// we write must re-import and re-write to itself, byte for byte.
    @Test("import → export → import is stable", arguments: Self.corpus.importCases)
    func identityRoundTrip(_ case_: FdxCorpus.ImportCase) {
        let once = Fdx.parse(case_.source, options: case_.importOptions).script
        // A note is written with a thread, ids and a date new each time: pinned.
        func export(_ script: Screenplay) -> String {
            Fdx.write(script, options: Fdx.ExportOptions(notes: NoteWritingSpec.pinned.writing())).xml
        }
        let exported = export(once)
        #expect(export(Fdx.parse(exported).script) == exported,
                "\(case_.name): our own export did not re-import to itself")
    }
}

/// Conformance of `Fdx.write` against `Fixtures/fdx.json`.
@Suite("FDX export conformance")
struct FdxExportConformanceTests {

    private static let corpus: FdxCorpus.Root = {
        do { return try FixtureStore.load("fdx.json") }
        catch {
            Issue.record("Failed to load fdx.json: \(error)")
            return FdxCorpus.Root(importCases: [], exportCases: [])
        }
    }()

    @Test("export", arguments: Self.corpus.exportCases)
    func export(_ case_: FdxCorpus.ExportCase) {
        let result = Fdx.write(case_.screenplay, options: Fdx.ExportOptions(notes: case_.notes?.writing()))
        #expect(result.xml == case_.expected.xml,
                "\(case_.name): exported FDX differs from the TypeScript engine")
        #expect(result.diagnostics == case_.expected.diagnostics,
                "\(case_.name): diagnostics differ from the TypeScript engine")
    }

    /// model → fdx → model restores every element FDX has a paragraph for,
    /// and the title page; the rest are omitted by design. The expected side
    /// is normalised by the export contract, exactly as the TypeScript
    /// tests express it: illegal XML code points come back repaired as
    /// U+FFFD (the export reports that repair), and a title line's absent
    /// alignment prints centered and comes back recorded.
    @Test("export → import restores representable elements", arguments: Self.corpus.exportCases)
    func printingRoundTrip(_ case_: FdxCorpus.ExportCase) {
        let result = Fdx.write(case_.screenplay, options: Fdx.ExportOptions(notes: case_.notes?.writing()))
        let back = Fdx.parse(result.xml).script
        // Stated rather than derived from the map the export uses, so this
        // fails when the subset changes instead of agreeing with it. Most of
        // what does not print is still representable — a Note is a line that
        // does not print, an Outline level is a section, a Summary is a
        // synopsis. A page break is the only thing left with no counterpart.
        // A note is a ScriptNote now (IL-0039), and one that names nobody is
        // written with the writer's name (D3): it comes back signed.
        let writer = case_.notes?.writer
        let printable = case_.screenplay.elements
            .filter { $0.type != .pagebreak }
            .map { element in
                var copy = element
                copy.text = Self.xmlLegal(element.text)
                copy.sceneNumber = element.sceneNumber.map(Self.xmlLegal)
                if element.type == .note, let writer, !copy.text.hasPrefix("\(writer): ") {
                    copy.text = "\(writer): \(copy.text)"
                }
                return copy
            }
        #expect(back.elements == printable,
                "\(case_.name): representable elements did not survive the round-trip")
        /* The line contract (RFC-TITLE-PAGE D5): text XML-legal, alignment
           recorded (absent prints Center), runs and the key annotation
           carried — an empty key is not written and comes back absent. */
        let expectedTitlePage = case_.screenplay.titlePage.map { line in
            TitlePageLine(
                text: Self.xmlLegal(line.text),
                alignment: line.alignment ?? .center,
                runs: line.runs,
                key: line.key?.isEmpty == false ? line.key : nil
            )
        }
        #expect(back.titlePage == expectedTitlePage,
                "\(case_.name): title page did not survive the round-trip")
    }

    /// The XML 1.0 Char production applied as the export applies it:
    /// anything else becomes U+FFFD.
    private static func xmlLegal(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x09, 0x0A, 0x0D, 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF:
                scalar
            default:
                "\u{FFFD}"
            }
        }))
    }
}
