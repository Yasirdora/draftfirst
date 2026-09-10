import AppKit
import EDraftEngine
import XCTest
import EDraftCore
@testable import EDraftMacSurface

/// Runs land on the flattened script as real attributes (RFC v2.1): bold
/// and italic as Courier's own traits, underline and strikethrough as
/// decorations. Nothing re-measures — Courier's advance is fixed, so a
/// styled word stands exactly where its plain self stood.
@MainActor
final class RunAttributeTests: XCTestCase {

    private func traits(of font: NSFont) -> NSFontTraitMask {
        NSFontManager.shared.traits(of: font)
    }

    func testRunsLandAsAttributes() throws {
        let elements = [ScriptElement(
            type: .action, text: "plain bold under",
            runs: [
                StyleRun(start: 6, end: 10, styles: .bold),
                StyleRun(start: 11, end: 16, styles: .underline)
            ]
        )]
        let (text, ranges) = ScriptLayout.attributedScript(elements, measure: 500)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(text.string, "plain bold under")

        let plain = try XCTUnwrap(text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertFalse(traits(of: plain).contains(.boldFontMask))

        let bold = try XCTUnwrap(text.attribute(.font, at: 7, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(traits(of: bold).contains(.boldFontMask))
        XCTAssertFalse(traits(of: bold).contains(.italicFontMask))

        XCTAssertEqual(
            text.attribute(.underlineStyle, at: 12, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
        XCTAssertNil(text.attribute(.underlineStyle, at: 0, effectiveRange: nil))
    }

    func testCombinedStylesLandTogether() throws {
        let elements = [ScriptElement(
            type: .action, text: "both ends",
            runs: [StyleRun(start: 0, end: 4, styles: [.bold, .italic, .strikeout])]
        )]
        let (text, _) = ScriptLayout.attributedScript(elements, measure: 500)

        let font = try XCTUnwrap(text.attribute(.font, at: 2, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(traits(of: font).contains(.boldFontMask))
        XCTAssertTrue(traits(of: font).contains(.italicFontMask))
        XCTAssertEqual(
            text.attribute(.strikethroughStyle, at: 2, effectiveRange: nil) as? Int,
            NSUnderlineStyle.single.rawValue
        )
        // The span ends cleanly: the next word is plain Courier.
        let after = try XCTUnwrap(text.attribute(.font, at: 6, effectiveRange: nil) as? NSFont)
        XCTAssertFalse(traits(of: after).contains(.boldFontMask))
        XCTAssertNil(text.attribute(.strikethroughStyle, at: 6, effectiveRange: nil))
    }

    func testAnElementWithoutRunsIsUntouched() throws {
        let elements = [ScriptElement(type: .action, text: "plain throughout")]
        let (text, _) = ScriptLayout.attributedScript(elements, measure: 500)
        let font = try XCTUnwrap(text.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)
        XCTAssertFalse(traits(of: font).contains(.boldFontMask))
        XCTAssertNil(text.attribute(.underlineStyle, at: 3, effectiveRange: nil))
    }
}
