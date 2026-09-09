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
/// Google Docs, Final Draft and Pages do not clip a tall glyph, and the reason
/// is that their line grows: they are spacing lines "at least" this far apart,
/// not exactly. Set any of them to *exact* twelve-point leading and they clip
/// too.
///
/// TextKit will not even do that much — it clips glyph drawing to the line
/// fragment. Measured: a fragment pinned to a twelfth of a glyph's height
/// paints 25 rows of its ink where an unpinned fragment paints 69. So on this
/// text system, holding six lines to the inch exactly and letting a tall glyph
/// overflow are not both available, and a screenplay cannot give up the first
/// — 55 lines to the page is what pagination, the page count and the PDF all
/// rest on.
///
/// What this class does, then, is own the leading rather than buy it with
/// `maximumLineHeight`: same exact twelve points, same baseline, but the
/// paragraph spacing between elements is carried rather than squashed. Fitting
/// the glyph into that box is `ScriptLayout.fitTallGlyphs`, and the PDF applies
/// the same factor so the page and the printed page agree.
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
