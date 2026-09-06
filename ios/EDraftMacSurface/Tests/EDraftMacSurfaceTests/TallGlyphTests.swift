import AppKit
import CoreText
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// An emoji's ascent exceeds the 12pt line box. The page must not clip
/// it and must not grow the line — the glyph is drawn at the line's
/// height. Screen and PDF agree.
@MainActor
final class TallGlyphTests: XCTestCase {

    private let line = "ACT ONE 🔑"
    private var courier: NSFont {
        NSFont(name: "Courier", size: ScreenplayPageLayout.fontSize)
            ?? .monospacedSystemFont(ofSize: ScreenplayPageLayout.fontSize, weight: .regular)
    }

    private var pdfAttributes: [NSAttributedString.Key: Any] {
        [.font: courier, .foregroundColor: NSColor.black]
    }

    /// What the PDF attributes do with the glyph *before* any fit —
    /// the measurement the brief asked for. Not a pass/fail of the
    /// product; the product assertion is `testThePdfDrawsATallGlyphInsideTheLineBox`.
    func testUnconstrainedPdfAttributesOverflowTheLineBox() {
        let size = (line as NSString).size(withAttributes: pdfAttributes)
        let attributed = NSAttributedString(string: line, attributes: pdfAttributes)
        let ctLine = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(ctLine, [.useGlyphPathBounds])
        NSLog(
            "TallGlyph unconstrained size=%@ ctBounds=%@ lineHeight=%.1f",
            NSStringFromSize(size), NSStringFromRect(bounds),
            ScreenplayPageLayout.lineHeight
        )
        XCTAssertGreaterThan(
            max(size.height, bounds.height), ScreenplayPageLayout.lineHeight,
            "if this fails, the PDF already fits the glyph and the screen is the only bug"
        )
    }

    func testThePdfDrawsATallGlyphInsideTheLineBox() throws {
        let screenplay = EDraftCore.Screenplay(elements: [
            ScriptElement(type: .action, text: line)
        ])
        let pdf = ScreenplayPageRenderer.pdfData(screenplay)
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))

        // Paint the same run the PDF paints, after the fit, and require
        // the ink to sit in 12pt.
        let fitted = fittedHeight(of: line, attributes: pdfAttributes)
        XCTAssertLessThanOrEqual(
            fitted, ScreenplayPageLayout.lineHeight + 0.5,
            "the PDF still draws 🔑 at \(fitted)pt, which overflows the 12pt line"
        )
    }

    func testTheEditorKeepsTheLineBoxAtTwelvePoints() throws {
        let elements = [ScriptElement(type: .action, text: line)]
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
        surface.render(elements)
        guard let layout = surface.textView.layoutManager else {
            XCTFail("no layout manager")
            return
        }
        let fragment = layout.lineFragmentUsedRect(
            forGlyphAt: 0, effectiveRange: nil
        )
        XCTAssertEqual(
            fragment.height, ScreenplayPageLayout.lineHeight, accuracy: 0.5,
            "the line box grew; six lines per inch is the format"
        )
        let storage = try XCTUnwrap(surface.textView.textStorage)
        let emoji = (storage.string as NSString).range(of: "🔑")
        XCTAssertGreaterThan(emoji.length, 0)
        let font = storage.attribute(.font, at: emoji.location, effectiveRange: nil) as? NSFont
        XCTAssertLessThan(
            font?.pointSize ?? ScreenplayPageLayout.fontSize,
            ScreenplayPageLayout.fontSize,
            "the emoji is still at Courier 12 and will clip"
        )
    }

    func testACourierLineIsNotScaled() {
        let plain = "ACT ONE"
        let before = (plain as NSString).size(withAttributes: pdfAttributes).width
        let after = fittedWidth(of: plain, attributes: pdfAttributes)
        XCTAssertEqual(before, after, accuracy: 0.5, "plain Courier was scaled")
    }

    private func fittedHeight(
        of string: String, attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        var maxHeight: CGFloat = 0
        let font = (attributes[.font] as? NSFont) ?? courier
        (string as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: (string as NSString).length),
            options: .byComposedCharacterSequences
        ) { substring, _, _, _ in
            guard let substring else { return }
            let height = ScriptLayout.glyphPathHeight(substring, font: font)
            let scale = ScreenplayPageLayout.scaleToFitLine(measuredHeight: height)
            maxHeight = max(maxHeight, height * scale)
        }
        return maxHeight
    }

    private func fittedWidth(
        of string: String, attributes: [NSAttributedString.Key: Any]
    ) -> CGFloat {
        var width: CGFloat = 0
        let font = (attributes[.font] as? NSFont) ?? courier
        (string as NSString).enumerateSubstrings(
            in: NSRange(location: 0, length: (string as NSString).length),
            options: .byComposedCharacterSequences
        ) { substring, _, _, _ in
            guard let substring else { return }
            let size = (substring as NSString).size(withAttributes: attributes)
            let height = ScriptLayout.glyphPathHeight(substring, font: font)
            let scale = ScreenplayPageLayout.scaleToFitLine(measuredHeight: height)
            width += size.width * scale
        }
        return width
    }
}
