import AppKit
import EDraftCore
import EDraftEngine
import SwiftUI

/// The marks a writer can put on a selection, plus the two things a
/// selection is often the start of.
///
/// Emphasis is data now, not notation (RFC v2.1): bold, italic, underline
/// and strikethrough are style runs in the model, toggled through
/// `ScriptSurface.toggleStyle`, and the file hears them exactly because the
/// serialiser synthesises the markers at the boundary. A centred line is
/// the element's type, flipped through the same model path
/// (`ScriptSurface.toggleCentered`) — the file hears `Alignment="Center"`
/// exactly, and the text never carries a `> <` — and a note is anchored
/// to the element, not the selection — see `ScriptAsides`.
enum FormatMark: CaseIterable {
    case bold, italic, underline, strikethrough, centered, note

    var symbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        case .centered: "text.aligncenter"
        case .note: "note.text.badge.plus"
        }
    }

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .strikethrough: "Strikethrough"
        case .centered: "Center Line"
        case .note: "Add Note"
        }
    }

    /// The run style the mark commands; nil for a mark that is not a style.
    var styleSet: StyleSet? {
        switch self {
        case .bold: .bold
        case .italic: .italic
        case .underline: .underline
        case .strikethrough: .strikeout
        case .centered, .note: nil
        }
    }

    /// A thin rule stands before the first mark of each group.
    var opensGroup: Bool { self == .centered || self == .note }
}

/// The bar's window into SwiftUI, and the three guarantees a palette owes the
/// text it floats over:
///
/// - Every point inside the frame hits the bar. A click that misses a
///   button lands on glass — never on the script. Without this, a click in
///   the capsule's gaps falls through to the page, moves the caret into the
///   very text the writer was about to format, and the button then has no
///   selection left to act on: the one symptom read as "the bar does
///   nothing and the text eats my click".
/// - It never takes first responder, so clicking it keeps the selection —
///   and the keyboard — with the text view. A bar that takes focus turns
///   the selection grey and swallows the next keystroke.
/// - Over chrome the cursor says "press me", not "type here". Said with a
///   tracking area rather than a cursor rect: a cursor rect is one entry in
///   the window's whole stack of them, and the text view's I-beam — added
///   for a frame that spans the document — kept winning the overlap. A
///   `cursorUpdate` area on the topmost view under the mouse is answered
///   first, so the arrow is final. `.inVisibleRect` because the bar is
///   re-framed on every scroll tick; the area follows without a reinstall.
private final class FormatBarHost: NSHostingView<FormatBarView> {
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let superview else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
    }

    /// Ours alone, so SwiftUI's own areas neither suppress nor replace it.
    private var cursorArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let cursorArea {
            guard !trackingAreas.contains(cursorArea) else { return }
            self.cursorArea = nil
        }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.cursorUpdate, .activeAlways, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        cursorArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        applyCursor()
    }

    /// The arrow. A separate call so a test can hear it without an event.
    func applyCursor() {
        NSCursor.arrow.set()
    }
}

/// The emphasis controls floating over a selection.
///
/// The bar is chrome, not content — the right-click menu's trick. It lives
/// in the scroll view's own coordinate space, above the clip view, so it
/// never joins the magnification transform the document is drawn through:
/// one size at 60% and at 200%, crisp even mid-pinch, when AppKit is
/// compositing the document as bitmaps rather than redrawing it.
///
/// That costs it a free ride: the page moves under the bar on every scroll
/// tick, resize and pinch frame, so the bar is re-placed from the clip
/// view's bounds changes — one observer hears all three — and hidden
/// outright when its selection has scrolled out of sight.
@MainActor
final class SelectionFormatBar {
    var onApply: ((FormatMark) -> Void)?

    private let host: FormatBarHost
    private weak var scrollView: NSScrollView?
    /// The document the bar floats over. Placement is reasoned about in its
    /// coordinates; see `reposition`.
    private weak var canvas: NSView?
    /// What the bar is showing as lit, and at what scale — the two things a
    /// rebuild spends. A re-place that changes neither leaves the SwiftUI
    /// tree alone.
    private var lit: Set<FormatMark> = []
    private var appliedScale: CGFloat = 1

    init() {
        host = FormatBarHost(rootView: FormatBarView(active: []) { _ in })
        host.isHidden = true
    }

    func attach(to scrollView: NSScrollView, canvas: NSView) {
        self.scrollView = scrollView
        self.canvas = canvas
        rebuild()
        scrollView.addSubview(host, positioned: .above, relativeTo: scrollView.contentView)
    }

    private func rebuild() {
        host.rootView = FormatBarView(active: lit, scale: appliedScale) { [weak self] mark in
            self?.onApply?(mark)
        }
    }

    /// What is lit, and where the bar floats. `active` is the set of marks
    /// the selection already wears — drawn lit, the way a pressed Bold
    /// button reads in any editor.
    func update(selection: NSRange, in textView: NSTextView, active: Set<FormatMark>) {
        if active != lit {
            lit = active
            rebuild()
        }
        reposition(selection: selection, in: textView)
    }

