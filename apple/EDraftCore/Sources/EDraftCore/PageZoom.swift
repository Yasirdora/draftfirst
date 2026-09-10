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

    /// What a document opens at.
    ///
    /// Not 100%, for the reason above: a typographic point is 1/72 of an inch
    /// and a screen point is not, so a page at its own metrics comes out under
    /// half life size on a laptop. Word processors have landed on the same
    /// answer from the same arithmetic — a default a notch above actual size,
    /// around 125% to 150% — and it is a better place to start writing than
    /// either extreme. The percentage button is one press from the truth.
    ///
    /// The calm end of that range, 125%: large enough that the page reads as
    /// a page, small enough that it and its desk margins fit a modest window
    /// beside the Navigator with room kept for a character's thread.
    /// Anything larger opens already scrolling sideways, which is a bad
    /// first impression of a page.
    public static let opening: CGFloat = 1.25

    /// Twice life size on a typical laptop, and the point past which a reader
    /// sees type rather than a page.
    public static let maximum: CGFloat = 2

    /// The stops ⌘+ and ⌘− walk between. Coarse on purpose: a writer choosing
    /// a size wants a different size, not a nudge.
    public static let stops: [CGFloat] = [1, 1.1, 1.25, 1.5, 1.75, 2]

    /// The grid a pinch settles onto: every five points. Every stop above
    /// already stands on it, so a size arrived at by hand and a size arrived
    /// at by keyboard are the same sizes.
    public static let snapIncrement: CGFloat = 0.05

    /// Where a pinch that let go at `zoom` comes to rest: the nearest five
    /// points, within the same bounds as everything else.
    ///
    /// A gesture never lands on a number, and a page left at 103% is a page
    /// forever between stops — the size drifts to the grid rather than
    /// staying wherever the fingers happened to lift.
    public static func settled(_ zoom: CGFloat) -> CGFloat {
        clamped((zoom / snapIncrement).rounded() * snapIncrement)
    }

    /// The position along a drift, `progress` of the way from `from` to
    /// `to`: a smootherstep, t³(6t² − 15t + 10), so position, velocity and
    /// acceleration are all continuous at both ends and the value never
    /// overshoots — the page glides onto a stop the way the rubber-band
    /// returns at the limits, minus the bounce. The pure curve, held here
    /// so a test can hold it; the display link that paces it is only a
    /// clock.
    public static func eased(from: CGFloat, to: CGFloat, progress: CGFloat) -> CGFloat {
        let t = min(max(progress, 0), 1)
        let s = t * t * t * (t * (6 * t - 15) + 10)
        return from + (to - from) * s
    }

    /// How long a drift of a given distance takes. Longer jumps take longer,
    /// but sublinearly — with √distance — so a far one never drags and a
    /// near one never whips: a two-and-a-half-point settle is a breath
    /// (0.2s), and a drift the width of the whole range is under half a
    /// second.
    public static func driftDuration(for distance: CGFloat) -> CFTimeInterval {
        0.16 + 0.24 * sqrt(min(max(distance, 0), 1))
    }

    /// How large floating chrome — the selection's format bar — is drawn at
    /// a magnification.
    ///
    /// Chrome is not the page. Grown one-for-one with the zoom, a palette
    /// meant to mark the text ends up covering it; pinned at one size it
    /// reads as *shrinking* the further in the page goes — the same points
    /// measured against ever-larger type. Perceived size runs on a power
    /// law rather than a linear one, so the bar follows the square root of
    /// the zoom: the page doubles at 200% while the bar rises 41%, and at
    /// the 125% opening it is a barely-felt 12% up. The page shouts; the
    /// chrome nods.
    public static func chromeScale(at magnification: CGFloat) -> CGFloat {
        sqrt(min(max(magnification, actualSize), maximum))
    }

    /// The band past each end of the range that a pinch may pull into.
    ///
    /// A hard wall at 100% or 200% reads as a broken gesture: fingers that
    /// keep spreading expect the page to answer. So the scroll view's own
    /// limits stand a spring's width past the page's, and `resisted` maps a
    /// pull into the band at a third of its strength — the end says "here"
    /// without ever holding the writer there. The settle that follows the
    /// gesture walks the size back inside the range; nothing but a gesture
    /// may sit out here.
    public static let bandMinimum: CGFloat = actualSize * 0.92
    public static let bandMaximum: CGFloat = maximum * 1.08

    /// Where a pinch's raw target lands: inside the range, itself; past an
    /// end, a third of the way into the band and never past 8% of the
    /// limit.
    public static func resisted(_ magnification: CGFloat) -> CGFloat {
        let limit = min(max(magnification, actualSize), maximum)
        let overshoot = magnification - limit
        guard overshoot != 0 else { return magnification }
        let spring = overshoot / 3
        let cap = limit * 0.08
        return limit + min(max(spring, -cap), cap)
    }

    /// How the control says it: 152%, not 1.52.
    public static func percentage(_ zoom: CGFloat) -> String {
        "\(displayedPercentage(zoom))%"
    }

    /// The whole points the readout displays, for comparing two sizes at
    /// the granularity the writer sees rather than the floating point's.
    public static func displayedPercentage(_ zoom: CGFloat) -> Int {
        Int((zoom * 100).rounded())
    }

    /// Whether the control's percentage acts as a menu rather than the
    /// actual-size toggle. The toggle answers "how big is this really?" by
    /// going away to actual size and back — at actual size it is already
    /// there, and a press would only nod. So near the truth the control
    /// offers the stops by name instead, and the toggle keeps its place
    /// everywhere else.
    public static func percentageShowsMenu(at zoom: CGFloat) -> Bool {
        displayedPercentage(zoom) < 110
    }

    /// What the writer asked for.
    public enum Command: Sendable, Equatable {
        case zoomIn
        case zoomOut
        /// 100% — the page at its own metrics, whatever that measures here.
        case actualSize
        /// The default: as large as the window allows, within the bounds.
        case fit
        /// The percentage button: away to actual size, and back to whatever
        /// the writer had. One control that answers "how big is this really?"
        /// without costing them the size they were working at.
        case toggleActualSize
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
        case .fit, .toggleActualSize: return current
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
        case .fit, .toggleActualSize: return true
        }
    }

    private static func clamped(_ value: CGFloat) -> CGFloat {
        min(max(value, actualSize), maximum)
    }
}
