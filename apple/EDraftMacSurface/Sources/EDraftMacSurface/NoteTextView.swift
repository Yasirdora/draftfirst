import AppKit
import SwiftUI

/// The note's words.
///
/// SwiftUI's `TextEditor` was tried first and could not be made to behave
/// inside an `NSPopover`. Two symptoms, one cause: it drew its text and its
/// caret at the card's own origin — behind the title, which is where a writer
/// found the caret blinking — and its focus request went nowhere, because
/// `@FocusState` is asked for in `onAppear`, before the popover has a window
/// to move first responder inside. Both are SwiftUI placing the editor's
/// AppKit view at a moment the popover has not finished arranging itself.
///
/// An `NSTextView` placed directly is this app's answer for text anyway — the
/// page is one — and it makes all three of the card's problems answerable
/// rather than negotiable: where the text sits, where the caret sits, and
/// what has focus.
struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    /// Focus on the first appearance only. A note being read is not a note
    /// being retyped, and stealing first responder on every SwiftUI pass
    /// would fight the writer moving between cards.
    let focusesOnAppear: Bool
    /// Whether there is more of this note than the box shows, so the card can
    /// say so. A note clipped in silence reads as a note that ends there.
    let onOverflowChange: (Bool) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PlaceholderTextView()
        textView.delegate = context.coordinator
        textView.placeholder = placeholder
        textView.string = text
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        // The words start where the box starts. The default four points of
        // line-fragment padding is what an overlaid placeholder could never
        // guess at; owning the text view means there is nothing to guess.
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        context.coordinator.textView = textView
        context.coordinator.scrollView = scroll
        return scroll
    }

    /// Whether the note is taller than the box it is shown in.
    private static func overflows(_ scroll: NSScrollView) -> Bool {
        guard let document = scroll.documentView else { return false }
        return document.frame.height > scroll.contentView.bounds.height + 1
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        // Only when it really differs: assigning `string` collapses the
        // selection, so echoing the writer's own keystroke back at them
        // would send the caret to the end of every line they edit.
        if textView.string != text { textView.string = text }

        // Reported after the layout pass that this update causes, or the
        // document view still has its previous height.
        DispatchQueue.main.async {
            onOverflowChange(Self.overflows(scroll))
        }

        guard focusesOnAppear, !context.coordinator.hasFocused else { return }
        // On the next turn, because the popover's window does not exist until
        // it has finished showing — and first responder needs a window.
        context.coordinator.hasFocused = true
        DispatchQueue.main.async {
            guard let window = textView.window else { return }
            window.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        weak var textView: NSTextView?
        weak var scrollView: NSScrollView?
        var hasFocused = false

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }
    }
}

/// An `NSTextView` that says what it is for while it is empty.
///
/// Drawn by the text view itself, at its own text origin, so the placeholder
/// and the caret cannot disagree about where the first line begins — which
/// they did when the placeholder was a SwiftUI overlay guessing at the
/// editor's insets.
private final class PlaceholderTextView: NSTextView {
    var placeholder: String = "" {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        (placeholder as NSString).draw(at: textContainerOrigin, withAttributes: attributes)
    }
}
