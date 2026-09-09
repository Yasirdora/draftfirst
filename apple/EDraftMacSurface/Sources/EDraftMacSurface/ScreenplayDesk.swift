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
    /// **Reversed 2026-09-08.** `windowBackgroundColor` is tinted by the desktop
    /// behind the window on this OS — a blue wallpaper made a blue desk,
    /// measured at (28, 28, 40) — and a desk is not a wall. Now that the bar
    /// is glass over the desk itself there is no chrome band to match, so the
    /// desk is its own colour: a neutral near-black, and a neutral light, both
    /// darker than the paper. `ScreenplayDeskTests` holds the neutrality.
    static let screenplayDesk = NSColor(name: "screenplayDesk") { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.106, green: 0.106, blue: 0.110, alpha: 1)   // #1B1B1C
            : NSColor(srgbRed: 0.929, green: 0.929, blue: 0.929, alpha: 1)   // #EDEDED
    }

    /// The desk with its grid of dots — what the scroll view paints.
    ///
    /// A pattern colour rather than a drawn view, so the grid costs nothing
    /// to scroll and stays put under the page, the way Freeform's does. Built
    /// for an appearance, because a pattern image is a snapshot; the canvas
    /// rebuilds it whenever its appearance changes.
    static func screenplayDeskGrid(for appearance: NSAppearance) -> NSColor {
        NSColor(patternImage: DeskGrid.tile(for: appearance))
    }

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

    /// A note's mark in the margin, and the tint of its card.
    ///
    /// Yellow, because that is what a note in a margin has always been and
    /// what Pages uses for a comment — and one yellow rather than two, keyed
    /// to the paper the way `screenplayInk` is: a light page in a dark app
    /// still takes the mark meant for paper. `systemYellow` would follow the
    /// *app's* appearance instead, and go pale on a page that had not changed.
    static let screenplayNoteTint = NSColor(name: "screenplayNoteTint") { appearance in
        guard appearance.isDark, PagePaper.stored == .inverted else {
            // Deep enough to read as ink on off-white rather than as a
            // highlighter, which is what full-strength yellow looks like at
            // 16 points.
            return NSColor(srgbRed: 0.784, green: 0.573, blue: 0.086, alpha: 1) // #C89216
        }
        // Lifted on a dark page, where the same yellow goes muddy.
        return NSColor(srgbRed: 0.961, green: 0.780, blue: 0.290, alpha: 1)     // #F5C74A
    }

    /// The wash over a line that has a note on it, and the stronger one over
    /// the line whose card is open.
    ///
    /// Pages tints the commented words; this tints the whole line, because a
    /// note here is anchored to an element and not to a range of characters.
    /// Neither Fountain's `[[ ]]` nor Final Draft's Note paragraph can say
    /// "these five words", so a highlight that claimed to would be a promise
    /// the file cannot keep the moment it leaves the app.
    ///
    /// Pale enough to read Courier through: it marks the line, it does not
    /// take it over. Measured on the dark page, where a yellow that reads as
    /// a wash on paper turns into an olive slab — 0.30 was a block with type
    /// on it rather than a highlighted line.
    static var screenplayNoteWash: NSColor { screenplayNoteTint.withAlphaComponent(0.10) }
    static var screenplayOpenNoteWash: NSColor { screenplayNoteTint.withAlphaComponent(0.20) }

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

/// One tile of the desk: the ground, and a dot in its corner.
///
/// Thirty points apart, a point and a half wide, and barely there: a surface
/// the eye feels rather than a pattern it reads. Five percent of ink is the
/// most the desk can carry before it turns into graph paper — measured by
/// eye against the prototype, 2026-09-08.
enum DeskGrid {
    static let spacing: CGFloat = 30
    static let dot: CGFloat = 1.5

    static func tile(for appearance: NSAppearance) -> NSImage {
        let size = NSSize(width: spacing, height: spacing)
        return NSImage(size: size, flipped: false) { _ in
            appearance.performAsCurrentDrawingAppearance {
                NSColor.screenplayDesk.setFill()
                NSRect(origin: .zero, size: size).fill()
                let ink = appearance.isDark
                    ? NSColor.white.withAlphaComponent(0.055)
                    : NSColor.black.withAlphaComponent(0.045)
                ink.setFill()
                NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: dot, height: dot)).fill()
            }
            return true
        }
    }
}
