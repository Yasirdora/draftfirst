import AppKit

/// A note, in the margin, beside the line it is about.
///
/// This is the whole of a note on the page: the words are in the card the
/// marker opens, never in the script. A note that printed as a line of the
/// screenplay is what the writer was reading before — their own private aside
/// set in Courier among the stage directions, counted toward a page number a
/// production schedules against.
///
/// It sits in the right-hand margin, which nothing printed reaches: a heading
/// starts at the left, action wraps at sixty characters, dialogue is indented
/// well inside. So the mark never lands on a word.
final class NoteMarker: NSView {

    /// The note this marker opens.
    var noteID: UUID?

    /// Whether this note's card is the one currently open. Pages fills the
    /// active marker and outlines the rest; so does this.
    var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            applySymbol()
        }
    }

    /// Told, not asked. The marker is a subview of the canvas and has no way
    /// to reach the surface that placed it.
    var onOpen: ((UUID) -> Void)?

    /// Big enough to be an easy click target at the sizes a script is read
    /// at, small enough to stay out of the way of the words beside it. This
    /// is the size Pages draws its comment marker at.
    static let size = CGSize(width: 16, height: 16)

    /// An `NSImageView` rather than `draw(_:)` with a colour set on the
    /// context: an SF Symbol arrives as a template image, and a template
    /// takes its colour from the view that hosts it — `NSColor.set()` before
    /// `NSImage.draw(in:)` is simply ignored, and the mark comes out black.
    /// `contentTintColor` is the mechanism AppKit provides, and it re-resolves
    /// the colour on an appearance change without being asked.
    private let symbol = NSImageView()
    private var cursorArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Note")

        symbol.imageScaling = .scaleProportionallyUpOrDown
        symbol.contentTintColor = .screenplayNoteTint
        // The marker handles its own clicks; an image view in the way would
        // swallow them.
        symbol.isEditable = false
        symbol.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbol)
        NSLayoutConstraint.activate([
            symbol.leadingAnchor.constraint(equalTo: leadingAnchor),
            symbol.trailingAnchor.constraint(equalTo: trailingAnchor),
            symbol.topAnchor.constraint(equalTo: topAnchor),
            symbol.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        applySymbol()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoteMarker is created in code")
    }

    override var isFlipped: Bool { true }

    /// Filled while its card is open, outlined otherwise — Pages' own
    /// distinction, and one a reader can make at a glance without a colour
    /// change to notice.
    private func applySymbol() {
        let image = NSImage(
            systemSymbolName: isActive ? "bubble.fill" : "bubble",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(
            NSImage.SymbolConfiguration(pointSize: Self.size.height, weight: .regular)
        )
        // Said rather than assumed: `withSymbolConfiguration` returns a fresh
        // image, and a configured symbol does not always come back templated.
        // Untemplated, `contentTintColor` has nothing to tint and the mark
        // draws in the symbol's own black.
        image?.isTemplate = true
        symbol.image = image
    }

    // MARK: - Pointing at it

    /// An arrow over the marker, not the I-beam the page is full of.
    ///
    /// `resetCursorRects` loses this argument: `NSTextView` maintains its own
    /// cursor rects for the text under here and wins. A tracking area with
    /// `.cursorUpdate` is the one that holds.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorArea { removeTrackingArea(cursorArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.cursorUpdate, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        cursorArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    /// The image view is decoration; the marker is the button.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let noteID else { return }
        onOpen?(noteID)
    }

    override func accessibilityPerformPress() -> Bool {
        guard let noteID else { return false }
        onOpen?(noteID)
        return true
    }
}
