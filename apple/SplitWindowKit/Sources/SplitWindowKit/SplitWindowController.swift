import AppKit
import SwiftUI

/// A document-style window: a sidebar and content columns, each a SwiftUI
/// view, under a unified toolbar whose glass reacts to what scrolls beneath it.
///
/// Why this is AppKit and not a `NavigationSplitView`. On macOS 26 the system
/// draws a "scroll pocket" under the toolbar: a blur and a tint over whatever
/// scrolls beneath the chrome, and — when the content is bright enough — it
/// flips the toolbar's floating glass items from dark to light, which is how
/// Pages' buttons turn white as the page passes under them. That flip only
/// happens when the window's content view controller is an
/// `NSSplitViewController` inside a window AppKit created. Measured on macOS
/// 26.5 with real scroll events: a SwiftUI `WindowGroup` holding a
/// `NavigationSplitView` never flips, in any of its styles, with or without
/// the sidebar toggle, and with an AppKit toolbar installed on it; an
/// `NSSplitViewController` hosted in a SwiftUI window loses the full-height
/// sidebar and the sidebar toggle. An AppKit window with SwiftUI columns is
/// the arrangement that has all of it.
///
/// Subclass it, add the columns, install a toolbar. The columns are
/// `NSHostingController`s with no intrinsic size, so the split view alone
/// decides their width — a hosted `List` would otherwise ask for the width of
/// its longest row.
open class SplitWindowController: NSWindowController {

    /// The split view that is the window's content. Also the object AppKit's
    /// `toggleSidebar:` and the sidebar tracking separator act on.
    public let splitViewController = NSSplitViewController()

    /// A window sized to `contentSize`, that will not shrink below
    /// `minimumSize`. The title bar is transparent and the content runs to the
    /// top of the window, which is what gives the toolbar something to soften.
    public init(contentSize: NSSize, minimumSize: NSSize) {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // The controller owns the window's lifetime, not the close button.
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        window.minSize = minimumSize
        window.contentViewController = splitViewController
        // Giving a window a content view controller resizes it to that
        // controller's view — a split view's default, not `contentSize`.
        // Measured: 1093×500 for an 1280×860 window. So the size is stated
        // again, after.
        window.setContentSize(contentSize)
        super.init(window: window)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("SplitWindowController is created in code")
    }

    // MARK: Columns

