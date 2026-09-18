import AppKit
import EDraftCore
import EDraftMacSurface
import EDraftUI
import SplitWindowKit
import SwiftUI

/// eDraft on the Mac.
///
/// Deliberately almost nothing. The document is `ScreenplayDocument`, an
/// `NSDocument` over the same `ScreenplayFile` the phone opens. The window is
/// `ScriptWindowController` from EDraftMacSurface, and everything it does is
/// under test there. The menu bar is `MainMenu`.
///
/// AppKit's lifecycle rather than SwiftUI's, and that is the one decision in
/// this file. A `DocumentGroup` window keeps its toolbar glass dark whatever
/// scrolls beneath it; an `NSDocument` window turns it light over the page,
/// which is the toolbar Pages has — `SplitWindowController` records the
/// measurement. Everything a document app should do for free — Save, Duplicate,
/// Rename, Versions, Open Recent, tabs — comes with the same decision.
/// The one iCloud documents container both platforms share — what puts the
/// eDraft folder in iCloud Drive on every device. Declared in
/// `macOS/eDraft.entitlements` and matched by the phone.
let iCloudContainerID = "iCloud.xyz.edraft"

@main
@MainActor
enum EDraftMacApp {
    static func main() {
        NSApplication.shared.delegate = MacAppDelegate.shared
        NSApplication.shared.mainMenu = MainMenu.build()
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }
}

/// What only the application object can answer.
///
/// A document app launches into one of two things: a file dialog, or a new
/// untitled document. Neither is a greeting, and neither says what this app
/// is. Refusing the untitled file leaves the launch window as the thing a
/// writer meets — the same choice the phone makes with
/// `DocumentGroupLaunchScene`.
final class MacAppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    static let shared = MacAppDelegate()

    private var launchWindow: LaunchWindowController?

    /// No untitled document at launch. A writer who wants one presses ⌘N,
    /// which the launch window puts in front of them.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        showLaunchWindow()
        return false
    }

    /// Tahoe inserts its own Open Recent into a document app's File menu,
    /// but fills it only for nib-built menus — built in code, it opens with
    /// nothing but Clear Menu, next to the working one MainMenu makes. The
    /// system's copy goes; Close All and Share, also inserted, are kept.
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let file = NSApp.mainMenu?.item(withTitle: "File")?.submenu else { return }
        for item in file.items where item.title == "Open Recent"
            && !(item.submenu?.delegate is RecentDocumentsMenu) {
            file.removeItem(item)
        }
        // The container lookup can take seconds the first time; ask it now,
        // off the main thread, so the first save panel never waits on it.
        DispatchQueue.global().async {
            _ = FileManager.default.url(forUbiquityContainerIdentifier: iCloudContainerID)
        }
    }

    /// Reopening from the Dock with nothing on screen means the same thing as
    /// launching: show the window that says what this is.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        if flag { return true }
        showLaunchWindow()
        return false
    }

    /// Shows the library. Given a window it is replacing — a document going
    /// Back — it takes that window's frame first, so the writer sees one
    /// window change what it holds rather than two windows trading places.
    func showLaunchWindow(replacing window: NSWindow? = nil) {
        let controller = launchWindow ?? LaunchWindowController()
        launchWindow = controller
        if let window, let launch = controller.window {
            launch.setFrame(window.frame, display: false)
        }
        controller.showWindow(nil)
    }

    /// eDraft → Settings… (⌘,). One window for the app, answered with or
    /// without a document open.
    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(nil)
    }

    /// The recents menu's items reach here, each carrying its file.
    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }

    /// View → Page. App-level, so it answers with or without a window; the
    /// surfaces watch `UserDefaults` and every open window restyles.
    @objc func setPagePaper(_ sender: NSMenuItem) {
        guard let paper = sender.representedObject as? PagePaper else { return }
        PagePaper.store(paper)
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(setPagePaper(_:)) {
            item.state = (item.representedObject as? PagePaper) == PagePaper.stored ? .on : .off
        }
        return true
    }
}

/// The recents the launch window shows, re-read whenever something could
/// have changed them: the app coming to the front, or a file operation here.
@MainActor
@Observable
final class LaunchLibrary {
    private(set) var recents: [RecentScript] = []
    /// What the toolbar's search field says.
    var query = ""
    /// Grid or list, remembered between launches.
    var showsGrid: Bool {
        didSet { UserDefaults.standard.set(showsGrid, forKey: LaunchModel.layoutKey) }
    }

