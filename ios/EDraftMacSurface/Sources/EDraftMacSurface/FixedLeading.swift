import AppKit
import EDraftCore

/// Six lines to the inch, without cropping anything that is taller than a line.
///
/// A screenplay's leading is exact: 55 lines to a page is what pagination, the
/// page count and the PDF all rest on, so the baseline-to-baseline distance has
/// to be 12 points and cannot grow for a tall glyph.
///
/// The obvious way to say that is `maximumLineHeight`, and it is the wrong one.
/// It does not merely space the line — it compresses the fragment, cutting the
/// ascent, so an emoji comes out with its top sliced off. Scaling the glyph
/// down to fit was treating that symptom, and it showed: a shrunken emoji whose
/// ink still overran its advance, with the caret drawn through it.
///
/// Every other editor — Google Docs, Final Draft, Pages — treats line height as
/// an *advance*, not a clipping box. A glyph taller than the line overflows
/// into the space above it and nothing crops it, which is why their emoji look
/// right. This says the same thing to TextKit: the fragment is exactly one line
/// tall, the baseline sits where Courier expects it, and drawing is left alone.
final class FixedLeading: NSObject, NSLayoutManagerDelegate {

    private let lineHeight = ScreenplayPageLayout.lineHeight
    /// Where the baseline sits inside the line box. Courier's own ascent and
    /// descent very nearly fill 12 points; the remainder is split so the type
    /// sits where it did before, and no line moves.
    private let baseline: CGFloat = {
        let font = ScriptLayout.font(for: .action)
        let inked = font.ascender - font.descender
        let slack = max(0, ScreenplayPageLayout.lineHeight - inked)
        return (slack / 2) + font.ascender
    }()

    func layoutManager(
        _ layoutManager: NSLayoutManager,
        shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
        lineFragmentUsedRect: UnsafeMutablePointer<NSRect>,
        baselineOffset: UnsafeMutablePointer<CGFloat>,
        in textContainer: NSTextContainer,
        forGlyphRange glyphRange: NSRange
    ) -> Bool {
        // The *used* rect is the line of type; the fragment rect is that plus
        // whatever spacing follows the paragraph. Pin the first and carry the
        // second, or the blank line between a heading and its action is
        // squashed to nothing along with the leading.
        let spacingBelow = max(
            0, lineFragmentRect.pointee.height - lineFragmentUsedRect.pointee.height
        )
        lineFragmentUsedRect.pointee.size.height = lineHeight
        lineFragmentRect.pointee.size.height = lineHeight + spacingBelow
        baselineOffset.pointee = baseline
        return true
    }
}
