import AppKit
import EDraftCore

/// A text container that knows the desk between the sheets.
///
/// The gap between one page and the next is a full-width band the type must
/// skip. AppKit's mechanism for that is exclusion paths, and its price is the
/// problem: every candidate line is checked against every path, so a
/// feature's eight hundred gaps measured 4.8 seconds a layout where the same
/// draft laid out bare takes 0.3 — and combining the gaps into one path is
/// worse (12.6s), because the bounding box no longer rejects anything. The
/// bands here are sorted and full-width, so the same answer is a binary
/// search, and the layout costs what the bare layout costs.
///
/// The movement rule is AppKit's, verified against exclusion paths fragment
/// for fragment: a line that meets a band is carried to the band's far edge.
final class PageGapContainer: NSTextContainer {

    /// The bands the type skips, top to bottom, never overlapping, each the
    /// full width of the container. Assigning re-lays the container, as
    /// assigning exclusion paths would — and assigning what is already there
    /// does not, which is the whole reason the guard exists: an unchanged
    /// assignment used to buy a full layout with one line.
    ///
    /// Lock-protected rather than `nonisolated(unsafe)`: the typesetter reads
    /// the bands from inside `lineFragmentRect` without actor isolation, and
    /// a future layout off the main thread must meet a lock, not a data race.
    /// The read copies the array out under the lock; the cost is tens of
    /// nanoseconds a line, nothing next to the layout it answers.
    nonisolated var gapBands: [CGRect] {
        get { bandLock.withLock { bandStorage } }
        set {
            let changed = bandLock.withLock {
                guard newValue != bandStorage else { return false }
                bandStorage = newValue
                return true
            }
            guard changed else { return }
            // The same invalidation assigning exclusionPaths performs.
            layoutManager?.textContainerChangedGeometry(self)
        }
    }
    nonisolated private var bandStorage: [CGRect] = []
    nonisolated private let bandLock = NSLock()

    nonisolated override init(size: CGSize) {
        super.init(size: size)
    }

    nonisolated required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    nonisolated override func lineFragmentRect(
        forProposedRect proposedRect: CGRect,
        at characterIndex: Int,
        writingDirection baseWritingDirection: NSWritingDirection,
        remaining remainingRect: UnsafeMutablePointer<CGRect>?
    ) -> CGRect {
        // The container keeps no exclusion paths, so the superclass answer is
        // the proposed rect clamped to the page's measure, and nothing more.
        var rect = super.lineFragmentRect(
            forProposedRect: proposedRect,
            at: characterIndex,
            writingDirection: baseWritingDirection,
            remaining: remainingRect
        )
        // One lock per line: the search runs against this copy.
        let bands = gapBands
        while let band = bandMeeting(rect, in: bands) {
            rect.origin.y = band.maxY
        }
        return rect
    }

    /// The band `rect` lands in, if any. Binary search: the bands are sorted
    /// by their top edge and never overlap.
    nonisolated private func bandMeeting(_ rect: CGRect, in bands: [CGRect]) -> CGRect? {
        var low = 0
        var high = bands.count
        while low < high {
            let mid = (low + high) / 2
            let band = bands[mid]
            if band.maxY <= rect.minY {
                low = mid + 1
            } else if band.minY >= rect.maxY {
                high = mid
            } else {
                return band
            }
        }
        return nil
    }
}
