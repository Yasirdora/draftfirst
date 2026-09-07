import AppKit

/// Where one page ends and the next begins.
///
/// In `pages` it is a hairline at the join: the sheets meet rather than
/// standing apart, so something has to say the boundary is there, and the
/// cards' own borders are 10% ink and do not. In `continuous` the sheets are
/// gone and this is the *only* thing that says it, so it carries the page
/// number as well — a page is a minute of screen time, and a break that does
/// not count is a rule across the page.
///
/// It draws and nothing else. Clicking a break to prise two sheets apart was
/// tried and removed: with a hundred pages it is a hundred clicks, and doing
/// them all at once is the mode switch, which is what `PageLayoutMode` is.
final class PageBreakMarker: NSView {

    /// The page beginning below this line, or nil to draw the line alone.
    var pageNumber: Int? {
        didSet {
            guard pageNumber != oldValue else { return }
            needsDisplay = true
        }
    }

    /// How present the mark is, which is: barely.
    ///
    /// It is a reference, not punctuation — the writer looks for it when they
    /// want to know where a page turns and should not be reading it the rest
    /// of the time. A rule dark enough to notice while writing is a rule that
    /// cuts the script into pieces every fifty-five lines, which is what the
    /// mode exists to stop.
    private static let lineInk: CGFloat = 0.14
    private static let numberInk: CGFloat = 0.25

    /// How long the rule is. Not the page's width: a line all the way across
    /// is a divider, and a divider every fifty-five lines cuts the script
    /// into pieces, which is the thing this mode exists to stop. This is a
    /// mark in the margin beside the number — the width of a proofreader's
    /// tick, enough to read as a rule and not as a stray pixel.
    private static let ruleWidth: CGFloat = 44
    private static let ruleGap: CGFloat = 6

    /// A little air between the number and the sheet's edge, so it reads as
    /// sitting in the margin rather than falling off it.
    private static let rightInset: CGFloat = 4

    /// Room for the number to sit under the line without touching it.
    static let height: CGFloat = 18

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PageBreakMarker is created in code")
    }

    override var isFlipped: Bool { true }

    /// Decoration. The writer clicks through it to the line underneath.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        // Resolved before the weight is applied: `withAlphaComponent` on a
        // dynamic `NSColor` does not compose, and the line then draws at full
        // ink — a rule across the page rather than a printer's mark.
        let ink = NSColor.screenplayInk.usingColorSpace(.sRGB) ?? .labelColor

        // One physical pixel, not one point: on this display a point is two
        // pixels, and two is a rule where one is a hairline.
        let hairline = 1 / max(1, window?.backingScaleFactor ?? 2)
        let midline = (bounds.height / 2).rounded()

        guard let pageNumber else {
            // No number, no mark: in `pages` the gap between the sheets says
            // where a page ended and this draws nothing at all.
            return
        }

        // Right-aligned, in the margin no line of a screenplay reaches — a
        // scene heading starts at the left and dialogue is centred, so
        // nothing collides with it.
        let caption = "Page \(pageNumber)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 8, weight: .regular),
            .foregroundColor: ink.withAlphaComponent(Self.numberInk)
        ]
        let size = caption.size(withAttributes: attributes)
        let numberX = bounds.maxX - Self.rightInset - size.width
        caption.draw(
            at: NSPoint(x: numberX, y: midline - (size.height / 2).rounded()),
            withAttributes: attributes
        )

        ink.withAlphaComponent(Self.lineInk).setFill()
        NSRect(
            x: numberX - Self.ruleGap - Self.ruleWidth,
            y: midline,
            width: Self.ruleWidth,
            height: hairline
        ).fill()
    }

    override func accessibilityLabel() -> String? {
        pageNumber.map { "Start of page \($0)" } ?? "Page break"
    }
}
