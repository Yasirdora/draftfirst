import SwiftUI
import UIKit

/// The editor's command row: (back) (element selector) … (undo/redo)
/// (document menu) — three circles and one pill, nothing else. Back sits
/// top-left and actions cluster right, the idiom of Apple's own document
/// apps; the Navigator lives inside the document menu, which keeps the row
/// calm and gives the pill room for even the longest element name.
///
/// The controls are genuine UIKit buttons hosted in SwiftUI. A SwiftUI Menu
/// presented from page content takes iOS 26's broken reparenting path (the
/// source button stays visible behind the open menu and taps fall through to
/// whatever sits underneath), while the toolbar alternative lets DocumentGroup
/// inject its own chrome. UIKit button menus present through the system
/// window-level path from any host view: the source morphs into the open
/// menu and input is captured until it dismisses, which is exactly the
/// behavior of Apple's own apps — so the document menu is a UIMenu on the
/// ellipsis button, morphing from its source like Pages' does.
struct EditorChrome: UIViewRepresentable {
    let editor: EditorState
    let closeDocument: () -> Void
    let showStory: () -> Void
    let showTitlePage: () -> Void
    let showSettings: () -> Void
    /// Appearance changes route through EditorView's own @AppStorage
    /// mutation: a raw UserDefaults write from UIKit is not guaranteed to
    /// reach SwiftUI's observation, which is why a menu-picked theme used
    /// to do nothing.
    let setAppearance: (AppearancePreference) -> Void

    // Plain tracked values, read in EditorView's body, so SwiftUI calls
    // updateUIView whenever any of them changes.
    let activeKind: ScreenplayKind
    let contextualKinds: [ScreenplayKind]
    let canUndo: Bool
    let canRedo: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    /// The row has exactly one natural height; without this the representable
    /// would accept the full proposed height and the safe-area inset would
    /// swallow the writing surface.
    func sizeThatFits(
        _ proposal: ProposedViewSize,
        uiView: UIStackView,
        context: Context
    ) -> CGSize? {
        CGSize(
            width: proposal.width ?? UIView.noIntrinsicMetric,
            height: ChromeMetrics.controlSize
        )
    }

    func makeUIView(context: Context) -> UIStackView {
        let coordinator = context.coordinator

        let back = ChromeButton.circle(
            systemName: "chevron.left",
            label: "All Screenplays",
            hint: "Closes this screenplay and returns to Documents",
            target: coordinator,
            action: #selector(Coordinator.backTapped)
        )

        let element = ElementModeButton()
        element.onSelect = { [weak coordinator] kind in
            guard let coordinator else { return }
            coordinator.chrome.editor.onChangeElementKind?(kind)
            UISelectionFeedbackGenerator().selectionChanged()
        }

        let undo = ChromeButton.circle(
            systemName: "arrow.uturn.backward",
            label: "Undo",
            // The long-press-for-redo hint is set in updateUIView, where
            // it can be withdrawn whenever Redo is not actually offered.
            hint: nil,
            target: coordinator,
            action: #selector(Coordinator.undoTapped)
        )
        // Tap undoes; a long press presents the menu (Redo) — the same idiom
        // as Safari's back button.
        undo.showsMenuAsPrimaryAction = false

        let settings = ChromeButton.circle(
            systemName: "ellipsis",
            label: "Document Menu",
            hint: nil,
            target: coordinator,
            action: #selector(Coordinator.settingsTapped)
        )
        // The menu is the action: tapping morphs the button into the open
        // document menu, exactly like Pages' ellipsis.
        settings.showsMenuAsPrimaryAction = true

        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [back, element, spacer, undo, settings])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = ChromeMetrics.spacing

