import SwiftUI
import UIKit

/// The editor's chrome, configured straight onto the system navigation
/// item: the platform's own close button leads (DocumentGroup installs it;
/// it stays), the element pill is the title view, and undo + document menu
/// are genuine UIBarButtonItems trailing.
///
/// Earlier iterations drew our own glass buttons inside SwiftUI toolbar
/// slots. In DocumentGroup's bar that produced a second glass layer around
/// each control — the bar wraps items in its own treatment, so our
/// UIButton.Configuration.glass() rendered a tile inside a ring — and the
/// system's compact document-menu chevron floated beside the pill with no
/// SwiftUI surface able to retire it. Genuine bar items render through the
/// system's own glass treatment — one layer, always in lockstep with the
/// platform — and retiring the chevron is a plain property write
/// (documentProperties / titleMenuProvider), not a fight with the bar.
///
/// Menus stay UIKit-owned: presentation goes through the system
/// window-level path, the source morphs into the open menu, and input is
/// captured until dismissal — exactly like Pages' controls.

/// Everything the chrome needs, as one value. Its fields are read in
/// EditorView's body, so SwiftUI re-renders and re-applies the chrome
/// whenever any of them changes.
struct EditorChrome {
    let editor: EditorState
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

/// Owns the bar controls and applies them to the editor's navigation item.
/// One instance per editor, created by EditorBarConfigurator.
@MainActor
final class ChromeCoordinator {
    var chrome: EditorChrome
    /// The zero-size anchor planted in the editor's view hierarchy; the
    /// responder-chain walk to the navigation item starts here.
    weak var anchorView: UIView?

    /// The inputs each control last rendered. SwiftUI re-runs the update
    /// pass on every editor change — every keystroke is one — and rewriting
    /// an item's image or replacing its menu mid-gesture tears an in-flight
    /// press or silently dismisses the open menu. chrome itself refreshes
    /// every pass (menu actions read it at invocation time, so cached menus
    /// act on live state); only the visible writes are gated on these.
    private var lastUndoSignature: (canUndo: Bool, canRedo: Bool)?
    private var lastMenuAppearance: AppearancePreference?

    // The controls are created once and mutated in place: identity matters,
    // because replacing an item's menu while it is presented kills the
    // presentation.
    let elementButton = ElementModeButton()

