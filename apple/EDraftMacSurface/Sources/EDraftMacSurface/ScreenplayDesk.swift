import AppKit
import EDraftCore

extension NSColor {

    /// The two surfaces a script is drawn on.
    ///
    /// **The rule below was reversed for dark mode on 2026-09-12.** The desk
    /// is no longer painted at all: the scroll view draws no background, the
    /// system's own surface shows through, and `DeskGridView` lays the dots
    /// over it. So in dark mode the sheet is now the *darker* of the two —
    /// #141414 against a desk that measures about #22232D — and this colour
    /// survives only as the Launch window's ground. Everything from here to
    /// the 2026-09-08 note is the history of the arrangement it replaced,
    /// kept because it records what each system colour actually resolved to.
    ///
    /// The old rule, for that history: **the desk is darker than the paper,
    /// in both looks.**
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
            // Warm, and no longer nearly white. #FAF8F4 was chosen when the
            // desk was a painted grey and the page only had to avoid being a
            // lamp on it. The desk is not painted now and resolves to pure
            // white in light mode, so a near-white page had nothing to be
            // seen by — it read as a faint warm patch on a brighter field,
            // the sheet and the surface the wrong way round.
            //
            // This is paper rather than a lightened white: the warmth is
            // carried by dropping blue furthest (R−B = 9, against 6 before),
            // which is what stock does under a lamp. Enough to lift the sheet
            // off the white desk and no further — #F3EFE5 was tried first and
            // read as cream, which is a colour the eye stops on rather than a
            // page it reads through.
            return NSColor(srgbRed: 0.969, green: 0.957, blue: 0.933, alpha: 1) // #F7F4EE
        }
        // The sheet is now the *dark* thing in the window and the desk is the
        // light one — the reverse of the arrangement above, and deliberate:
        // the desk stopped being painted, so it resolves to the system's own
        // mid grey and the page has to be told apart from it downward.
        return NSColor(srgbRed: 0.078, green: 0.078, blue: 0.078, alpha: 1)     // #141414
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

    /// The attention mark on paper — one yellow, bright enough to read as
    /// the highlighter it is against the note's pale wash, and never as a
    /// color on the ink (docs/RFC-HIGHLIGHTER.md). Keyed to the paper the
    /// way the note's tint is: lifted on the dark page, where the flat
    /// yellow goes muddy.
    static let highlightWash = NSColor(name: "highlightWash") { appearance in
        guard appearance.isDark, PagePaper.stored == .inverted else {
            return NSColor(srgbRed: 1.0, green: 0.93, blue: 0.42, alpha: 1)   // #FFEE6B
        }
        return NSColor(srgbRed: 0.98, green: 0.84, blue: 0.42, alpha: 1)      // #FAD66B
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

/// One tile of the desk: the ground, and a dot in its corner.
///
/// Thirty points apart, a point and a half wide, and barely there: a surface
/// the eye feels rather than a pattern it reads. Five percent of ink is the
/// most the desk can carry before it turns into graph paper — measured by
/// eye against the prototype, 2026-09-08.
enum DeskGrid {
    static let spacing: CGFloat = 30
    static let dot: CGFloat = 1.5

    /// The tile is the dot and nothing else: no ground.
    ///
    /// It used to fill itself with `screenplayDesk` first, because it was the
    /// scroll view's *background* colour and a background has to cover. Now
    /// the desk is not painted at all — the system's surface shows through —
    /// so a ground here would put the old colour straight back and undo that.
    /// `DeskGridView` composites this over whatever is behind it.
    static func tile(for appearance: NSAppearance) -> NSImage {
        let size = NSSize(width: spacing, height: spacing)
        return NSImage(size: size, flipped: false) { _ in
            appearance.performAsCurrentDrawingAppearance {
                // Lifted from 0.055/0.045. The dots sat on a near-black desk
                // and now sit on a mid grey, which swallows a wash that faint.
                // Not the same number in both looks, because the grounds are
                // not the same distance from the ink. Dark lays 0.10 white on
                // a #21222E desk and lands 22 levels above it; light laying
                // 0.10 black on a desk that is now pure white lands 26 levels
                // below — the same arithmetic, and invisible, because the eye
                // reads a faint dark mark on a bright field far more weakly
                // than a faint light one on a dark field.
                let ink = appearance.isDark
                    ? NSColor.white.withAlphaComponent(0.10)
                    : NSColor.black.withAlphaComponent(0.18)
                ink.setFill()
                NSBezierPath(ovalIn: NSRect(x: 0, y: 0, width: dot, height: dot)).fill()
            }
            return true
        }
    }
}

/// The dots, and only the dots, over whatever the system puts behind them.
///
/// A view rather than a background colour, because a background colour has to
/// be opaque to be a background: assigning a pattern with a transparent ground
/// to `NSScrollView.backgroundColor` gets it composited against the scroll
/// view's own fill, which is the colour we are trying not to draw. Sitting
/// below the clip view keeps it exactly where the pattern used to be — fixed
/// to the window, not scrolling with the page, the way Freeform's grid is.
final class DeskGridView: NSView {

    override var isOpaque: Bool { false }

    /// Patterns are anchored to the bottom-left of the *window* unless the
    /// phase is stated, so without this the grid slides by a few points
    /// whenever the view's origin moves.
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.patternPhase = convert(NSPoint.zero, to: nil)
        NSColor.screenplayDeskGrid(for: effectiveAppearance).setFill()
        dirtyRect.fill(using: .sourceOver)
    }

    /// A pattern image is a snapshot of one appearance, so it is rebuilt —
    /// not just redrawn — whenever the window changes look.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}
