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
///
/// A document *wider* than the window is the writer's to pan — except while a
/// pinch or its landing drift owns the size (`centresHorizontally`), when the
/// horizontal anchor is the page's own midline rather than the cursor's.
final class CentringClipView: NSClipView {

    /// While a pinch — or the drift that lands it — owns the magnification.
    ///
    /// The surface knows when, and the clip view cannot infer it: AppKit
    /// applies one gesture frame in two constrained steps, a size set and an
    /// origin set, so a proposal's shape never says what it belongs to.
    var centresHorizontally = false

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView else { return rect }

        // A pinch anchors on the point under the cursor, and the cursor is
        // rarely on the page's midline — so the page slid sideways as the
        // fingers wandered. While a gesture or its landing drift owns the
        // size, the horizontal anchor is the page's own centre instead, and
        // every proposal is centred. Vertical stays with the gesture: the
        // line under the fingers stays under them. Between gestures x is the
        // writer's — a pan is how the far edge of a deep-zoomed page is read.
        if centresHorizontally || rect.width > document.frame.width {
            rect.origin.x = (document.frame.width - rect.width) / 2
        }
        if rect.height > document.frame.height {
            rect.origin.y = (document.frame.height - rect.height) / 2
        }
        return rect
    }
}
