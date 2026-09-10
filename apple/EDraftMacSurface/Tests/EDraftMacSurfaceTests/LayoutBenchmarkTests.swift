import AppKit
import XCTest
@testable import EDraftCore
@testable import EDraftMacSurface

/// A stopwatch on the first draw of a feature-length script — not a test
/// suite citizen: it prints timings and asserts nothing, and it is skipped
/// unless asked for directly: `EDRAFT_BENCHMARKS=1 swift test --filter LayoutBenchmark`.
///
/// The question it answers: a 910-page draft opens with ~9.5s inside
/// TextKit. Which call is that — building the string, the layout itself,
/// the delegate, or the whole-document bounding box?
@MainActor
final class LayoutBenchmarkTests: XCTestCase {

    /// A screenplay-shaped document of roughly `pages` pages: Courier's
    /// measure, real element mix, realistic line counts.
    private func syntheticScript(pages: Int) -> [ScriptElement] {
        // 55 lines to a page; the mix below averages ~3 lines per element
        // once spacing is counted, so pages * 18 elements lands near it.
        var elements: [ScriptElement] = []
        let target = pages * 18
        var index = 0
        while elements.count < target {
            elements.append(ScriptElement(
                type: .scene, text: "INT. LOCATION \(index) - DAY"
            ))
            elements.append(ScriptElement(
                type: .action,
                text: "The room is quiet. A long action line that runs past sixty characters so it wraps onto a second line of the page."
            ))
            elements.append(ScriptElement(type: .character, text: "CHARACTER \(index % 40)"))
            elements.append(ScriptElement(
                type: .dialogue,
                text: "A line of dialogue, measured and calm, that also runs long enough to wrap across the measure of the page."
            ))
            elements.append(ScriptElement(
                type: .dialogue, text: "A shorter reply."
            ))
            elements.append(ScriptElement(
                type: .action, text: "They wait. Nothing moves."
            ))
            index += 1
        }
        return elements
    }

