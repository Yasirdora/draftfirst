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
    func testTheDeskIsTheWindowsOwnGround() {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            XCTAssertEqual(
                rgb(.screenplayDesk, in: name).r,
                rgb(.windowBackgroundColor, in: name).r,
                "the desk left the ground the Navigator's glass is laid on, and "
                    + "will read as a panel beside it again"
            )
        }
    }

    /// The relationship that was actually wrong, and the one Finder gets
    /// right: the area beside a sidebar is *not darker* than the sidebar.
    ///
    /// Measured on screen, same wallpaper: Finder's sidebar #1D1C26 against
    /// its content #21202C, content lighter by four. This window had it
    /// inverted — sidebar 28, desk 24 — with `underPageBackgroundColor`,
    /// which is why the Navigator read as a panel raised off the page.
    func testTheDarkDeskIsNotBelowTheChrome() {
        let desk = rgb(.screenplayDesk, in: .darkAqua)
        let chrome = rgb(.windowBackgroundColor, in: .darkAqua)

        XCTAssertGreaterThanOrEqual(
            desk.r, chrome.r,
            "a desk below the window's own ground makes the sidebar a raised panel"
        )
    }

    /// One rule, every combination: a sheet is the lit thing and the desk is
    /// darker. It is what makes a page read as a page, and it is the distance
    /// the header's fade travels across.
    ///
    /// This is the assertion that caught the desk moving back to
    /// `underPageBackgroundColor`: #282828 left the *dark* page four levels
    /// above its own desk, which is not a sheet, it is a slightly different
    /// patch of desk.
    func testTheDarkDeskIsAlwaysBelowThePaper() {
        for choice in PagePaper.allCases {
            withPaper(choice) {
                let desk = rgb(.screenplayDesk, in: .darkAqua)
                let paper = rgb(.screenplayPaper, in: .darkAqua)
                XCTAssertGreaterThanOrEqual(
                    paper.r - desk.r, 10,
                    "\(choice.title): desk \(desk.r), paper \(paper.r)"
                )
            }
        }
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