    init() {
        showsGrid = UserDefaults.standard.object(forKey: LaunchModel.layoutKey) as? Bool ?? true
    }

    func reload() {
        recents = LaunchModel.rows(
            from: NSDocumentController.shared.recentDocumentURLs,
            favorites: LaunchFavorites.load()
        )
    }
}

/// eDraft before a word is written: `LaunchWindow` from the surface, in a
/// window with no title bar, because the window's name is the first thing
/// written on it.
///
/// Also the one place that does things to files a writer has not opened —
/// rename, duplicate, trash, star — because it is the one place that can ask
/// the document controller whether a file *is* open, and hand the operation
/// to that document so its window follows.
final class LaunchWindowController: NSWindowController, NSSearchFieldDelegate {
    private let library = LaunchLibrary()
    private var toolbar: DeclaredToolbar?

    private enum ItemID {
        static let new = "eDraft.library.new"
        static let layout = "eDraft.library.layout"
        static let search = "eDraft.library.search"
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "eDraft"
        window.toolbarStyle = .unified
        // The library runs under the bar, as the script does: one ground for
        // the window, and the system's own edge as the cards scroll up.
        window.titlebarAppearsTransparent = true
        window.contentMinSize = NSSize(width: 640, height: 420)
        super.init(window: window)
        window.contentViewController = NSHostingController(
            rootView: LaunchWindowHost(library: library, actions: actions)
        )
        // A content view controller resizes the window to its view; the size
        // is stated again so the window opens as designed, not as the view's
        // minimum. See `SplitWindowController`.
        window.setContentSize(NSSize(width: 820, height: 640))
        window.center()
        installToolbar()
        NotificationCenter.default.addObserver(
            self, selector: #selector(reload),
            name: NSApplication.didBecomeActiveNotification, object: nil
        )
    }

