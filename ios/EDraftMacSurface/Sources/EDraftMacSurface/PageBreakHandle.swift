import AppKit

/// The line between two pages, and the only thing that can be clicked on it.
///
/// The sheets meet rather than floating apart, because a screenplay is read as
/// a continuous column and a desk-wide gutter every fifty-five lines breaks the
/// read for no gain. What is worth seeing is *where* the break falls — that is
/// a page number, and a page number is a minute of screen time — so the
/// boundary is a hairline, and clicking it opens the two sheets far enough to
/// see them as two.
///
/// It sits in the margins on either side of the break, which are blank by the
/// format's own rules — 60 points at the foot of one page, 72 at the head of
/// the next — so it never covers type. It has to be above the text view all
/// the same, because the text view spans every page and would otherwise take
/// the click.
final class PageBreakHandle: NSView {

    /// How tall the strip is when the pages are joined. Enough to hit
    /// comfortably; small enough that a selection dragged through the
    /// boundary is barely interrupted.
    static let closedHeight: CGFloat = 8

    /// What clicking it does. The canvas does not decide — opening a break
    /// moves every page below it, which is a re-layout, and that belongs to
    /// whoever owns the layout.
    var onClick: (() -> Void)?

    /// Whether the pages either side are currently apart, for the cursor,
    /// the accessibility value and the line's weight.
    var isOpen = false {
        didSet {
            guard isOpen != oldValue else { return }
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Page break")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PageBreakHandle is created in code")
    }

    override var isFlipped: Bool { true }

    /// How present the line is at rest, and under the pointer.
    ///
    /// `separatorColor` was the obvious choice and is the wrong one here: it
    /// is 10% ink, which is right for a divider between two panels of chrome
    /// and invisible on paper. This is the page's own ink instead, at a
    /// weight that reads as a printer's mark rather than as a rule.
    private static let restingInk: CGFloat = 0.38
    private static let hoveredInk: CGFloat = 0.62

    private var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        // A full point rather than one physical pixel: a hairline on a white
        // sheet at this contrast disappears, and the mark has to be findable
        // before it can be pressed.
        let line = NSRect(x: 0, y: (bounds.height - 1) / 2, width: bounds.width, height: 1)
        // Resolved before the alpha is applied. `screenplayInk` is a dynamic
        // colour, and `withAlphaComponent` on one of those does not compose —
        // measured, the line drew at full ink whatever weight was asked for,
        // which is a rule across the page rather than a printer's mark.
        let ink = NSColor.screenplayInk.usingColorSpace(.sRGB) ?? .labelColor
        ink.withAlphaComponent(isHovered ? Self.hoveredInk : Self.restingInk).setFill()
        line.fill()
    }

    // MARK: - Under the pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    /// A pointing hand, so the line reads as something to press rather than
    /// as decoration that happens to be in the way.
    ///
    /// Through `cursorUpdate` and not `resetCursorRects`: `NSTextView` sets an
    /// I-beam across its whole frame, the text view spans every page including
    /// this strip, and cursor *rects* are resolved in a way that lets it win.
    /// A tracking area with `.cursorUpdate` is delivered to the view under the
    /// pointer, which is this one, because it is above the text view.
    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func accessibilityValue() -> Any? {
        isOpen ? "Separated" : "Joined"
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }
}
