import AppKit

extension NSColor {

    /// The two surfaces a script is drawn on, and the one rule that orders
    /// them: **the desk is darker than the paper, in both looks.**
    ///
    /// That is how a page has always read — a lit sheet on a darker surface —
    /// and it is what Pages shows: a white page on grey. It also decides the
    /// header, which is why it is stated here rather than left to whichever
    /// semantic colour seemed closest.
    ///
    /// Dark mode had it backwards. The desk was `underPageBackgroundColor`
    /// (#282828 nominally, #181925 once a window resolved it) and the paper
    /// was `textBackgroundColor` (#1E1E1E), so the ground was *lighter* than
    /// the sheet on it. Two things followed. The page stopped reading as a
    /// page, because a sheet darker than its surround is a hole. And the
    /// toolbar — whose own ground is `windowBackgroundColor`, #1E1E1E — met
    /// the desk at a twelve-level step, which is a visible line across the
    /// top of the window and the opposite of the gradient the system was
    /// trying to draw there.
    ///
    /// With the desk at the chrome's own value there is nothing to step
    /// between, and the scroll edge effect has the paper to ramp from.
    static let screenplayDesk = NSColor(name: "screenplayDesk") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.118, green: 0.118, blue: 0.118, alpha: 1)   // #1E1E1E
            : NSColor(srgbRed: 0.588, green: 0.588, blue: 0.588, alpha: 1)   // #969696
    }

    /// The page. White on paper; in the dark, the lightest thing in the
    /// window rather than the darkest, so it is still a sheet.
    static let screenplayPaper = NSColor(name: "screenplayPaper") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.173, green: 0.173, blue: 0.180, alpha: 1)   // #2C2C2E
            : .white
    }
}
