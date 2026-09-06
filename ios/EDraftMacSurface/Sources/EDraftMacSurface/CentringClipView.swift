import AppKit

/// Keeps the page in the middle of the window without anyone re-measuring it.
///
/// The canvas used to be grown to the size of the viewport so the page could be
/// centred inside it. That made the canvas depend on the magnification, so a
/// pinch needed a re-measure to stay centred — and re-measuring mid-gesture
/// fights AppKit's own rubber-banding, while re-measuring after it lands the
/// page in one visible jump. Neither is smooth, and both were tried.
///
/// A clip view is allowed to decide where its document sits when the document
/// is the smaller of the two. Centring it here means the canvas can be exactly
/// as large as the pages on it, at any magnification, and the page stays in the
/// middle continuously — during the pinch, at the end of it, and on a resize —
/// with nothing scheduled and nothing to jump.
final class CentringClipView: NSClipView {

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }

        if rect.width > document.frame.width {
            rect.origin.x = (document.frame.width - rect.width) / 2
        }
        if rect.height > document.frame.height {
            rect.origin.y = (document.frame.height - rect.height) / 2
        }
        return rect
    }
}
