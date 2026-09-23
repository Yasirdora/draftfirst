import AppKit
import EDraftCore

/// One engine page of Two Pages. All sheets share the
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
        let view = PageSheetTextView(
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

    /// Carries this sheet's start and end through an edit the storage has
    /// just processed, before TextKit lays anything out again — the way
    /// TextKit carries its own ranges (IL-0091).
    ///
    /// A keystroke moves every later page's boundary by the characters it
    /// added. Assigned as a geometry change, each move threw away the layout
    /// of every page after the edit, so anything that then asked a later
    /// page where a line was — a note's mark, say — re-typeset the rest of
    /// the script. Moved with the text, the layout TextKit already has stays
    /// good; when pagination then says a boundary really moved, `update`
    /// invalidates as it always did.
    func follow(editAt location: Int, replacedLength: Int, insertedLength: Int) {
        startLocation = Self.follow(startLocation, location, replacedLength, insertedLength)
        container.follow(to: Self.follow(container.breakAt, location, replacedLength, insertedLength))
    }

    /// Where a boundary lands after `replacedLength` characters at `location`
    /// became `insertedLength`: unmoved before the edit, shifted after it,
    /// and at the end of the new text when the edit swallowed it.
    nonisolated static func follow(_ index: Int, _ location: Int, _ replacedLength: Int, _ insertedLength: Int) -> Int {
        guard index != .max, index > location else { return index }
        if index >= location + replacedLength { return index + insertedLength - replacedLength }
        return location + insertedLength
    }
}

/// A sheet's text view.
///
/// The sheets are one script, so they are one stop in the key-view loop:
/// only the sheet holding the selection accepts keyboard focus from Tab —
/// the legacy column's single stop, kept (IL-0091). Every sheet still takes
/// a click; this is only about moving focus with the keyboard.
final class PageSheetTextView: NSTextView {
    var isKeyStop: () -> Bool = { true }
    override var canBecomeKeyView: Bool { super.canBecomeKeyView && isKeyStop() }
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

    /// The same boundary, moved with the text rather than re-set: no
    /// geometry changed, so no layout is thrown away (`PageSheet.follow`).
    nonisolated func follow(to newValue: Int) {
        breakLock.withLock { storedBreak = newValue }
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
