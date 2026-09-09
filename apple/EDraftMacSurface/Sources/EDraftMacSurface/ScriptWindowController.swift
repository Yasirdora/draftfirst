import AppKit
import EDraftCore
import EDraftUI
import SplitWindowKit
import SwiftUI

/// What the Navigator column and the desk column share, and what the chrome
/// asks of them.
@Observable
final class ScriptWindowState {
    var tab: StoryPanel.Tab = .scenes
    var sceneQuery = ""
    /// Bumped by ⌘L; the scene filter takes focus when it changes.
    var focusSceneFilter = 0
    /// Whose thread is open beside the cast, if anyone's.
    var selectedCharacter: String?
    var showingTitlePage = false
    /// Focus: the sidebar folds away and the thread and zoom control leave, so
    /// the page is the only thing on the desk.
    var isFocused = false
}

/// One screenplay, in one window.
///
/// The structure on the left, the page in the middle. A properties column on
/// the right is reserved for comments and notes — something to read
/// *alongside* the page. Title page, scene facts and a character rename are
/// transient, and a transient thing is a sheet or a destination in the
/// sidebar, not a pane.
///
/// The window is AppKit's and the columns are SwiftUI — `SplitWindowController`
/// says why. The sidebar is `StoryList`, the same Navigator the phone shows in
/// a sheet, visible by default because on a Mac the sidebar *is* the
/// organisation panel. The desk runs under the toolbar and the page scrolls
/// beneath it, and the system does the rest: the script softens as it passes
/// under the chrome, and the toolbar's glass turns light over the paper and
/// dark over the desk. Nothing here draws a gradient or hides a background.
public final class ScriptWindowController: SplitWindowController, NSMenuDelegate, NSMenuItemValidation {

    public let editor: EditorState
    let state = ScriptWindowState()
    /// Back: what the app does after this window has been asked to close.
    public var onBack: (() -> Void)?

    private let elementMenu = NSMenu()
    private var elementItem: NSMenuToolbarItem?
    private var paperItem: NSToolbarItem?
    private var focusItem: NSToolbarItem?

    private enum ItemID {
        static let element = "eDraft.element"
        static let paper = "eDraft.paper"
        static let titlePage = "eDraft.titlePage"
        static let export = "eDraft.export"
        static let document = "eDraft.document"
        static let more = "eDraft.more"
        static let back = "eDraft.back"
        static let view = "eDraft.view"
        static let focus = "eDraft.focus"
        static let zoom = "eDraft.zoom"
    }

    public init(editor: EditorState) {
        self.editor = editor
        // Wide enough to hold a page at a size a person can read: a 240-point
        // Navigator leaves 1040 for the page, which draws it at about 1.5×.
        super.init(
            contentSize: NSSize(width: 1280, height: 860),
            minimumSize: NSSize(width: 720, height: 480)
        )
        let state = self.state
        addSidebar(minimumWidth: 240, maximumWidth: 360) {
            NavigatorColumn(editor: editor, state: state)
        }
        addContent(minimumWidth: 480) {
            DeskColumn(editor: editor, state: state)
        }
        installToolbar(identifier: "eDraft.script", entries: toolbarEntries())

        editor.onFindScene = { [weak self] in self?.revealSceneFilter() }
        followTheModel()
        NotificationCenter.default.addObserver(
            self, selector: #selector(pagePaperChanged),
            name: UserDefaults.didChangeNotification, object: nil
        )
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("ScriptWindowController is created in code")
    }

    // MARK: Toolbar

