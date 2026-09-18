import XCTest
import AppKit
import EDraftCore
@testable import EDraftMacSurface

/// The desk is a stated colour, and that is the point of it.
///
/// It used to be `NSColor.underPageBackgroundColor`, which is the obvious
/// choice and reads correctly in a colour dump: #282828 in dark, comfortably
/// lighter than the page at #1E1E1E. In an actual window on an actual Mac it
/// resolved to #181925 — blue, and *darker* than the page — because a
/// semantic colour is resolved against the window, and the window's own
/// ground answers to the writer's desktop picture. The sheet sank into the
/// desk and the window read as one flat blue field.
///
/// So this does not test that the desk looks nice, which no test can. It pins
/// the thing that broke: that the desk is a fixed value, not a semantic
/// colour something else is entitled to re-resolve. Swap either literal back
/// for a system colour and these fail.
@MainActor
final class ScreenplayDeskTests: XCTestCase {

    private func rgb(_ color: NSColor, in name: NSAppearance.Name) -> (r: Int, g: Int, b: Int) {
        var out = (r: 0, g: 0, b: 0)
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let c = color.usingColorSpace(.sRGB)!
            out = (
                Int((c.redComponent * 255).rounded()),
                Int((c.greenComponent * 255).rounded()),
                Int((c.blueComponent * 255).rounded())
            )
        }
        return out
    }

    /// The desk is Apple's own behind-the-page colour, and is meant to be.
    ///
    /// It was a stated literal for a while, because with the old near-black
    /// page the tinted value resolved *darker* than the sheet and the page
    /// became a hole. The page is paper now, so the reason is gone — and a
    /// fixed grey made this the one window on the desktop that does not
    /// answer to the writer's Appearance settings. Measured against Finder in
    /// the same session: its window edge #1F1E2C, sidebar #1D1C26, content
    /// #21202C, all tinted, all within a few levels of each other. This
    /// window now lands within two of each.
    /// The desk is a neutral, in both looks: `windowBackgroundColor` takes the
    /// desktop's tint, and a blue wallpaper once made a blue desk.
    func testTheDeskIsNeutralInBothLooks() {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let desk = rgb(.screenplayDesk, in: name)
            XCTAssertEqual(desk.r, desk.g, accuracy: 2, "\(name.rawValue)")
            XCTAssertEqual(desk.g, desk.b, accuracy: 2, "\(name.rawValue)")
        }
    }

    /// Near-black, not black: a page on a black desk is a lamp, and a desk
    /// that is pure black shows no grid.
    func testTheDarkDeskIsNearBlack() {
        let desk = rgb(.screenplayDesk, in: .darkAqua)
        XCTAssertGreaterThanOrEqual(desk.r, 16)
        XCTAssertLessThanOrEqual(desk.r, 40)
    }

    /// The desk is no longer painted, and the dots carry no ground.
    ///
    /// This replaces `testTheDarkDeskIsAlwaysBelowThePaper`, which pinned the
    /// old arrangement — a near-black desk under a lighter sheet. That rule is
    /// deliberately reversed: the desk resolves to the system's own surface
    /// and the dark page is now the darker of the two. What has to hold
    /// instead is that nothing puts a ground back, in either direction — a
    /// fill in the tile would repaint the desk one dot-spacing at a time.
    @MainActor
    func testTheDeskTileIsDotsAndNoGround() {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let tile = DeskGrid.tile(for: NSAppearance(named: name)!)
            let shot = NSBitmapImageRep(data: tile.tiffRepresentation!)!
            // The far corner from the dot, which sits at the tile's origin.
            let corner = shot.colorAt(x: shot.pixelsWide - 1, y: 0)
            XCTAssertEqual(
                Double(corner?.alphaComponent ?? 1), 0, accuracy: 0.01,
                "\(name.rawValue): the tile has a ground, so the desk is painted after all"
            )
        }
    }

    /// The dots have to be legible in both looks, and one alpha cannot do
    /// that — the two grounds sit at opposite ends of the range.
    ///
    /// Dark lays white ink on a surface near #21222E, where a little goes a
    /// long way. Light lays black ink on a desk that is now pure white, and
    /// the same alpha reads as nothing: a faint dark mark on a bright field
    /// is far weaker to the eye than a faint light one on a dark field. This
    /// composites the real tile over the real ground and pins the distance.
    @MainActor
    func testTheDotsAreLegibleOnTheGroundEachLookPutsThemOn() {
        // The surfaces the grid actually sits on, measured on screen now that
        // the desk is unpainted: pure white in light, about #21222E in dark.
        let grounds: [(NSAppearance.Name, NSColor, CGFloat)] = [
            (.aqua, .white, 35),
            (.darkAqua, NSColor(srgbRed: 33 / 255, green: 34 / 255, blue: 46 / 255, alpha: 1), 18)
        ]
        for (name, ground, leastVisibleStep) in grounds {
            let shot = NSBitmapImageRep(
                data: DeskGrid.tile(for: NSAppearance(named: name)!).tiffRepresentation!
            )!
            // The densest pixel of the dot, wherever antialiasing has put it.
            var ink: NSColor?
            for x in 0..<shot.pixelsWide {
                for y in 0..<shot.pixelsHigh {
                    guard let here = shot.colorAt(x: x, y: y) else { continue }
                    if here.alphaComponent > (ink?.alphaComponent ?? 0) { ink = here }
                }
            }
            let dot = ink!.usingColorSpace(.sRGB)!
            let under = ground.usingColorSpace(.sRGB)!
            let a = dot.alphaComponent
            let landed = under.redComponent * (1 - a) + dot.redComponent * a
            let step = abs(landed - under.redComponent) * 255

            XCTAssertGreaterThanOrEqual(
                step, leastVisibleStep,
                "\(name.rawValue): the dots land \(Int(step)) levels off the desk and vanish"
            )
        }
    }

    /// And the scroll view does not fill either — clearing only the scroll
    /// view leaves the clip view still painting, which was the bug that made
    /// this look like it had not worked at all.
    @MainActor
    func testTheSurfaceDrawsNoDeskBehindThePage() {
        let surface = ScriptSurface()
        surface.bind(to: EditorState(source: "INT. A - DAY"))

        XCTAssertFalse(surface.scrollView.drawsBackground)
        XCTAssertFalse(surface.scrollView.contentView.drawsBackground)
        XCTAssertTrue(
            surface.scrollView.subviews.contains { $0 is DeskGridView },
            "without the grid view the dots have nowhere to be drawn"
        )
    }

    /// In light the sheet is told from the desk by its shadow and corner, not
    /// by a border — the border was removed to avoid the double-line where
    /// pages meet.
    func testTheLightPageHasAnEdgeToBeToldApartBy() {
        let canvas = PageCanvasView()
        canvas.appearance = NSAppearance(named: .aqua)
        _ = canvas.pageView          // the first sheet, created on demand
        canvas.applyAppearance()

        XCTAssertEqual(canvas.pageView.layer?.borderWidth, 0)
        XCTAssertGreaterThan(
            canvas.pageView.layer?.shadowOpacity ?? 0, 0,
            "without a shadow a white page on a white desk has nothing to be seen by"
        )
        XCTAssertEqual(canvas.pageView.layer?.cornerRadius, 2)
    }

    // MARK: - What the page is made of

    /// Saves and restores the writer's real choice, so running the suite does
    /// not silently change how their app looks.
    private func withPaper(_ paper: PagePaper, _ body: () -> Void) {
        let original = PagePaper.stored
        PagePaper.store(paper)
        defer { PagePaper.store(original) }
        body()
    }

    /// The default, and the reason the header can draw a gradient at all.
    ///
    /// Pages, Preview and Word darken the chrome and leave the document
    /// alone. With a dark page the fade at the top of the window had fourteen
    /// levels to travel; with paper it has over two hundred, which is the
    /// difference between an effect that is present and one that is visible.
    func testTheDefaultPageIsPaperEvenInTheDark() {
        withPaper(.paper) {
            let paper = rgb(.screenplayPaper, in: .darkAqua)
            let desk = rgb(.screenplayDesk, in: .darkAqua)

            XCTAssertGreaterThan(
                paper.r - desk.r, 200,
                "the header fade is only as visible as the distance it travels"
            )
        }
    }

    /// And the writer can have the dark page back.
    func testTheInvertedPageIsDarkAndStillASheet() {
        withPaper(.inverted) {
            let paper = rgb(.screenplayPaper, in: .darkAqua)

            XCTAssertLessThan(paper.r, 80, "an inverted page is a dark page")
        }
    }

    /// The ink is paired with the paper, not with the app.
    ///
    /// `labelColor` is white in a dark app, and a light page in a dark app is
    /// exactly the case it cannot know about — the script would have been
    /// white on off-white. The caret has the same bug one layer down, which
    /// is why `insertionPointColor` is set from here too.
    func testInkFollowsThePaperRatherThanTheAppearance() {
        withPaper(.paper) {
            let ink = rgb(.screenplayInk, in: .darkAqua)
            XCTAssertLessThan(ink.r, 60, "dark type belongs on a light page")
        }
        withPaper(.inverted) {
            let ink = rgb(.screenplayInk, in: .darkAqua)
            XCTAssertGreaterThan(ink.r, 190, "light type belongs on a dark page")
        }
    }

    /// In daylight the choice means nothing: a page is paper either way.
    func testTheChoiceDoesNotReachLightMode() {
        var byChoice: [(Int, Int, Int)] = []
        for choice in PagePaper.allCases {
            withPaper(choice) { byChoice.append(rgb(.screenplayPaper, in: .aqua)) }
        }
        XCTAssertEqual(byChoice[0].0, byChoice[1].0)
    }
}
