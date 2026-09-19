import Foundation
import EDraftEngine

/// Loads the conformance corpus exported from the TypeScript engine by
/// `scripts/engine-conformance-export.mjs`. The fixtures live at the package
/// root (`apple/EDraftEngine/Fixtures`), outside the SPM targets, so they
/// are located relative to this source file rather than as bundle resources.
enum FixtureStore {

    static let directory: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EDraftEngineTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Fixtures", isDirectory: true)
    }()

    static func load<T: Decodable>(_ name: String, as type: T.Type = T.self) throws -> T {
        let url = directory.appendingPathComponent(name)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Corpus payload shapes (mirror of the exporter's JSON)

enum ChoreographyCorpus {
    struct Root: Decodable {
        let tabNext: [TabNext]
        let tabSetFor: [TabSetFor]
        let tabCycle: [TabCycle]
        let nextElement: [NextElement]
    }
    struct TabNext: Decodable {
        let current: String
        let reverse: Bool
        let result: String
    }
    struct TabSetFor: Decodable {
        let prev: String?
        let result: [String]
    }
    struct TabCycle: Decodable {
        let current: String
        let prev: String?
        let reverse: Bool
        let result: String
    }
    struct NextElement: Decodable {
        let current: String
        let key: String
        let text: String
        let result: String
    }
}

enum NormalizeCorpus {
    struct Root: Decodable {
        let parenthetical: [TextCase]
        let unwrapParenthetical: [TextCase]
        let cue: [TextCase]
        let looksLikeCue: [BoolCase]
        let elementText: [ElementTextCase]
    }
    struct TextCase: Decodable {
        let input: String
        let result: String
    }
    struct BoolCase: Decodable {
        let input: String
        let result: Bool
    }
    struct ElementTextCase: Decodable {
        let type: String
        let input: String
        let result: String
    }
}

enum CRC32Corpus {
    struct Root: Decodable {
        let cases: [Case]
    }
    struct Case: Decodable {
        let hex: String
        let result: UInt32
    }

    static func bytes(fromHex hex: String) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            bytes.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return bytes
    }
}

enum ParseCorpus {
    struct Case: Decodable {
        let name: String
        let source: String
        let expected: Screenplay
    }
}

enum SerialiseCorpus {
    struct Case: Decodable {
        let name: String
        let screenplay: Screenplay
        let expected: String
    }
}

enum PaginateCorpus {
    struct Case: Decodable {
        let name: String
        let screenplay: Screenplay
        let expected: Expected
    }
    struct Expected: Decodable {
        let pages: [ScriptPage]
        let runtime: String
        let printedLines: Int
    }
}

enum PredictCorpus {
    struct Case: Decodable {
        let name: String
        let screenplay: Screenplay
        let context: Context
        let expected: [Prediction]
    }
    struct Context: Decodable {
        let type: String
        let text: String
        let index: Int
    }
}

enum GhostSuffixCorpus {
    struct Case: Decodable {
        let candidate: String
        let text: String
        let hint: Bool
        let expected: String
    }
}

enum EmphasisCorpus {
    struct ParseCase: Decodable {
        let input: String
        let expected: Parsed
    }
    struct Parsed: Decodable {
        let text: String
        let runs: [StyleRun]
    }
    struct SynthesiseCase: Decodable {
        let input: Input
        let expected: String

        struct Input: Decodable {
            let text: String
            let runs: [StyleRun]
        }
    }
    struct RoundTripCase: Decodable {
        let source: String
        let expected: Expected

        struct Expected: Decodable {
            let text: String
            let runs: [StyleRun]
            let synthesised: String
            let fixedPoint: Parsed
        }
    }
}

/// Runs under editing (RFC v2.1 §4): propagation, the toggle verbs, and the
/// live collapse. Pinned by `Fixtures/style-edits.json`.
enum StyleEditsCorpus {
    struct Root: Decodable {
        let propagate: [PropagateCase]
        let toggle: [ToggleCase]
        let collapse: [CollapseCase]
    }

    struct PropagateCase: Decodable {
        let name: String
        let runs: [StyleRun]
        let replace: Range
        let insert: Int
        /// The PRE-edit text length; expected runs index the post-edit text.
        let textLength: Int
        let expected: [StyleRun]

        struct Range: Decodable {
            let start: Int
            let end: Int
        }
    }

    struct ToggleCase: Decodable {
        let name: String
        let runs: [StyleRun]
        let start: Int
        let end: Int
        /// A single Style token — the same spelling the StyleSet Codable
        /// conformance uses, wrapped in an array for the decode.
        let style: String
        let textLength: Int
        let covered: Bool
        let expected: [StyleRun]
    }

    struct CollapseCase: Decodable {
        let name: String
        let text: String
        let at: Int
        let expected: Expected?

        struct Expected: Decodable, Equatable {
            let text: String
            let run: StyleRun
            let removed: [Removed]
            let caret: Int

            struct Removed: Decodable, Equatable {
                let start: Int
                let end: Int
            }
        }
    }
}

enum FdxCorpus {    struct Root: Decodable {
        let importCases: [ImportCase]
        let exportCases: [ExportCase]
        /// The ScriptNotes section — apart, so every import case keeps its
        /// expected output exactly.
        var scriptNoteCases: [ScriptNotesCase] = []
        /// The preserving save — the file, the screenplay it is handed, and
        /// the bytes it must write.
        var rewriteCases: [RewriteCase] = []

        enum CodingKeys: String, CodingKey {
            case importCases = "import"
            case exportCases = "export"
            case scriptNoteCases = "scriptNotes"
            case rewriteCases = "rewrite"
        }
    }

    /// The source is inline, or a file beside the corpus named by
    /// `sourceFile`. The screenplay saved is `screenplay`, or the document's
    /// own script; `unedited` is the caller's reading passed to the save;
    /// `through: "fountain"` builds both from the file the way the app does,
    /// after `edit` — `find`, which occurs once in the Fountain source,
    /// replaced by `replace`. The expected result is exact bytes, whether the
    /// save returns the file unchanged, or the one change it makes: at UTF-16
    /// `at`, `removed` became `inserted` — read, when `scriptNoteRanges` is
    /// given, with every ScriptNote Range value emptied on both sides, and the
    /// saved Range values, in note order, those.
    struct RewriteCase: Decodable {
        let name: String
        let source: String?
        let sourceFile: String?
        let screenplay: Screenplay?
        let unedited: Screenplay?
        let through: String?
        let edit: Edit?
        /// How the writer's notes are written, everything new pinned (IL-0039).
        let notes: NoteWritingSpec?
        let expected: Expected

        struct Edit: Decodable {
            let find: String
            let replace: String
        }

        struct Expected: Decodable {
            let xml: String?
            let identical: Bool?
            let changed: Changed?
            let scriptNoteRanges: [String]?
        }

        struct Changed: Decodable {
            let at: Int
            let removed: String
            let inserted: String
        }

        func xml() throws -> String {
            if let source { return source }
            return try String(
                contentsOf: FixtureStore.directory.appendingPathComponent(sourceFile ?? ""),
                encoding: .utf8
            )
        }
    }

    /// A ScriptNotes reading. The source is inline, or a file beside the
    /// corpus named by `sourceFile`; the screenplay is pinned only for an
    /// inline source.
    struct ScriptNotesCase: Decodable {
        let name: String
        let source: String?
        let sourceFile: String?
        let options: ImportCase.Options
        let expected: Expected

        struct Expected: Decodable {
            let script: Screenplay?
            let diagnostics: [Fdx.Diagnostic]
            let scriptNotes: [Fdx.ScriptNote]
        }

        func xml() throws -> String {
            if let source { return source }
            return try String(
                contentsOf: FixtureStore.directory.appendingPathComponent(sourceFile ?? ""),
                encoding: .utf8
            )
        }

        var importOptions: Fdx.ImportOptions {
            Fdx.ImportOptions(
                maxSourceCharacters: options.maxSourceCharacters,
                maxParagraphs: options.maxParagraphs,
                maxTextRuns: options.maxTextRuns,
                maxWarnings: options.maxWarnings
            )
        }
    }

    struct ImportCase: Decodable {
        let name: String
        let source: String
        let options: Options
        let expected: Expected

        struct Options: Decodable {
            let maxSourceCharacters: Int?
            let maxParagraphs: Int?
            let maxTextRuns: Int?
            let maxWarnings: Int?
        }

        struct Expected: Decodable {
            let script: Screenplay
            let diagnostics: [Fdx.Diagnostic]
        }

        var importOptions: Fdx.ImportOptions {
            Fdx.ImportOptions(
                maxSourceCharacters: options.maxSourceCharacters,
                maxParagraphs: options.maxParagraphs,
                maxTextRuns: options.maxTextRuns,
                maxWarnings: options.maxWarnings
            )
        }
    }

    struct ExportCase: Decodable {
        let name: String
        let screenplay: Screenplay
        /// How the writer's notes are written, everything new pinned (IL-0039).
        let notes: NoteWritingSpec?
        let expected: Expected

        struct Expected: Decodable {
            let xml: String
            let diagnostics: [Fdx.Diagnostic]
        }
    }
}

/// How a save writes the writer's notes, with everything that is new each
/// time — RefId, paragraph ids, date — given in order (IL-0039, IL-0042).
struct NoteWritingSpec: Decodable {
    let writer: String?
    let now: String
    let ids: [String]

    /// A fresh writing: its ids handed out from the start.
    func writing() -> Fdx.NoteWriting {
        let ids = Supply(ids)
        return Fdx.NoteWriting(writer: writer, now: now, newId: { ids.next() })
    }

    /// The same values the corpus pins, for a test that writes notes itself.
    static let pinned = NoteWritingSpec(
        writer: "Dana Reyes (Director)",
        now: "20260918T120000",
        ids: (1...24).map { "00000000-0000-4000-8000-" + String(String($0, radix: 16)).leftPadded(to: 12) }
    )

    init(writer: String?, now: String, ids: [String]) {
        self.writer = writer
        self.now = now
        self.ids = ids
    }

    private final class Supply: @unchecked Sendable {
        private let items: [String]
        private var index = 0
        private let lock = NSLock()

        init(_ items: [String]) { self.items = items }

        func next() -> String {
            lock.lock()
            defer { lock.unlock() }
            let item = items[index % items.count]
            index += 1
            return item
        }
    }
}

private extension String {
    func leftPadded(to width: Int) -> String {
        String(repeating: "0", count: max(0, width - count)) + self
    }
}

/// The act derivation (RFC-ACT-BREAK §4). Pinned by `Fixtures/acts.json`.
enum ActsCorpus {
    struct Root: Decodable {
        let ordinals: [OrdinalCase]
        let canonical: [CanonicalCase]
        let actCards: [CanonicalCase]
        let endCards: [CanonicalCase]
        let renumber: [RenumberCase]
    }
    struct OrdinalCase: Decodable {
        let n: Int
        let result: String
    }
    struct CanonicalCase: Decodable {
        let text: String
        let result: Bool
    }
    struct RenumberCase: Decodable {
        let input: [ScreenplayElement]
        let result: [String]
    }
}

/// The numbered scene heading grammar (routing pack, step 1). Pinned by
/// `Fixtures/sceneheading.json`.
enum SceneheadingCorpus {
    struct Root: Decodable {
        let cases: [Case]
    }
    struct Case: Decodable {
        let text: String
        let result: Parsed?
    }
    struct Parsed: Decodable, Equatable {
        let number: String?
        let text: String
    }
}

/// The .draft file's corpus (`Fixtures/draft.json`). Trees travel as
/// canonical JSON text, so member order is compared exactly; bytes as hex.
enum DraftCorpus {
    struct Root: Decodable {
        let writer: Writer
        let sha256: [Digest]
        let json: JSONCases
        let contexts: [Context]
        let detect: [Detect]
        let bridges: [Bridge]
        let write: [Write]
        let read: [Read]
    }
    struct Writer: Decodable {
        let name: String
        let version: String
    }
    struct Digest: Decodable {
        let hex: String
        let sha256: String
    }
    struct JSONCases: Decodable {
        let valid: [Valid]
        let invalid: [String]
    }
    struct Valid: Decodable {
        let input: String
        let canonical: String
        let jcs: String
    }
    struct Context: Decodable {
        let text: String
        let start: Int
        let end: Int
        let prefix: String
        let suffix: String
    }
    struct Detect: Decodable {
        let name: String
        let hex: String
        let format: String
    }
    struct Doc: Decodable {
        let title: String?
        let script: String
        let notes: String?
        let manifestExtra: String?
        let parts: [Part]
    }
    struct Part: Decodable, Equatable {
        let path: String
        let hex: String
        let damaged: Bool
    }
    struct Bridge: Decodable {
        let name: String
        let source: String?
        let corpus: String?
        let document: Doc?
        let back: String?
        let scriptSha256: String?
        let notesSha256: String?
        let backSha256: String?
        let diagnostics: [DraftDiagnostic]
    }
    struct Write: Decodable {
        let name: String
        let document: Doc
        let bytes: String
    }
    struct Read: Decodable {
        let name: String
        let bytes: String
        let document: Doc?
        let diagnostics: [DraftDiagnostic]?
        let readOnly: Bool?
        let refused: String?
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    struct NotAnObject: Error {}

    static func object(_ text: String) throws -> JSONObject {
        guard let object = try CanonicalJSON.parse(text).objectValue else { throw NotAnObject() }
        return object
    }

    /// The fixture's document, as the engine holds it.
    static func document(_ doc: Doc) throws -> DraftDocument {
        DraftDocument(
            title: doc.title,
            script: try object(doc.script),
            notes: try doc.notes.map(object),
            parts: doc.parts.map { DraftPart(path: $0.path, data: CRC32Corpus.bytes(fromHex: $0.hex), damaged: $0.damaged) },
            manifestExtra: try doc.manifestExtra.map(object)
        )
    }

    /// The engine's document, as the fixture carries it.
    static func doc(_ document: DraftDocument) -> (title: String?, script: String, notes: String?, manifestExtra: String?, parts: [Part]) {
        (
            document.title,
            CanonicalJSON.canonical(.object(document.script)),
            document.notes.map { CanonicalJSON.canonical(.object($0)) },
            document.manifestExtra.map { CanonicalJSON.canonical(.object($0)) },
            document.parts.map { Part(path: $0.path, hex: hex($0.data), damaged: $0.damaged) }
        )
    }
}
