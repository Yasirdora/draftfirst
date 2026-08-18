import UIKit

/// The element selector as a UIKit menu button: a glass pill showing the
/// active element (symbol leads, name follows in secondary — no chevron).
/// Tap presents the element menu through UIKit's window-level presentation;
/// the pill morphs into the open menu and input is captured until dismissal.
///
/// The row carries only three circles besides the pill, so even the longest
/// kind name ("Parenthetical") fits at full size on the narrowest phone —
/// no truncation, no wrapping.
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

        var config = UIButton.Configuration.glass()
        config.image = UIImage(systemName: activeKind.symbol, withConfiguration: ChromeMetrics.symbol)
        config.imagePadding = 6
        var title = AttributedString(activeKind.shortTitle)
        title.foregroundColor = .secondaryLabel
        title.font = .systemFont(ofSize: 17, weight: .medium)
        config.attributedTitle = title
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16)
        config.background.cornerRadius = ChromeMetrics.controlSize / 2
        configuration = config

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
