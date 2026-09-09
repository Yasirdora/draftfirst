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

    /// The PDF draws the glyph at its own size and lets it overflow, which is
    /// what the screen does and what every other editor does. It is emphatically
    /// not scaled: the earlier version of this test measured a helper in this
    /// file that did its own scaling, so it asserted its own arithmetic and
    /// could not fail for the right reason.
    func testThePdfDrawsATallGlyphAtItsOwnSize() throws {
        let screenplay = EDraftCore.Screenplay(elements: [
            ScriptElement(type: .action, text: line)
        ])
        let pdf = ScreenplayPageRenderer.pdfData(screenplay)
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))

        let font = try XCTUnwrap(
            ScreenplayPageRenderer.textAttributesForTests[.font] as? NSFont
        )
        XCTAssertEqual(
            font.pointSize, ScreenplayPageLayout.fontSize, accuracy: 0.01,
            "the PDF is drawing at something other than Courier 12"
        )
    }

    /// Screen and PDF must agree, which is the whole point — the same script
    /// exported from a desk and read on a phone should be one document.
    ///
    /// They agree by both asking `scaleToFitLine`, not by carrying the same
    /// number: the editor bakes the factor into the glyph's font attribute,
    /// while the PDF applies it to the drawing context at paint time. So the
    /// thing to assert is that the screen's baked size is exactly what the
    /// shared rule says, which is the same answer the renderer acts on.
    func testTheScreenScalesTheGlyphByTheSharedRule() throws {
        let elements = [ScriptElement(type: .action, text: line)]
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
        surface.render(elements)

        let storage = try XCTUnwrap(surface.textView.textStorage)
        let emoji = (storage.string as NSString).range(of: "🔑")
        let onScreen = try XCTUnwrap(
            storage.attribute(.font, at: emoji.location, effectiveRange: nil) as? NSFont
        )

        let ink = ScriptLayout.glyphPathHeight("🔑", font: courier)
        let expected = ScreenplayPageLayout.fontSize
            * ScreenplayPageLayout.scaleToFitLine(measuredHeight: ink)

        XCTAssertEqual(
            onScreen.pointSize, expected, accuracy: 0.01,
            "the page is not using the rule the printed page uses"
        )
        XCTAssertLessThan(expected, ScreenplayPageLayout.fontSize)
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
        // And the glyph is brought into that box rather than left to overflow
        // it, because TextKit clips glyph drawing to the line fragment.
        // Measured: pinning a fragment to a twelfth of the glyph's height
        // paints 25 rows of its ink where an unpinned fragment paints 69. So
        // "let it overflow", which is what Google Docs and Final Draft do, is
        // not available here while six lines to the inch is held exactly.
        let storage = try XCTUnwrap(surface.textView.textStorage)
        let emoji = (storage.string as NSString).range(of: "🔑")
        XCTAssertGreaterThan(emoji.length, 0)
        let font = storage.attribute(.font, at: emoji.location, effectiveRange: nil) as? NSFont
        XCTAssertLessThan(
            font?.pointSize ?? ScreenplayPageLayout.fontSize,
            ScreenplayPageLayout.fontSize,
            "the emoji is at Courier 12 and the line fragment will clip its top"
        )
    }

    /// Every line in the document is one line tall, whatever it contains.
    /// This is the property pagination rests on, and the one `maximumLineHeight`
    /// used to buy at the cost of cropping.
    func testEveryLineIsOneLineTallIncludingTheOneWithTheEmoji() throws {
        let elements = [
            ScriptElement(type: .action, text: line),
            ScriptElement(type: .action, text: "A plain line of action."),
            ScriptElement(type: .action, text: line)
        ]
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        surface.render(elements)
        let layout = try XCTUnwrap(surface.textView.layoutManager)

        var index = 0
        var checked = 0
        while index < layout.numberOfGlyphs {
            var effective = NSRange(location: 0, length: 0)
            // The *used* rect: the line of type itself. The fragment rect is
            // that plus any paragraph spacing below, which is a blank line
            // between elements and must survive.
            let rect = layout.lineFragmentUsedRect(forGlyphAt: index, effectiveRange: &effective)
            XCTAssertEqual(
                rect.height, ScreenplayPageLayout.lineHeight, accuracy: 0.01,
                "a line of type was \(rect.height) points, not one line"
            )
            checked += 1
            index = NSMaxRange(effective)
        }
        XCTAssertGreaterThan(checked, 2, "expected several lines to check")
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

/// Fixing the leading must not cost the blank line between elements.
///
/// A screenplay's shape is as much the space between things as the type: a
/// heading, a blank line, then action. TextKit carries that spacing in the
/// line fragment rect, the same rectangle the leading fix pins — so pinning
/// the wrong one squashes the page flat and every element runs together.
@MainActor
final class ParagraphSpacingTests: XCTestCase {

    func testAHeadingIsStillSeparatedFromItsAction() throws {
        let elements = [
            ScriptElement(type: .scene, text: "INT. LIVING ROOM - DAY"),
            ScriptElement(type: .action, text: "She waits by the window.")
        ]
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        surface.render(elements)
        let layout = try XCTUnwrap(surface.textView.layoutManager)

        let heading = layout.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let headingType = layout.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)

        XCTAssertEqual(
            headingType.height, ScreenplayPageLayout.lineHeight, accuracy: 0.01,
            "the line of type is one line"
        )
        XCTAssertGreaterThan(
            heading.height, headingType.height + 1,
            "the blank line after a scene heading was squashed out"
        )
    }
}
