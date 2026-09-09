import AppKit

/// Apple's own soft scroll edge, asked for the way AppKit says to ask.
///
/// `NSScrollEdgeEffectStyle` is declared on accessory view controllers rather
/// than on the scroll view, and there are two of them: one for a titlebar and
/// one for a split view item. The page lives in the detail column of a split
/// view, so it is the second — `NSSplitViewItem.addTopAlignedAccessoryViewController`
/// — that governs how content fades as it scrolls under the chrome above it.
/// The titlebar one was tried first and installs without doing anything,
/// which is what the header documents: it is for the titlebar's own accessory,
/// not for a column's content.
///
/// The accessory shows nothing. It exists to carry one property, so it takes
/// no height and declines the standard insets that would otherwise move the
/// page down to make room for it.
@available(macOS 26.1, *)
final class SoftScrollEdgeAccessory: NSSplitViewItemAccessoryViewController {

    init() {
        super.init(nibName: nil, bundle: nil)
        view = NSView(frame: .zero)
        automaticallyAppliesContentInsets = false
        preferredScrollEdgeEffectStyle = .soft
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SoftScrollEdgeAccessory is created in code")
    }
}
