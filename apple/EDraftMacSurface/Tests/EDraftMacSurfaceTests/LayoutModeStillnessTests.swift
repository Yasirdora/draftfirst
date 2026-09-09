import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// Switching between sheets and one column must not move the writer.
///
/// The mode change moves every line: `pages` pushes each page's first line
/// down onto its own sheet, and the distance accumulates — by page ten a line
/// stands more than a thousand points from where `continuous` puts it. The
/// surface anchors on the character at the top of the viewport and puts it
/// back, and this is what says it actually does.
///
/// `DiscreteSheetsTests` already had a case for this and allowed 400
/// characters of drift — five lines of dialogue — in one direction only. That
/// tolerance is why "the text jumps to a completely different page, worse the
/// further you scroll" was reported from the app rather than caught here.
@MainActor
final class LayoutModeStillnessTests: XCTestCase {

    override func setUp() {
        super.setUp()
        let original = PageLayoutMode.stored
        addTeardownBlock { PageLayoutMode.store(original) }
    }

    /// Long enough that the accumulated gap between the two modes is larger
    /// than the window — which is the condition the bug needs.
    private func script(scenes: Int = 60) -> [ScriptElement] {
        var elements: [ScriptElement] = []
        for beat in 1...scenes {
            elements.append(ScriptElement(type: .scene, text: "INT. ROOM \(beat) - DAY"))
            elements.append(ScriptElement(
                type: .action,
                text: "Action for beat \(beat). The road holds its breath for a full line of the page."
            ))
            elements.append(ScriptElement(type: .character, text: "MARA"))
            elements.append(ScriptElement(
                type: .dialogue,
                text: "Line \(beat), spoken plainly and without hurry at all."
            ))
        }
        return elements
    }

    private func surface(mode: PageLayoutMode) -> ScriptSurface {
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
        surface.render(script())
        surface.setLayoutMode(mode)
        surface.scrollView.layoutSubtreeIfNeeded()
        return surface
    }

    private func scroll(_ surface: ScriptSurface, toFraction fraction: CGFloat) {
        let clip = surface.scrollView.contentView
        let travel = max(0, surface.canvas.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: (travel * fraction).rounded()))
        surface.scrollView.reflectScrolledClipView(clip)
    }

    /// A line, not a character offset: what the writer notices is the words at
    /// the top of the window, and one line is the honest unit of "still".
    private func assertStill(
        _ surface: ScriptSurface,
        _ change: () -> Void,
        _ what: String,
        line: UInt = #line
    ) throws {
        let before = try XCTUnwrap(surface.topmostVisibleCharacter)
        change()
        let after = try XCTUnwrap(surface.topmostVisibleCharacter)
        // Roughly one line of dialogue. Anything more and the words at the top
        // of the window are different words.
        XCTAssertEqual(
            after, before, accuracy: 60,
            "\(what): the writer moved \(abs(after - before)) characters",
            line: line
        )
    }

    func testGoingToOneColumnKeepsTheWriterInPlaceAtEveryDepth() throws {
        for fraction in [0.25, 0.55, 0.85] as [CGFloat] {
            let surface = surface(mode: .pages)
            scroll(surface, toFraction: fraction)
            try assertStill(surface, { surface.setLayoutMode(.continuous) },
                            "pages → continuous at \(Int(fraction * 100))%")
        }
    }

    /// The return trip, which the old case never made — and the one the app
    /// was reported to break.
    func testGoingBackToSheetsKeepsTheWriterInPlaceAtEveryDepth() throws {
        for fraction in [0.25, 0.55, 0.85] as [CGFloat] {
            let surface = surface(mode: .continuous)
            scroll(surface, toFraction: fraction)
            try assertStill(surface, { surface.setLayoutMode(.pages) },
                            "continuous → pages at \(Int(fraction * 100))%")
        }
    }

    /// The app is not at 1.0. A writer opens a script at 150% and the desk
    /// scrolls in magnified coordinates; the anchor arithmetic mixes the
    /// canvas's own points with the clip view's, and magnification is what
    /// makes those two different numbers.
    func testTheWriterStaysInPlaceWhileZoomedIn() throws {
        for magnification in [1.5, 2.0] as [CGFloat] {
            let surface = surface(mode: .pages)
            surface.scrollView.magnification = magnification
            surface.scrollView.layoutSubtreeIfNeeded()
            scroll(surface, toFraction: 0.7)

            try assertStill(surface, { surface.setLayoutMode(.continuous) },
                            "pages → continuous at \(magnification)×")
        }
    }

    func testTheWriterStaysInPlaceGoingBackWhileZoomedIn() throws {
        for magnification in [1.5, 2.0] as [CGFloat] {
            let surface = surface(mode: .continuous)
            surface.scrollView.magnification = magnification
            surface.scrollView.layoutSubtreeIfNeeded()
            scroll(surface, toFraction: 0.7)

            try assertStill(surface, { surface.setLayoutMode(.pages) },
                            "continuous → pages at \(magnification)×")
        }
    }

    /// Every break says which page begins under it, and the marks are the
    /// pages — not however many rectangles happened to resolve.
    ///
    /// The number used to come from the surviving array's index, so a page
    /// start whose rectangle did not resolve did not just lose its own mark:
    /// it renamed every mark below it. That is a page number a production
    /// schedules against, wrong by one, and further down the further you read.
    func testEveryBreakCarriesItsOwnPageNumber() throws {
        let elements = script()
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
        surface.render(elements)
        surface.setLayoutMode(.continuous)
        surface.scrollView.layoutSubtreeIfNeeded()

        let pages = try XCTUnwrap(ScreenplayExporter.paginate(Screenplay(elements: elements)))
        XCTAssertGreaterThan(pages.count, 5, "the script must run past five pages to be worth asking")

        XCTAssertEqual(
            surface.breakMarkerPageNumbers, Array(2...pages.count),
            "the break marks do not read 2…\(pages.count) in order"
        )
    }

    /// There and back again lands where it started, which is the strongest
    /// statement of the same rule.
    func testARoundTripLandsWhereItStarted() throws {
        let surface = surface(mode: .pages)
        scroll(surface, toFraction: 0.7)
        let before = try XCTUnwrap(surface.topmostVisibleCharacter)

        surface.setLayoutMode(.continuous)
        surface.setLayoutMode(.pages)

        let after = try XCTUnwrap(surface.topmostVisibleCharacter)
        XCTAssertEqual(
            after, before, accuracy: 60,
            "a round trip moved the writer \(abs(after - before)) characters"
        )
    }
}