    /// Plus for the two doors, the grid/list switch, and search — the same
    /// three things Finder's bar carries, in Finder's order.
    private func installToolbar() {
        let doors = NSMenu()
        doors.addItem(NSMenuItem(title: "New Screenplay", action: #selector(newDocument(_:)), keyEquivalent: ""))
        doors.addItem(NSMenuItem(title: "Open…", action: #selector(openDocument(_:)), keyEquivalent: ""))
        let entries: [ToolbarEntry] = [
            .flexibleSpace,
            .item(ToolbarItems.menu(ItemID.new, symbol: "plus", label: "New", showsIndicator: false, menu: doors)),
            .item(ToolbarItems.choice(
                ItemID.layout, symbols: ["square.grid.2x2", "list.bullet"], labels: ["Grid", "List"],
                selected: library.showsGrid ? 0 : 1, target: self, action: #selector(changeLayout(_:))
            )),
            .item(ToolbarItems.search(ItemID.search, delegate: self))
        ]
        let declared = DeclaredToolbar(identifier: "eDraft.library", entries: entries)
        toolbar = declared
        window?.toolbar = declared.toolbar
    }

    @objc private func changeLayout(_ sender: NSToolbarItemGroup) {
        library.showsGrid = sender.selectedIndex == 0
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSSearchField else { return }
        library.query = field.stringValue
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LaunchWindowController is created in code")
    }

    override func showWindow(_ sender: Any?) {
        reload()
        super.showWindow(sender)
    }

    @objc private func reload() {
        library.reload()
    }

    private var actions: LaunchActions {
        LaunchActions(
            new: { [weak self] in self?.newDocument(nil) },
            open: { [weak self] in self?.openDocument(nil) },
            pick: { [weak self] url in self?.open(url) },
            openInNewWindow: { [weak self] url in self?.open(url, inNewWindow: true) },
            rename: { [weak self] url, name in self?.rename(url, to: name) },
            duplicate: { [weak self] url in self?.duplicate(url) },
            trash: { [weak self] url in self?.trash(url) },
            toggleFavorite: { [weak self] url in self?.toggleFavorite(url) }
        )
    }

    // MARK: Doors

    /// File → New reaches here while this window is key, so the new script
    /// takes this window's place — the same as the library's own button.
    @objc func newDocument(_ sender: Any?) {
        do {
            let document = try NSDocumentController.shared.openUntitledDocumentAndDisplay(false)
            hand(over: document)
        } catch {
            finish(error)
        }
    }

    /// A sheet on the launch window rather than an application-modal panel:
    /// `runModal()` floats the panel free of any window, while a sheet is
    /// attached to the window the writer clicked, which is what every
    /// document app on the platform does.
    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.edraftScreenplay, .plainText, .finalDraftScreenplay]
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.open(url)
        }
    }

    /// Opens a script in this window's place, or — the one explicit exception
    /// — in a window of its own, with the library left open behind it.
    ///
    /// A recent that has gone since the list was read is the writer's answer,
    /// not a crash: the document controller reports it and the window stays.
    func open(_ url: URL, inNewWindow: Bool = false) {
        NSDocumentController.shared.openDocument(withContentsOf: url, display: false) { [weak self] document, _, error in
            guard let self else { return }
            guard let document else {
                finish(error)
                return
            }
            if inNewWindow {
                document.showWindows()
            } else {
                hand(over: document)
            }
        }
    }

    /// The document takes this window's place and this window goes: to the
    /// writer, the library became the script. The library hands over its
    /// *place*, not its size — the document window computed the width its
    /// page needs at the opening zoom, and the library's narrower frame
    /// would crop the sheet the writer came for. The library's top-left
    /// corner anchors the swap, so the title bar stays where the eye left
    /// it, and the screen's visible frame holds the result on screen.
    private func hand(over document: NSDocument) {
        if document.windowControllers.isEmpty {
            document.makeWindowControllers()
            if let frame = window?.frame, let target = document.windowControllers.first?.window {
                var fitted = target.frame
                fitted.origin.x = frame.origin.x
                fitted.origin.y = frame.maxY - fitted.height
                if let screen = target.screen ?? NSScreen.main {
                    let visible = screen.visibleFrame
                    if fitted.maxX > visible.maxX { fitted.origin.x = visible.maxX - fitted.width }
                    if fitted.maxY > visible.maxY { fitted.origin.y = visible.maxY - fitted.height }
                    if fitted.origin.x < visible.minX { fitted.origin.x = visible.minX }
                    if fitted.origin.y < visible.minY { fitted.origin.y = visible.minY }
                }
                target.setFrame(fitted, display: false)
            }
        }
        document.showWindows()
        close()
    }

    // MARK: Files

    func rename(_ url: URL, to name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != url.deletingPathExtension().lastPathComponent else { return }
        let target = url.deletingLastPathComponent()
            .appendingPathComponent(name)
            .appendingPathExtension(url.pathExtension)
        if let document = NSDocumentController.shared.document(for: url) {
            // Open: the document moves itself, and its window follows.
            document.move(to: target) { [weak self] error in self?.finish(error) }
        } else {
            attempt {
                try FileManager.default.moveItem(at: url, to: target)
                NSDocumentController.shared.noteNewRecentDocumentURL(target)
            }
        }
    }

    func duplicate(_ url: URL) {
        attempt {
            let copy = Self.copyURL(for: url)
            try FileManager.default.copyItem(at: url, to: copy)
            NSDocumentController.shared.noteNewRecentDocumentURL(copy)
        }
    }

    /// The Trash, never a delete: a writer's script is recoverable or it is
    /// not touched.
    func trash(_ url: URL) {
        NSDocumentController.shared.document(for: url)?.close()
        attempt { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
    }

    func toggleFavorite(_ url: URL) {
        LaunchFavorites.toggle(url)
        reload()
    }

    /// "<name> copy", then "<name> copy 2" — the way Finder names them.
    private static func copyURL(for url: URL) -> URL {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        var candidate = folder.appendingPathComponent("\(base) copy").appendingPathExtension(url.pathExtension)
        var count = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) copy \(count)").appendingPathExtension(url.pathExtension)
            count += 1
        }
        return candidate
    }

    /// A file operation that fails says so on this window; the list is
    /// re-read either way.
    private func attempt(_ operation: () throws -> Void) {
        do {
            try operation()
            finish(nil)
        } catch {
            finish(error)
        }
    }

    private func finish(_ error: Error?) {
        reload()
        if let error, let window {
            NSAlert(error: error).beginSheetModal(for: window)
        }
    }
}

/// The launch window's contents: the library, rendered.
private struct LaunchWindowHost: View {
    let library: LaunchLibrary
    let actions: LaunchActions

    var body: some View {
        LaunchWindow(recents: library.recents, query: library.query, showsGrid: library.showsGrid, actions: actions)
    }
}
