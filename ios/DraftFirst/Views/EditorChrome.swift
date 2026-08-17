import SwiftUI
import UIKit

/// The editor's commands as genuine system-toolbar content: (back) on the
/// leading edge, (element selector) as the principal item, (undo/redo) and
/// (document menu) trailing — the idiom of Apple's own document apps.
///
/// The header itself is no longer ours to draw. Every hand-rolled backdrop
/// we tried — bar materials, masked blurs, glass sheets — read as a band
/// because none of them ARE the platform's treatment. The controls now live
/// in the real navigation bar, so the header is iOS's own transparent
/// glass on every device, forever in lockstep with the system.
///
/// The controls stay genuine UIKit buttons hosted per toolbar slot: a
/// SwiftUI Menu presented from page content takes iOS 26's broken
/// reparenting path (the source button stays visible behind the open menu
/// and taps fall through to whatever sits underneath), while UIKit button
/// menus present through the system window-level path — the source morphs
/// into the open menu and input is captured until it dismisses, exactly
/// like Pages' ellipsis.

/// Everything a toolbar control needs, as one value. Its fields are read in
/// EditorView's body, so SwiftUI re-renders the controls whenever any of
/// them changes.
struct EditorChrome {
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

    let activeKind: ScreenplayKind
    let contextualKinds: [ScreenplayKind]
    let canUndo: Bool
    let canRedo: Bool
}

/// One coordinator per control. Coordinators share nothing: each only
/// serves its own button, so per-slot instances keep the wiring local.
@MainActor
final class ChromeCoordinator {
    var chrome: EditorChrome
    /// The control's own button — the anchor for share popovers, the print
    /// sheet, and the topmost-presenter walk.
    var button: UIButton?

    init(chrome: EditorChrome) { self.chrome = chrome }

    @objc func backTapped() { chrome.closeDocument() }
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
            title: "Navigator", image: UIImage(systemName: "safari")
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
        var controller = button?.window?.rootViewController
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
        activity.popoverPresentationController?.sourceView = button
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
        if UIDevice.current.userInterfaceIdiom == .pad, let anchor = button {
            controller.present(from: anchor.bounds, in: anchor, animated: true)
        } else {
            controller.present(animated: true)
        }
    }
}

/// Shared sizing for a fixed 44 pt control: without it the representable
/// would accept the bar's full proposed extent.
private func controlSizeThatFits(
    _ proposal: ProposedViewSize, uiView: UIButton
) -> CGSize? {
    CGSize(width: ChromeMetrics.controlSize, height: ChromeMetrics.controlSize)
}

/// The leading back button.
struct BackToolbarControl: UIViewRepresentable {
    let chrome: EditorChrome

    func makeCoordinator() -> ChromeCoordinator { ChromeCoordinator(chrome: chrome) }

    func makeUIView(context: Context) -> UIButton {
        let button = ChromeButton.circle(
            systemName: "chevron.left",
            label: "All Screenplays",
            hint: "Closes this screenplay and returns to Documents",
            target: context.coordinator,
            action: #selector(ChromeCoordinator.backTapped)
        )
        context.coordinator.button = button
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.chrome = chrome
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        controlSizeThatFits(proposal, uiView: uiView)
    }
}

/// The principal element selector: a glass pill showing the active element.
struct ElementToolbarControl: UIViewRepresentable {
    let chrome: EditorChrome

    func makeCoordinator() -> ChromeCoordinator { ChromeCoordinator(chrome: chrome) }

    func makeUIView(context: Context) -> ElementModeButton {
        let button = ElementModeButton()
        button.onSelect = { [weak coordinator = context.coordinator] kind in
            guard let coordinator else { return }
            coordinator.chrome.editor.onChangeElementKind?(kind)
            UISelectionFeedbackGenerator().selectionChanged()
        }
        context.coordinator.button = button
        return button
    }

    func updateUIView(_ button: ElementModeButton, context: Context) {
        context.coordinator.chrome = chrome
        button.update(activeKind: chrome.activeKind, contextualKinds: chrome.contextualKinds)
    }