    /// Back before the title, then the writer's controls at the trailing
    /// edge: the element under the caret; Focus and Zoom in one piece of
    /// glass; the three that change how the page looks or what leaves the app
    /// with it; and, standing apart because it opens a list rather than
    /// acting, the overflow.
    private func toolbarEntries() -> [ToolbarEntry] {
        elementMenu.delegate = self
        let back = ToolbarItems.button(
            ItemID.back, symbol: "chevron.backward", label: "Back",
            toolTip: "Back to the library", navigational: true,
            target: self, action: #selector(goBack(_:))
        )
        let element = ToolbarItems.menu(
            ItemID.element,
            symbol: editor.activeKind.symbol,
            title: editor.activeKind.shortTitle,
            label: "Element",
            toolTip: "Screenplay element",
            menu: elementMenu
        )
        elementItem = element

        let focus = ToolbarItems.button(
            ItemID.focus, symbol: "rectangle", label: "Focus",
            toolTip: "Focus on the page", target: self, action: #selector(toggleFocus(_:))
        )
        focusItem = focus
        let zoom = ToolbarItems.menu(
            ItemID.zoom, symbol: "chevron.down", label: "Zoom",
            toolTip: "Zoom", showsIndicator: false,
            menu: ScriptMenus.menu(ScriptMenus.zoomItems())
        )

        let paper = ToolbarItems.button(
            ItemID.paper, symbol: "moon", label: "Page",
            target: self, action: #selector(togglePagePaper(_:))
        )
        paperItem = paper
        let titlePage = ToolbarItems.button(
            ItemID.titlePage, symbol: "text.document", label: "Title Page",
            target: self, action: #selector(showTitlePage(_:))
        )
        let export = ToolbarItems.menu(
            ItemID.export, symbol: "square.and.arrow.up", label: "Export",
            toolTip: "Export the screenplay", showsIndicator: false,
            menu: ScriptMenus.menu(ScriptMenus.exportItems())
        )
        let more = ToolbarItems.menu(
            ItemID.more, symbol: "ellipsis", label: "More",
            toolTip: "More actions", showsIndicator: false,
            menu: ScriptMenus.overflowMenu()
        )

        return [
            .toggleSidebar, .sidebarSeparator, .item(back), .flexibleSpace,
            .item(element),
            .item(ToolbarItems.group(ItemID.view, label: "View", [focus, zoom])),
            .item(ToolbarItems.group(ItemID.document, label: "Document", [paper, titlePage, export])),
            .space,
            .item(more)
        ]
    }

    /// The name of the element the toolbar shows. What the tests read.
    var elementControlTitle: String? { elementItem?.title }

