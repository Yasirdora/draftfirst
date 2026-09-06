import CoreGraphics

/// How large the page is drawn, and why it is not simply "actual size".
///
/// A screenplay's measurements are absolute: 612 × 792 points is 8½ × 11
/// inches, because a point is 1/72 of an inch. A *screen* point is not. On a
/// 13.6-inch display running 1710 points across, one point measures 0.0067
/// inches, so a page drawn at its own metrics comes out 4.1 inches wide — 48%
/// of life size, with 12-point Courier reading as under 6. The metrics are
/// right and the page still looks wrong, which is a display question rather
/// than a document one and is answered here rather than by changing the font.
///
/// Fitting the page to the window is the default because it needs no decision
/// from the writer and no setting to remember: a maximised window lands near
/// life size, a narrow one still shows a whole line. It never goes below
/// actual size — a page smaller than its own metrics helps nobody — and never
/// above twice it, past which the page stops reading as a page.
public nonisolated enum PageZoom {

    /// The page at its own metrics: 612 points drawn as 612 points.
    public static let actualSize: CGFloat = 1

    /// Twice life size on a typical laptop, and the point past which a reader
    /// sees type rather than a page.
    public static let maximum: CGFloat = 2

    /// The stops ⌘+ and ⌘− walk between. Coarse on purpose: a writer choosing
    /// a size wants a different size, not a nudge.
    public static let stops: [CGFloat] = [1, 1.1, 1.25, 1.5, 1.75, 2]

    /// What the writer asked for.
    public enum Command: Sendable, Equatable {
        case zoomIn
        case zoomOut
        /// 100% — the page at its own metrics, whatever that measures here.
        case actualSize
        /// The default: as large as the window allows, within the bounds.
        case fit
    }

    /// The magnification at which a page of `pageWidth`, with `padding` of
    /// canvas either side, fills a canvas `canvasWidth` points wide.
    ///
    /// Clamped, so a window narrower than a page leaves the page at actual
    /// size and scrolling sideways — shrinking it would make a bad situation
    /// smaller rather than better.
    public static func fitting(
        canvasWidth: CGFloat, pageWidth: CGFloat, padding: CGFloat
    ) -> CGFloat {
        let wanted = pageWidth + padding * 2
        guard wanted > 0, canvasWidth > 0 else { return actualSize }
        return clamped(canvasWidth / wanted)
    }

    /// The next stop up or down from where the page is now.
    ///
    /// Measured against the stops rather than multiplied, so ⌘+ from a fitted
    /// 1.83 lands on 2 rather than 2.01, and ⌘− lands on 1.75 rather than
    /// 1.66 — the writer arrives at a round number either way.
    public static func stepped(from current: CGFloat, _ command: Command) -> CGFloat {
        switch command {
        case .actualSize: return actualSize
        case .fit: return current
        case .zoomIn: return clamped(stops.first(where: { $0 > current + 0.001 }) ?? maximum)
        case .zoomOut: return clamped(stops.last(where: { $0 < current - 0.001 }) ?? actualSize)
        }
    }

    /// Whether a command can do anything from here, so a menu item can say so
    /// rather than doing nothing when chosen.
    public static func isAvailable(_ command: Command, at current: CGFloat) -> Bool {
        switch command {
        case .zoomIn: return current < maximum - 0.001
        case .zoomOut: return current > actualSize + 0.001
        case .actualSize: return abs(current - actualSize) > 0.001
        case .fit: return true
        }
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, actualSize), maximum)
    }
}
