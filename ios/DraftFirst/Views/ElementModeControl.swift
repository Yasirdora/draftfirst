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
    var onSelect: ((ScreenplayKind) -> Void)?
    /// The inputs the control currently displays; see update's idempotence
    /// contract. nil means "never rendered", so the first update always lands.
    private var lastActiveKind: ScreenplayKind?
    private var lastContextualKinds: [ScreenplayKind] = []

    init() {
        super.init(frame: .zero)
        showsMenuAsPrimaryAction = true
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: ChromeMetrics.controlSize).isActive = true
        // The bar's title area negotiates width; the pill never yields its
        // content to it — truncation is the only permitted compromise.
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)
        accessibilityHint = "Tap to choose a screenplay element. Return selects the likely next element."
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ElementModeButton is created in code")
    }

    func update(activeKind: ScreenplayKind, contextualKinds: [ScreenplayKind]) {
        // Idempotent by contract: SwiftUI re-runs updateUIView on every
        // editor render pass (each keystroke is one), and rewriting the
        // configuration or replacing the menu mid-gesture tears an in-flight
        // press or silently dismisses the open menu — the "button reacts
        // but nothing happens" class of bug. Only what the control actually
        // displays may invalidate it.
        guard activeKind != lastActiveKind || contextualKinds != lastContextualKinds else { return }
        lastActiveKind = activeKind
        lastContextualKinds = contextualKinds

        // No background of our own: the bar wraps custom items in its own
        // glass platter, and a second glass layer behind it reads as a
        // double edge. Plain configuration — the platter is the capsule.
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: activeKind.symbol, withConfiguration: ChromeMetrics.symbol)
        config.imagePadding = 6
        var title = AttributedString(activeKind.shortTitle)
        title.foregroundColor = .secondaryLabel
        title.font = .systemFont(ofSize: 17, weight: .medium)
        config.attributedTitle = title
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
        // Never wrap to a second line inside the capsule — if the bar's
        // leading area is tight, the title truncates instead of stacking.
        config.titleLineBreakMode = .byTruncatingTail
        configuration = config
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
