import XCTest
@testable import EDraftCore
@testable import EDraftEngine

/// The whole scripts corpus through the paste route (RFC-ACT-BREAK
/// phase 3): the same facts `scripts/paste-corpus-gate.mjs` holds the
/// TypeScript engine to, held here against the Core planner — one gate,
/// both paste paths, as the corpus plan asks.
///
/// The scripts themselves are not committed — they are not ours to ship —
/// so the gate skips cleanly when the corpus directory is absent, and the
/// facts it holds are the golden the TypeScript gate records. Set
/// EDRAFT_SCRIPT_CORPUS to point the gate at a corpus elsewhere.
@MainActor
final class PasteCorpusGateTests: XCTestCase {

    private let corpusDir =
        ProcessInfo.processInfo.environment["EDRAFT_SCRIPT_CORPUS"]
            ?? "/Users/x/Documents/kimi/tasks/2026-09-09/17-57-54-2b2c55e4/scripts-corpus"

    /// A card line adopted as a speaker: the exact failure this phase
    /// removes. Matches the TypeScript gate's pattern.
    private func isCardCue(_ text: String) -> Bool {
        text.hasPrefix("ACT ") || text == "TEASER" || text == "COLD OPEN" || text.hasPrefix("END ")
    }

    private func paste(_ source: String) -> [ScriptElement] {
        ScreenplayEditPlanner.plan(
            elements: [ScriptElement(type: .action, text: "")],
            replacing: NSRange(location: 0, length: 0),
            with: source,
            intent: .multilinePaste,
            kindForNewElement: { previous, text, depth in
                EditorState(source: "").kindForInsertedElement(
                    after: previous, text: text, pasteDepth: depth
                )
            }
        )?.elements ?? []
    }

    private func corpusFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: corpusDir)
            .filter { $0.hasSuffix(".txt") }
            .sorted()
    }

    func testBreakingBadCarriesItsFiveActsAndNoCardSpeakers() throws {
        guard FileManager.default.fileExists(atPath: corpusDir) else {
            throw XCTSkip("no corpus at \(corpusDir) — the scripts are not committed")
        }
        let source = try String(contentsOfFile: "\(corpusDir)/breaking-bad.txt", encoding: .utf8)
        let elements = paste(source)

        XCTAssertEqual(
            elements.filter { $0.type == .actbreak }.map(\.text),
            ["TEASER", "ACT ONE", "ACT TWO", "ACT THREE", "ACT FOUR"],
            "the pilot's five acts, in order"
        )
        XCTAssertEqual(
            elements.filter { $0.type == .character && isCardCue($0.text) }.count, 0,
            "no card line is adopted as a speaker"
        )
        XCTAssertEqual(
            elements.filter { Acts.isEndActCard($0.text) }.count, 0,
            "the four closing cards are dropped, never stored"
        )
    }

    func testNoOtherScriptProducesAnActBoundary() throws {
        guard FileManager.default.fileExists(atPath: corpusDir) else {
            throw XCTSkip("no corpus at \(corpusDir) — the scripts are not committed")
        }
        for file in try corpusFiles() where file != "breaking-bad.txt" {
            let source = try String(contentsOfFile: "\(corpusDir)/\(file)", encoding: .utf8)
            let elements = paste(source)
            XCTAssertEqual(
                elements.filter { $0.type == .actbreak }.count, 0,
                "\(file) gains no actbreak"
            )
            XCTAssertEqual(
                elements.filter { Acts.isEndActCard($0.text) }.count, 0,
                "\(file) stores no end-of-act card"
            )
        }
    }
}
