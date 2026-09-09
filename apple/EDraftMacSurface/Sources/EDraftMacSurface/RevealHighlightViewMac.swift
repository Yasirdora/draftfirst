import AppKit
import EDraftCore

/// The mark that says *here* when the Navigator sends a reader somewhere.
///
/// The Mac's counterpart to the phone's `RevealHighlightView`, and deliberately
/// the same mark: the timing and the padding come from `RevealMark` in the
/// core, so the two platforms cannot fall out of step about how long a reader
/// is given to find the line they asked for.
///
/// Why the mark exists at all — that scrolling alone cannot answer "did that
/// work?" — is written down once, in `RevealMark`.
public final class RevealHighlightViewMac: NSView {

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = RevealMark.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.36).cgColor
        alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// A mark is decoration over the page, never something to click.
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Text views are flipped, and so is this: a mark whose coordinates ran
    /// the other way would land as far below the line as it should be on it.
    public override var isFlipped: Bool { true }

    /// Marks `rect`, in the coordinates of the view it is drawn into.
    ///
    /// One view is reused, so a reader working quickly down a list of scenes
    /// sees the mark move rather than a drift of fading boxes.
    public func mark(_ rect: CGRect, in host: NSView, reduceMotion: Bool) {
        guard !rect.isNull, rect.height > 0 else { return }
        if superview !== host { host.addSubview(self) }

        frame = rect.insetBy(
            dx: -RevealMark.horizontalPadding, dy: -RevealMark.verticalPadding
        )
        layer?.removeAllAnimations()
        alphaValue = 0

        let timing = RevealMark.timing(reduceMotion: reduceMotion)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = timing.fadeIn
            animator().alphaValue = 1
        } completionHandler: { [weak self] in
            guard let self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + timing.hold) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = timing.fadeOut
                    self.animator().alphaValue = 0
                }
            }
        }
    }
}
