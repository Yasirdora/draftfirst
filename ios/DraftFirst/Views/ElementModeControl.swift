import UIKit

/// The element selector as a UIKit menu button: an icon + name capsule that
/// lives in the system navigation bar as a custom leading item. The bar
/// wraps custom items in its own glass platter, so the button itself draws
/// no background of its own — one glass layer, rendered by the system,
/// always in lockstep with the platform's look. Tap presents the element
/// menu through UIKit's window-level presentation; the capsule morphs into
/// the open menu and input is captured until dismissal.
///
/// The row carries only three circles besides the capsule, so even the
/// longest kind name ("Parenthetical") fits at full size on the narrowest
/// phone — no truncation, no wrapping.
final class ElementModeButton: UIButton {
    /// What the control is for at this moment. Reading offers the way into
    /// the script; writing names the element under the caret and offers the
    /// others. One control, because they are the same question asked of the
    /// same place — and because a control that never leaves the bar cannot
    /// animate itself in twice on the way back to a document.
    enum Mode: Equatable {
        case reading
        case writing(active: ScreenplayKind, contextual: [ScreenplayKind])
    }

    var onSelect: ((ScreenplayKind) -> Void)?
    var onEdit: (() -> Void)?
    /// What the control currently displays; see update's idempotence
    /// contract. nil means "never rendered", so the first update always lands.
    private var lastMode: Mode?

    init() {
        super.init(frame: .zero)
        showsMenuAsPrimaryAction = true
        // Fires only while the menu is not the primary action — that is, only
        // while reading. One action, gated by the mode rather than added and
        // removed with it.
        addAction(UIAction { [weak self] _ in self?.onEdit?() }, for: .primaryActionTriggered)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: ChromeMetrics.controlSize).isActive = true
        // A trackpad pointer must find this control the way it finds the
        // system's own bar buttons: the capsule lifts under the cursor
        // rather than staying inert. Free on iPhone, essential on iPad.
        isPointerInteractionEnabled = true
        pointerStyleProvider = { button, effect, _ in
            .init(effect: .lift(.init(view: button)))
        }
        // The bar's title area negotiates width; the pill never yields its
        // content to it — truncation is the only permitted compromise.
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ElementModeButton is created in code")
    }

    func update(_ mode: Mode) {
        // Idempotent by contract: SwiftUI re-runs updateUIView on every
        // editor render pass (each keystroke is one), and rewriting the
        // configuration or replacing the menu mid-gesture tears an in-flight
        // press or silently dismisses the open menu — the "button reacts
        // but nothing happens" class of bug. Only what the control actually
        // displays may invalidate it.
        guard mode != lastMode else { return }
        lastMode = mode

        switch mode {
        case .reading:
            showReading()
        case let .writing(activeKind, contextualKinds):
            showWriting(activeKind: activeKind, contextualKinds: contextualKinds)
        }
    }

    /// The way into the script: the same capsule, offering to open it.
    ///
    /// Blue, and the only colour in the bar, because it is the one control a
    /// reader has to be able to find — everything else there acts on a script
    /// they are already writing.
    private func showReading() {
        showsMenuAsPrimaryAction = false
        menu = nil
        configuration = capsule(
            symbol: nil, text: "Edit", glyph: nil, title: .systemBlue
        )
        titleLabel?.numberOfLines = 1
        accessibilityLabel = "Edit Screenplay"
        accessibilityHint = "Opens the script for writing."
    }

    private func showWriting(activeKind: ScreenplayKind, contextualKinds: [ScreenplayKind]) {
        showsMenuAsPrimaryAction = true
        configuration = capsule(
            symbol: activeKind.symbol, text: activeKind.shortTitle,
            glyph: nil, title: .secondaryLabel
        )
        titleLabel?.numberOfLines = 1

        let suggested = contextualKinds.map { menuAction(for: $0, active: activeKind) }
        let remaining = ScreenplayKind.editorKinds
            .filter { !contextualKinds.contains($0) }
            .map { menuAction(for: $0, active: activeKind) }
        menu = UIMenu(children: [
            UIMenu(title: "Suggested", options: .displayInline, children: suggested),
            UIMenu(title: "All Elements", options: .displayInline, children: remaining)
        ])
        accessibilityLabel = "Screenplay element: \(activeKind.title)"
        accessibilityHint = "Tap to choose a screenplay element. Return selects the likely next element."
    }

    /// No background of our own: the bar wraps custom items in its own glass
    /// platter, and a second glass layer behind it reads as a double edge.
    /// Plain configuration — the platter is the capsule.
    ///
    /// A nil `glyph` leaves the symbol in the bar's own colour, which is what
    /// the element selector has always worn; the way in states its colour on
    /// both halves, so the whole capsule reads as one blue control rather
    /// than a blue word beside a black mark.
    private func capsule(
        symbol: String?, text: String, glyph: UIColor?, title titleColor: UIColor
    ) -> UIButton.Configuration {
        var config = UIButton.Configuration.plain()
        let image = symbol.flatMap {
            UIImage(systemName: $0, withConfiguration: ChromeMetrics.symbol)
        }
        config.image = glyph.map { image?.withTintColor($0, renderingMode: .alwaysOriginal) } ?? image
        config.imagePadding = image == nil ? 0 : 6
        var title = AttributedString(text)
        title.foregroundColor = titleColor
        title.font = .systemFont(ofSize: 17, weight: .medium)
        config.attributedTitle = title
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        // Never wrap to a second line inside the capsule — if the bar's
        // leading area is tight, the title truncates instead of stacking.
        config.titleLineBreakMode = .byTruncatingTail
        return config
    }

    private func menuAction(for kind: ScreenplayKind, active: ScreenplayKind) -> UIAction {
        // The icon identifies the element; the selected state alone draws
        // the checkmark. Never trade the icon for a second checkmark.
        UIAction(
            title: kind.title,
            image: UIImage(systemName: kind.symbol),
            state: kind == active ? .on : .off
        ) { [weak self] _ in
            self?.onSelect?(kind)
        }
    }
}
