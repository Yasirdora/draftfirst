import AppKit

extension NSColor {

    /// What the page lies on.
    ///
    /// This was `NSColor.underPageBackgroundColor`, which is AppKit's own
    /// behind-the-page grey and is the obvious thing to reach for. On this
    /// system it resolves to #181925 in dark mode: blue, and *darker* than
    /// the page at #1E1E1E. So the desk sank below the sheet it was meant to
    /// hold, the window read as one blue field with some type on it, and no
    /// amount of rearranging the views changed it, because the colour itself
    /// was the whole of the problem.
    ///
    /// Two values, stated once. Light is Apple's own — a page needs a mid
    /// grey behind it and #969696 is that grey. Dark is a neutral one step
    /// above the page, which puts it beside the Navigator's #292A32 rather
    /// than under it, so the two halves of the window read as one surface.
    static let screenplayDesk = NSColor(name: "screenplayDesk") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.165, green: 0.165, blue: 0.169, alpha: 1)   // #2A2A2B
            : NSColor(srgbRed: 0.588, green: 0.588, blue: 0.588, alpha: 1)   // #969696
    }
}
