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

    /// How present the line is. Not `separatorColor`, which is 10% ink —
    /// right between panels of chrome, invisible on paper.
    private static let lineInk: CGFloat = 0.34
    private static let numberInk: CGFloat = 0.45

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

        let midline = (bounds.height / 2).rounded()
        ink.withAlphaComponent(Self.lineInk).setFill()
        NSRect(x: 0, y: midline, width: bounds.width, height: 1).fill()

        guard let pageNumber else { return }
        let caption = "Page \(pageNumber)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .medium),
            .foregroundColor: ink.withAlphaComponent(Self.numberInk)
        ]
        let size = caption.size(withAttributes: attributes)
        // Trailing, in the right margin, where no line of a screenplay
        // reaches — a scene heading starts at the left and dialogue is
        // centred, so nothing collides with it.
        caption.draw(
            at: NSPoint(x: bounds.maxX - size.width, y: midline + 3),
            withAttributes: attributes
        )
    }

    override func accessibilityLabel() -> String? {
        pageNumber.map { "Start of page \($0)" } ?? "Page break"
    }
}
