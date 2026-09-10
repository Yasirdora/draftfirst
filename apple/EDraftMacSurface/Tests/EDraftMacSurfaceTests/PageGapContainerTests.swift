import AppKit
import XCTest
@testable import EDraftCore
@testable import EDraftMacSurface

/// `PageGapContainer` must put every line exactly where AppKit's exclusion
/// paths put it — the sheets, the marks and the caret are all placed from
/// those positions, so "faster" is only shippable if it is the same.
@MainActor
final class PageGapContainerTests: XCTestCase {

    /// A document with page gaps, laid out both ways. Every line fragment
    /// must agree to within a hairline.
    func testTheBandsLandWhereExclusionPathsLand() {
        var elements: [ScriptElement] = []
        for beat in 1...400 {
            elements.append(ScriptElement(type: .scene, text: "INT. ROOM \(beat) - DAY"))
            elements.append(ScriptElement(
                type: .action,
                text: "Action for beat \(beat), long enough to wrap across the measure of the page twice over and then some."
            ))
            elements.append(ScriptElement(type: .character, text: "WALKER"))
            elements.append(ScriptElement(
                type: .dialogue, text: "A line of dialogue for beat \(beat), also long enough to wrap."
            ))
        }
        let script = ScriptLayout.attributedScript(elements, measure: ScriptLayout.pageMeasure)

        // Gaps like applyPageBreaks places them: full width, one per sheet.
        let pitch = PageFormat.letter.pageRect.height + PageCanvasView.pageGap
        var bands: [CGRect] = []
        var y = PageFormat.letter.textTop + ScreenplayPageLayout.textBlockHeight(.letter)
        while y < 40 * pitch {
            bands.append(CGRect(x: 0, y: y, width: ScriptLayout.pageMeasure, height: 132))
            y += pitch
        }

        func fragmentTops(withExclusions: Bool) -> [CGFloat] {
            let storage = NSTextStorage()
            let layout = NSLayoutManager()
            let container: NSTextContainer
            if withExclusions {
                container = NSTextContainer(
                    size: CGSize(width: ScriptLayout.pageMeasure, height: .greatestFiniteMagnitude)
                )
                container.exclusionPaths = bands.map(NSBezierPath.init(rect:))
            } else {
                let gaps = PageGapContainer(
                    size: CGSize(width: ScriptLayout.pageMeasure, height: .greatestFiniteMagnitude)
                )
                gaps.gapBands = bands
                container = gaps
            }
            container.lineFragmentPadding = 0
            layout.delegate = FixedLeading()
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            storage.setAttributedString(script.text)
            layout.ensureLayout(for: container)

            var tops: [CGFloat] = []
            layout.enumerateLineFragments(
                forGlyphRange: NSRange(location: 0, length: layout.numberOfGlyphs)
            ) { rect, _, _, _, _ in tops.append(rect.minY) }
            tops.append(layout.extraLineFragmentRect.minY)
            return tops
        }

        let reference = fragmentTops(withExclusions: true)
        let measured = fragmentTops(withExclusions: false)

        XCTAssertEqual(measured.count, reference.count,
                       "the two layouts produced different line counts")
        for (index, (a, b)) in zip(measured, reference).enumerated() {
            XCTAssertEqual(a, b, accuracy: 0.01, "line \(index) landed somewhere else")
        }
    }
}
