import AppKit
import EDraftCore
import EDraftEngine

/// The chrome of a cut scene — RFC-DRAFT-PRODUCTION §7.3.
///
/// Collapsed, this sits on the card's own line and carries the two things
/// the line cannot say by itself: how much page was cut, and that there is
/// text behind it to read. Expanded, it closes the body with a dotted rule
/// so the region has a foot as well as a head.
///
/// An overlay rather than a text attachment, the way the page-break marker
/// and the reveal highlight are: the text storage stays plain text — so
/// find, copy and the paginator see a script and not a widget — and the
/// control is a real view that VoiceOver can reach.
final class OmittedSceneRegionView: NSView {

    private(set) var scene: OmittedScene
    private(set) var collapsed: Bool
    /// Called when the writer asks to see the cut text, or to put it away.
    var onToggle: ((DraftElementID) -> Void)?

    private let pill = NSTextField(labelWithString: "")
    private let disclosure = NSButton()

    init(scene: OmittedScene, collapsed: Bool) {
        self.scene = scene
        self.collapsed = collapsed
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(pill)
        addSubview(disclosure)
        disclosure.target = self
        disclosure.action = #selector(toggle)
        disclosure.isBordered = false
        disclosure.bezelStyle = .inline
        disclosure.setButtonType(.momentaryChange)
        apply()
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not in a nib") }

    func update(scene: OmittedScene, collapsed: Bool) {
        self.scene = scene
        self.collapsed = collapsed
        apply()
    }

    /// The same sepia the type takes, resolved against the paper — never a
    /// label colour, which would follow the app's appearance and go pale on
    /// a page that had not changed.
    static var ink: NSColor { NSColor.screenplayOmittedInk.usingColorSpace(.sRGB) ?? .secondaryLabelColor }

    private func apply() {
        let ink = Self.ink
        pill.stringValue = scene.pillText
        pill.font = .systemFont(ofSize: 10, weight: .medium)
        pill.textColor = ink
        pill.sizeToFit()

        let title = collapsed ? "View Cut Text" : "Hide Cut Text"
        disclosure.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: ink
            ]
        )
        disclosure.image = NSImage(
            systemSymbolName: collapsed ? "chevron.right" : "chevron.down",
            accessibilityDescription: nil
        )
        disclosure.imagePosition = .imageLeading
        disclosure.contentTintColor = ink
        disclosure.sizeToFit()

        /* Spoken, because a pill and a chevron are not. The state is in the
           label rather than only in the chevron, so a reader hears what a
           sighted writer sees at a glance. */
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(scene.spoken(collapsed: collapsed))
        needsLayout = true
        needsDisplay = true
    }

    @objc private func toggle() { onToggle?(scene.key) }

    override func accessibilityPerformPress() -> Bool {
        toggle()
        return true
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 8
        let pillSize = pill.intrinsicContentSize
        let buttonSize = disclosure.intrinsicContentSize
        /* Both ride the head of the region — the card's line when
           collapsed, the body's first line when open — at the trailing
           edge, where a page has margin rather than type. */
        let headHeight = min(bounds.height, max(pillSize.height, buttonSize.height) + 4)
        let top = bounds.maxY - headHeight
        disclosure.frame = NSRect(
            x: bounds.maxX - buttonSize.width - inset,
            y: top + (headHeight - buttonSize.height) / 2,
            width: buttonSize.width, height: buttonSize.height
        )
        pill.frame = NSRect(
            x: disclosure.frame.minX - pillSize.width - inset,
            y: top + (headHeight - pillSize.height) / 2,
            width: pillSize.width, height: pillSize.height
        )
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !collapsed else { return }
        /* The region's foot. Dotted, so it reads as an edge of something
           shown rather than a rule the script itself contains. */
        let rule = NSBezierPath()
        rule.move(to: NSPoint(x: bounds.minX, y: bounds.minY + 0.5))
        rule.line(to: NSPoint(x: bounds.maxX, y: bounds.minY + 0.5))
        rule.lineWidth = 1
        rule.setLineDash([2, 3], count: 2, phase: 0)
        Self.ink.withAlphaComponent(0.6).setStroke()
        rule.stroke()
    }

    /// The chrome never takes a click meant for the page, except on the
    /// disclosure itself.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let inside = convert(point, from: superview)
        return disclosure.frame.contains(inside) ? disclosure : nil
    }
}