    /// Tap undoes (or redoes in the redo-only state, so the item is never
    /// inert); a long press offers Redo when that direction is live — the
    /// same idiom as Safari's back button, delivered by the system itself.
    lazy var undoItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.backward"),
            primaryAction: UIAction { [weak self] _ in self?.undoPrimary() },
            menu: nil
        )
        item.accessibilityLabel = "Undo"
        return item
    }()

    /// Menu-only item: the tap presents the document menu directly.
    lazy var settingsItem: UIBarButtonItem = {
        let item = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), menu: nil)
        item.accessibilityLabel = "Document Menu"
        return item
    }()

    /// The seam between the two trailing items: without it iOS 26 fuses
    /// adjacent items into one capsule; a fixed space splits them into
    /// separate circles, matching the system's own inter-group gap.
    private let trailingSpacer: UIBarButtonItem = {
        let spacer = UIBarButtonItem(systemItem: .fixedSpace)
        spacer.width = 8
        return spacer
    }()

    init(chrome: EditorChrome) {
        self.chrome = chrome
        elementButton.onSelect = { [weak self] kind in
            guard let self else { return }
            self.chrome.editor.onChangeElementKind?(kind)
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    // MARK: Navigation item

    /// Applies the chrome to the owning navigation item. Returns false when
    /// the view hierarchy has not attached far enough to find it yet — the
    /// anchor retries briefly; afterwards every SwiftUI update pass
    /// re-applies, which also re-retires any document chrome the system
    /// re-installs.
    @discardableResult
    func configureNavigationItemIfPossible() -> Bool {
        guard let controller = owningViewController() else { return false }
        let item = controller.navigationItem

        // Retire the compact document-menu chevron DocumentGroup installs:
        // with a custom title view in place, its document-properties menu
        // renders as a floating chevron circle between the pill and the
        // trailing items. Rename already lives in Settings, so the menu has
        // no unique job in this bar.
        if item.documentProperties != nil { item.documentProperties = nil }
        if item.titleMenuProvider != nil { item.titleMenuProvider = nil }
        // The center slot is ours alone; anything the system parked there
        // (the compact document menu) goes. Leading groups are untouched —
        // that is where the system's close button lives.
        if !item.centerItemGroups.isEmpty { item.centerItemGroups = [] }

        if item.titleView !== elementButton { item.titleView = elementButton }
        elementButton.update(
            activeKind: chrome.activeKind, contextualKinds: chrome.contextualKinds
        )

        // First element is rightmost: [undo] [settings] left to right, with
        // a fixed space between them so they render as two circles.
        let trailing = [settingsItem, trailingSpacer, undoItem]
        if item.rightBarButtonItems != trailing { item.rightBarButtonItems = trailing }
        updateUndoItem()
        updateSettingsMenu()
#if DEBUG
        writeBarXrayFile(controller: controller, item: item)
#endif
        return true
    }

    private func owningViewController() -> UIViewController? {
        var responder: UIResponder? = anchorView?.next
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }

    private func undoPrimary() {
        if chrome.canUndo { chrome.editor.undo() }
        else if chrome.canRedo { chrome.editor.redo() }
    }

    private func updateUndoItem() {
        let signature = (canUndo: chrome.canUndo, canRedo: chrome.canRedo)
        if let last = lastUndoSignature, last == signature { return }
        lastUndoSignature = signature

        // Enabled whenever either direction exists: a disabled item cannot
        // present its long-press menu, so gating on canUndo alone would
        // strand Redo exactly when it is the only thing available. In the
        // redo-only state the item must not be inert or dishonest — the tap
        // redoes (see undoPrimary) and the glyph and label say so.
        let redoOnly = !chrome.canUndo && chrome.canRedo
        undoItem.isEnabled = chrome.canUndo || chrome.canRedo
        undoItem.image = UIImage(
            systemName: redoOnly ? "arrow.uturn.forward" : "arrow.uturn.backward"
        )
        undoItem.accessibilityLabel = redoOnly ? "Redo" : "Undo"
        // The long-press menu exists only when it offers a real action.
        // In redo-only mode the counterpart (Undo) is unavailable by
        // definition, and before anything has been undone there is no Redo —
        // a permanently disabled menu there reads as broken. No actionable
        // counterpart, no menu; the tap still carries the live direction.
        let redoAvailableOnLongPress = !redoOnly && chrome.canRedo
        undoItem.menu = redoAvailableOnLongPress
            ? UIMenu(children: [
                UIAction(
                    title: "Redo",
                    image: UIImage(systemName: "arrow.uturn.forward")
                ) { [weak self] _ in
                    self?.chrome.editor.redo()
                }
            ])
            : nil
        // VoiceOver gets the same rule: the rotor offers Redo only when the
        // menu would, and the hint never promises a menu that is not there.
        undoItem.accessibilityHint = redoAvailableOnLongPress ? "Long press for redo" : nil
        undoItem.accessibilityCustomActions = redoAvailableOnLongPress
            ? [
                UIAccessibilityCustomAction(name: "Redo") { [weak self] _ in
                    guard let self, self.chrome.canRedo else { return false }
                    self.chrome.editor.redo()
                    return true
                }
            ]
            : []
    }

    private func updateSettingsMenu() {
        // The menu's structure depends only on the stored appearance (the
        // checkmarks); every action reads chrome when invoked, so a cached
        // menu still acts on live state. Rebuilding it on every pass would
        // dismiss the menu while it is open.
        let storedAppearance = AppearancePreference(
            rawValue: UserDefaults.standard.string(forKey: "appearance") ?? ""
        ) ?? .dark
        guard storedAppearance != lastMenuAppearance else { return }
        lastMenuAppearance = storedAppearance
        settingsItem.menu = settingsMenu()
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

        var children: [UIMenuElement] = [documentGroup, exportGroup, viewGroup, settingsGroup]
        return UIMenu(children: children)
    }

#if DEBUG
    /// A full x-ray of the navigation item and the bar's view tree, written
    /// to Documents/bar-xray.txt so it can be pulled from a device with
    /// devicectl. DocumentGroup's bar is not a UINavigationController's
    /// (navigationController is nil in the editor), so the tree walk starts
    /// from our own pill and climbs to the window: the ancestor chain names
    /// the bar's real class, and the bar-level subtree — with frames,
    /// visibility, and accessibility labels — identifies any
    /// system-injected control outright. Debug builds only.
    private func writeBarXrayFile(controller: UIViewController, item: UINavigationItem) {
        var lines: [String] = []
        lines.append("title: \(item.title ?? "nil")")
        lines.append("titleView: \(item.titleView.map { String(describing: type(of: $0)) } ?? "nil") frame=\(item.titleView?.frame ?? .zero)")
        lines.append("documentProperties: \(item.documentProperties == nil ? "no" : "yes")")
        lines.append("titleMenuProvider: \(item.titleMenuProvider == nil ? "no" : "yes")")
        lines.append("leftBarButtonItems: \(describe(item.leftBarButtonItems))")
        lines.append("rightBarButtonItems: \(describe(item.rightBarButtonItems))")
        lines.append("groups leading=\(item.leadingItemGroups.count) center=\(item.centerItemGroups.count) trailing=\(item.trailingItemGroups.count)")
        lines.append("navigationController: \(controller.navigationController == nil ? "nil" : "present")")
        lines.append("--- pill ancestors (pill → window) ---")
        var ancestors: [UIView] = []
        var cursor: UIView? = elementButton.superview
        while let view = cursor {
            ancestors.append(view)
            cursor = view.superview
        }
        for (index, view) in ancestors.enumerated() {
            lines.append("[\(index)] \(describe(view))")
        }
        if let windowIndex = ancestors.firstIndex(where: { $0 is UIWindow }), windowIndex > 0 {
            lines.append("--- bar subtree ---")
            dumpBarView(ancestors[windowIndex - 1], depth: 0, into: &lines)
        }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("bar-xray.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private func describe(_ view: UIView) -> String {
        let f = view.frame
        var line = "\(type(of: view)) f=(\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)))"
        if view.isHidden || view.alpha < 0.05 { line += " HIDDEN" }
        if let label = view.accessibilityLabel, !label.isEmpty { line += " a11y=\"\(label)\"" }
        if let label = view as? UILabel, let text = label.text { line += " text=\"\(text)\"" }
        if let button = view as? UIButton, let title = button.currentTitle { line += " title=\"\(title)\"" }
        return line
    }

    private func describe(_ items: [UIBarButtonItem]?) -> String {
        guard let items else { return "nil" }
        return "["
            + items.map { "\($0.title ?? $0.accessibilityLabel ?? "-"):\(type(of: $0)) customView=\($0.customView.map { String(describing: type(of: $0)) } ?? "nil")" }
                .joined(separator: " | ")
            + "]"
    }

    private func dumpBarView(_ view: UIView, depth: Int, into lines: inout [String]) {
        let indent = String(repeating: "  ", count: min(depth, 12))
        lines.append(indent + describe(view))
        for subview in view.subviews { dumpBarView(subview, depth: depth + 1, into: &lines) }
    }
#endif

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

    /// The topmost presenter in the editor's window, so alerts and share
    /// sheets appear above everything — including our own panels.
    private func topViewController() -> UIViewController? {
        var controller = anchorView?.window?.rootViewController
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
        activity.popoverPresentationController?.barButtonItem = settingsItem
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
        // exception — the print sheet must anchor to the source item.
        if UIDevice.current.userInterfaceIdiom == .pad {
            controller.present(from: settingsItem, animated: true)
        } else {
            controller.present(animated: true)
        }
    }
}

/// A zero-size view planted in the editor's hierarchy. Its only job is to
/// reach the owning navigation item through the responder chain and hand it
/// to the coordinator — genuine UIBarButtonItems and a UIKit title view,
/// applied idempotently on every pass.
struct EditorBarConfigurator: UIViewRepresentable {
    let chrome: EditorChrome

    func makeCoordinator() -> ChromeCoordinator { ChromeCoordinator(chrome: chrome) }

    func makeUIView(context: Context) -> BarAnchorView {
        let view = BarAnchorView()
        context.coordinator.anchorView = view
        view.coordinator = context.coordinator
        return view
    }

    func updateUIView(_ view: BarAnchorView, context: Context) {
        context.coordinator.chrome = chrome
        view.configureIfPossible()
    }
}

final class BarAnchorView: UIView {
    weak var coordinator: ChromeCoordinator?
    private var configureAttempts = 0

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { configureIfPossible() }
    }

    /// The first pass can run before the view attaches to a window, so a
    /// bounded async retry covers that ordering; once attached, every
    /// SwiftUI update pass re-applies idempotently.
    func configureIfPossible() {
        guard let coordinator else { return }
        coordinator.anchorView = self
        if coordinator.configureNavigationItemIfPossible() {
            configureAttempts = 0
            return
        }
        guard configureAttempts < 5 else { return }
        configureAttempts += 1
        DispatchQueue.main.async { [weak self] in
            self?.configureIfPossible()
        }
    }
}

enum ChromeMetrics {
    /// The 44 pt top-bar control size measured from Apple's own iOS chrome.
    static let controlSize: CGFloat = 44
    /// One uniform glyph: 18 pt medium, matching Apple's top bars.
    static let symbol = UIImage.SymbolConfiguration(font: .systemFont(ofSize: 18, weight: .medium))
}
