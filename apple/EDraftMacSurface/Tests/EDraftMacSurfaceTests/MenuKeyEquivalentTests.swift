import AppKit
import EDraftCore
import SwiftUI
import XCTest
@testable import EDraftMacSurface

/// One shortcut, one command — IL-0108.
///
/// ⌘9 was Format ▸ Element ▸ Lyrics and View ▸ Zoom to Fit at once, and the
/// running app never showed it: AppKit blanks the second of two identical key
/// equivalents when the bar is installed, so Zoom to Fit simply had no key.
/// The bar is therefore walked as declared, before it reaches
/// `NSApp.mainMenu`, together with every menu a script window offers.
@MainActor
final class MenuKeyEquivalentTests: XCTestCase {

    /// The bar hands AppKit its Services, Window and Help menus, which needs
    /// the application object the running app always has.
    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
    }

    private struct Keys: Hashable {
        let key: String
        let modifiers: UInt
    }

    /// What an item does: two items with the same action and the same
    /// represented object are one command offered twice, not two commands.
    private struct Command: Hashable {
        let action: String
        let object: String
    }

    private struct Keyed {
        let keys: Keys
        let command: Command
        let path: String
    }

    private func keyed(_ menu: NSMenu, _ path: String, into out: inout [Keyed]) {
        for item in menu.items {
            let here = "\(path) ▸ \(item.title)"
            if !item.keyEquivalent.isEmpty {
                var modifiers = item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask)
                var key = item.keyEquivalent
                // An upper-case letter is its lower-case one with Shift.
                if key.lowercased() != key {
                    key = key.lowercased()
                    modifiers.insert(.shift)
                }
                out.append(Keyed(
                    keys: Keys(key: key, modifiers: modifiers.rawValue),
                    command: Command(
                        action: item.action.map(NSStringFromSelector) ?? "—",
                        object: item.representedObject.map { "\($0)" } ?? ""
                    ),
                    path: here
                ))
            }
            if let submenu = item.submenu { keyed(submenu, here, into: &out) }
        }
    }

    /// The menu bar, and every menu the script window's toolbar opens.
    private func everyMenu() -> [Keyed] {
        var out: [Keyed] = []
        keyed(MainMenu.build(), "Menu bar", into: &out)
        let editor = EditorState(source: "INT. KITCHEN - NIGHT\n\nThe kettle screams.")
        let element = NSMenu()
        ScriptMenus.fillElementMenu(element, for: editor)
        keyed(element, "Toolbar ▸ Element", into: &out)
        keyed(ScriptMenus.overflowMenu(), "Toolbar ▸ More", into: &out)
        keyed(ScriptMenus.menu(ScriptMenus.exportItems()), "Toolbar ▸ Export", into: &out)
        keyed(ScriptMenus.menu(ScriptMenus.arrangementItems()), "Toolbar ▸ Arrangement", into: &out)
        return out
    }

    private func item(_ path: [String]) -> NSMenuItem? {
        var menu: NSMenu? = MainMenu.build()
        var found: NSMenuItem?
        for title in path {
            found = menu?.items.first { $0.title == title }
            menu = found?.submenu
        }
        return found
    }

    func testNoShortcutRunsTwoCommands() {
        let all = everyMenu()
        XCTAssertGreaterThan(all.count, 40, "the walk reached the whole bar")
        let clashes = Dictionary(grouping: all, by: \.keys).values
            .filter { Set($0.map(\.command)).count > 1 }
            .map { $0.map(\.path).sorted() }
        XCTAssertEqual(clashes, [], "one shortcut bound to two commands")
    }

    /// The element keys are one table, read by the Mac's Format ▸ Element and
    /// the iPad's hardware keyboard alike, and ⌘9 is Lyrics on both.
    func testTheElementKeysAreOneTable() throws {
        let element = try XCTUnwrap(item(["Format", "Element"])?.submenu)
        XCTAssertEqual(element.items.map(\.keyEquivalent), (1...9).map(String.init))
        XCTAssertEqual(
            element.items.compactMap { $0.representedObject as? ScreenplayKind },
            ScreenplayKind.shortcutKinds,
            "the Mac's keys and the iPad's are the same table"
        )
        XCTAssertEqual(
            Array(ScreenplayKind.shortcutKinds.prefix(7)),
            [.scene, .action, .character, .parenthetical, .dialogue, .transition, .shot],
            "⌘1–⌘7 are Final Draft's"
        )
        XCTAssertEqual(ScreenplayKind.shortcutKinds.last, .lyrics)
    }

    /// Beside Actual Size, not on the element row (MACOS-DESIGN §3.4).
    func testZoomToFitIsOptionCommandZero() throws {
        let fit = try XCTUnwrap(item(["View", "Zoom to Fit"]))
        XCTAssertEqual(fit.keyEquivalent, "0")
        XCTAssertEqual(fit.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask), [.command, .option])
        let actual = try XCTUnwrap(item(["View", "Actual Size"]))
        XCTAssertEqual(actual.keyEquivalent, "0")
        XCTAssertEqual(actual.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask), [.command])
    }

    // MARK: - The launch window's ⌘Z

    /// A Move to Trash is Edit ▸ Undo's, named for what it did.
    func testAMoveToTrashIsEditUndos() {
        let undo = UndoManager()
        let item = LaunchTrashUndo(
            name: "The Last Light",
            originalURL: URL(fileURLWithPath: "/tmp/The Last Light.draft"),
            trashURL: URL(fileURLWithPath: "/tmp/.Trash/The Last Light.draft")
        )
        var putBack: [LaunchTrashUndo] = []
        item.registerUndo(on: undo) { putBack.append($0) }
        XCTAssertTrue(undo.canUndo, "Edit ▸ Undo can take the trash back")
        XCTAssertEqual(undo.undoMenuItemTitle, "Undo Move to Trash")
        undo.undo()
        XCTAssertEqual(putBack, [item])
    }

    /// The banner's button no longer answers ⌘Z itself: the key goes on to
    /// the menu bar, where it means Edit ▸ Undo in every window.
    func testTheTrashBannerLeavesCommandZToEditUndo() throws {
        /* A file really in the "trash", or the button is disabled — and a
           disabled button answers no shortcut, which would pass this test
           on any code. */
        let trashed = FileManager.default.temporaryDirectory
            .appendingPathComponent("IL-0108-\(UUID().uuidString).draft")
        try Data("INT. KITCHEN - NIGHT".utf8).write(to: trashed)
        defer { try? FileManager.default.removeItem(at: trashed) }
        let item = LaunchTrashUndo(
            name: "The Last Light",
            originalURL: URL(fileURLWithPath: "/tmp/The Last Light.draft"),
            trashURL: trashed
        )
        XCTAssertTrue(item.canPutBack(), "the banner's Undo is enabled")
        var pressed = 0
        let host = NSHostingView(rootView: LaunchTrashBanner(item: item, onUndo: { pressed += 1 }, onDismiss: {}))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let commandZ = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "z",
            charactersIgnoringModifiers: "z", isARepeat: false, keyCode: 6
        ))
        let handled = window.performKeyEquivalent(with: commandZ)
        XCTAssertFalse(handled, "the banner took ⌘Z for itself")
        XCTAssertEqual(pressed, 0)
    }
}
