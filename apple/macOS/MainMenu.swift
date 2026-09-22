import AppKit
import EDraftCore
import EDraftMacSurface

/// The menu bar, built in code.
///
/// Every item names a selector and no target, so AppKit finds who answers —
/// the text view for Cut and Paste, the document for Save, the document
/// controller for New and Open, `ScriptWindowController` for everything that
/// acts on the script — and greys the item out when nobody does. There is no
/// state kept here and nothing to keep in sync: the menu asks, each time it
/// opens.
///
/// Where things live follows the platform, not the app: editing actions in
/// Edit (Accept Suggestion after Paste, Find where every app puts it),
/// element conversion under Format with ⌘1–⌘9, how the page is drawn under
/// View, and the document's life under File. Nothing is added to the toolbar
/// that this menu could not carry.
enum MainMenu {

    static func build() -> NSMenu {
        let bar = NSMenu()
        bar.addItem(submenu("eDraft", appMenu()))
        bar.addItem(submenu("File", fileMenu()))
        bar.addItem(submenu("Edit", editMenu()))
        bar.addItem(submenu("Format", formatMenu()))
        bar.addItem(submenu("View", viewMenu()))

        let window = windowMenu()
        bar.addItem(submenu("Window", window))
        NSApp.windowsMenu = window

        let help = NSMenu(title: "Help")
        help.addItem(item("eDraft Help", #selector(NSApplication.showHelp(_:)), "?"))
        bar.addItem(submenu("Help", help))
        NSApp.helpMenu = help
        return bar
    }

    // MARK: Menus

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "eDraft")
        menu.addItem(item("About eDraft", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        // Between About and Services, on ⌘, — where the platform keeps it.
        menu.addItem(item("Settings…", #selector(MacAppDelegate.showSettings(_:)), ","))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        menu.addItem(submenu("Services", services))
        NSApp.servicesMenu = services
        menu.addItem(.separator())
        menu.addItem(item("Hide eDraft", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit eDraft", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New", #selector(NSDocumentController.newDocument(_:)), "n"))
        menu.addItem(item("Open…", #selector(NSDocumentController.openDocument(_:)), "o"))
        menu.addItem(submenu("Open Recent", RecentDocumentsMenu.make()))
        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save", #selector(NSDocument.save(_:)), "s"))
        menu.addItem(item("Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift]))
        menu.addItem(item("Rename…", #selector(NSDocument.rename(_:))))
        menu.addItem(item("Move To…", #selector(NSDocument.move(_:))))
        menu.addItem(item("Show in Finder", #selector(ScriptWindowController.showInFinder(_:))))
        let revert = NSMenu(title: "Revert To")
        revert.addItem(item("Browse All Versions…", #selector(NSDocument.browseVersions(_:))))
        revert.addItem(item("Last Saved", #selector(NSDocument.revertToSaved(_:))))
        menu.addItem(submenu("Revert To", revert))
        menu.addItem(.separator())
        // The same sheet the phone presents — not a second form.
        menu.addItem(item("Title Page…", #selector(ScriptWindowController.showTitlePage(_:))))
        menu.addItem(submenu("Export", ScriptMenus.menu(ScriptMenus.exportItems())))
        menu.addItem(.separator())
        menu.addItem(item("Page Setup…", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift]))
        menu.addItem(item("Print…", #selector(NSDocument.printDocument(_:)), "p"))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Delete", #selector(NSText.delete(_:))))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        // Accepting a completion is an editing action, not a formatting one,
        // with the key a writer already reaches for on the phone (⌘→).
        menu.addItem(item("Accept Suggestion", #selector(ScriptWindowController.acceptSuggestion(_:)), rightArrow))
        menu.addItem(.separator())
        // Where Pages puts it, and the key it uses.
        menu.addItem(item("Add Note", #selector(ScriptWindowController.addNote(_:)), "k", [.command, .shift]))
        menu.addItem(.separator())
        // Find is the system bar, Replace omitted: `NSTextView.replaceCharacters`
        // does not go through the planner. Find Scene is go-to-scene, not a
        // second text search.
        let find = NSMenu(title: "Find")
        find.addItem(item("Find…", #selector(ScriptWindowController.showFind(_:)), "f"))
        find.addItem(item("Find Next", #selector(ScriptWindowController.findNext(_:)), "g"))
        find.addItem(item("Find Previous", #selector(ScriptWindowController.findPrevious(_:)), "g", [.command, .shift]))
        menu.addItem(submenu("Find", find))
        menu.addItem(item("Find Scene", #selector(ScriptWindowController.findScene(_:)), "l"))
        menu.addItem(.separator())
        menu.addItem(item("Emoji & Symbols", #selector(NSApplication.orderFrontCharacterPalette(_:)), " ", [.command, .control]))
        return menu
    }

    private static func formatMenu() -> NSMenu {
        let menu = NSMenu(title: "Format")
        menu.addItem(submenu("Element", ScriptMenus.menu(ScriptMenus.elementBarItems())))
        // A verb, so it does not live in the sidebar (MACOS-DESIGN §1.1).
        let numbers = NSMenu(title: "Scene Numbers")
        numbers.addItem(item("Number New Scenes", #selector(ScriptWindowController.numberNewScenes(_:))))
        numbers.addItem(item("Number All Scenes…", #selector(ScriptWindowController.numberAllScenes(_:))))
        numbers.addItem(item("Remove Scene Numbers…", #selector(ScriptWindowController.removeSceneNumbers(_:))))
        menu.addItem(submenu("Scene Numbers", numbers))
        // Beside the numbers it keeps: an omitted scene holds its number
        // (RFC-DRAFT-PRODUCTION §7.3). Retitles to Restore Scene on a card.
        menu.addItem(ScriptMenus.omitSceneItem())
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        ScriptMenus.zoomItems().forEach(menu.addItem)
        menu.addItem(.separator())
        ScriptMenus.layoutItems().forEach(menu.addItem)
        menu.addItem(.separator())
        // Only meaningful in dark mode, where it decides whether the script
        // darkens with the app or stays paper. Offered in both, because a
        // control that disappears is harder to find than one that is simply
        // not doing anything yet.
        for paper in PagePaper.allCases {
            let choice = item(paper.title, #selector(MacAppDelegate.setPagePaper(_:)))
            choice.representedObject = paper
            menu.addItem(choice)
        }
        menu.addItem(.separator())
        menu.addItem(item("Show Sidebar", #selector(NSSplitViewController.toggleSidebar(_:)), "s", [.command, .control]))
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Show Previous Tab", #selector(NSWindow.selectPreviousTab(_:))))
        menu.addItem(item("Show Next Tab", #selector(NSWindow.selectNextTab(_:))))
        menu.addItem(item("Move Tab to New Window", #selector(NSWindow.moveTabToNewWindow(_:))))
        menu.addItem(item("Merge All Windows", #selector(NSWindow.mergeAllWindows(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }

    // MARK: Building

    private static var rightArrow: String {
        String(utf16CodeUnits: [unichar(NSRightArrowFunctionKey)], count: 1)
    }

    private static func item(
        _ title: String,
        _ action: Selector,
        _ key: String = "",
        _ modifiers: NSEvent.ModifierFlags = .command
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        menu.title = title
        return item
    }
}

/// File → Open Recent, read from the document controller each time it opens.
///
/// Tahoe inserts its own Open Recent into a document app's File menu, but
/// fills it only for nib-built menus — built in code, it opens with nothing
/// but Clear Menu, next to a working one. So this one is asked instead, the
/// system's copy is removed at launch (see `MacAppDelegate`), and
/// `NSDocumentController` has kept the list correctly for thirty years, so
/// there is no reason to keep a second one.
final class RecentDocumentsMenu: NSObject, NSMenuDelegate {
    static let shared = RecentDocumentsMenu()
    private override init() { super.init() }

    static func make() -> NSMenu {
        let menu = NSMenu(title: "Open Recent")
        menu.delegate = shared
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs {
            let item = NSMenuItem(
                title: url.deletingPathExtension().lastPathComponent,
                action: #selector(MacAppDelegate.openRecent(_:)),
                keyEquivalent: ""
            )
            item.representedObject = url
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !menu.items.isEmpty { menu.addItem(.separator()) }
        menu.addItem(NSMenuItem(
            title: "Clear Menu",
            action: #selector(NSDocumentController.clearRecentDocuments(_:)),
            keyEquivalent: ""
        ))
    }
}