    /// The two things the chrome states about the model: which element the
    /// caret is in, and how long the script is.
    private func followTheModel() {
        observeChanges { [weak self] in
            guard let self else { return }
            let kind = editor.activeKind
            elementItem?.title = kind.shortTitle
            elementItem?.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: kind.title)
        }
        observeChanges { [weak self] in
            guard let self else { return }
            // Under the name: the two numbers a writer actually watches.
            let pages = editor.stats.pages
            window?.subtitle = "\(pages) \(pages == 1 ? "page" : "pages") · \(editor.stats.runtime)"
        }
        observeChanges { [weak self] in
            guard let self else { return }
            let focused = state.isFocused
            isSidebarCollapsed = focused
            focusItem?.image = NSImage(
                systemSymbolName: focused ? "rectangle.inset.filled" : "rectangle",
                accessibilityDescription: "Focus"
            )
        }
        pagePaperChanged()
    }

    /// Sun on paper, moon on a dark page — the symbol says which one you are
    /// looking at, the way the system's own light/dark controls do.
    @objc private func pagePaperChanged() {
        let onPaper = PagePaper.stored == .paper
        paperItem?.image = NSImage(
            systemSymbolName: onPaper ? "moon" : "sun.max",
            accessibilityDescription: "Page appearance"
        )
        paperItem?.toolTip = onPaper ? "Darken the page" : "Return the page to paper"
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === elementMenu else { return }
        ScriptMenus.fillElementMenu(menu, for: editor)
    }

    // MARK: Actions

    @objc public func changeElementKind(_ sender: NSMenuItem) {
        guard let kind = sender.representedObject as? ScreenplayKind else { return }
        editor.onChangeElementKind?(kind)
    }

    @objc public func acceptSuggestion(_ sender: Any?) { editor.acceptPrediction() }
    @objc public func addNote(_ sender: Any?) { editor.onAddNote?() }
    @objc public func showFind(_ sender: Any?) { editor.onShowFind?() }
    @objc public func findNext(_ sender: Any?) { editor.onFindNext?() }
    @objc public func findPrevious(_ sender: Any?) { editor.onFindPrevious?() }
    @objc public func findScene(_ sender: Any?) { revealSceneFilter() }

    @objc public func zoomIn(_ sender: Any?) { editor.onZoom?(.zoomIn) }
    @objc public func zoomOut(_ sender: Any?) { editor.onZoom?(.zoomOut) }
    @objc public func actualSize(_ sender: Any?) { editor.onZoom?(.actualSize) }
    @objc public func zoomToFit(_ sender: Any?) { editor.onZoom?(.fit) }

    @objc public func setLayoutMode(_ sender: NSMenuItem) {
        guard let mode = sender.representedObject as? PageLayoutMode else { return }
        editor.onSetLayoutMode?(mode)
    }

    /// The same choice as View → Page and the same storage: the surfaces watch
    /// `UserDefaults`, so writing it restyles every open window.
    @objc public func togglePagePaper(_ sender: Any?) {
        PagePaper.store(PagePaper.stored == .paper ? .inverted : .paper)
    }

    @objc public func showTitlePage(_ sender: Any?) { state.showingTitlePage = true }
    @objc public func toggleFocus(_ sender: Any?) { state.isFocused.toggle() }

    /// The library first, then this window goes — so the writer is never
    /// looking at nothing.
    @objc public func goBack(_ sender: Any?) {
        onBack?()
        window?.performClose(sender)
    }

    @objc public func export(_ sender: NSMenuItem) {
        guard let format = sender.representedObject as? ScreenplayExportFormat else { return }
        editor.onExport?(format)
    }

    /// Number All and Remove confirm, because they change addresses a
    /// schedule may already cite.
    @objc public func numberNewScenes(_ sender: Any?) {
        _ = editor.applySceneNumbering(.newScenesOnly)
    }

    @objc public func numberAllScenes(_ sender: Any?) {
        confirm(
            title: "Renumber Every Scene?",
            body: "Every scene is numbered again from 1. Any number already in use changes, including ones a schedule or call sheet may already cite.",
            action: "Renumber"
        ) { [weak self] in _ = self?.editor.applySceneNumbering(.all) }
    }

    @objc public func removeSceneNumbers(_ sender: Any?) {
        confirm(
            title: "Remove Every Scene Number?",
            body: "The script keeps its scenes; it loses the numbers people cite them by.",
            action: "Remove"
        ) { [weak self] in _ = self?.editor.applySceneNumbering(.clear) }
    }

    /// ⌘L: the sidebar is the destination list. Reveal it, show Scenes, focus
    /// the filter. Not a Spotlight overlay — those are forbidden.
    private func revealSceneFilter() {
        isSidebarCollapsed = false
        state.tab = .scenes
        state.focusSceneFilter += 1
    }

    private func confirm(title: String, body: String, action: String, run: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard let window else {
            if alert.runModal() == .alertFirstButtonReturn { run() }
            return
        }
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { run() }
        }
    }

    // MARK: Validation

    /// Grey rather than silent: a command that would change nothing says so
    /// before it is chosen. Radio items read their state here too, so the
    /// menu bar, the toolbar menus and a shortcut cannot disagree.
    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard let action = item.action else { return true }
        switch action {
        case #selector(acceptSuggestion(_:)):
            return editor.currentPrediction?.hint != true
                && !(editor.currentSuggestionSuffix ?? "").isEmpty
        case #selector(addNote(_:)):
            return editor.onAddNote != nil
        case #selector(zoomIn(_:)):
            return PageZoom.isAvailable(.zoomIn, at: editor.zoom)
        case #selector(zoomOut(_:)):
            return PageZoom.isAvailable(.zoomOut, at: editor.zoom)
        case #selector(actualSize(_:)):
            return PageZoom.isAvailable(.actualSize, at: editor.zoom)
        case #selector(removeSceneNumbers(_:)):
            return editor.isSceneNumbered
        case #selector(setLayoutMode(_:)):
            item.state = (item.representedObject as? PageLayoutMode) == editor.layoutMode ? .on : .off
            return true
        default:
            return true
        }
    }
}

