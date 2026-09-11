import EDraftEngine
import XCTest
import EDraftCore
@testable import EDraftMacSurface

/// The highlight a selection paints reaches into the paragraph spacing
/// beside its lines — but TextKit's range-based display invalidation covers
/// line fragments only, and the spacing between two elements belongs to no
/// fragment. Taking such a selection down left slivers of highlight in the
/// bands: two faint rules, one above and one below the text, that only a
/// scroll or a pinch cleaned off. `selectionPaintRect` is the surface's own
/// answer: what the paint actually touched.
@MainActor
final class SelectionPaintTests: XCTestCase {

    private func surface(_ source: String) -> ScriptSurface {
        let editor = EditorState(source: source)
        let surface = ScriptSurface()
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        return surface
    }

    /// The fragments TextKit would dirty for a range, in text view
    /// coordinates — the region the fix must exceed.
    private func fragmentUnion(for range: NSRange, in surface: ScriptSurface) -> CGRect {
        let layoutManager = surface.textView.layoutManager!
        let container = surface.textView.textContainer!
        let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var union = CGRect.null
        layoutManager.enumerateLineFragments(forGlyphRange: glyphs) { rect, _, _, _, _ in
            union = union.union(rect)
        }
        return union.offsetBy(
            dx: surface.textView.textContainerOrigin.x,
            dy: surface.textView.textContainerOrigin.y
        )
    }

    /// The paint rect opens out past the fragments by two lines each way —
    /// the widest spacing the page uses — so the bands a selection
    /// highlighted into are dirtied when the highlight comes down.
    func testThePaintRectCoversTheSpacingBands() throws {
        let surface = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        let range = (surface.textView.string as NSString).range(of: "Dust hangs")

        let paint = try XCTUnwrap(surface.selectionPaintRect(for: range))
        let fragments = fragmentUnion(for: range, in: surface)

        XCTAssertLessThanOrEqual(
            paint.minY, fragments.minY - ScreenplayPageLayout.lineHeight,
            "the spacing band above the line is not dirtied"
        )
        XCTAssertGreaterThanOrEqual(
            paint.maxY, fragments.maxY + ScreenplayPageLayout.lineHeight,
            "the spacing band below the line is not dirtied"
        )
        XCTAssertTrue(paint.contains(fragments), "the fragments themselves are dirtied")
    }

    /// A caret paints no highlight; a range a render cut off the end of the
    /// text still answers where its paint was.
    func testThePaintRectRefusesCaretsAndSurvivesShortening() {
        let surface = surface("INT. LAB - DAY\n\nDust hangs in the light.")
        let length = (surface.textView.string as NSString).length

        XCTAssertNil(surface.selectionPaintRect(for: NSRange(location: 5, length: 0)))
        XCTAssertNil(surface.selectionPaintRect(for: NSRange(location: length, length: 4)))
        XCTAssertNotNil(
            surface.selectionPaintRect(for: NSRange(location: length - 3, length: 10)),
            "a centred line drops its markers; the paint that was there still comes down"
        )
    }
}
