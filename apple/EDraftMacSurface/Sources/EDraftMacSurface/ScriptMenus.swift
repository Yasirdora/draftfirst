import AppKit
import EDraftCore

/// The menus a script window offers — in its toolbar and in the menu bar.
///
/// Every item sends its selector up the responder chain with no target, so a
/// toolbar menu, a menu-bar item and a keyboard shortcut all arrive at the same
/// `ScriptWindowController` action. That is also what greys the menu bar out
/// when no script window is key: nothing answers, so AppKit disables the item.
public enum ScriptMenus {

    /// The kinds a writer converts between, in the order ⌘1–⌘9 number them —
    /// the table the iPad's keyboard reads too.
    static let keyedKinds: [(kind: ScreenplayKind, key: String)] =
        ScreenplayKind.shortcutKinds.enumerated().map { ($0.element, String($0.offset + 1)) }

    // MARK: Element

    /// Fills the toolbar's element menu: the kinds the caret's position
    /// suggests first, then everything else — the phone's arrangement.
    ///
    /// Rebuilt each time the menu opens, because the suggestions follow the
    /// caret and a menu that stated them once would be wrong by the next line.
    static func fillElementMenu(_ menu: NSMenu, for editor: EditorState) {
        menu.removeAllItems()
        menu.addItem(.sectionHeader(title: "Suggested"))
        for kind in editor.contextualKinds {
            menu.addItem(elementItem(kind))
        }
        menu.addItem(.sectionHeader(title: "All Elements"))
        for kind in ScreenplayKind.editorKinds where !editor.contextualKinds.contains(kind) {
            menu.addItem(elementItem(kind))
        }
        // An act break is not a conversion — there is nothing a paragraph
        // could become that says "a new act starts here" — so it sits apart
        // from the kinds and inserts instead (RFC-ACT-BREAK §6).
        menu.addItem(.separator())
        let actBreak = NSMenuItem(
            title: ScreenplayKind.actbreak.title,
            action: #selector(ScriptWindowController.insertActBreak(_:)),
            keyEquivalent: ""
        )
        actBreak.image = NSImage(
            systemSymbolName: ScreenplayKind.actbreak.symbol, accessibilityDescription: nil
        )
        menu.addItem(actBreak)
    }

    /// Format → Element, with ⌘1–⌘9.
    public static func elementBarItems() -> [NSMenuItem] {
        keyedKinds.map { elementItem($0.kind, key: $0.key) }
    }

    private static func elementItem(_ kind: ScreenplayKind, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(
            title: kind.title,
            action: #selector(ScriptWindowController.changeElementKind(_:)),
            keyEquivalent: key
        )
        item.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)
        item.representedObject = kind
        return item
    }

    /// A menu of exactly these items.
    public static func menu(_ items: [NSMenuItem]) -> NSMenu {
        let menu = NSMenu()
        items.forEach(menu.addItem)
        return menu
    }

    // MARK: Export

    /// PDF · FDX · Fountain · Text, from `ScreenplayExportFormat` so the
    /// toolbar and File → Export cannot come to offer different ones.
    public static func exportItems() -> [NSMenuItem] {
        ScreenplayExportFormat.allCases.map { format in
            let item = NSMenuItem(
                title: "\(format.title)…",
                action: #selector(ScriptWindowController.export(_:)),
                keyEquivalent: ""
            )
            item.representedObject = format
            return item
        }
    }

    // MARK: View

    /// Sheets, or one column. Radio state is set as the menu validates.
    public static func layoutItems() -> [NSMenuItem] {
        PageLayoutMode.allCases.map { mode in
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(ScriptWindowController.setLayoutMode(_:)),
                keyEquivalent: ""
            )
            item.representedObject = mode
            return item
        }
    }

    /// Single · Two-page · Grid. Radio state is set as the menu validates.
    public static func arrangementItems() -> [NSMenuItem] {
        PageArrangement.allCases.map { mode in
            let item = NSMenuItem(
                title: mode.title,
                action: #selector(ScriptWindowController.setArrangement(_:)),
                keyEquivalent: ""
            )
            item.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
            item.representedObject = mode
            return item
        }
    }

    /// Omit Scene — retitled Restore Scene on an OMITTED card, and dimmed
    /// with its reason where the file could not keep one (as the menu
    /// validates; see `ScriptWindowController.validateMenuItem`).
    public static func omitSceneItem() -> NSMenuItem {
        NSMenuItem(
            title: SceneAction.omit.title,
            action: #selector(ScriptWindowController.toggleSceneOmission(_:)),
            keyEquivalent: ""
        )
    }

    /// Zoom In · Zoom Out · Actual Size with Preview's keys, and Zoom to Fit
    /// on ⌥⌘0, beside Actual Size: ⌘9 is Lyrics, the last of the element keys
    /// (MACOS-DESIGN §3.4).
    public static func zoomItems() -> [NSMenuItem] {
        let fit = NSMenuItem(title: "Zoom to Fit", action: #selector(ScriptWindowController.zoomToFit(_:)), keyEquivalent: "0")
        fit.keyEquivalentModifierMask = [.command, .option]
        return [
            NSMenuItem(title: "Zoom In", action: #selector(ScriptWindowController.zoomIn(_:)), keyEquivalent: "+"),
            NSMenuItem(title: "Zoom Out", action: #selector(ScriptWindowController.zoomOut(_:)), keyEquivalent: "-"),
            NSMenuItem(title: "Actual Size", action: #selector(ScriptWindowController.actualSize(_:)), keyEquivalent: "0"),
            fit
        ]
    }

    /// The things a writer reaches for occasionally, behind one mark in the
    /// toolbar. Each has a place in the menu bar already; this is a second
    /// way to the same action for a hand that is on the trackpad.
    static func overflowMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Find…", action: #selector(ScriptWindowController.showFind(_:)), keyEquivalent: "f"))
        let note = NSMenuItem(title: "Add Note", action: #selector(ScriptWindowController.addNote(_:)), keyEquivalent: "k")
        note.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(note)
        menu.addItem(.separator())
        layoutItems().forEach(menu.addItem)
        return menu
    }
}
