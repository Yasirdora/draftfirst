import UIKit

/// The brief mark that says *here* when the Navigator sends a reader
/// somewhere.
///
/// Scrolling alone cannot answer "did that work?". A script can only scroll
/// until its last page reaches the bottom, so every target within a screen of
/// the end stops short of the top — tap the last scene of a short script and
/// the page moves a little and leaves the heading in the middle, looking as
/// though the tap went nowhere. A line already on screen moves the page not at
/// all. And while reading there is no caret to mark the landing either, which
/// is why the cast list looked completely dead: its lines are usually already
/// in view.
///
/// So the answer is not to scroll harder. It is to say where you landed —
/// the same thing Xcode's Open Quickly and Pages' navigator do. The mark
/// fades in over the line, holds long enough to be seen, and goes.
///
/// It is a view rather than a background attribute on the text: the text
/// storage is the document, and everything that reads it — the model
/// synchroniser, undo, the pagination — would have to learn that some of its
/// attributes are decoration. A view over the glyphs owes nothing to any of
/// them.
final class RevealHighlightView: UIView {

    /// The Navigator is still sliding away when the mark is asked for, so it
    /// waits for the page to be uncovered before appearing — a mark that
    /// fades in behind a dismissing sheet is a mark the reader never sees.
    private static let wait: TimeInterval = 0.25
    private static let fadeIn: TimeInterval = 0.15
    private static let hold: TimeInterval = 1.0
    private static let fadeOut: TimeInterval = 0.5

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        layer.cornerRadius = 6
        layer.cornerCurve = .continuous
        // Light enough to read straight through — this marks the line, it
        // does not select it.
        backgroundColor = UIColor.tintColor.withAlphaComponent(0.18)
        alpha = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Marks `rect`, in the coordinate space of `textView`'s content.
    ///
    /// Repeated reveals reuse one view, so a reader working quickly down a
    /// list of lines sees the mark move rather than a pile of fading boxes.
    func mark(_ rect: CGRect, in textView: UITextView) {
        guard !rect.isNull, !rect.isEmpty else { return }
        if superview !== textView { textView.addSubview(self) }
        layer.removeAllAnimations()
        frame = rect.insetBy(dx: -6, dy: -2)
        alpha = 0

        UIView.animate(withDuration: Self.fadeIn, delay: Self.wait) {
            self.alpha = 1
        } completion: { finished in
            guard finished else { return }
            UIView.animate(
                withDuration: Self.fadeOut,
                delay: Self.hold,
                options: [.beginFromCurrentState]
            ) {
                self.alpha = 0
            }
        }
    }
}
