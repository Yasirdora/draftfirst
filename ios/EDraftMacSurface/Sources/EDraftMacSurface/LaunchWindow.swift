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
            LaunchIdentity.Background()
            VStack(alignment: .leading, spacing: 28) {
                header
                actions
                Divider().opacity(0.35)
                if recents.isEmpty { emptyState } else { recentList }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 44)
            .padding(.top, 44)
            .padding(.bottom, 24)
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            LaunchIdentity.title
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(LaunchIdentity.ink.resolved(scheme))
            Text("Screenplays, in plain text that stays yours.")
                .font(.callout)
                .foregroundStyle(LaunchIdentity.ink.resolved(scheme).opacity(0.65))
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
                .foregroundStyle(LaunchIdentity.ink.resolved(scheme))
            Text("To start one, click New Screenplay.")
                .font(.subheadline)
                .foregroundStyle(LaunchIdentity.ink.resolved(scheme).opacity(0.6))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LaunchIdentity.ink.resolved(scheme).opacity(0.6))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(recents) { script in
                        Button { onPick(script.url) } label: {
                            HStack {
                                Text(script.name)
                                    .foregroundStyle(LaunchIdentity.ink.resolved(scheme))
                                Spacer()
                                Text(script.when)
                                    .font(.caption)
                                    .foregroundStyle(
                                        LaunchIdentity.ink.resolved(scheme).opacity(0.5)
                                    )
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        .help(script.url.path)
                    }
                }
            }
        }
    }
}
