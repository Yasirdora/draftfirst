import Foundation
import Testing
import EDraftEngine

/// Conformance of the Phase A edit arithmetic — `Emphasis.propagate`,
/// `isCovered`/`toggle`, and `liveCollapse` — against the TypeScript
/// engine's golden masters in `style-edits.json` (RFC v2.1 §4 / §3.3).
@Suite("Style edit conformance")
struct StyleEditConformanceTests {

    private static let corpus: StyleEditsCorpus.Root = {
        do { return try FixtureStore.load("style-edits.json") }
        catch {
            Issue.record("Failed to load style-edits.json: \(error)")
            return StyleEditsCorpus.Root(propagate: [], toggle: [], collapse: [])
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.propagate.count == 11)
        #expect(Self.corpus.toggle.count == 5)
        #expect(Self.corpus.collapse.count == 15)
    }

    @Test("propagate", arguments: Self.corpus.propagate)
    func propagate(_ case_: StyleEditsCorpus.PropagateCase) {
        let newLength = case_.textLength - (case_.replace.end - case_.replace.start) + case_.insert
        let result = Emphasis.propagate(
            case_.runs,
            replacing: (start: case_.replace.start, end: case_.replace.end),
            insertedLength: case_.insert,
            newLength: newLength
        )
        #expect(result == case_.expected, "\(case_.name): got \(result)")
    }

    @Test("toggle", arguments: Self.corpus.toggle)
    func toggle(_ case_: StyleEditsCorpus.ToggleCase) throws {
        let style = try styleSet(case_.style)
        #expect(
            Emphasis.isCovered(case_.runs, from: case_.start, to: case_.end, style: style)
                == case_.covered,
            "\(case_.name): coverage"
        )
        let result = Emphasis.toggle(
            case_.runs,
            from: case_.start,
            to: case_.end,
            style: style,
            textLength: case_.textLength
        )
        #expect(result == case_.expected, "\(case_.name): got \(result)")
    }

    @Test("collapse", arguments: Self.corpus.collapse)
    func collapse(_ case_: StyleEditsCorpus.CollapseCase) {
        let result = Emphasis.liveCollapse(case_.text, insertedAt: case_.at)
        switch (result, case_.expected) {
        case (nil, nil):
            break
        case let (result?, expected?):
            let removed = result.removed.map { (start: $0.start, end: $0.end) }
            let expectedRemoved = expected.removed.map { (start: $0.start, end: $0.end) }
            #expect(
                result.text == expected.text && result.run == expected.run
                    && result.caret == expected.caret
                    && removed.count == expectedRemoved.count
                    && zip(removed, expectedRemoved).allSatisfy {
                        $0.start == $1.start && $0.end == $1.end
                    },
                "\(case_.name): got \(result)"
            )
        default:
            Issue.record(
                "\(case_.name): expected \(case_.expected == nil ? "nil" : "a collapse"), got \(result == nil ? "nil" : "a collapse")"
            )
        }
    }

    private func styleSet(_ token: String) throws -> StyleSet {
        switch token {
        case "Bold": return .bold
        case "Italic": return .italic
        case "Underline": return .underline
        case "Strikeout": return .strikeout
        case "AllCaps": return .allCaps
        case "HiddenText": return .hiddenText
        default:
            throw FixtureError.unknownStyleToken(token)
        }
    }

    private enum FixtureError: Error {
        case unknownStyleToken(String)
    }
}
