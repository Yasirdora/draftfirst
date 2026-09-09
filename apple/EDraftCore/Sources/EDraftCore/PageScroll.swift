import CoreGraphics
import Foundation

/// Where the page is allowed to rest, and where it must go.
///
/// This is the arithmetic that has cost this project more bugs than any other
/// part of it, and every one of them was a sum done slightly differently in a
/// different place: a page pinned under the navigation bar because "the top"
/// was assumed to be zero; a Navigator row that did nothing because the page
/// had nowhere left to scroll; a caret typed under the keyboard because the
/// correction that would have revealed it was skipped.
///
/// None of that arithmetic is about UIKit or AppKit. It is about a piece of
/// paper longer than the window it is read through — so it lives here, is
/// tested once without a text view in sight, and is the only copy either
/// surface uses.
///
/// One convention throughout: offsets are *content* offsets, increasing
/// downward, in the same space a scroll view reports its own. The top of the
/// scrollable range is not zero when the content begins beneath a bar; that
/// single fact is what most of the bugs were.
public nonisolated enum PageScroll {

    /// The offsets a page may rest at.
    ///
    /// A page shorter than its window has exactly one legal offset: the top,
    /// which is minus the clearance the content begins below. Returning a
    /// range whose bounds are equal says that plainly, and callers that check
    /// `range.isEmpty` before scrolling are asking the right question.
    public static func range(
        contentHeight: CGFloat,
        viewportHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> ClosedRange<CGFloat> {
        let top = -topInset
        let bottom = max(contentHeight - viewportHeight + bottomInset, top)
        return top...bottom
    }

    /// Whether the page can move at all.
    public static func canScroll(_ range: ClosedRange<CGFloat>) -> Bool {
        range.upperBound > range.lowerBound
    }

    /// The offset that brings `rectTop` to rest at the top of the readable
    /// area — as near as the document allows. `airAbove` rests it that many
    /// points lower instead: a line arrived at flush against the chrome is
    /// easy to miss, and the lines above it are the context that says where
    /// you are.
    ///
    /// A target within a window's height of the end cannot reach the top,
    /// because the page stops when its last line does. The result is clamped
    /// rather than refused: going as far as possible is right, and it is the
    /// *mark*, not the scroll, that tells the reader where they landed. See
    /// `RevealMark`.
    public static func offset(
        bringingContentY rectTop: CGFloat,
        toTopOf range: ClosedRange<CGFloat>,
        airAbove air: CGFloat = 0
    ) -> CGFloat {
        clamp(rectTop + range.lowerBound - air, to: range)
    }

    /// The smallest correction that brings the caret back into view, or nil
    /// when it is already there.
    ///
    /// Holding the page still across a re-render is right until the place it
    /// is holding is hidden — under a rising keyboard, or above the bar — and
    /// then the least movement that shows it again is what a writer expects.
    /// Scrolling it to the top instead would be a jump of its own.
    public static func correction(
        revealing caret: ClosedRange<CGFloat>,
        within visible: ClosedRange<CGFloat>,
        margin: CGFloat,
        from offset: CGFloat,
        in range: ClosedRange<CGFloat>
    ) -> CGFloat? {
        let corrected: CGFloat
        if caret.lowerBound < visible.lowerBound + margin {
            corrected = offset - (visible.lowerBound + margin - caret.lowerBound)
        } else if caret.upperBound > visible.upperBound - margin {
            corrected = offset + (caret.upperBound - (visible.upperBound - margin))
        } else {
            return nil
        }
        let clamped = clamp(corrected, to: range)
        return abs(clamped - offset) > 0.5 ? clamped : nil
    }

    /// Where the page should sit after a re-render, so that the line being
    /// written does not move on screen.
    ///
    /// Rebuilding the text moves lines about; the insertion point should not
    /// wander because of it. With no caret to follow — nothing selected, or a
    /// surface nobody is typing into — the page simply stays where it was.
    public static func settled(
        caretWas: CGFloat?,
        caretIs: CGFloat?,
        preserved: CGFloat,
        offset: CGFloat,
        in range: ClosedRange<CGFloat>
    ) -> CGFloat {
        guard let caretWas, let caretIs else { return clamp(preserved, to: range) }
        return clamp(offset + (caretIs - caretWas), to: range)
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
