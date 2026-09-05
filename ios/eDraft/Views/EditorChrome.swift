import SwiftUI
import EDraftEngine
import UIKit

/// The editor's chrome, configured straight onto the system navigation
/// item: the platform's own close button leads (DocumentGroup installs it;
/// it stays), the element pill supplements it as a leading bar item, and
/// undo + document menu trail as standard image items. Standard items are
/// the only way to the system's own rendering: the bar draws them as the
/// same perfect glass circles as its close button, spaces them with its
/// own rhythm, and morphs them into their menus — no custom view can
/// negotiate that platter from the outside.
///
/// The title slot stays empty: DocumentGroup draws its document-menu
/// chevron from the bar's title control, and with no title or title view
/// there is no title control — the chevron is gone by construction, never
/// hidden. DocumentGroup re-assigns the file name on its own schedule, so
/// an observation clears any title the instant it appears rather than
/// waiting for the next render pass.
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
    /// Reading or writing. Read from the text surface's own focus, never
    /// kept here — see `EditorState.isEditing`.
    let isEditing: Bool
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
    /// Whether this coordinator has put its items in the bar before. Until it
    /// has, there is no previous state to animate from.
    private var hasConfiguredBar = false

    // The controls are created once and mutated in place: identity matters,
    // because replacing an item's menu while it is presented kills the
    // presentation.
    let elementButton = ElementModeButton()

    /// Tap undoes (or redoes in the redo-only state, so the control is
    /// never inert); a long press offers Redo when that direction is live —
    /// the same idiom as Safari's back button. A standard image item with
    /// a primary action and a menu: the system renders the circle, fires
    /// the tap, and presents the long-press menu itself.
    lazy var undoItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.backward", withConfiguration: ChromeMetrics.symbol),
            primaryAction: UIAction { [weak self] _ in self?.undoPrimary() }
        )
        item.accessibilityLabel = "Undo"
        return item
    }()

    /// Menu-only control: with a menu and no primary action, the system
    /// presents the document menu on tap — the Files "ellipsis" idiom.
    lazy var settingsItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis", withConfiguration: ChromeMetrics.symbol)
        )
        item.accessibilityLabel = "Document Menu"
        return item
    }()

    /// Reading's counterpart to Undo: the same slot beside the menu, holding
    /// the tool that belongs to the mode. Nothing can be undone while reading,
    /// and the Navigator is what a reader reaches for — so the slot carries
    /// the Navigator there and the undo arrow once writing starts.
    lazy var navigatorItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "safari", withConfiguration: ChromeMetrics.symbol),
            primaryAction: UIAction { [weak self] _ in self?.chrome.showStory() }
        )
        item.accessibilityLabel = "Navigator"
        return item
    }()

    /// The element pill as a leading bar item, right after the system's
    /// close button — (back) (element) … (undo) (settings).
    lazy var pillItem: UIBarButtonItem = {
        UIBarButtonItem(customView: elementButton)
    }()

    /// The seam between trailing items: adjacent items fuse into one capsule
    /// on this bar (groups included — verified), so a fixed space splits them
    /// into separate circles at the system's inter-group gap. One instance
    /// per seam, because a bar button item can occupy only one position.
    private let trailingSpacer = ChromeMetrics.seam()

    init(chrome: EditorChrome) {
        self.chrome = chrome
        elementButton.onSelect = { [weak self] kind in
            guard let self else { return }
            self.chrome.editor.onChangeElementKind?(kind)
            UISelectionFeedbackGenerator().selectionChanged()
        }
        elementButton.onEdit = { [weak self] in self?.chrome.editor.beginEditing() }
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

        // The title slot stays empty by design: DocumentGroup draws its
        // document-menu chevron from the bar's title control, and the title
        // control exists only while the item carries a title or a title
        // view. Neither is ever allowed to survive here — the chevron is
        // gone because its host is never created, not because anything is
        // hidden.
        if item.titleView != nil { item.titleView = nil }
        if item.title != nil { item.title = nil }
        enforceEmptyTitle(on: item)
        // Retire DocumentGroup's document-menu sources on the item itself:
        // rename already lives in Settings, so the menu has no unique job
        // in this bar.
        if item.documentProperties != nil { item.documentProperties = nil }
        if item.titleMenuProvider != nil { item.titleMenuProvider = nil }
        if !item.centerItemGroups.isEmpty { item.centerItemGroups = [] }

        // The bar states which of the two things the writer is doing, and
        // says it by what it leaves out.
        //
        // Reading is (close) (Edit) … (menu); writing is (close) (element) …
        // (undo) (menu). The capsule is the same control throughout — the
        // way in while reading, the element selector while writing — so the
        // mode change is a morph in place rather than a control arriving.
        // The undo arrow is the only thing that comes and goes, because an
        // undo arrow for edits not being made describes an activity that is
        // not happening.
        //
        // Nothing floats over the page for this: the way out is the menu,
        // the keyboard's own dismissal, or Escape.
        //
        // Hiding the close button belongs to SwiftUI, not here: it owns this
        // navigation item under DocumentGroup and re-applies its own state
        // every pass, so a UIKit-level `hidesBackButton` is overwritten and
        // the writer gets a back chevron beside the Done tick. EditorView
        // carries `.navigationBarBackButtonHidden` instead.
        //
        // The animated setters are what make the change a morph rather than
        // a swap: the bar cross-fades and re-spaces its own items. They are
        // reached only through the change guards, because this method re-runs
        // on every SwiftUI pass — one per keystroke — and animating an
        // unchanged bar would flicker it under the writer's hands.
        //
        // The first configuration is not a change and is not animated. A
        // screen arriving has no previous state to morph from, and animating
        // there plays the pill into a bar the writer is only now seeing —
        // twice over when a document is opened, closed and opened again,
        // since the item outlives the view that configured it.
        item.leftItemsSupplementBackButton = true
        let animated = hasConfiguredBar
        // Never animated. The capsule is in both modes, so this only ever
        // re-seats an item the system dropped during a transition — and
        // animating that plays the capsule out of the close button's edge, as
        // though it were arriving from inside it.
        let leading = [pillItem]
        if item.leftBarButtonItems ?? [] != leading {
            item.setLeftBarButtonItems(leading, animated: false)
        }
        // The capsule stays; only what it says changes. Reading, it offers
        // the way in; writing, it names the element under the caret.
        elementButton.update(
            chrome.isEditing
                ? .writing(active: chrome.activeKind, contextual: chrome.contextualKinds)
                : .reading
        )

        // First element is rightmost, so both modes read the same way left to
        // right: one tool, then the menu. Writing puts Undo in that slot;
        // reading puts the Navigator in it, where a reader's hand already is.
        // The fixed space between them splits the capsule in two.
        let trailing = chrome.isEditing
            ? [settingsItem, trailingSpacer, undoItem]
            : [settingsItem, trailingSpacer, navigatorItem]
        if item.rightBarButtonItems ?? [] != trailing {
            item.setRightBarButtonItems(trailing, animated: animated)
        }
        hasConfiguredBar = true
        updateUndoButton()
        updateSettingsMenu()
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

    private var titleObservation: NSKeyValueObservation?
    private weak var observedTitleItem: UINavigationItem?

    /// DocumentGroup assigns the file name to the item on its own schedule
    /// (open, rename, save) — never on ours — and any surviving title
    /// recreates the bar's title control, and with it the document-menu
    /// chevron. While title and title view are both nil the control is
    /// never created at all (the x-ray shows the hosted-title container
    /// empty in that state), so the observation clears a title the instant
    /// one appears instead of waiting for the next render pass.
    private func enforceEmptyTitle(on item: UINavigationItem) {
        guard observedTitleItem !== item else { return }
        titleObservation?.invalidate()
        observedTitleItem = item
        titleObservation = item.observe(\.title, options: [.new]) { observedItem, _ in
            guard observedItem.title != nil else { return }
            DispatchQueue.main.async { observedItem.title = nil }
        }
    }

    private func undoPrimary() {
        if chrome.canUndo { chrome.editor.undo() }
        else if chrome.canRedo { chrome.editor.redo() }
    }

    private func updateUndoButton() {
        let signature = (canUndo: chrome.canUndo, canRedo: chrome.canRedo)
        if let last = lastUndoSignature, last == signature { return }
        lastUndoSignature = signature

        // Enabled whenever either direction exists: a disabled item cannot
        // present its long-press menu, so gating on canUndo alone would
        // strand Redo exactly when it is the only thing available. In the
        // redo-only state the control must not be inert or dishonest — the
        // tap redoes (see undoPrimary) and the glyph and label say so.
        let redoOnly = !chrome.canUndo && chrome.canRedo
        undoItem.isEnabled = chrome.canUndo || chrome.canRedo
        undoItem.image = UIImage(
            systemName: redoOnly ? "arrow.uturn.forward" : "arrow.uturn.backward",
            withConfiguration: ChromeMetrics.symbol
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
        // VoiceOver gets the same rule: the hint promises the menu only
        // when a long press would actually present one.
        undoItem.accessibilityHint = redoAvailableOnLongPress ? "Long press for redo" : nil
    }

    private func updateSettingsMenu() {
        // The menu's structure depends only on the stored appearance (the
        // checkmarks); every action reads chrome when invoked, so a cached
        // menu still acts on live state. Rebuilding it on every pass would
        // dismiss the menu while it is open.
        let storedAppearance = AppearancePreference.stored
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

        // Leaving the script is the one row here that is about the moment
        // rather than the document, so it leads — and it is absent while
        // reading, where it would only name the state the writer is already
        // in. Deferred rather than rebuilt: this menu is cached on purpose
        // (rebuilding it dismisses it mid-gesture), and an uncached element
        // is resolved each time the menu opens, which is exactly when the
        // answer can have changed.
        let readingGroup = UIMenu(
            title: "", options: .displayInline,
            children: [
                UIDeferredMenuElement.uncached { [weak self] complete in
                    guard let self, self.chrome.editor.isEditing else { return complete([]) }
                    complete([
                        UIAction(
                            title: "Reading Mode",
                            image: UIImage(systemName: "book")
                        ) { [weak self] _ in
                            self?.chrome.editor.endEditing()
                        }
                    ])
                }
            ]
        )

        // Paper, brought in where the writing is. Two sources and no more:
        // where the pages should land is a better question once there are
        // pages to land, and a scan that comes back unreadable never has to
        // ask it at all.
        let importGroup = UIMenu(
            title: "", options: .displayInline,
            children: [
                UIAction(
                    title: "Import Screenplay",
                    image: UIImage(systemName: "square.and.arrow.down")
                ) { [weak self] _ in
                    self?.addPages(scanning: false)
                },
                UIAction(
                    title: "Scan Screenplay",
                    image: UIImage(systemName: "doc.viewfinder")
                ) { [weak self] _ in
                    self?.addPages(scanning: true)
                }
            ]
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
                exportAction("Final Draft (FDX)", ext: "fdx") {
                    Data(ScreenplayExporter.fdxSource($0).utf8)
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

        let storedAppearance = AppearancePreference.stored
        let appearance = UIMenu(
            title: "Appearance", image: UIImage(systemName: storedAppearance.symbol),
            children: AppearancePreference.allCases.map { option in
                UIAction(
                    title: option.title,
                    image: UIImage(systemName: option.symbol),
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

        return UIMenu(children: [
            readingGroup, documentGroup, importGroup, exportGroup, viewGroup, settingsGroup
        ])
    }

    // MARK: Adding pages

    private func addPages(scanning: Bool) {
        Task { @MainActor in
            let editor = chrome.editor
            let source: String?

            if scanning {
                let pages = await ScanPresenter.shared.scan()
                guard !pages.isEmpty else { return }   // cancelled
                editor.showBanner("Reading the pages…")
                source = await ScanCreation.readScreenplay(from: pages)
            } else {
                guard let url = await ScanPresenter.shared.pickDocument() else { return }
                editor.showBanner("Reading the pages…")
                source = try? await ScreenplayImport.source(at: url)
            }

            guard let source, !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let parsed = try? Fountain.parse(source),
                  !parsed.elements.isEmpty else {
                editor.showBanner("Nothing readable on those pages")
                return
            }

            guard let intoOpenScript = await askDestination(scanned: scanning, read: parsed.elements.count)
            else { return }   // cancelled: the pages are simply not used

            if intoOpenScript {
                insert(Screenplay(engineModel: parsed).elements, into: editor)
            } else {
                saveAsNewScript(source, announcingTo: editor)
            }
        }
    }

    /// True to add to the open screenplay, false to start a new one, nil if
    /// the writer changed their mind. Asked only once there is something to
    /// place, and phrased in terms of what was actually read.
    private func askDestination(scanned: Bool, read count: Int) async -> Bool? {
        guard let presenter = topViewController() else { return nil }

        return await withCheckedContinuation { continuation in
            var answered = false
            func answer(_ value: Bool?) {
                guard !answered else { return }
                answered = true
                continuation.resume(returning: value)
            }

            let alert = UIAlertController(
                title: scanned ? "Pages Scanned" : "Screenplay Imported",
                message: count == 1
                    ? "Read 1 element. Where should it go?"
                    : "Read \(count) elements. Where should they go?",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Add to This Screenplay", style: .default) { _ in
                answer(true)
            })
            alert.addAction(UIAlertAction(title: "Create New Screenplay", style: .default) { _ in
                answer(false)
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in
                answer(nil)
            })
            presenter.present(alert, animated: true)
        }
    }

    /// Hands the pages to the text view, which places them after the element
    /// the caret is in — never inside it, so nothing lands mid-sentence — and
    /// registers the whole arrival as one step on the writer's undo timeline.
    private func insert(_ pages: [ScriptElement], into editor: EditorState) {
        guard let place = editor.onInsertElements else {
            editor.showBanner("The editor isn't ready yet — try again")
            return
        }
        place(pages)
        editor.showBanner(pages.count == 1 ? "Added 1 element" : "Added \(pages.count) elements")
    }

    /// Writes the pages as their own screenplay beside this one.
    ///
    /// It cannot be opened from here: iOS gives a document app no way to open
    /// one document from inside another — `openDocument` is macOS only — so
    /// the honest thing is to say where it went rather than appear to fail.
    private func saveAsNewScript(_ source: String, announcingTo editor: EditorState) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let stamp = "Scan \(formatter.string(from: .now))"
        let folder = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]

        // Never write over a screenplay that is already there. Two scans can
        // land in the same second, and the one that arrived first is somebody's
        // work.
        var name = stamp
        var url = folder.appendingPathComponent("\(name).draft")
        var attempt = 2
        while FileManager.default.fileExists(atPath: url.path) {
            name = "\(stamp) (\(attempt))"
            url = folder.appendingPathComponent("\(name).draft")
            attempt += 1
        }

        do {
            try Data(source.utf8).write(to: url, options: .withoutOverwriting)
            editor.showBanner("Saved as \(name) — close this script to open it")
        } catch {
            editor.showBanner("Couldn't save: \(error.localizedDescription)")
        }
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

    /// A gap between two bar items. Adjacent items fuse into one capsule on
    /// this bar, so every seam needs its own instance: an item can occupy
    /// only one position.
    static func seam() -> UIBarButtonItem {
        let spacer = UIBarButtonItem(systemItem: .fixedSpace)
        spacer.width = 8
        return spacer
    }
}
