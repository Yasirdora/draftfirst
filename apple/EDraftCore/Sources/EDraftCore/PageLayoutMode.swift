import Foundation

/// Whether the script is drawn as sheets or as one column.
///
/// These are two jobs, not two tastes. Drafting is reading a column, and the
/// margins repeated at every page boundary — 60 points at the foot of one and
/// 72 at the head of the next — are 132 points of nothing every fifty-five
/// lines. Proofing is the opposite: page turns, a heading stranded at a foot,
/// where a scene lands. Final Draft calls them Normal and Page; Fade In,
/// Highland and WriterDuet all draw the same line.
///
/// What does *not* change between them is pagination. The engine decides
/// which line begins which page and neither mode may move it — continuous
/// only stops drawing the margins, and marks the boundary with the page
/// number instead, because a page is a minute of screen time and a writer
/// who cannot count them has lost their clock.
public nonisolated enum PageLayoutMode: String, CaseIterable, Sendable {
    /// Sheets, with their margins, as printed.
    case pages
    /// One column, the vertical page margins collapsed, breaks marked.
    case continuous

    public var title: String {
        switch self {
        case .pages: "Pages"
        case .continuous: "Continuous"
        }
    }

    // MARK: - Where it is kept

    public static let defaultsKey = "PageLayoutMode"

    /// Pages, because that is the promise the app makes: the page count in
    /// the window's subtitle is a running time, and it is only trustworthy if
    /// what the writer sees is what prints. Continuous is one keystroke away.
    public static var stored: PageLayoutMode {
        read(from: .standard)
    }

    public static func read(from defaults: UserDefaults) -> PageLayoutMode {
        defaults.string(forKey: defaultsKey).flatMap(PageLayoutMode.init(rawValue:)) ?? .pages
    }

    public static func store(_ mode: PageLayoutMode, in defaults: UserDefaults = .standard) {
        defaults.set(mode.rawValue, forKey: defaultsKey)
    }
}