    private func timed<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
        let start = CACurrentMediaTime()
        let result = try body()
        let elapsed = CACurrentMediaTime() - start
        print("BENCH \(label): \(String(format: "%.3f", elapsed))s")
        return result
    }

    private func makeStack(
        text: NSAttributedString, delegate: NSLayoutManagerDelegate?, nonContiguous: Bool
    ) -> (NSTextStorage, NSLayoutManager, NSTextContainer) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(
            size: CGSize(width: ScriptLayout.pageMeasure, height: .greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        layout.delegate = delegate
        layout.allowsNonContiguousLayout = nonContiguous
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)
        return (storage, layout, container)
    }

    func testBenchmarkFirstDraw() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["EDRAFT_BENCHMARKS"] == "1",
                          "a stopwatch, not a gate: run with EDRAFT_BENCHMARKS=1")
        let elements = syntheticScript(pages: 910)
        print("BENCH elements: \(elements.count)")

        let pages = timed("ScreenplayExporter.paginate") {
            ScreenplayExporter.paginate(Screenplay(elements: elements))
        }
        if let pages {
            timed("pageStartLocations") {
                _ = ScreenplayPageLayout.pageStartLocations(elements: elements, pages: pages)
            }
            print("BENCH paginated pages: \(pages.count)")
        }

        let script = timed("attributedScript") {
            ScriptLayout.attributedScript(elements, measure: ScriptLayout.pageMeasure)
        }
        print("BENCH characters: \(script.text.length)")

        // As shipped: FixedLeading delegate, contiguous layout.
        do {
            let (storage, layout, container) = makeStack(
                text: script.text, delegate: FixedLeading(), nonContiguous: false
            )
            timed("setAttributedString (contiguous, delegate)") {
                storage.setAttributedString(script.text)
            }
            timed("ensureLayout whole container (contiguous, delegate)") {
                layout.ensureLayout(for: container)
            }
            timed("usedRect") { _ = layout.usedRect(for: container) }
            timed("boundingRect all glyphs") {
                _ = layout.boundingRect(
                    forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs),
                    in: container
                )
            }
            print("BENCH glyphs: \(layout.numberOfGlyphs)")
        }

        // No delegate.
        do {
            let (storage, layout, container) = makeStack(
                text: script.text, delegate: nil, nonContiguous: false
            )
            storage.setAttributedString(script.text)
            timed("ensureLayout whole container (contiguous, NO delegate)") {
                layout.ensureLayout(for: container)
            }
        }

        // Non-contiguous, delegate on — does lazy layout change the bill?
        do {
            let (storage, layout, container) = makeStack(
                text: script.text, delegate: FixedLeading(), nonContiguous: true
            )
            storage.setAttributedString(script.text)
            timed("layout viewport only (non-contiguous, delegate)") {
                layout.ensureLayout(forGlyphRange: NSRange(location: 0, length: 2_000))
            }
            timed("ensureLayout whole container (non-contiguous, delegate)") {
                layout.ensureLayout(for: container)
            }
        }

        // Per-page-start rectangle lookups at full length, as applyPageBreaks
        // does: 910 of them, each through ScriptLayout.boundingRect.
        do {
            let textView = NSTextView(
                frame: NSRect(x: 0, y: 0, width: ScriptLayout.pageMeasure, height: 100)
            )
            textView.textContainer?.lineFragmentPadding = 0
            textView.layoutManager?.delegate = FixedLeading()
            textView.textStorage?.setAttributedString(script.text)
            timed("910x ScriptLayout.boundingRect (page starts)") {
                let strideLength = max(1, script.text.length / 910)
                var location = 0
                while location < script.text.length {
                    _ = ScriptLayout.boundingRect(
                        of: NSRange(location: location, length: 1), in: textView
                    )
                    location += strideLength
                }
            }
        }
    }

    /// Two property assignments that `layOut` makes unconditionally. If
    /// either invalidates the container even when nothing changed, every
    /// `layOut` pays for a whole new layout of the script.
    func testInvalidationCost() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["EDRAFT_BENCHMARKS"] == "1",
                          "a stopwatch, not a gate: run with EDRAFT_BENCHMARKS=1")
        let elements = syntheticScript(pages: 910)
        let script = ScriptLayout.attributedScript(elements, measure: ScriptLayout.pageMeasure)
        let (storage, layout, container) = makeStack(
            text: script.text, delegate: FixedLeading(), nonContiguous: false
        )
        storage.setAttributedString(script.text)
        layout.ensureLayout(for: container)

        timed("ensureLayout again, nothing touched") { layout.ensureLayout(for: container) }

        let sameSize = container.size
        timed("assign SAME container.size, re-lay") {
            container.size = sameSize
            layout.ensureLayout(for: container)
        }

        layout.ensureLayout(for: container)
        timed("assign EMPTY exclusionPaths when already empty, re-lay") {
            container.exclusionPaths = []
            layout.ensureLayout(for: container)
        }
    }

    /// The open flow's pageStartY walk, step for step: after a full layout,
    /// nine hundred range-scoped probes — then a final whole-container
    /// ensure, to see whether the probes poisoned it.
    func testRangeProbesDoNotPoisonTheContainer() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["EDRAFT_BENCHMARKS"] == "1",
                          "a stopwatch, not a gate: run with EDRAFT_BENCHMARKS=1")
        let elements = syntheticScript(pages: 910)
        let script = ScriptLayout.attributedScript(elements, measure: ScriptLayout.pageMeasure)
        let textView = NSTextView(
            frame: NSRect(x: 0, y: 0, width: ScriptLayout.pageMeasure, height: 100)
        )
        textView.textContainer?.lineFragmentPadding = 0
        textView.layoutManager?.delegate = FixedLeading()
        textView.textContainerInset = NSSize(width: 0, height: 12)
        textView.textStorage?.setAttributedString(script.text)
        guard let layout = textView.layoutManager, let container = textView.textContainer
        else { return XCTFail("no stack") }

        timed("full layout") { layout.ensureLayout(for: container) }
        timed("910 range-scoped probes") {
            let strideLength = max(1, script.text.length / 910)
            var location = 0
            while location < script.text.length {
                _ = ScriptLayout.boundingRect(
                    of: NSRange(location: location, length: 1), in: textView
                )
                location += strideLength
            }
        }
        timed("whole-container ensure after the probes") {
            layout.ensureLayout(for: container)
        }
    }

    /// Layout with page-gap exclusions, two ways: hundreds of separate
    /// bezier paths versus one path holding all the gaps. AppKit checks
    /// each path against each candidate fragment; whether a combined path
    /// collapses that decides how the sheets get their gaps.
    func testExclusionPathCost() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["EDRAFT_BENCHMARKS"] == "1",
                          "a stopwatch, not a gate: run with EDRAFT_BENCHMARKS=1")
        let elements = syntheticScript(pages: 910)
        let script = ScriptLayout.attributedScript(elements, measure: ScriptLayout.pageMeasure)

        func stack() -> (NSTextStorage, NSLayoutManager, NSTextContainer) {
            let storage = NSTextStorage()
            let layout = NSLayoutManager()
            let container = NSTextContainer(
                size: CGSize(width: ScriptLayout.pageMeasure, height: .greatestFiniteMagnitude)
            )
            container.lineFragmentPadding = 0
            layout.delegate = FixedLeading()
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            storage.setAttributedString(script.text)
            return (storage, layout, container)
        }

        // One full-width gap every text block, like the 780-page breaks.
        let line = ScreenplayPageLayout.lineHeight
        let pitch = PageFormat.letter.pageRect.height + 24
        var rects: [CGRect] = []
        var y = PageFormat.letter.textTop + 660
        while y < 780 * pitch { rects.append(CGRect(x: 0, y: y, width: 432, height: 132)); y += pitch }
        print("BENCH exclusion gaps: \(rects.count)")

        do {
            let (storage, layout, container) = stack(); _ = storage
            timed("layout, no exclusions") { layout.ensureLayout(for: container) }
        }
        do {
            let (storage, layout, container) = stack(); _ = storage
            container.exclusionPaths = rects.map(NSBezierPath.init(rect:))
            timed("layout, \(rects.count) separate exclusion paths") {
                layout.ensureLayout(for: container)
            }
        }
        do {
            let (storage, layout, container) = stack(); _ = storage
            let combined = NSBezierPath()
            for rect in rects { combined.appendRect(rect) }
            container.exclusionPaths = [combined]
            timed("layout, one combined exclusion path") {
                layout.ensureLayout(for: container)
            }
        }
        _ = line
    }

    /// The whole open flow through the real ScriptSurface, with a probe on
    /// `ensureLayout(for:)` counting how many whole-document layouts happen
    /// before the first pixel could be drawn — and where they come from.
    func testOpenFlowLayoutCount() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["EDRAFT_BENCHMARKS"] == "1",
                          "a stopwatch, not a gate: run with EDRAFT_BENCHMARKS=1")
        let elements = syntheticScript(pages: 910)
        LayoutProbe.install()
        for mode: PageLayoutMode in [.continuous, .pages] {
            LayoutProbe.reset()
            _ = timed("open flow (\(mode))") {
                let (editor, surface) = ScriptSurfaceHarness.bound(elements)
                surface.setLayoutMode(mode)
                surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1209, height: 700)
                surface.scrollView.layoutSubtreeIfNeeded()
                surface.remeasure(to: 1209, elements: elements)
                surface.renderIfNeeded(editor)
            }
            print("BENCH \(mode): full-container layouts = \(LayoutProbe.calls), "
                + "real (>5ms) = \(LayoutProbe.real), "
                + "cumulative \(String(format: "%.3f", LayoutProbe.time))s")
            for entry in LayoutProbe.log { print("BENCH   \(entry)") }
            for (index, stack) in LayoutProbe.stacks.enumerated() {
                print("BENCH slow #\(index): \(stack.prefix(3).joined(separator: " ← "))")
            }
        }
    }
}

