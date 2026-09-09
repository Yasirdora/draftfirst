import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// The Mac page, driven without a window.
///
/// The phone learned every one of these lessons the hard way and in public;
/// they are written down here so the Mac never has to. Each test names the
/// behaviour rather than the mechanism, because the mechanism is allowed to
/// change and the behaviour is not.
@MainActor
final class ScriptSurfaceTests: XCTestCase {

    private func script(scenes: Int = 12) -> [ScriptElement] {
        var elements: [ScriptElement] = []
        for beat in 1...scenes {
            elements.append(ScriptElement(type: .scene, text: "INT. ROOM \(beat) - DAY"))
            elements.append(ScriptElement(type: .action, text: "Action for beat \(beat). The road holds its breath."))
            elements.append(ScriptElement(type: .character, text: "MARA"))
            elements.append(ScriptElement(type: .dialogue, text: "Line \(beat), spoken plainly and without hurry at all."))
        }
        return elements
    }

    /// A surface with a real viewport, laid out, as a window would leave it.
    private func surface(_ elements: [ScriptElement]) -> ScriptSurface {
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        // Deliberately no sizeToFit or layout pass here: bringing its own
        // geometry up to date is the surface's job, and a harness that does it
        // for the code hides exactly the bug the phone shipped.
        surface.render(elements)
        return surface
    }

    // MARK: - Going somewhere

    func testAJumpToALateSceneMovesThePage() throws {
        let elements = script()
        let surface = surface(elements)
        let last = try XCTUnwrap(elements.last { $0.type == .scene })
        let before = surface.scrollView.contentView.bounds.origin.y

        XCTAssertTrue(surface.reveal(last.id))

        XCTAssertGreaterThan(
            surface.scrollView.contentView.bounds.origin.y, before,
            "the page did not move towards the scene the row named"
        )
    }

    func testAJumpPutsTheCaretOnTheElement() throws {
        let elements = script()
        let surface = surface(elements)
        let target = try XCTUnwrap(elements.last { $0.type == .character })

        XCTAssertTrue(surface.reveal(target.id))

        let selected = surface.textView.selectedRange()
        XCTAssertEqual(surface.element(at: selected.location), target.id)
    }

    /// The reported bug, in its Mac form: a target the page cannot bring to the
    /// top must still be marked, or the row looks dead.
    func testAnElementThePageCannotReachIsStillMarked() throws {
        let elements = script(scenes: 2)
        let surface = surface(elements)
        let last = try XCTUnwrap(elements.last)

        XCTAssertTrue(surface.reveal(last.id))
        XCTAssertTrue(surface.isMarking, "a target the page cannot reach was left unmarked")
    }

