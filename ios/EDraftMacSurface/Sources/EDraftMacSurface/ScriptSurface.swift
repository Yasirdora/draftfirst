import AppKit
import EDraftCore
import Foundation

/// The page, on a Mac.
///
/// Everything that happens between the model and an `NSTextView`: setting the
/// script, remembering which characters belong to which element, moving the
/// page when a Navigator row asks, and marking where it landed.
///
/// It is a plain class rather than a view so it can be driven by a test. The
/// SwiftUI wrapper around it (`ScriptPageView`) adds nothing but lifetime — a
/// deliberate arrangement, because every hard bug this project has had lived
/// in exactly this arithmetic and none of them were visible from a screenshot.
///
/// TextKit 1, following the measurements in `ScriptLayoutTests`: its rectangles
/// are the ones `PageScroll` and the reveal were written against, so the phone's
/// hard-won behaviour ports rather than being invented again.
@MainActor
public final class ScriptSurface {

    public let scrollView: NSScrollView
    public let textView: NSTextView

    private var ranges: [ScriptLayout.ElementRange] = []
    private let highlight = RevealHighlightViewMac()

    /// The measure the script is set to. A Mac window is resizable, so this
    /// changes; the indents are fractions of it, which is why they are
    /// fractions in the first place.
    private var measure: CGFloat

    public init(measure: CGFloat = 640) {
        self.measure = measure

        let container = NSTextContainer(
            size: CGSize(width: measure, height: .greatestFiniteMagnitude)
        )
        container.widthTracksTextView = true
        let layoutManager = NSLayoutManager()
        let storage = NSTextStorage()
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        textView = NSTextView(
            frame: NSRect(x: 0, y: 0, width: measure, height: 0), textContainer: container
        )
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 0, height: 24)
        container.lineFragmentPadding = 0
        textView.backgroundColor = .textBackgroundColor
        // The screenplay's own rules decide what a line looks like; nothing
        // the system might helpfully add belongs on a page that has to print
        // exactly as it reads.
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: measure, height: 480))
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
    }

    // MARK: - Setting the script

    /// Replaces the page with the model's current text.
    ///
    /// The whole string at once, as on the phone: the elements are the
    /// document, and rebuilding from them is what keeps the text and the model
    /// from ever disagreeing about what is on the page.
    public func render(_ elements: [ScriptElement]) {
        let script = ScriptLayout.attributedScript(elements, measure: measure)
        ranges = script.ranges
        textView.textStorage?.setAttributedString(script.text)
        if let layoutManager = textView.layoutManager, let container = textView.textContainer {
            layoutManager.ensureLayout(for: container)
        }
    }

    /// Re-sets the page for a new width. A resized window is a re-measured
    /// script, because every indent is a fraction of the measure.
    public func remeasure(to width: CGFloat, elements: [ScriptElement]) {
        guard width > 0, abs(width - measure) > 0.5 else { return }
        measure = width
        textView.textContainer?.size = CGSize(
            width: width, height: .greatestFiniteMagnitude
        )
        render(elements)
    }

    // MARK: - Going to an element

    /// Brings an element into view and marks it.
    ///
    /// Two jobs, and the second is not optional: a script stops scrolling when
    /// its last page reaches the bottom, so a target near the end never reaches
    /// the top and one already in view does not move the page at all. See
    /// `RevealMark`.
    @discardableResult
    public func reveal(_ id: UUID, reduceMotion: Bool = false) -> Bool {
        guard let mapped = ranges.first(where: { $0.id == id }),
              let rect = ScriptLayout.boundingRect(of: mapped.range, in: textView)
        else { return false }

        textView.setSelectedRange(NSRange(location: mapped.range.location, length: 0))
        scroll(bringingToTop: rect)
        mark(rect, reduceMotion: reduceMotion)
        return true
    }

    /// Where the page rests, in the scroll view's own terms.
    public var scrollableRange: ClosedRange<CGFloat> {
        PageScroll.range(
            contentHeight: textView.frame.height,
            viewportHeight: scrollView.contentView.bounds.height,
            topInset: scrollView.contentInsets.top,
            bottomInset: scrollView.contentInsets.bottom
        )
    }

    /// Moves the page so `rect` rests at the top of the readable area — as
    /// near as the document allows.
    public func scroll(bringingToTop rect: CGRect) {
        let range = scrollableRange
        guard PageScroll.canScroll(range) else { return }
        let y = PageScroll.offset(
            bringingContentY: rect.minY + textView.textContainerInset.height, toTopOf: range
        )
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    private func mark(_ rect: CGRect, reduceMotion: Bool) {
        var marked = rect
        marked.origin.x += textView.textContainerInset.width
        marked.origin.y += textView.textContainerInset.height
        if marked.width < 1, let container = textView.textContainer {
            marked.size.width = container.size.width
        }
        highlight.mark(marked, in: textView, reduceMotion: reduceMotion)
    }

    /// Whether a mark is currently on the page — the surface's own answer to
    /// "did that reveal say anything?", and what a test asks.
    public var isMarking: Bool {
        highlight.superview === textView && highlight.frame.height > 0
    }

    /// Which element the insertion point is in, if any.
    public func element(at location: Int) -> UUID? {
        ranges.first { NSLocationInRange(location, $0.range) || $0.range.location == location }?.id
    }
}