/// The probe: swap `ensureLayout(for:)` for a counting, timing wrapper that
/// keeps the app-side frames of the first few *real* layouts.
private final class LayoutProbe {
    nonisolated(unsafe) static var calls = 0
    nonisolated(unsafe) static var real = 0
    nonisolated(unsafe) static var time: CFAbsoluteTime = 0
    nonisolated(unsafe) static var stacks: [[String]] = []
    nonisolated(unsafe) static var log: [String] = []
    nonisolated(unsafe) private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let original = class_getInstanceMethod(
            NSLayoutManager.self, #selector(NSLayoutManager.ensureLayout(for:))
        )!
        let probe = class_getInstanceMethod(
            NSLayoutManager.self, #selector(NSLayoutManager.probe_ensureLayout(for:))
        )!
        method_exchangeImplementations(original, probe)
    }

    static func reset() { calls = 0; real = 0; time = 0; stacks = []; log = [] }
}

extension NSLayoutManager {
    @objc dynamic func probe_ensureLayout(for container: NSTextContainer) {
        let start = CACurrentMediaTime()
        // After the exchange this name resolves to the original implementation.
        probe_ensureLayout(for: container)
        let elapsed = CACurrentMediaTime() - start
        LayoutProbe.time += elapsed
        LayoutProbe.calls += 1
        // The app's own frame, a few below the probe and TextKit.
        let caller = Thread.callStackSymbols.dropFirst(5).first(where: {
            $0.contains("EDraftMacSurface")
        }) ?? "?"
        LayoutProbe.log.append(
            "#\(LayoutProbe.calls) \(String(format: "%.3f", elapsed))s ← \(caller)")
        if elapsed > 0.005 {
            LayoutProbe.real += 1
            // The app's own frames, below the probe and TextKit.
            let frames = Thread.callStackSymbols.dropFirst(2).prefix(30)
                .filter { $0.contains("EDraftMacSurface") }
                .map { $0.components(separatedBy: " ").dropFirst(3).joined(separator: " ") }
            LayoutProbe.stacks.append(Array(frames))
        }
    }
}
