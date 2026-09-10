import AppKit
import EDraftEngine
import SwiftUI

/// The marks a writer can put on a selection, plus the two things a
/// selection is often the start of.
///
/// Emphasis is data now, not notation (RFC v2.1): bold, italic, underline
/// and strikethrough are style runs in the model, toggled through
/// `ScriptSurface.toggleStyle`, and the file hears them exactly because the
/// serialiser synthesises the markers at the boundary. A centred line is an
/// element-level rewrite and a note is anchored to the element, not the
/// selection — see `ScriptAsides`.
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

/// The bar's window into SwiftUI, and the two guarantees a palette owes the
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
private final class FormatBarHost: NSHostingView<FormatBarView> {
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, let superview else { return nil }
        return bounds.contains(convert(point, from: superview)) ? self : nil
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
    /// What the bar is showing as lit, so a re-place does not rebuild the
    /// SwiftUI tree — only a change of what the selection wears does.
    private var lit: Set<FormatMark> = []

    init() {
        host = FormatBarHost(rootView: FormatBarView(active: []) { _ in })
        host.isHidden = true
    }

    func attach(to scrollView: NSScrollView, canvas: NSView) {
        self.scrollView = scrollView
        self.canvas = canvas
        host.rootView = FormatBarView(active: []) { [weak self] mark in
            self?.onApply?(mark)
        }
        scrollView.addSubview(host, positioned: .above, relativeTo: scrollView.contentView)
    }

    /// What is lit, and where the bar floats. `active` is the set of marks
    /// the selection already wears — drawn lit, the way a pressed Bold
    /// button reads in any editor.
    func update(selection: NSRange, in textView: NSTextView, active: Set<FormatMark>) {
        if active != lit {
            lit = active
            host.rootView = FormatBarView(active: active) { [weak self] mark in
                self?.onApply?(mark)
            }
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
struct FormatBarView: View {
    let active: Set<FormatMark>
    let apply: (FormatMark) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FormatMark.allCases, id: \.self) { mark in
                if mark.opensGroup {
                    Divider().frame(height: 12).padding(.horizontal, 3)
                }
                Button {
                    apply(mark)
                } label: {
                    Image(systemName: mark.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(active.contains(mark) ? Color.accentColor : .primary)
                        .frame(width: 22, height: 22)
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
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .glassEffect(.regular.interactive(), in: .capsule)
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        .padding(4)
    }
}

extension ScriptSurface {

    /// Routes a mark to its mechanism. A style run is toggled through the
    /// model (`toggleStyle`); a centred line still travels through the text
    /// view's own input path, so the planner sees it exactly as it sees
    /// typing — undoable, and never behind the model's back. A note is not a
    /// text mark; the surface routes it to `addNoteAtCaret` itself.
    func applyMark(_ mark: FormatMark) {
        if let style = mark.styleSet {
            toggleStyle(style, named: mark.title)
            return
        }
        guard mark == .centered else { return }
        let selection = textView.selectedRange()
        let text = textView.string as NSString
        var line = text.lineRange(for: selection)
        var content = text.substring(with: line)
        if content.hasSuffix("\n") {
            content.removeLast()
            line.length -= 1
        }
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        let centred = trimmed.hasPrefix(">") && trimmed.hasSuffix("<")
        let replacement = centred
            ? String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            : "> \(trimmed) <"
        textView.insertText(replacement, replacementRange: line)
        textView.setSelectedRange(NSRange(location: line.location, length: (replacement as NSString).length))
    }
}
