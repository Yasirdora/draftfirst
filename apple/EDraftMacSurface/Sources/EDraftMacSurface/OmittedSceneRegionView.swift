import AppKit
import EDraftCore
import EDraftEngine

/// The chrome of a cut scene — RFC-DRAFT-PRODUCTION §7.3.
///
/// Quiet, the way the page is quiet. Collapsed, the card's line is only the
/// word OMITTED in muted ink; hovering the line lays a soft highlight over
/// it and shows a small chevron at the column's trailing edge, the way
/// Xcode's fold ribbon appears when the pointer asks for it. The chevron
/// opens the cut text, and stays showing while the region is open, because
/// it is the way back. There is no pill and no label on the page: how much
/// was cut is production data, and it lives where production data belongs —
/// the Navigator row, the hover tooltip, and VoiceOver.
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

    /// The pointer is over the line. Set by the tracking area; readable to
    /// the package so the reveal is proven by a test and not by an eyeball.
    private(set) var hovered = false

    private let chevron = NSButton()

    init(scene: OmittedScene, collapsed: Bool) {
        self.scene = scene
        self.collapsed = collapsed
        super.init(frame: .zero)
        wantsLayer = true
        /* Layer-backed so the fade is a real opacity animation: the model
           value moves to its target at once, the presentation eases. */
        chevron.wantsLayer = true
        addSubview(chevron)
        chevron.target = self
        chevron.action = #selector(toggle)
        chevron.isBordered = false
        chevron.bezelStyle = .inline
        chevron.setButtonType(.momentaryChange)
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
        chevron.image = NSImage(
            systemSymbolName: collapsed ? "chevron.right" : "chevron.down",
            accessibilityDescription: nil
        )
        chevron.imagePosition = .imageOnly
        chevron.contentTintColor = Self.ink
        chevron.sizeToFit()

        /* The length, said plainly, where a hover and a reader can find it
           — never stamped on the page itself. */
        toolTip = scene.spoken(collapsed: collapsed)

        /* Spoken, because a chevron is not. The state is in the label, so a
           reader hears what a sighted writer sees at a glance. */
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(scene.spoken(collapsed: collapsed))
        updateChrome()
    }

    /// The chevron shows when the region is open — it is the way back — or
    /// when the pointer is on the line. At rest there is nothing but the
    /// word OMITTED. It appears and disappears with a short ease, the way
    /// hover chrome does across macOS — never a snap.
    private func updateChrome() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            chevron.animator().alphaValue = chevronVisible ? 1 : 0
        }
        needsLayout = true
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    @objc private func toggle() { onToggle?(scene.key) }

    override func accessibilityPerformPress() -> Bool {
        toggle()
        return true
    }

    /// Where the chevron sits, in the region's own coordinates — so a test
    /// can prove it never overprints the card's words, rather than that
    /// being asserted in prose.
    var chevronFrame: CGRect { chevron.frame }

    /// Whether the chevron is logically showing — collapsed and at rest,
    /// it is not. The fade animates the alpha; this is the truth tests
    /// and the hit test read.
    var chevronVisible: Bool { !collapsed || hovered }

    /// The card line's own band and where its glyphs end — set by the
    /// surface at placement. `top` is the distance from the frame's
    /// *visual* top (the host text view is flipped; this view is not), and
    /// `glyphMaxX` is measured from the frame's leading edge. The chevron
    /// rides this line at its trailing edge.
    struct HeadAnchor: Equatable {
        let top: CGFloat
        let height: CGFloat
        let glyphMaxX: CGFloat
    }
    var headAnchor: HeadAnchor? {
        didSet { needsLayout = true; needsDisplay = true }
    }

    /// The line the chevron rides, in local coordinates. Unflipped: the
    /// anchor's `top` counts down from the visual top, this view's y
    /// counts up from the bottom.
    private var headBand: CGRect {
        let height = headAnchor?.height ?? min(bounds.height, 18)
        let top = headAnchor?.top ?? 0
        return NSRect(x: 0, y: max(0, bounds.height - top - height),
                      width: bounds.width, height: height)
    }

    /// The hover zone is simply the frame: the chevron now lives inside
    /// it, at the line's trailing edge, so the pointer's walk from the
    /// word to the chevron never crosses an edge. (The gutter experiment
    /// died here: a zone that ended at the frame's edge hid the chevron
    /// exactly when it was reached for.)
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        updateChrome()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        updateChrome()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard chevronVisible else { return }
        /* A generous hand over a small mark: the glyph is ten points, the
           click target is not. */
        addCursorRect(chevronHome.insetBy(dx: -6, dy: -6), cursor: .pointingHand)
    }

    /// Where the chevron sits: the trailing edge of the card's own line,
    /// inside the frame — computed from the anchor rather than read back
    /// from the button, so layout, the cursor rect and the hit test all
    /// agree, even before `layout()` has run.
    private var chevronHome: CGRect {
        let size = chevron.intrinsicContentSize
        let band = headBand
        return NSRect(
            x: max(0, bounds.width - size.width - 4),
            y: band.midY - size.height / 2,
            width: size.width, height: size.height
        )
    }

    override func layout() {
        super.layout()
        /* The right end of the line, inside the page: the control is
           ordinary in-bounds chrome, so hover, cursor and click all work
           without reaching past the frame. */
        chevron.frame = chevronHome
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard hovered else { return }
        /* The line reads as one tappable thing while the pointer is on it.
           A breath of the same sepia, not a selection colour: nothing here
           is selected, and nothing here is live. */
        let wash = NSBezierPath(roundedRect: headBand.insetBy(dx: -2, dy: -3), xRadius: 4, yRadius: 4)
        Self.ink.withAlphaComponent(0.07).setFill()
        wash.fill()
    }

    /// The chrome never takes a click meant for the page, except on the
    /// chevron itself — the card's line stays a live line the caret can
    /// land on.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let inside = convert(point, from: superview)
        let target = chevronHome.insetBy(dx: -8, dy: -8)
        return chevronVisible && target.contains(inside) ? chevron : nil
    }
}