    /// Position only — the scroll/zoom/resize tick. One bounding rectangle
    /// of the selection and frame arithmetic; the SwiftUI tree is untouched.
    ///
    /// Placement is reasoned about in the canvas's coordinates — the
    /// document's own space, where the clip view's bounds *is* the visible
    /// region — and only the bar's centre is converted for the scroll view.
    /// A point converts true through every flip and scale in the hierarchy;
    /// a size would not, which is exactly how the bar would end up
    /// magnified again.
    func reposition(selection: NSRange, in textView: NSTextView) {
        guard let scrollView, let canvas,
              selection.length > 0,
              let rect = ScriptLayout.boundingRect(of: selection, in: textView) else {
            host.isHidden = true
            return
        }
        let placed = canvas.convert(rect, from: textView)
        let viewport = scrollView.contentView.bounds
        // A selection scrolled out of sight has no bar: the bar speaks for
        // text on screen, and hovering over the desk would point at nothing.
        guard placed.intersects(viewport) else {
            host.isHidden = true
            return
        }

        // The bar breathes with the zoom at the square root of it — see
        // `PageZoom.chromeScale` — growing a shade slower than the page
        // rather than reading as shrinking beside it. Applied before the
        // size is measured: the fitting size is the scaled layout's.
        let scale = PageZoom.chromeScale(at: scrollView.magnification)
        if scale != appliedScale {
            appliedScale = scale
            rebuild()
        }

        let size = host.fittingSize
        let magnification = scrollView.magnification
        // The bar's half-extents in the document's units, for clamping; its
        // screen size never changes.
        let halfSize = CGSize(
            width: size.width / (2 * magnification),
            height: size.height / (2 * magnification)
        )
        let gap: CGFloat = 8 / magnification
        let margin: CGFloat = 6

        // Centred on the selection, kept inside the visible region.
        let x = min(
            max(placed.midX, viewport.minX + margin + halfSize.width),
            viewport.maxX - margin - halfSize.width
        )
        // Above the selection, below it when the window's top has no room —
        // a palette reaches for open space the way a popover does. The
        // canvas is flipped: "above" is a smaller y here.
        let above = placed.minY - gap - halfSize.height
        let below = placed.maxY + gap + halfSize.height
        let y: CGFloat
        if above - halfSize.height >= viewport.minY + margin {
            y = above
        } else if below + halfSize.height <= viewport.maxY - margin {
            y = below
        } else {
            y = min(
                max(above, viewport.minY + margin + halfSize.height),
                viewport.maxY - margin - halfSize.height
            )
        }
        let centre = scrollView.convert(CGPoint(x: x, y: y), from: canvas)
        host.frame = CGRect(
            x: (centre.x - size.width / 2).rounded(),
            y: (centre.y - size.height / 2).rounded(),
            width: size.width,
            height: size.height
        )
        host.isHidden = false
    }

    // MARK: - Test handles

    /// Whether the bar is up.
    var isVisible: Bool { !host.isHidden }
    /// Where it floats, in the scroll view's coordinates.
    var frame: CGRect { host.frame }
    /// The view itself, for hit-testing and responder questions.
    var hostView: NSView { host }
}

/// The bar itself: the marks in one small piece of glass.
///
/// Laid out at `scale` — the zoom's square root (`PageZoom.chromeScale`) —
/// so it grows with the page a shade slower than the page does, rather than
/// reading as shrinking beside it. Real layout scaling, not a transform: the
/// glyphs are set at the scaled point size, so the bar stays crisp instead
/// of being bitmap-stretched, and the frame the host measures is the frame
/// the writer clicks in.
struct FormatBarView: View {
    let active: Set<FormatMark>
    var scale: CGFloat = 1
    let apply: (FormatMark) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FormatMark.allCases, id: \.self) { mark in
                if mark.opensGroup {
                    Divider().frame(height: 14 * scale).padding(.horizontal, 4 * scale)
                }
                Button {
                    apply(mark)
                } label: {
                    Image(systemName: mark.symbol)
                        .font(.system(size: 13 * scale, weight: .medium))
                        .foregroundStyle(active.contains(mark) ? Color.accentColor : .primary)
                        .frame(width: 26 * scale, height: 26 * scale)
                        .background {
                            if active.contains(mark) {
                                Capsule().fill(Color.accentColor.opacity(0.18))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(mark.title)
                .accessibilityLabel(mark.title)
                .accessibilityValue(active.contains(mark) ? "On" : "")
            }
        }
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 3 * scale)
        .glassEffect(.regular.interactive(), in: .capsule)
        // Glass answers what is behind it, and over a dark page that answer
        // is a dark body on a dark ground — the bar read as glyphs floating
        // on the script. A hairline marks the capsule in both looks, the
        // way a menu's edge does; the shadow alone only lifts it off paper.
        .overlay {
            Capsule().strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
        }
        // The shadow is a screen-space effect: it does not zoom.
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        .padding(5 * scale)
    }
}

extension ScriptSurface {

    /// Routes a mark to its mechanism. A style run is toggled through the
    /// model (`toggleStyle`); a centred line is an element-level change of
    /// the same kind (`toggleCentered`) — the type flips through the model,
    /// the file hears `Alignment="Center"` at the boundary, and no `> <`
    /// marker ever enters the text. A note is not a text mark; the surface
    /// routes it to `addNoteAtCaret` itself.
    func applyMark(_ mark: FormatMark) {
        if let style = mark.styleSet {
            toggleStyle(style, named: mark.title)
            return
        }
        guard mark == .centered else { return }
        toggleCentered(named: mark.title)
    }
}