    /// A script that fits in the window has nowhere to scroll. The reveal must
    /// still answer — with the mark, which is the whole reason it exists.
    ///
    /// The window has to be measured at the size the page is *drawn*, not at
    /// its own metrics: a document opens at `PageZoom.opening`, so one letter
    /// sheet plus its desk padding needs 864 × 1.25 points of height before it
    /// fits. Sizing this at 1000 was right until the opening zoom landed and
    /// wrong the moment it did.
    func testAScriptThatFitsIsStillAnswered() throws {
        let elements = [
            ScriptElement(type: .scene, text: "INT. ROOM - DAY"),
            ScriptElement(type: .action, text: "She waits.")
        ]
        let fits = (PageFormat.letter.pageRect.height + 72) * PageZoom.opening + 40
        let surface = ScriptSurface(measure: 700)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: fits)
        surface.render(elements)
        XCTAssertFalse(
            PageScroll.canScroll(surface.scrollableRange),
            "this script is meant to fit in the window"
        )
        XCTAssertTrue(surface.reveal(elements[1].id))
        XCTAssertTrue(surface.isMarking)
    }

    /// The design's page: a real sheet, centred, with the PDF's left margin.
    /// Flush-to-divider text was the thing that broke the length-ruler.
    func testThePageIsACardAtPrintMetrics() {
        let surface = surface([ScriptElement(type: .scene, text: "INT. ROOM - DAY")])
        XCTAssertEqual(surface.pageFrame.width, PageFormat.letter.pageRect.width, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(surface.pageFrame.height, PageFormat.letter.pageRect.height)
        XCTAssertEqual(
            surface.textView.frame.minX - surface.pageFrame.minX,
            ScreenplayPageLayout.textLeft,
            accuracy: 0.5
        )
        XCTAssertEqual(
            surface.textView.frame.width,
            ScreenplayPageLayout.textBlockWidth(.letter),
            accuracy: 0.5
        )
        XCTAssertEqual(surface.canvas.pageView.layer?.borderWidth ?? 0, 0)
    }

    /// The card is not the page. A glyph of the last element must sit on it
    /// — position and containment, not a height greater than zero, which a
    /// one-line-tall view would also satisfy. This is the assertion that
    /// would have stopped a blank page shipping green.
    func testTheLastElementLandsOnTheCard() throws {
        let elements = script(scenes: 3)
        let surface = surface(elements)
        let last = try XCTUnwrap(ScreenplayEditPlanner.ranges(for: elements).last)
        let lastRect = try XCTUnwrap(
            ScriptLayout.boundingRect(of: last.range, in: surface.textView),
            "the last element has no rectangle — there is nothing to put on the card"
        )

        let view = surface.textView
        XCTAssertTrue(
            view.bounds.insetBy(dx: -1, dy: -1).contains(lastRect),
            """
            the last line sits at \(lastRect) but the text view is only \(view.frame.size) \
            (minSize=\(view.minSize) maxSize=\(view.maxSize)) — the script is not on the card
            """
        )

        let inCanvas = surface.canvas.convert(lastRect, from: view)
        let lastCard = try XCTUnwrap(surface.pageFrames.last, "a script has no sheets")
        XCTAssertTrue(
            lastCard.insetBy(dx: -1, dy: -1).contains(inCanvas),
            "the last line \(inCanvas) is not inside the last sheet \(lastCard)"
        )
    }

    /// The page card is taller than a short window. If the text view is
    /// pinned to the bottom of an unflipped page, the writer sees a blank
    /// card and has to scroll to find a script that is already "on" it.
    func testTheFirstLineSitsAtTheTopOfTheCard() throws {
        let elements = script(scenes: 3)
        let surface = surface(elements)
        let first = try XCTUnwrap(ScreenplayEditPlanner.ranges(for: elements).first)
        let firstRect = try XCTUnwrap(
            ScriptLayout.boundingRect(of: first.range, in: surface.textView)
        )
        let inCanvas = surface.canvas.convert(firstRect, from: surface.textView)
        let expectedY = surface.pageFrame.minY + PageFormat.current.textTop
        XCTAssertEqual(
            inCanvas.minY, expectedY, accuracy: 8,
            "the first line is at canvas y=\(inCanvas.minY), expected \(expectedY) (page top + 1″ margin). a blank window means the script is at the bottom of the card"
        )
    }

    /// A 450pt window on an 11″ card. The first line has to be in the
    /// visible rect without the writer scrolling — a flipped document
    /// view that opens at the foot looks like a blank page.
    func testAShortWindowShowsTheFirstLineWithoutScrolling() throws {
        let elements = script(scenes: 3)
        let surface = ScriptSurface(measure: 700)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.render(elements)
        let first = try XCTUnwrap(ScreenplayEditPlanner.ranges(for: elements).first)
        let firstRect = try XCTUnwrap(
            ScriptLayout.boundingRect(of: first.range, in: surface.textView)
        )
        let visible = surface.scrollView.contentView.bounds
        let inClip = surface.textView.convert(firstRect, to: surface.scrollView.contentView)
        XCTAssertFalse(
            visible.intersection(inClip).isNull,
            "the first line is at \(inClip) and the visible rect is \(visible) — the window opened looking at empty paper"
        )
    }

    /// A page card is a surface with edges. Layer `cgColor`s do not track
    /// appearance on their own, so both looks have to be applied and read
    /// back — a card that only looks right in light has no edge in dark.
    /// The border was removed (to avoid the double-line where pages meet);
    /// the shadow and colour difference are what separate the page now.
    func testThePageCardHasAnEdgeInDarkAndLight() {
        let surface = surface([ScriptElement(type: .scene, text: "INT. ROOM - DAY")])
        let canvas = surface.canvas

        canvas.appearance = NSAppearance(named: .darkAqua)
        canvas.layoutSubtreeIfNeeded()
        canvas.applyAppearance()
        let darkFill = canvas.pageView.layer?.backgroundColor
        let darkCanvas = canvas.layer?.backgroundColor
        XCTAssertEqual(canvas.pageView.layer?.borderWidth, 0)
        XCTAssertNotEqual(
            darkFill, darkCanvas,
            "in dark mode the page and the canvas must not be the same colour or the edge vanishes"
        )

        canvas.appearance = NSAppearance(named: .aqua)
        canvas.layoutSubtreeIfNeeded()
        canvas.applyAppearance()
        let lightFill = canvas.pageView.layer?.backgroundColor
        let lightCanvas = canvas.layer?.backgroundColor
        XCTAssertEqual(canvas.pageView.layer?.borderWidth, 0)
        XCTAssertNotEqual(
            lightFill, lightCanvas,
            "in light mode the page and the canvas must not be the same colour or the edge vanishes"
        )
        // The page deliberately does *not* change with the appearance any
        // more, which is the whole of `PagePaper.paper`: the chrome darkens
        // at night and the document does not, as in Pages and Preview. What
        // must still hold is the edge, asserted above in both looks.
        XCTAssertEqual(
            darkFill, lightFill,
            "with the default paper the page is the same sheet in both looks"
        )

        // And the writer who asks for a dark page gets one that does change.
        let original = PagePaper.stored
        PagePaper.store(.inverted)
        defer { PagePaper.store(original) }

        canvas.appearance = NSAppearance(named: .darkAqua)
        canvas.applyAppearance()
        let invertedDark = canvas.pageView.layer?.backgroundColor
        canvas.appearance = NSAppearance(named: .aqua)
        canvas.applyAppearance()
        let invertedLight = canvas.pageView.layer?.backgroundColor

        XCTAssertNotEqual(
            invertedDark, invertedLight,
            "an inverted page follows the appearance — that is what it is for"
        )
    }

    /// The blank line a writer is about to type into — the case that was
    /// silently broken on the phone until the Mac's measurements found it.
    func testABlankLineIsRevealable() throws {
        let elements = [
            ScriptElement(type: .scene, text: "INT. ROOM - DAY"),
            ScriptElement(type: .action, text: "")
        ]
        let surface = surface(elements)
        XCTAssertTrue(surface.reveal(elements[1].id), "a blank line is still a place")
        XCTAssertTrue(surface.isMarking)
    }

    func testAnElementTheScriptNoLongerHasIsRefusedRatherThanGuessed() {
        let surface = surface(script())
        XCTAssertFalse(surface.reveal(UUID()))
    }

    // MARK: - The page keeps its shape

    /// Asking the page which element a character belongs to has to give the
    /// same answer the model would — that mapping is what every reveal, every
    /// selection report and every conversion is built on.
    func testEveryElementOwnsItsOwnCharacters() {
        let elements = script(scenes: 3)
        let surface = surface(elements)
        var location = 0
        for element in elements {
            XCTAssertEqual(
                surface.element(at: location), element.id,
                "the character at \(location) should belong to “\(element.text)”"
            )
            location += (element.text as NSString).length + 1   // the joining newline
        }
    }

    /// A resized window recentres the card. It must not stretch the script —
    /// the page is paper, and a line that grew with the window would no
    /// longer be the line the PDF prints.
    func testResizingDoesNotStretchTheScript() throws {
        let elements = [
            ScriptElement(type: .dialogue, text: "A line she says.")
        ]
        let surface = surface(elements)
        let before = try XCTUnwrap(
            ScriptLayout.boundingRect(of: NSRange(location: 0, length: 16), in: surface.textView)
        )

        surface.scrollView.frame.size.width = 900
        surface.remeasure(to: 900, elements: elements)
        let after = try XCTUnwrap(
            ScriptLayout.boundingRect(of: NSRange(location: 0, length: 16), in: surface.textView)
        )

        XCTAssertEqual(
            after.minX, before.minX, accuracy: 0.5,
            "dialogue's indent is a print measurement, not a fraction of the window"
        )
        XCTAssertEqual(surface.pageFrame.width, PageFormat.letter.pageRect.width, accuracy: 0.5)
    }

    /// The writer must be able to click anywhere on the page and get a caret.
    ///
    /// The text view used to be sized to the glyphs it held, so a new document
    /// gave a one-line strip at the top of a full sheet — the only place an
    /// I-beam appeared or a click landed. Reported from the running Mac app as
    /// "I should take my cursor to one specific area to get the typing cursor".
    func testTheTextViewFillsThePagesTextBlockNotJustItsLines() {
        let surface = surface([ScriptElement(type: .scene, text: "")])

        // The block is the paginator's 55 lines, plus a line of headroom above
        // and below for a glyph taller than its own line — an emoji rises about
        // three points over the box, and on the first line the view's own edge
        // is what would cut it.
        let format = PageFormat.current
        let slack = ScreenplayPageLayout.glyphOverflow
        XCTAssertEqual(
            surface.textView.frame.height,
            ScreenplayPageLayout.textBlockHeight(format) + slack * 2,
            accuracy: 0.5,
            "an almost empty page left nowhere to click — the block is \(format.linesPerPage) lines plus headroom"
        )
        // The type still starts exactly on the 1″ margin: the view is moved up
        // by the headroom and the text inset back down by the same amount.
        XCTAssertEqual(
            surface.textView.textContainerInset.height, slack, accuracy: 0.5,
            "headroom without a matching inset would move every line up"
        )
    }

    /// And past a page the block is the text, so nothing is invented below it.
    func testALongScriptsTextBlockIsStillItsOwnHeight() throws {
        let elements = (1...120).map {
            ScriptElement(type: .action, text: "A line of action, number \($0).")
        }
        let surface = surface(elements)

        let pages = try XCTUnwrap(ScreenplayExporter.paginate(Screenplay(elements: elements)))
        XCTAssertGreaterThan(pages.count, 1, "this fixture must actually paginate")
        XCTAssertEqual(surface.pageFrames.count, pages.count)
        for frame in surface.pageFrames {
            XCTAssertEqual(frame.height, PageFormat.current.pageRect.height, accuracy: 0.5)
        }
        XCTAssertGreaterThan(
            surface.textView.frame.height, PageFormat.current.pageRect.height,
            "a script longer than a page should have a text block longer than one"
        )
    }

    /// A canvas narrower than the paper must scroll the page, never shrink it.
    ///
    /// This is the width the character-thread column leaves behind: a 900pt
    /// window less a 240pt Navigator, a 260pt thread and the divider is about
    /// 400pt of canvas — two thirds of a page. The card has to keep its
    /// 612 points regardless, because the page edge is the ruler a screenwriter
    /// reads length by, and a page that quietly narrows to fit the furniture is
    /// lying about how long the script is.
    ///
    /// The scroll view carries a horizontal scroller for exactly this, which is
    /// what makes the third column survivable where a properties pane was not.
    /// It is still a reason to give the window a sensible minimum width, and
    /// that is a judgement to make with the window in front of you.
    func testACanvasNarrowerThanThePaperScrollsRatherThanShrinkingIt() throws {
        let elements = [ScriptElement(type: .dialogue, text: "A line she says.")]
        let surface = surface(elements)

        surface.scrollView.frame.size.width = 400
        surface.remeasure(to: 400, elements: elements)

        XCTAssertEqual(
            surface.pageFrame.width, PageFormat.letter.pageRect.width, accuracy: 0.5,
            "the page card shrank to fit the window; the page is no longer a page"
        )
        XCTAssertTrue(
            surface.scrollView.hasHorizontalScroller,
            "a page wider than its canvas needs somewhere to go"
        )
    }

    /// The phone's bug, in its Mac form: a reveal that arrives in the same turn
    /// as a render must still move the page. A text view's height is a result
    /// of laying out, so measuring before the layout catches up says the page
    /// is one screen tall and cannot move — and the row does nothing.
    func testARevealInTheSameTurnAsARenderStillMovesThePage() throws {
        let elements = script()
        let surface = surface(elements)
        let last = try XCTUnwrap(elements.last { $0.type == .scene })
        let before = surface.scrollView.contentView.bounds.origin.y

        surface.render(elements)          // no layout pass in between
        XCTAssertTrue(surface.reveal(last.id))

        XCTAssertGreaterThan(
            surface.scrollView.contentView.bounds.origin.y, before,
            "a reveal in the same turn as a render measured a page that did not exist yet"
        )
    }
}
