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

    /// The exact values, because the relationship tests below cannot catch
    /// the bug on their own: resolved *outside* a window,
    /// `underPageBackgroundColor` is #282828 and passes every one of them.
    /// It was only wrong in a window. Pinning the numbers is what notices a
    /// semantic colour being put back.
    func testTheDeskIsTheStatedGreyAndNotASemanticColour() {
        XCTAssertEqual(rgb(.screenplayDesk, in: .darkAqua).r, 30)
        XCTAssertEqual(rgb(.screenplayDesk, in: .aqua).r, 150)
    }

    /// The desk is the chrome's own value in dark, and that is not a
    /// coincidence to be tidied away: the toolbar draws
    /// `windowBackgroundColor` behind itself, and any other desk meets it at
    /// a step across the top of the window. Change one and this notices.
    func testTheDarkDeskMeetsTheToolbarWithoutAStep() {
        XCTAssertEqual(
            rgb(.screenplayDesk, in: .darkAqua).r,
            rgb(.windowBackgroundColor, in: .darkAqua).r,
            "a desk that is not the chrome's value draws a line under the toolbar"
        )
    }

    /// Neutral, in both looks. A desk with a hue in it tints everything drawn
    /// on it, and the one this replaced had a blue cast of 13 — which is
    /// exactly what "the background is ugly dark blue" was describing.
    func testTheDeskHasNoColourInIt() {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let desk = rgb(.screenplayDesk, in: name)
            XCTAssertLessThanOrEqual(
                abs(desk.b - desk.r), 1,
                "the desk has a cast in \(name.rawValue): "
                    + String(format: "#%02X%02X%02X", desk.r, desk.g, desk.b)
            )
            XCTAssertLessThanOrEqual(abs(desk.g - desk.r), 1)
        }
    }

    /// One rule, both looks: a sheet is the lit thing and the desk is
    /// darker. Dark mode used to invert it — the desk lighter than the page —
    /// which made the page a hole rather than a sheet, and put a step between
    /// the desk and the chrome above it.
    func testTheDeskIsDarkerThanThePaperInBothLooks() {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let desk = rgb(.screenplayDesk, in: name)
            let paper = rgb(.screenplayPaper, in: name)

            XCTAssertGreaterThanOrEqual(
                paper.r - desk.r, 10,
                "in \(name.rawValue) the desk is not below the sheet: "
                    + "desk \(desk.r), paper \(paper.r)"
            )
        }
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
            let desk = rgb(.screenplayDesk, in: .darkAqua)

            XCTAssertLessThan(paper.r, 60, "an inverted page is a dark page")
            XCTAssertGreaterThanOrEqual(
                paper.r - desk.r, 10, "and is still lighter than the desk under it"
            )
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
