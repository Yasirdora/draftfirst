import Foundation
import Testing
@testable import EDraftEngine

/// A stopwatch inside `paginate` — not a suite citizen: it prints timings
/// and asserts nothing, and it is skipped unless asked for directly:
/// `EDRAFT_BENCHMARKS=1 swift test --filter PaginateBenchmark`.
///
/// The question it answers: a feature-length script paginates in ~1.2s.
/// Which phase is that — the per-element word wrap, or the page assembly
/// with its keep-together rules? The wrap is timed by calling the exact
/// function `buildBlocks` uses, element for element, so the split is
/// honest rather than approximate.
@Suite("Paginate benchmark", .enabled(if: ProcessInfo.processInfo.environment["EDRAFT_BENCHMARKS"] == "1"))
struct PaginateBenchmarkTests {

    /// The same screenplay-shaped document the surface benchmark uses:
    /// Courier's measure, a real element mix, ~910 pages of it.
    static func syntheticScreenplay(pages: Int) -> Screenplay {
        var elements: [ScreenplayElement] = []
        let target = pages * 18
        var index = 0
        while elements.count < target {
            elements.append(ScreenplayElement(
                type: .scene, text: "INT. LOCATION \(index) - DAY"
            ))
            elements.append(ScreenplayElement(
                type: .action,
                text: "The room is quiet. A long action line that runs past sixty characters so it wraps onto a second line of the page."
            ))
            elements.append(ScreenplayElement(type: .character, text: "CHARACTER \(index % 40)"))
            elements.append(ScreenplayElement(
                type: .dialogue,
                text: "A line of dialogue, measured and calm, that also runs long enough to wrap across the measure of the page."
            ))
            elements.append(ScreenplayElement(
                type: .dialogue, text: "A shorter reply."
            ))
            elements.append(ScreenplayElement(
                type: .action, text: "They wait. Nothing moves."
            ))
            index += 1
        }
        return Screenplay(elements: elements)
    }

    static func now() -> CFAbsoluteTime { CFAbsoluteTimeGetCurrent() }

    /// `buildBlocks`' wrap dispatch, replicated call for call so the wrap
    /// phase is timed exactly as `paginate` performs it.
    static func wrapPhase(_ script: Screenplay) -> Int {
        var lineCount = 0
        for element in script.elements {
            guard element.type != .pagebreak, element.type.isPrinting else { continue }
            let geo = Paginator.geometry[element.type] ?? Paginator.geometry[.action]!
            let text = element.type == .character && element.dual == true
                ? element.text + " ^" : element.text
            let width = element.type == .transition || element.type == .centered
                ? Paginator.pageWidthChars : (element.type == .character ? Paginator.geometry[.character]!.width : geo.width)
            lineCount += Paginator.wrapText(text, width: width).count
        }
        return lineCount
    }

    @Test("wrap phase versus page assembly")
    func phaseSplit() throws {
        let script = Self.syntheticScreenplay(pages: 910)
        print("BENCH elements: \(script.elements.count)")

        // Warm both paths, then time three runs each.
        _ = Self.wrapPhase(script)
        _ = try Paginator.paginate(script)

        var wrapBest = Double.greatestFiniteMagnitude
        var wrappedLines = 0
        for _ in 0..<3 {
            let start = Self.now()
            wrappedLines = Self.wrapPhase(script)
            wrapBest = min(wrapBest, Self.now() - start)
        }
        print("BENCH wrap phase (all elements): \(String(format: "%.3f", wrapBest))s, lines \(wrappedLines)")

        var buildBest = Double.greatestFiniteMagnitude
        var itemCount = 0
        for _ in 0..<3 {
            let start = Self.now()
            let items = Paginator.buildBlocks(script)
            buildBest = min(buildBest, Self.now() - start)
            itemCount = items.count
        }
        print("BENCH buildBlocks (wrap + blocks): \(String(format: "%.3f", buildBest))s, items \(itemCount)")

        var paginateBest = Double.greatestFiniteMagnitude
        var pageCount = 0
        var pages: [ScriptPage] = []
        for _ in 0..<3 {
            let start = Self.now()
            pages = try Paginator.paginate(script)
            paginateBest = min(paginateBest, Self.now() - start)
            pageCount = pages.count
        }
        print("BENCH paginate total: \(String(format: "%.3f", paginateBest))s, pages \(pageCount)")

        var markBest = Double.greatestFiniteMagnitude
        for _ in 0..<3 {
            var copy = pages
            let start = Self.now()
            Paginator.markSceneContinues(script, &copy)
            markBest = min(markBest, Self.now() - start)
        }
        print("BENCH markSceneContinues: \(String(format: "%.3f", markBest))s")
        print("BENCH main loop (total - build - mark): "
            + String(format: "%.3f", paginateBest - buildBest - markBest) + "s")
    }

    @Test("the per-flow-block cue stripping")
    func cueStripping() {
        let script = Self.syntheticScreenplay(pages: 910)
        let cues = script.elements.filter { $0.type == .character }.map(\.text)
        print("BENCH flow cues: \(cues.count)")

        var stripBest = Double.greatestFiniteMagnitude
        for _ in 0..<3 {
            let start = Self.now()
            var total = 0
            for cue in cues {
                total += SmartType.stripCueExtensions(cue)
                    .trimmingCharacters(in: .whitespacesAndNewlines).count
            }
            stripBest = min(stripBest, Self.now() - start)
            if total < 0 { print("impossible") }
        }
        print("BENCH stripCueExtensions over all cues: \(String(format: "%.3f", stripBest))s")
    }
}
