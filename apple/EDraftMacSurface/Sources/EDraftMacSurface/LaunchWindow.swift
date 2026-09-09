import AppKit
import EDraftUI
import SwiftUI

/// One script a writer had open before.
public nonisolated struct RecentScript: Identifiable, Equatable, Sendable {
    public let url: URL
    /// The file's name without `.draft` — what the writer called it, not what
    /// the filesystem calls it.
    public let name: String
    /// "Today", "Yesterday", or a date. See `LaunchModel.when`.
    public let when: String
    /// Starred by the writer. A recent is a file, and a file has nowhere to
    /// carry a star, so the star is kept by path — see `LaunchFavorites`.
    public let isFavorite: Bool

    public var id: URL { url }
}

/// What the launch window shows, decided before anything is drawn.
///
/// The view below renders this and nothing else. That split is deliberate: a
/// SwiftUI view cannot be honestly asserted without a rendering harness, so
/// every decision worth checking — which scripts, what they are called, when
/// they were touched, which come first — is made here where a test can read it.
public nonisolated enum LaunchModel {

    /// How many recents the gallery shows before it stops being a launch
    /// window and starts being a file browser. Finder is the file browser.
    /// Cards are small, so more of them fit than rows did.
    public static let limit = 24

    /// Where the grid-or-list choice is remembered.
    public static let layoutKey = "LaunchGalleryGrid"

    /// The rows for a run of recent document URLs, newest first as the
    /// document controller supplies them.
    ///
    /// Duplicates are dropped — the same script opened twice is one script —
    /// and the list is capped. A URL whose file has gone is dropped too: the
    /// document controller prunes lazily, and a row that cannot be opened is
    /// worse than a row that is missing.
    public static func rows(
        from urls: [URL],
        now: Date = Date(),
        calendar: Calendar = .current,
        favorites: Set<URL> = [],
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        modified: (URL) -> Date? = { url in
            try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
    ) -> [RecentScript] {
        var seen = Set<URL>()
        var rows: [RecentScript] = []
        for url in urls {
            guard rows.count < limit else { break }
            let key = url.standardizedFileURL
            guard !seen.contains(key), exists(url) else { continue }
            seen.insert(key)
            rows.append(
                RecentScript(
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    when: when(modified(url), now: now, calendar: calendar),
                    isFavorite: favorites.contains(key)
                )
            )
        }
        return rows
    }

    /// The rows a search narrows to, starred ones first. An empty search is
    /// everything.
    public static func filtered(_ rows: [RecentScript], query: String) -> [RecentScript] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = needle.isEmpty
            ? rows
            : rows.filter { $0.name.localizedCaseInsensitiveContains(needle) }
        return matching.filter(\.isFavorite) + matching.filter { !$0.isFavorite }
    }

    /// A date said the way a person would say it. Today and yesterday have
    /// names; anything older is a date, because "5 days ago" is arithmetic the
    /// reader has to undo.
    public static func when(
        _ date: Date?,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String {
        guard let date else { return "" }
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// The starred recents, kept by path in `UserDefaults`.
public enum LaunchFavorites {
    public static let key = "LaunchFavorites"

    public static func load(from defaults: UserDefaults = .standard) -> Set<URL> {
        Set((defaults.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0).standardizedFileURL })
    }

    public static func toggle(_ url: URL, in defaults: UserDefaults = .standard) {
        var stars = load(from: defaults)
        let path = url.standardizedFileURL
        if stars.contains(path) { stars.remove(path) } else { stars.insert(path) }
        defaults.set(stars.map(\.path).sorted(), forKey: key)
    }
}

/// What the launch window can ask the app to do.
///
/// The window knows nothing about documents or files; each of these is a door
/// the app wires, which is what keeps this view testable and the file
/// operations in the one place that knows about `NSDocumentController`.
public struct LaunchActions {
    public var new: () -> Void
    public var open: () -> Void
    public var pick: (URL) -> Void
    /// The one way to a second window; everything else opens in this one.
    public var openInNewWindow: (URL) -> Void
    public var rename: (URL, String) -> Void
    public var duplicate: (URL) -> Void
    public var trash: (URL) -> Void
    public var toggleFavorite: (URL) -> Void

    public init(
        new: @escaping () -> Void,
        open: @escaping () -> Void,
        pick: @escaping (URL) -> Void,
        openInNewWindow: @escaping (URL) -> Void,
        rename: @escaping (URL, String) -> Void,
        duplicate: @escaping (URL) -> Void,
        trash: @escaping (URL) -> Void,
        toggleFavorite: @escaping (URL) -> Void
    ) {
        self.new = new
        self.open = open
        self.pick = pick
        self.openInNewWindow = openInNewWindow
        self.rename = rename
        self.duplicate = duplicate
        self.trash = trash
        self.toggleFavorite = toggleFavorite
    }
}

/// eDraft, before a word is written: the library.
///
/// The Mac has no `DocumentGroupLaunchScene` — that API is
/// `@available(macOS, unavailable)` — so this is an ordinary document-style
/// window: a title bar, a toolbar with the plus menu, the grid/list switch and
/// search, and below it the name, the two doors, and the recent scripts as lit
/// sheets. The search and the switch live in the toolbar, so this view is
/// handed what they say and renders it — every decision worth testing is in
/// `LaunchModel`.
public struct LaunchWindow: View {
    private let recents: [RecentScript]
    private let query: String
    private let showsGrid: Bool
    private let actions: LaunchActions

    @State private var renaming: RecentScript?
    @State private var newName = ""

    public init(recents: [RecentScript], query: String, showsGrid: Bool, actions: LaunchActions) {
        self.recents = recents
        self.query = query
        self.showsGrid = showsGrid
        self.actions = actions
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 32)
                    .padding(.bottom, 24)
                Divider()
                library
                    .padding(.top, 24)
            }
            .padding(.horizontal, 48)
            .padding(.bottom, 32)
        }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background(Color(nsColor: .screenplayDesk))
        .frame(minWidth: 640, minHeight: 420)
        .alert("Rename Screenplay", isPresented: isRenaming, presenting: renaming) { script in
            TextField("Name", text: $newName)
            Button("Rename") { actions.rename(script.url, newName) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The file keeps its place; only its name changes.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            LaunchIdentity.title
                .font(.system(size: 40, weight: .bold))
            Text("Screenplays, in plain text that stays yours.")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
            // Their shortcuts belong to the menu bar, which reaches this
            // window through the responder chain.
            HStack(spacing: 12) {
                Button("New Screenplay", action: actions.new)
                    .buttonStyle(.borderedProminent)
                Button("Open…", action: actions.open)
                    .buttonStyle(.bordered)
            }
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .padding(.top, 16)
        }
    }

    // MARK: Library

    private var visible: [RecentScript] {
        LaunchModel.filtered(recents, query: query)
    }

    private var isRenaming: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    @ViewBuilder
    private var library: some View {
        if recents.isEmpty {
            emptyState
        } else if visible.isEmpty {
            Text("Nothing matches “\(query)”.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if showsGrid {
            grid
        } else {
            list
        }
    }

    /// Journal's lesson, in this app's words: a mark, a short line, and one
    /// sentence naming one gesture. Not a tour.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Recent Scripts")
                .font(.headline)
            Text("To start one, click New Screenplay.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 24, alignment: .top)],
            alignment: .leading,
            spacing: 32
        ) {
            ForEach(visible) { script in
                Button { actions.pick(script.url) } label: {
                    VStack(alignment: .leading, spacing: 12) {
                        sheet.aspectRatio(0.77, contentMode: .fit)
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                title(script)
                                Text(script.when)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            menu(script)
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(script.url.path)
            }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(visible) { script in
                Button { actions.pick(script.url) } label: {
                    HStack(spacing: 16) {
                        sheet.frame(width: 52, height: 36)
                        title(script)
                        Spacer()
                        Text(script.when)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        menu(script)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(script.url.path)
                Divider()
            }
        }
    }

    /// A lit sheet on the desk — the page, before it is opened.
    private var sheet: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white)
            .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
    }

    private func title(_ script: RecentScript) -> some View {
        HStack(spacing: 4) {
            Text(script.name)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            if script.isFavorite {
                Image(systemName: "star.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorite")
            }
        }
    }

    private func menu(_ script: RecentScript) -> some View {
        Menu {
            Button("Open in New Window") { actions.openInNewWindow(script.url) }
            Divider()
            Button("Rename…") {
                newName = script.name
                renaming = script
            }
            Button("Duplicate") { actions.duplicate(script.url) }
            Button(script.isFavorite ? "Unfavorite" : "Favorite") { actions.toggleFavorite(script.url) }
            Divider()
            Button("Move to Trash", role: .destructive) { actions.trash(script.url) }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Actions for \(script.name)")
    }
}