        coordinator.elementButton = element
        coordinator.undoButton = undo
        coordinator.settingsButton = settings
        return row
    }

    func updateUIView(_ row: UIStackView, context: Context) {
        let coordinator = context.coordinator
        coordinator.chrome = self
        coordinator.elementButton?.update(
            activeKind: activeKind,
            contextualKinds: contextualKinds
        )
        coordinator.settingsButton?.menu = coordinator.settingsMenu()
        guard let undo = coordinator.undoButton else { return }

        // Enabled whenever either direction exists: a disabled UIButton cannot
        // present its menu, so gating on canUndo alone would strand Redo
        // exactly when it is the only thing available. In that redo-only
        // state the button must not be inert or dishonest — the tap redoes
        // (see undoTapped) and the glyph and label say so.
        let redoOnly = !canUndo && canRedo
        undo.isEnabled = canUndo || canRedo
        var config = undo.configuration
        config?.image = UIImage(
            systemName: redoOnly ? "arrow.uturn.forward" : "arrow.uturn.backward",
            withConfiguration: ChromeMetrics.symbol
        )
        config?.baseForegroundColor = canUndo || redoOnly ? .label : .secondaryLabel
        undo.configuration = config
        undo.accessibilityLabel = redoOnly ? "Redo" : "Undo"
        // The long-press menu exists only when it offers a real action.
        // In redo-only mode the counterpart (Undo) is unavailable by
        // definition — that is what redo-only means — so any menu there
        // could only ever hold a permanently disabled item, which reads
        // as broken. The same goes for a grayed-out Redo before anything
        // has been undone. No actionable counterpart, no menu; the tap
        // still carries whichever direction is live.
        let redoAvailableOnLongPress = !redoOnly && canRedo
        undo.menu = redoAvailableOnLongPress
            ? UIMenu(children: [
                UIAction(
                    title: "Redo",
                    image: UIImage(systemName: "arrow.uturn.forward")
                ) { [weak coordinator] _ in
                    coordinator?.chrome.editor.redo()
                }
            ])
            : nil
        // VoiceOver gets the same rule: the rotor offers Redo only when
        // the menu would, and the hint never promises a menu that is
        // not there.
        undo.accessibilityHint = redoAvailableOnLongPress ? "Long press for redo" : nil
        undo.accessibilityCustomActions = redoAvailableOnLongPress
            ? [
                UIAccessibilityCustomAction(name: "Redo") { [weak coordinator] _ in
                    guard let coordinator, coordinator.chrome.canRedo else { return false }
                    coordinator.chrome.editor.redo()
                    return true
                }
            ]
            : []
    }

    @MainActor
    final class Coordinator {
        var chrome: EditorChrome
        var elementButton: ElementModeButton?
        var undoButton: UIButton?
        var settingsButton: UIButton?

        init(_ chrome: EditorChrome) {
            self.chrome = chrome
        }

        @objc func backTapped() { chrome.closeDocument() }
        @objc func storyTapped() { chrome.showStory() }
        // Primary-action menus still deliver the target action; the tap only
        // ever presents the menu, so this stays empty by design.
        @objc func settingsTapped() {}
        // The button is enabled in the redo-only state so its menu stays
        // reachable; in that state the tap itself redoes instead of sitting
        // inert. A plain canUndo gate would make Redo unreachable exactly
        // when it is the only available action.
        @objc func undoTapped() {
            if chrome.canUndo { chrome.editor.undo() }
            else if chrome.canRedo { chrome.editor.redo() }
        }

        // MARK: Document menu

        /// Five focused destinations, one door to everything else:
        /// Navigator, Title Page, Export, Print, Appearance — and Settings
        /// for the preferences a writer touches once (suggestions, page
        /// size, rename, feedback, about).
        func settingsMenu() -> UIMenu {
            // No trailing ellipses: modern iOS menus drop them (the HIG
            // reserves "…" for legacy AppKit menus), and every row here
            // opens its destination directly.
            let navigator = UIAction(
                title: "Navigator", image: UIImage(systemName: "map")
            ) { [weak self] _ in
                self?.chrome.showStory()
            }
            let titlePage = UIAction(
                title: "Title Page", image: UIImage(systemName: "doc.text")
            ) { [weak self] _ in
                self?.chrome.showTitlePage()
            }
            let documentGroup = UIMenu(
                title: "", options: .displayInline, children: [navigator, titlePage]
            )

            let export = UIMenu(
                title: "Export & Send", image: UIImage(systemName: "square.and.arrow.up"),
                children: [
                    exportAction("eDraft Document", ext: "draft") {
                        Data(ScreenplayExporter.fountainSource($0).utf8)
                    },
                    exportAction("PDF", ext: "pdf") {
                        ScreenplayExporter.pdfData($0)
                    },
                    exportAction("Fountain", ext: "fountain") {
                        Data(ScreenplayExporter.fountainSource($0).utf8)
                    },
                    exportAction("Rich Text (RTF)", ext: "rtf") {
                        ScreenplayExporter.rtfData($0)
                    },
                    exportAction("Plain Text", ext: "txt") {
                        Data(ScreenplayExporter.plainText($0).utf8)
                    }
                ]
            )
            let print = UIAction(
                title: "Print", image: UIImage(systemName: "printer")
            ) { [weak self] _ in
                self?.printDocument()
            }
            let exportGroup = UIMenu(
                title: "", options: .displayInline, children: [export, print]
            )

            let storedAppearance = AppearancePreference(
                rawValue: UserDefaults.standard.string(forKey: "appearance") ?? ""
            ) ?? .dark
            let appearance = UIMenu(
                title: "Appearance", image: UIImage(systemName: "circle.lefthalf.filled"),
                children: AppearancePreference.allCases.map { option in
                    UIAction(
                        title: option.title,
                        state: storedAppearance == option ? .on : .off
                    ) { [weak self] _ in
                        self?.chrome.setAppearance(option)
                    }
                }
            )
            let viewGroup = UIMenu(
                title: "", options: .displayInline, children: [appearance]
            )

            let settings = UIAction(
                title: "Settings", image: UIImage(systemName: "gear")
            ) { [weak self] _ in
                self?.chrome.showSettings()
            }
            let settingsGroup = UIMenu(
                title: "", options: .displayInline, children: [settings]
            )

            return UIMenu(children: [documentGroup, exportGroup, viewGroup, settingsGroup])
        }

        private func exportAction(
            _ title: String, ext: String,
            _ make: @escaping (Screenplay) -> Data?
        ) -> UIAction {
            UIAction(title: title) { [weak self] _ in
                guard let self, let data = make(self.chrome.editor.screenplay) else { return }
                self.share(data: data, extension: ext)
            }
        }

        // MARK: Presentations

        /// The topmost presenter in the button's window, so alerts and share
        /// sheets appear above everything — including our own panels.
        private func topViewController() -> UIViewController? {
            var controller = settingsButton?.window?.rootViewController
            while let presented = controller?.presentedViewController {
                controller = presented
            }
            return controller
        }

        private func share(data: Data, extension ext: String) {
            let editor = chrome.editor
            guard let url = try? ScreenplayExporter.temporaryFile(
                named: editor.screenplay.title, extension: ext, contents: data
            ), let presenter = topViewController() else { return }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.popoverPresentationController?.sourceView = settingsButton
            presenter.present(activity, animated: true)
        }

        private func printDocument() {
            let editor = chrome.editor
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo.printInfo()
            info.jobName = editor.screenplay.title
            info.outputType = .general
            controller.printInfo = info
            controller.printingItem = ScreenplayExporter.pdfData(editor.screenplay)
            // present(animated:) is iPhone-only; on iPad it raises an
            // exception — the print sheet must anchor to a source rect.
            if UIDevice.current.userInterfaceIdiom == .pad, let anchor = settingsButton {
                controller.present(from: anchor.bounds, in: anchor, animated: true)
            } else {
                controller.present(animated: true)
            }
        }
    }
}

