import AppKit
import EDraftCore

extension NSColor {

    /// The two surfaces a script is drawn on, and the one rule that orders
    /// them: **the desk is darker than the paper, in both looks.**
    ///
    /// That is how a page has always read — a lit sheet on a darker surface —
    /// and it is what Pages shows. It also decides the header: the system
    /// fades the page into the chrome at the top of the window, and a fade is
    /// only as visible as the distance it travels. Paper on a near-black desk
    /// gives it about two hundred levels, which is the gradient Pages draws.
    ///
    /// Dark mode used to have it inverted — desk #2A2A2B under a #1E1E1E page
    /// — so the sheet was a hole, the desk met the toolbar at a twelve-level
    /// step that read as a line, and the fade had nowhere to go.
    ///
    /// The dark desk is the chrome's own `windowBackgroundColor`, so there is
    /// nothing left to step between; `ScreenplayDeskTests` ties the two.
    /// Behind the page: the window's own ground, in both looks.
    ///
    /// Measured against Finder, on the same wallpaper, twice. Finder's
    /// content area is *lighter* than its sidebar — #1D1C26 against #21202C —
    /// and that relationship is what makes a sidebar read as part of a window
    /// rather than as a panel raised off it.
    ///
    /// `underPageBackgroundColor` gets it backwards here. It is AppKit's
    /// behind-the-page grey, meant for a white page floating alone in
    /// Preview, and it resolved *below* the Navigator in dark (24 against 28)
    /// and to a #969696 slab in light — an eighty-nine level step from a
    /// near-white sidebar. Both were measured on screen; both read as two
    /// panels bolted together.
    ///
    /// `windowBackgroundColor` is the ground the Navigator's glass is already
    /// laid on, so it cannot disagree with it: 31 against a 28 sidebar in
    /// dark, which is Finder's own +3, and the same colour on both sides of
    /// the divider in light. The page is told from it by its own edge and
    /// shadow, which is how a sheet is told from a surface.
    static var screenplayDesk: NSColor { .windowBackgroundColor }

    /// The page. Light unless the writer has asked for a dark one — see
    /// `PagePaper`, and note that the choice only means anything in dark
    /// mode, because in light the page is paper either way.
    static let screenplayPaper = NSColor(name: "screenplayPaper") { appearance in
        guard appearance.isDark, PagePaper.stored == .inverted else {
            // Warm rather than pure white: it is the same off-white the phone
            // has always drawn, and against a near-black desk pure white is a
            // lamp rather than a page.
            return NSColor(srgbRed: 0.980, green: 0.973, blue: 0.957, alpha: 1) // #FAF8F4
        }
        // Lifted from #2C2C2E once the desk went back to
        // `underPageBackgroundColor`: four levels above it is not a sheet,
        // it is a slightly different patch of desk. `ScreenplayDeskTests`
        // holds the gap.
        return NSColor(srgbRed: 0.227, green: 0.227, blue: 0.235, alpha: 1)     // #3A3A3C
    }

    /// What is written on it. Tied to the paper rather than to the app's
    /// appearance, because a light page in a dark app takes dark type — this
    /// is the pairing `labelColor` cannot know about.
    static let screenplayInk = NSColor(name: "screenplayInk") { appearance in
        guard appearance.isDark, PagePaper.stored == .inverted else {
            return NSColor(srgbRed: 0.106, green: 0.106, blue: 0.118, alpha: 1) // #1B1B1E
        }
        return .labelColor
    }

    /// A prediction, and a hint, in the same ink at less weight — so they
    /// stay legible on either page.
    static var screenplayGhostInk: NSColor { screenplayInk.withAlphaComponent(0.45) }
    static var screenplayHintInk: NSColor { screenplayInk.withAlphaComponent(0.28) }
}

extension NSAppearance {
    /// `bestMatch` rather than a name comparison, so vibrant and
    /// accessibility appearances answer as the mode they belong to.
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