// MARK: - Columns

/// The Navigator: Scenes · Cast, with the scene filter ⌘L reaches.
///
/// Wrapped in a `NavigationStack` because `StoryList` declares the phone's
/// push destination and SwiftUI wants a stack to hang it on; the Mac never
/// pushes — choosing a character opens the thread beside the list instead.
private struct NavigatorColumn: View {
    let editor: EditorState
    @Bindable var state: ScriptWindowState

    var body: some View {
        NavigationStack {
            StoryList(
                editor: editor,
                tab: $state.tab,
                showsSceneFilter: true,
                showsSceneNumbering: false,
                sceneQuery: $state.sceneQuery,
                focusSceneFilter: state.focusSceneFilter,
                onFilterSubmit: { id in
                    editor.jump(to: id)
                    editor.beginEditing()
                },
                onSelectCharacter: { name in
                    // Choosing the open one closes it. A column that appeared
                    // by being chosen should leave the same way, rather than
                    // growing a dismiss control of its own.
                    state.selectedCharacter = state.selectedCharacter == name ? nil : name
                },
                selectedCharacter: state.selectedCharacter
            ) { element in
                // The sidebar stays where it is: a Mac reader keeps their
                // place in the list while the page moves beside it.
                editor.jump(to: element)
            }
        }
        .onChange(of: state.tab) { _, tab in
            if tab != .cast { state.selectedCharacter = nil }
        }
    }
}

/// The desk: a character's thread when one is chosen, then the page.
private struct DeskColumn: View {
    let editor: EditorState
    @Bindable var state: ScriptWindowState

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar, list, content — Notes' arrangement, and the Mac's.
            // Pushing the thread *inside* the sidebar hid the cast to show
            // one of them, which is losing your place to see your place.
            if !state.isFocused, let name = state.selectedCharacter {
                CharacterThreadView(editor: editor, name: name, chrome: .panel) { element in
                    editor.jump(to: element)
                }
                // The thread holds its own name so a rename performed inside
                // it does not pull the view out from under itself. A different
                // character is a different view, not the same one asked to
                // change its mind.
                .id(name)
                .frame(width: 260)
                Divider()
            }
            ScriptPageView(editor: editor)
                // The desk runs under the toolbar and the page scrolls
                // beneath it. `NSScrollView` insets its own *content* below
                // the toolbar while its background fills the frame — how
                // TextEdit, Pages and Xcode put a document under the chrome
                // and still start the first line in the clear.
                .ignoresSafeArea(edges: .top)
                // Over the canvas, never over the page — MACOS-DESIGN §1.6.
                .overlay(alignment: .bottomTrailing) {
                    if !state.isFocused { PageZoomControl(editor: editor) }
                }
        }
        .sheet(isPresented: $state.showingTitlePage) {
            TitlePageSheet(editor: editor)
        }
        // The thread takes 260 points from the desk, and gives them back. The
        // page fits whatever is left, on the next turn so the column has been
        // laid out first — a page drawn at 150% beside a thread does not fit
        // the window, and a writer should not have to zoom it themselves.
        .onChange(of: state.selectedCharacter == nil) { _, _ in
            DispatchQueue.main.async { editor.onZoom?(.fit) }
        }
    }
}
