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
            kindForNewElement: { previous, text, depth, attached in
                // The route the surfaces take: a paste's signal-less line
                // falls back to prose (a paste is not typing).
                EditorState(source: "").kindForInsertedElement(
                    after: previous, text: text, pasteDepth: depth,
                    attached: attached, fallback: .action
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

    /// The printed page's furniture never reaches the model (routing pack,
    /// step 1): 1,898 artifact lines stripped across the corpus, none
    /// stored. Matches the TypeScript gate's hard check.
    func testNoScriptStoresAPaginationArtifact() throws {
        guard FileManager.default.fileExists(atPath: corpusDir) else {
            throw XCTSkip("no corpus at \(corpusDir) — the scripts are not committed")
        }
        for file in try corpusFiles() {
            let source = try String(contentsOfFile: "\(corpusDir)/\(file)", encoding: .utf8)
            let elements = paste(source)
            XCTAssertEqual(
                elements.filter { PasteHeuristics.isPaginationArtifact($0.text) }.count, 0,
                "\(file) stores no page number, (MORE) or CONTINUED"
            )
        }
    }

    /// No revision asterisk is left sitting on stored text — gone-girl
    /// carried 616 of them before the strip; zero is the rule now. Matches
    /// the TypeScript gate's hard check (/[^*]\*$|^\*$/).
    func testNoScriptStoresARevisionAsterisk() throws {
        guard FileManager.default.fileExists(atPath: corpusDir) else {
            throw XCTSkip("no corpus at \(corpusDir) — the scripts are not committed")
        }
        for file in try corpusFiles() {
            let source = try String(contentsOfFile: "\(corpusDir)/\(file)", encoding: .utf8)
            let elements = paste(source)
            let starTailed = elements.filter { element in
                let text = element.text
                guard text.hasSuffix("*") else { return false }
                return text.count == 1 || text.dropLast().last != "*"
            }.count
            XCTAssertEqual(starTailed, 0, "\(file) stores no revision asterisk")
        }
    }

    /// No speech splits at its wrap into an action line. The raw route
    /// types every line on its own, so the pin counts every adjacent
    /// speech → prose pair, including the ones a blank line genuinely
    /// separates — tell-less prose continues the paragraph under way, and
    /// a structure-less paste cannot see it (named in PasteReassembly).
    /// pasted-26's eight are those genuine pairs, agreed with the
    /// TypeScript engine, whose own panel counts attached wrap-splits
    /// only and so reads zero. What the zeroes hold is the breaking-bad
    /// regression — 236 speeches shattered line-per-element when a single
    /// OCR-fused line vetoed the whole paste's reassembly — and the
    /// pasted-26 one: 664 wrap-splits when the NUL glue demoted the paste
    /// to the raw route, before attachment was read.
    func testNoSpeechSplitsIntoActionAtItsWrap() throws {
        guard FileManager.default.fileExists(atPath: corpusDir) else {
            throw XCTSkip("no corpus at \(corpusDir) — the scripts are not committed")
        }
        /// Measured on this route and pinned — the genuine blank-separated
        /// pairs agree with the TypeScript engine's typing, file for file.
        let expectedSplits: [String: Int] = ["pasted-26.txt": 8]
        for file in try corpusFiles() {
            let source = try String(contentsOfFile: "\(corpusDir)/\(file)", encoding: .utf8)
            let elements = paste(source)
            var splits = 0
            for pair in zip(elements, elements.dropFirst())
            where pair.0.type == .dialogue && pair.1.type == .action {
                splits += 1
            }
            XCTAssertEqual(
                splits, expectedSplits[file] ?? 0,
                "\(file) splits no speech at its wrap"
            )
        }
    }

    /// The numbered headings and OMITTED cards the corpus witnesses land
    /// as scenes with their numbers homed — gone-girl's 244 flanked
    /// headings, corpus-6's 62 numbered scenes and 13 omitted cards. The
    /// counts are this route's own observed truth, pinned file by file.
    func testNumberedAndOmittedScenesCarryTheirNumbers() throws {
        guard FileManager.default.fileExists(atPath: corpusDir) else {
            throw XCTSkip("no corpus at \(corpusDir) — the scripts are not committed")
        }
        /// Measured on this route and pinned — it agrees with the
        /// TypeScript engine's golden file for file.
        let expected: [String: (numbered: Int, omitted: Int)] = [
            "breaking-bad.txt": (0, 0),
            "corpus-1.txt": (0, 0),
            "corpus-6.txt": (62, 13),
            "emilia-perez.txt": (0, 0),
            "episode-101.txt": (0, 9),
            "foryourcon.txt": (0, 0),
            "from-the-black.txt": (0, 0),
            "gone-girl.txt": (244, 0),
            "heat.txt": (0, 0),
            "lalaland.txt": (0, 45),
            "manchester.txt": (0, 0),
            "no-country.txt": (0, 0),
            "pasted-26.txt": (0, 0),
            "whiplash.txt": (0, 17)
        ]
        for file in try corpusFiles() {
            let source = try String(contentsOfFile: "\(corpusDir)/\(file)", encoding: .utf8)
            let elements = paste(source)
            let numbered = elements.filter { $0.sceneNumber != nil }.count
            let omitted = elements.filter { $0.type == .scene && $0.text == "OMITTED" }.count
            if let pin = expected[file] {
                XCTAssertEqual(numbered, pin.numbered, "\(file) numbered scenes")
                XCTAssertEqual(omitted, pin.omitted, "\(file) omitted scenes")
            } else {
                XCTFail("\(file): unmeasured — numbered \(numbered), omitted \(omitted)")
            }
        }
    }
}
