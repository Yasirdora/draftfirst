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
        let inset = textView.textContainerInset
        let placed = rect.offsetBy(dx: inset.width, dy: inset.height)
        return [NSValue(rect: placed)]
    }
}