    /// The pill hugs its content up to whatever width the principal slot
    /// offers; the slot's own layout truncates beyond that.
    func sizeThatFits(
        _ proposal: ProposedViewSize, uiView: ElementModeButton, context: Context
    ) -> CGSize? {
        let content = uiView.sizeThatFits(UIView.layoutFittingCompressedSize)
        return CGSize(
            width: min(content.width, proposal.width ?? .greatestFiniteMagnitude),
            height: ChromeMetrics.controlSize
        )
    }
}

/// The trailing undo button: tap undoes, long press offers Redo — the same
/// idiom as Safari's back button.
struct UndoToolbarControl: UIViewRepresentable {
    let chrome: EditorChrome

    func makeCoordinator() -> ChromeCoordinator { ChromeCoordinator(chrome: chrome) }

    func makeUIView(context: Context) -> UIButton {
        let button = ChromeButton.circle(
            systemName: "arrow.uturn.backward",
            label: "Undo",
            // The long-press-for-redo hint is set in updateUIView, where
            // it can be withdrawn whenever Redo is not actually offered.
            hint: nil,
            target: context.coordinator,
            action: #selector(ChromeCoordinator.undoTapped)
        )
        button.showsMenuAsPrimaryAction = false
        context.coordinator.button = button
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        let coordinator = context.coordinator
        coordinator.chrome = chrome

        // Enabled whenever either direction exists: a disabled UIButton cannot
        // present its menu, so gating on canUndo alone would strand Redo
        // exactly when it is the only thing available. In that redo-only
        // state the button must not be inert or dishonest — the tap redoes
        // (see undoTapped) and the glyph and label say so.
        let redoOnly = !chrome.canUndo && chrome.canRedo
        button.isEnabled = chrome.canUndo || chrome.canRedo
        var config = button.configuration
        config?.image = UIImage(
            systemName: redoOnly ? "arrow.uturn.forward" : "arrow.uturn.backward",
            withConfiguration: ChromeMetrics.symbol
        )
        config?.baseForegroundColor = chrome.canUndo || redoOnly ? .label : .secondaryLabel
        button.configuration = config
        button.accessibilityLabel = redoOnly ? "Redo" : "Undo"
        // The long-press menu exists only when it offers a real action.
        // In redo-only mode the counterpart (Undo) is unavailable by
        // definition — that is what redo-only means — so any menu there
        // could only ever hold a permanently disabled item, which reads
        // as broken. The same goes for a grayed-out Redo before anything
        // has been undone. No actionable counterpart, no menu; the tap
        // still carries whichever direction is live.
        let redoAvailableOnLongPress = !redoOnly && chrome.canRedo
        button.menu = redoAvailableOnLongPress
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
        button.accessibilityHint = redoAvailableOnLongPress ? "Long press for redo" : nil
        button.accessibilityCustomActions = redoAvailableOnLongPress
            ? [
                UIAccessibilityCustomAction(name: "Redo") { [weak coordinator] _ in
                    guard let coordinator, coordinator.chrome.canRedo else { return false }
                    coordinator.chrome.editor.redo()
                    return true
                }
            ]
            : []
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        controlSizeThatFits(proposal, uiView: uiView)
    }
}

/// The trailing document menu: tapping morphs the button into the open
/// menu, exactly like Pages' ellipsis.
struct SettingsToolbarControl: UIViewRepresentable {
    let chrome: EditorChrome

    func makeCoordinator() -> ChromeCoordinator { ChromeCoordinator(chrome: chrome) }

    func makeUIView(context: Context) -> UIButton {
        let button = ChromeButton.circle(
            systemName: "ellipsis",
            label: "Document Menu",
            hint: nil,
            target: context.coordinator,
            action: #selector(ChromeCoordinator.settingsTapped)
        )
        button.showsMenuAsPrimaryAction = true
        context.coordinator.button = button
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.chrome = chrome
        button.menu = context.coordinator.settingsMenu()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIButton, context: Context) -> CGSize? {
        controlSizeThatFits(proposal, uiView: uiView)
    }
}

enum ChromeMetrics {
    /// The 44 pt top-bar control size measured from Apple's own iOS chrome.
    static let controlSize: CGFloat = 44
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
