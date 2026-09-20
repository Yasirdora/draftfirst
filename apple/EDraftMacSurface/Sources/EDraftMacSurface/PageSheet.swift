import AppKit
import EDraftCore

/// One engine page in the flagged spread editor. All sheets share the
/// surface's storage and layout manager; neither pagination nor text is copied.
@MainActor
public final class PageSheet {
    private let container: PageSheetContainer
    public var textContainer: NSTextContainer { container }
    public let textView: NSTextView
    public private(set) var startLocation: Int

    init(startLocation: Int, endLocation: Int, measure: CGFloat,
         layoutManager: NSLayoutManager) {
        self.startLocation = startLocation
        let container = PageSheetContainer(
            size: CGSize(width: measure, height: .greatestFiniteMagnitude)
        )
        self.container = container
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)
        let view = NSTextView(
            frame: NSRect(x: 0, y: 0, width: measure, height: 1),
            textContainer: container
        )
        textView = view
        view.isRichText = false
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.minSize = .zero
        view.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude
        )
        view.autoresizingMask = []
        view.textContainerInset = NSSize(width: 0, height: ScreenplayPageLayout.glyphOverflow)
        view.drawsBackground = false
        view.backgroundColor = .clear
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        // ScriptSurface enables interaction after connecting its edit delegate.
        view.isEditable = false
        view.isSelectable = false
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        update(startLocation: startLocation, endLocation: endLocation, measure: measure)
    }

    func update(startLocation: Int, endLocation: Int, measure: CGFloat) {
        self.startLocation = startLocation
        let size = CGSize(width: measure, height: .greatestFiniteMagnitude)
        if textContainer.size != size { textContainer.size = size }
        container.breakAt = endLocation
    }
}

/// TextKit may wrap lines, but only the engine decides where a page ends.
/// Height is deliberately unbounded: paper height must never create an
/// earlier break that disagrees with the printed screenplay.
final class PageSheetContainer: NSTextContainer {
    nonisolated private let breakLock = NSLock()
    nonisolated private var storedBreak = Int.max

    nonisolated var breakAt: Int {
        get { breakLock.withLock { storedBreak } }
        set {
            let changed = breakLock.withLock {
                guard storedBreak != newValue else { return false }
                storedBreak = newValue
                return true
            }
            guard changed else { return }
            // RFC §2.1: assignment without this leaves previously laid-out
            // text silently in the wrong container, including on later edits.
            layoutManager?.textContainerChangedGeometry(self)
        }
    }

    nonisolated override init(size: CGSize) { super.init(size: size) }
    nonisolated required init(coder: NSCoder) { super.init(coder: coder) }

    nonisolated override func lineFragmentRect(
        forProposedRect proposedRect: CGRect,
        at characterIndex: Int,
        writingDirection baseWritingDirection: NSWritingDirection,
        remaining remainingRect: UnsafeMutablePointer<CGRect>?
    ) -> CGRect {
        guard characterIndex < breakAt else {
            remainingRect?.pointee = .zero
            return .zero
        }
        return super.lineFragmentRect(
            forProposedRect: proposedRect, at: characterIndex,
            writingDirection: baseWritingDirection, remaining: remainingRect
        )
    }
}
