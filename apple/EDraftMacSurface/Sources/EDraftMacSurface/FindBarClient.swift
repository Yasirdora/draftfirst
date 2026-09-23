import AppKit

/// The system find bar's client, with Replace turned off.
///
/// `NSTextView.replaceCharacters(in:with:)` does not go through
/// `shouldChangeTextIn` — measured in `TextFinderMeasurementTests`. A
/// Replace All would write the storage behind the planner and desync the
/// model. `isEditable` is false here so the bar does not offer Replace;
/// the text view itself stays editable for typing.
final class FindBarClient: NSObject, NSTextFinderClient {
    private let textView: NSTextView

    init(textView: NSTextView) {
        self.textView = textView
        super.init()
    }

    var isEditable: Bool { false }
    var isSelectable: Bool { true }
    var allowsMultipleSelection: Bool { false }

    var string: String { textView.string }

    var firstSelectedRange: NSRange { textView.selectedRange() }

    var selectedRanges: [NSValue] {
        get { textView.selectedRanges }
        set { textView.selectedRanges = newValue }
    }

    func scrollRangeToVisible(_ range: NSRange) {
        textView.scrollRangeToVisible(range)
    }

    func contentView(at index: Int) -> NSView {
        textView
    }

    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        guard let rect = ScriptLayout.boundingRect(of: range, in: textView) else {
            return nil
        }
        // Already in the text view's coordinates; see `ScriptSurface.canvasY`.
        return [NSValue(rect: rect)]
    }
}

/// NSTextFinder's multi-view contract for Two Pages' page sheets.
/// The legacy client above deliberately retains its original implementation.
@MainActor
final class PageSheetFindBarClient: NSObject, NSTextFinderClient {
    private weak var surface: ScriptSurface?

    init(surface: ScriptSurface) {
        self.surface = surface
        super.init()
    }

    var isEditable: Bool { false } // Replace must not bypass the edit planner.
    var isSelectable: Bool { true }
    var allowsMultipleSelection: Bool { false }
    var string: String { surface?.textStorage.string ?? "" }
    var firstSelectedRange: NSRange {
        surface?.selectionTextView.selectedRange() ?? NSRange(location: NSNotFound, length: 0)
    }
    var selectedRanges: [NSValue] {
        get { surface?.selectionTextView.selectedRanges ?? [] }
        set {
            guard let surface, let first = newValue.first else { return }
            surface.textView(atCharacter: first.rangeValue.location).selectedRanges = newValue
        }
    }

    func scrollRangeToVisible(_ range: NSRange) {
        surface?.textView(atCharacter: range.location).scrollRangeToVisible(range)
    }

    func contentView(at index: Int, effectiveCharacterRange outRange: NSRangePointer) -> NSView {
        guard let surface else {
            outRange.pointee = NSRange(location: 0, length: 0)
            return NSView()
        }
        let view = surface.textView(atCharacter: index)
        if let layout = view.layoutManager, let container = view.textContainer {
            layout.ensureLayout(for: container)
            outRange.pointee = layout.characterRange(
                forGlyphRange: layout.glyphRange(for: container), actualGlyphRange: nil)
        }
        return view
    }

    func rects(forCharacterRange range: NSRange) -> [NSValue]? {
        guard let view = surface?.textView(atCharacter: range.location),
              let rect = ScriptLayout.sheetBoundingRect(of: range, in: view) else { return nil }
        // NSTextFinder guarantees this range belongs to one content view.
        return [NSValue(rect: rect)]
    }
}
