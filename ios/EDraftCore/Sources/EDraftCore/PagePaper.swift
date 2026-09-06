import Foundation

/// Whether the page goes dark with the app, or stays paper.
///
/// Pages, Preview and Word all darken their chrome at night and leave the
/// document alone: a page is a page, and what a writer is looking at is the
/// thing that will be printed. eDraft used to invert the paper as well, which
/// is a real preference some writers hold — and it is also why the header
/// could not draw the soft edge the system offers, because that effect fades
/// the page into the chrome and a near-black page fading into near-black
/// chrome has fourteen levels to do it in. Paper gives it two hundred.
///
/// So it is the writer's choice, with the platform's answer as the default.
public nonisolated enum PagePaper: String, CaseIterable, Sendable {
    /// The page stays light however dark the app is. The default.
    case paper
    /// The page darkens with everything else.
    case inverted

    public var title: String {
        switch self {
        case .paper: "Paper"
        case .inverted: "Dark Page"
        }
    }

    /// What it does, for a menu that has room to say so.
    public var explanation: String {
        switch self {
        case .paper: "The page stays light, as it prints."
        case .inverted: "The page darkens with the app."
        }
    }

    // MARK: - Where it is kept

    public static let defaultsKey = "PagePaper"

    public static var stored: PagePaper {
        read(from: .standard)
    }

    public static func read(from defaults: UserDefaults) -> PagePaper {
        defaults.string(forKey: defaultsKey).flatMap(PagePaper.init(rawValue:)) ?? .paper
    }

    public static func store(_ paper: PagePaper, in defaults: UserDefaults = .standard) {
        defaults.set(paper.rawValue, forKey: defaultsKey)
    }
}
