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

    public var id: URL { url }
}

/// What the launch window shows, decided before anything is drawn.
///
/// The view below renders this and nothing else. That split is deliberate: a
/// SwiftUI view cannot be honestly asserted without a rendering harness, so
/// every decision worth checking — which scripts, what they are called, when
/// they were touched, whether there are any — is made here where a test can
/// read it. A test that only reads back a value the view set would be an echo,
/// and this project has already shipped a blank page green that way.
public nonisolated enum LaunchModel {

    /// How many recents a launch window shows before it stops being a launch
    /// window and starts being a file browser. Finder is the file browser.
    public static let limit = 8

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
                    when: when(modified(url), now: now, calendar: calendar)
                )
            )
        }
        return rows
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

/// eDraft, before a word is written.
///
/// The Mac has no `DocumentGroupLaunchScene` — that API is
/// `@available(macOS, unavailable)` — so this is an ordinary window on the same
/// ground the phone's launch scene draws. Pages does the same thing for the
/// same reason: a document app has no window until a document exists, so the
/// place to greet someone is a window of its own, not a panel inside one.
public struct LaunchWindow: View {
    private let recents: [RecentScript]
    private let onNew: () -> Void
    private let onOpen: () -> Void
    private let onPick: (URL) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var selection: URL?

    public init(
        recents: [RecentScript],
        onNew: @escaping () -> Void,
        onOpen: @escaping () -> Void,
        onPick: @escaping (URL) -> Void
    ) {
        self.recents = recents
        self.onNew = onNew
        self.onOpen = onOpen
        self.onPick = onPick
    }

    public var body: some View {
        ZStack {
            // The desk, and nothing else on it.
            //
            // `LaunchIdentity.Background` also draws a margin rule and the
            // revision run, and both were ported here without asking whether
            // they still meant anything. On the phone that ground is a *frame*
            // around a system launch card, so those read at the edges as
            // texture. Filling a whole window with them, the rule slices the
            // title and the button at 17.6% of a window that is not a page,
            // and the revision run reads as a colour test pattern to anyone
            // who does not already know what it is. Decoration wearing the
            // costume of meaning. The palette is shared; the composition is
            // each platform's own.
            LaunchIdentity.desk.color(scheme).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                header
                actions
                Divider().opacity(0.35)
                // The list takes the room that is left; the empty state is a
                // sentence and must not be stretched into one.
                if recents.isEmpty {
                    emptyState
                    Spacer(minLength: 0)
                } else {
                    recentList
                }
            }
            .padding(.horizontal, 44)
            // Clear of the close/minimise/zoom buttons, which float over the
            // content once the title bar is hidden.
            .padding(.top, 56)
            .padding(.bottom, 28)
        }
        // Sized for the list a writer actually has, not for the longest one
        // `LaunchModel.limit` allows. Eight recents scroll; one does not leave
        // half a window of nothing under it.
        .frame(minWidth: 560, minHeight: 380)
        // The desk is dark in both appearances, so the system controls on it
        // must be too. Without this a bordered button renders for light mode
        // and puts dark lettering on a dark ground.
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            LaunchIdentity.title
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(LaunchIdentity.deskInk.color)
            Text("Screenplays, in plain text that stays yours.")
                .font(.callout)
                .foregroundStyle(LaunchIdentity.deskInk.color.opacity(0.65))
        }
    }

    private var actions: some View {
        HStack(spacing: 12) {
            Button("New Screenplay", action: onNew)
                .keyboardShortcut("n", modifiers: .command)
                .buttonStyle(.borderedProminent)
            Button("Open…", action: onOpen)
                .keyboardShortcut("o", modifiers: .command)
        }
        .controlSize(.large)
    }

    /// Journal's lesson, in this app's words: a mark, a short line, and one
    /// sentence naming one gesture. Not a tour.
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No Recent Scripts")
                .font(.headline)
                .foregroundStyle(LaunchIdentity.deskInk.color)
            Text("To start one, click New Screenplay.")
                .font(.subheadline)
                .foregroundStyle(LaunchIdentity.deskInk.color.opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `List` rather than a `ScrollView` of buttons.
    ///
    /// The hand-rolled version looked identical and was not: a list gives
    /// arrow-key navigation, selection, row semantics for VoiceOver, and the
    /// platform's own hover and highlight — none of which a `VStack` of plain
    /// buttons has, and all of which a writer expects from a list of files.
    /// The desk shows through because `scrollContentBackground` is the
    /// supported way to say so.
    private var recentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LaunchIdentity.deskInk.color.opacity(0.6))

            List(recents, selection: $selection) { script in
                HStack(spacing: 12) {
                    Label(script.name, systemImage: "doc.text")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(LaunchIdentity.deskInk.color)
                    Spacer(minLength: 12)
                    Text(script.when)
                        .font(.caption)
                        .foregroundStyle(LaunchIdentity.deskInk.color.opacity(0.5))
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                // Double-click opens and Return opens the selection, which is
                // what every other list of files on this platform does.
                .onTapGesture(count: 2) { onPick(script.url) }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .help(script.url.path)
                .accessibilityLabel("\(script.name), \(script.when)")
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            // The platform's own soft edge rather than a row guillotined at
            // the window's foot: content that continues should look like it
            // continues. `.soft` is Apple's; a hand-rolled gradient mask would
            // be a second answer to a solved problem.
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .environment(\.defaultMinListRowHeight, 30)
            // Return opens the highlighted row, which is what a list of files
            // does everywhere else on the platform.
            .onKeyPress(.return) {
                guard let selection else { return .ignored }
                onPick(selection)
                return .handled
            }
        }
    }
}
