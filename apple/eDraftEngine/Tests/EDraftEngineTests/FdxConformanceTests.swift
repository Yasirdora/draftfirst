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
        #expect(Self.corpus.importCases.count == 28)
        #expect(Self.corpus.exportCases.count == 12)
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

    /// fdx → model → fdx → model is an identity: once a file is in the
    /// model, our own export must re-import to the identical screenplay.
    @Test("import → export → import is stable", arguments: Self.corpus.importCases)
    func identityRoundTrip(_ case_: FdxCorpus.ImportCase) {
        let once = Fdx.parse(case_.source, options: case_.importOptions).script
        let twice = Fdx.parse(Fdx.writeXml(once)).script
        #expect(twice == once, "\(case_.name): fdx → model → fdx → model is not an identity")
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
        let result = Fdx.write(case_.screenplay)
        #expect(result.xml == case_.expected.xml,
                "\(case_.name): exported FDX differs from the TypeScript engine")
        #expect(result.diagnostics == case_.expected.diagnostics,
                "\(case_.name): diagnostics differ from the TypeScript engine")
    }

    /// model → fdx → model restores every element FDX has a paragraph for,
    /// and the title page; the rest are omitted by design. The expected side
    /// is normalised by the export contract, exactly as the TypeScript
    /// tests express it: illegal XML code points come back repaired as
    /// U+FFFD (the export reports that repair), and an empty title-page
    /// value list comes back as one empty line (`[]` → `[""]`).
    @Test("export → import restores representable elements", arguments: Self.corpus.exportCases)
    func printingRoundTrip(_ case_: FdxCorpus.ExportCase) {
        let result = Fdx.write(case_.screenplay)
        let back = Fdx.parse(result.xml).script
        // Stated rather than derived from the map the export uses, so this
        // fails when the subset changes instead of agreeing with it. Most of
        // what does not print is still representable — a Note is a line that
        // does not print, an Outline level is a section, a Summary is a
        // synopsis. A page break is the only thing left with no counterpart.
        let printable = case_.screenplay.elements
            .filter { $0.type != .pagebreak }
            .map { element in
                var copy = element
                copy.text = Self.xmlLegal(element.text)
                copy.sceneNumber = element.sceneNumber.map(Self.xmlLegal)
                return copy
            }
        #expect(back.elements == printable,
                "\(case_.name): representable elements did not survive the round-trip")
        let expectedTitlePage = case_.screenplay.titlePage.map { entry in
            TitlePageEntry(
                key: entry.key,
                values: entry.values.isEmpty ? [""] : entry.values.map(Self.xmlLegal)
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