    /// Adds a sidebar column. AppKit gives it the sidebar material, full
    /// height under the title bar, and the standard toggle and collapse.
    @discardableResult
    public func addSidebar<Content: View>(
        minimumWidth: CGFloat,
        maximumWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> NSSplitViewItem {
        let item = NSSplitViewItem(sidebarWithViewController: host(content()))
        item.minimumThickness = minimumWidth
        item.maximumThickness = maximumWidth
        splitViewController.addSplitViewItem(item)
        return item
    }

    /// Adds a content column, which takes whatever width the sidebar leaves.
    @discardableResult
    public func addContent<Content: View>(
        minimumWidth: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> NSSplitViewItem {
        let item = NSSplitViewItem(viewController: host(content()))
        item.minimumThickness = minimumWidth
        splitViewController.addSplitViewItem(item)
        return item
    }

    /// Whether the first column is folded away. Animated, like the toolbar
    /// button that does the same thing.
    public var isSidebarCollapsed: Bool {
        get { splitViewController.splitViewItems.first?.isCollapsed ?? false }
        set { splitViewController.splitViewItems.first?.animator().isCollapsed = newValue }
    }

    private func host<Content: View>(_ content: Content) -> NSHostingController<Content> {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = []
        return controller
    }

    // MARK: Toolbar

    private var declaredToolbar: DeclaredToolbar?

    /// Installs a toolbar holding exactly `entries`, in that order.
    public func installToolbar(identifier: String, entries: [ToolbarEntry]) {
        let declared = DeclaredToolbar(identifier: identifier, entries: entries)
        declaredToolbar = declared
        window?.toolbar = declared.toolbar
    }
}

/// One entry in a toolbar, left to right.
public enum ToolbarEntry {
    /// The standard sidebar button; needs a sidebar column to act on.
    case toggleSidebar
    /// The line that follows the sidebar's edge as it is dragged.
    case sidebarSeparator
    case flexibleSpace
    case space
    /// An item of the app's own. Its identifier must be unique in the bar.
    case item(NSToolbarItem)

    var identifier: NSToolbarItem.Identifier {
        switch self {
        case .toggleSidebar: .toggleSidebar
        case .sidebarSeparator: .sidebarTrackingSeparator
        case .flexibleSpace: .flexibleSpace
        case .space: .space
        case .item(let item): item.itemIdentifier
        }
    }
}

/// A toolbar declared as a list of entries, for any window.
///
/// Not user-customisable: what a bar holds is a design decision, and the menu
/// bar carries everything else. Keep the instance alive for as long as the
/// window — `NSToolbar` holds its delegate weakly.
public final class DeclaredToolbar: NSObject, NSToolbarDelegate {
    public let toolbar: NSToolbar
    private let order: [NSToolbarItem.Identifier]
    private let items: [NSToolbarItem.Identifier: NSToolbarItem]

    public init(identifier: String, entries: [ToolbarEntry]) {
        order = entries.map(\.identifier)
        var items: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
        for case .item(let item) in entries {
            items[item.itemIdentifier] = item
        }
        self.items = items
        toolbar = NSToolbar(identifier: identifier)
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { order }
    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { order }

    public func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier identifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        items[identifier]
    }
}

/// The three shapes a toolbar item takes in this kind of window, built the way
/// AppKit wraps each in its own glass.
public enum ToolbarItems {

    /// A button: a symbol that sends `action` to `target`, or up the responder
    /// chain when `target` is nil. `navigational` puts it before the title,
    /// where a Back control belongs.
    public static func button(
        _ identifier: String,
        symbol: String,
        label: String,
        toolTip: String? = nil,
        navigational: Bool = false,
        target: AnyObject? = nil,
        action: Selector
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: NSToolbarItem.Identifier(identifier))
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        item.label = label
        item.toolTip = toolTip ?? label
        item.isNavigational = navigational
        item.target = target
        item.action = action
        return item
    }

    /// A menu behind a symbol, optionally with a title beside it — the
    /// element selector's shape. `showsIndicator` draws the chevron.
    public static func menu(
        _ identifier: String,
        symbol: String,
        title: String? = nil,
        label: String,
        toolTip: String? = nil,
        showsIndicator: Bool = true,
        menu: NSMenu
    ) -> NSMenuToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: NSToolbarItem.Identifier(identifier))
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        if let title { item.title = title }
        item.label = label
        item.toolTip = toolTip ?? label
        item.showsIndicator = showsIndicator
        item.menu = menu
        return item
    }

    /// A segmented choice — the grid/list switch's shape. `selected` is the
    /// index of the segment that is on; the action reads `selectedIndex`.
    public static func choice(
        _ identifier: String,
        symbols: [String],
        labels: [String],
        selected: Int,
        target: AnyObject?,
        action: Selector
    ) -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(
            itemIdentifier: NSToolbarItem.Identifier(identifier),
            images: symbols.map { NSImage(systemSymbolName: $0, accessibilityDescription: nil)! },
            selectionMode: .selectOne,
            labels: labels,
            target: target,
            action: action
        )
        group.selectedIndex = selected
        return group
    }

    /// The system's search field, which collapses to a magnifier when the
    /// bar is narrow. The delegate hears every keystroke.
    public static func search(
        _ identifier: String,
        delegate: NSSearchFieldDelegate,
        width: CGFloat = 160
    ) -> NSSearchToolbarItem {
        let item = NSSearchToolbarItem(itemIdentifier: NSToolbarItem.Identifier(identifier))
        item.searchField.delegate = delegate
        item.preferredWidthForSearchField = width
        item.resignsFirstResponderWithCancel = true
        return item
    }

    /// Items that belong together, in one piece of glass.
    public static func group(
        _ identifier: String,
        label: String,
        _ items: [NSToolbarItem]
    ) -> NSToolbarItemGroup {
        let group = NSToolbarItemGroup(itemIdentifier: NSToolbarItem.Identifier(identifier))
        group.subitems = items
        group.label = label
        return group
    }
}