enum ChromeMetrics {
    /// The 44 pt top-bar control size measured from Apple's own iOS chrome.
    static let controlSize: CGFloat = 44
    /// Rendered air between separate capsules — 10 pt keeps five controls
    /// breathable without crowding the element pill.
    static let spacing: CGFloat = 10
    /// One uniform glyph: 18 pt medium, matching Apple's top bars.
    static let symbol = UIImage.SymbolConfiguration(font: .systemFont(ofSize: 18, weight: .medium))
}

enum ChromeButton {
    /// A 44 pt circular glass button — the native top-bar control. The system
    /// owns the glass material, press feedback, and hit testing.
    static func circle(
        systemName: String,
        label: String,
        hint: String?,
        target: AnyObject,
        action: Selector
    ) -> UIButton {
        var config = UIButton.Configuration.glass()
        config.image = UIImage(systemName: systemName, withConfiguration: ChromeMetrics.symbol)
        config.background.cornerRadius = ChromeMetrics.controlSize / 2
        let button = UIButton(configuration: config)
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: ChromeMetrics.controlSize),
            button.heightAnchor.constraint(equalToConstant: ChromeMetrics.controlSize)
        ])
        button.addTarget(target, action: action, for: .touchUpInside)
        button.accessibilityLabel = label
        button.accessibilityHint = hint
        return button
    }
}
