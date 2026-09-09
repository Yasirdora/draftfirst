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

enum FdxCorpus {
    struct Root: Decodable {
        let importCases: [ImportCase]
        let exportCases: [ExportCase]

        enum CodingKeys: String, CodingKey {
            case importCases = "import"
            case exportCases = "export"
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
        let expected: Expected

        struct Expected: Decodable {
            let xml: String
            let diagnostics: [Fdx.Diagnostic]
        }
    }
}
