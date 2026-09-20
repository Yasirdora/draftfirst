import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// Grid is a map of the pages: visible cards carry a miniature of the type,
/// the page number is ink on paper in both appearances, and a note mark sits
/// on the card that holds its line.
@MainActor
final class GridMapTests: XCTestCase {

    private var originalMode = PageLayoutMode.stored
    private var originalArrangement = PageArrangement.stored
    private var originalPaper = PagePaper.stored

    override func setUp() {
        super.setUp()
        originalMode = PageLayoutMode.stored
        originalArrangement = PageArrangement.stored
        originalPaper = PagePaper.stored
        PageLayoutMode.store(.pages)
        PageArrangement.store(.single)
    }

    override func tearDown() {
        // Grid writes the arrangement preference; leaving it set poisons
        // every later EditorState in the suite (ghosts, notes, zoom, viewport).
        PageLayoutMode.store(.pages)
        PageArrangement.store(.single)
        PagePaper.store(originalPaper)
        super.tearDown()
    }

    private func script(scenes: Int) -> [ScriptElement] {
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

    private func gridSurface(
        _ elements: [ScriptElement],
        viewport: CGSize = CGSize(width: 1400, height: 900)
    ) -> ScriptSurface {
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(origin: .zero, size: viewport)
        surface.render(elements)
        surface.setArrangement(.grid)
        surface.scrollView.layoutSubtreeIfNeeded()
        surface.canvas.refreshVisibleGridPreviews()
        return surface
    }

    private func rgb(_ color: NSColor) -> (r: Int, g: Int, b: Int) {
        let converted = color.usingColorSpace(.sRGB) ?? color
        return (
            Int((converted.redComponent * 255).rounded()),
            Int((converted.greenComponent * 255).rounded()),
            Int((converted.blueComponent * 255).rounded())
        )
    }

    private func inkPixels(in image: CGImage) -> Int {
        let rep = NSBitmapImageRep(cgImage: image)
        var ink = 0
        let width = rep.pixelsWide
        let height = max(rep.pixelsHigh - 8, 1)
        for y in 0..<height {
            for x in 0..<width {
                var pixel = [0, 0, 0, 0]
                rep.getPixel(&pixel, atX: x, y: y)
                if pixel[0] < 90, pixel[1] < 90, pixel[2] < 90 { ink += 1 }
            }
        }
        return ink
    }

    func testGridNoteMarkersSitOnTheOwningCard() throws {
        let elements = script(scenes: 40)
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1400, height: 900)
        let firstID = elements[0].id
        let lateID = try XCTUnwrap(elements.last { $0.type == .scene }?.id)
        editor.addNote("On the first sheet", to: firstID)
        editor.addNote("On a later sheet", to: lateID)
        surface.renderIfNeeded(editor)
        surface.setArrangement(.grid)
        surface.scrollView.layoutSubtreeIfNeeded()

        let firstNote = try XCTUnwrap(editor.notes.first { $0.anchor == firstID }?.id)
        let lateNote = try XCTUnwrap(editor.notes.first { $0.anchor == lateID }?.id)
        let firstMarker = try XCTUnwrap(surface.canvas.noteMarker(for: firstNote))
        let lateMarker = try XCTUnwrap(surface.canvas.noteMarker(for: lateNote))
        let cards = surface.canvas.pageViews.map(\.frame)
        XCTAssertGreaterThan(cards.count, 1, "the script must span more than one sheet")

        let firstCard = try XCTUnwrap(cards.first { $0.contains(CGPoint(x: firstMarker.frame.midX, y: firstMarker.frame.midY)) })
        let lateCard = try XCTUnwrap(cards.first { $0.contains(CGPoint(x: lateMarker.frame.midX, y: lateMarker.frame.midY)) })
        XCTAssertEqual(firstCard, cards[0], "the first note left the first card")
        XCTAssertNotEqual(lateCard, cards[0], "the later note landed on the first card")
        XCTAssertTrue(
            firstCard.insetBy(dx: -2, dy: -2).contains(firstMarker.frame),
            "first marker \(firstMarker.frame) is not inside card \(firstCard)"
        )
        XCTAssertTrue(
            lateCard.insetBy(dx: -2, dy: -2).contains(lateMarker.frame),
            "later marker \(lateMarker.frame) is not inside card \(lateCard)"
        )
    }

    func testGridPageNumbersContrastWithPaperInBothAppearances() throws {
        PagePaper.store(.paper)
        let surface = gridSurface(script(scenes: 8))
        let canvas = surface.canvas
        let label = try XCTUnwrap(canvas.gridPageNumberColors.first)

        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            canvas.appearance = appearance
            canvas.applyAppearance()
            let painted = try XCTUnwrap(canvas.gridPageNumberColors.first)
            var paper = (r: 0, g: 0, b: 0)
            var ink = (r: 0, g: 0, b: 0)
            var number = (r: 0, g: 0, b: 0)
            var tertiary = (r: 0, g: 0, b: 0)
            appearance.performAsCurrentDrawingAppearance {
                paper = rgb(.screenplayPaper)
                ink = rgb(.screenplayInk)
                number = rgb(painted)
                tertiary = rgb(.tertiaryLabelColor)
            }
            XCTAssertGreaterThan(paper.r, 200, "\(name): paper is not cream")
            XCTAssertLessThan(ink.r, 80, "\(name): ink is not dark on cream")
            XCTAssertLessThan(number.r, 80, "\(name): page number is not dark on cream")
            XCTAssertGreaterThan(
                abs(paper.r - number.r), 120,
                "\(name): page number \(number) has no contrast with paper \(paper)"
            )
            if name == .darkAqua {
                XCTAssertGreaterThan(tertiary.r, 140, "sanity: tertiaryLabelColor is light in the dark")
                XCTAssertLessThan(
                    number.r, tertiary.r - 40,
                    "\(name): page number still follows tertiaryLabelColor (\(tertiary))"
                )
            }
        }
        _ = label
    }

    func testVisibleGridCardsCarryRenderedTextAtCardScale() throws {
        var elements = script(scenes: 12)
        elements[1] = ScriptElement(
            type: .action,
            text: "UNIQUEGRIDINK a distinctive run of type so the miniature is not blank paper."
        )
        let surface = gridSurface(elements, viewport: CGSize(width: 1400, height: 900))
        let page = try XCTUnwrap(surface.canvas.pageViews.first)
        let image = try XCTUnwrap(
            surface.canvas.gridPreviewImage(at: 0),
            "the visible card was not painted"
        )
        let backing = surface.canvas.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 1
        XCTAssertEqual(
            CGFloat(image.width),
            (page.bounds.width * backing).rounded(),
            accuracy: 1.5,
            "the miniature was not drawn at the card's pixel size"
        )
        XCTAssertEqual(
            CGFloat(image.height),
            (page.bounds.height * backing).rounded(),
            accuracy: 1.5
        )
        XCTAssertLessThan(
            CGFloat(image.width),
            PageFormat.letter.pageRect.width * backing - 8,
            "a full-size bitmap was downscaled by the layer"
        )
        XCTAssertGreaterThan(
            inkPixels(in: image),
            30,
            "the visible card has no script ink"
        )
        XCTAssertTrue(surface.textView.isHidden)
        XCTAssertFalse(surface.textView.isEditable)
    }

    func testOffscreenGridCardsAreNotRasterized() {
        let surface = gridSurface(
            script(scenes: 120),
            viewport: CGSize(width: 700, height: 280)
        )
        let visHeight = surface.scrollView.frame.height
        let row = (surface.canvas.pageViews.first?.frame.height ?? 0) + PageCanvasView.gridGap
        let far = visHeight + row * 2
        var paintedVisible = 0
        var paintedFar = 0
        var farCards = 0
        for (index, page) in surface.canvas.pageViews.enumerated() {
            let painted = surface.canvas.gridPreviewImage(at: index) != nil
            if page.frame.minY < visHeight {
                if painted { paintedVisible += 1 }
            }
            if page.frame.minY > far {
                farCards += 1
                if painted { paintedFar += 1 }
            }
        }
        XCTAssertGreaterThan(
            surface.canvas.pageViews.count, 8,
            "need enough sheets that some sit below the fold"
        )
        XCTAssertGreaterThan(paintedVisible, 0, "no visible card was painted")
        XCTAssertGreaterThan(
            farCards, 0,
            "the viewport covered the whole map pages=\(surface.canvas.pageViews.count) visH=\(visHeight) row=\(row)"
        )
        XCTAssertEqual(paintedFar, 0, "cards well below the fold were snapshotted")
    }

    func testASingleGridClickStillDoesNotOpenASheet() {
        let surface = gridSurface(script(scenes: 12))
        var picked: Int?
        surface.canvas.onPickPage = { picked = $0 }
        let point = CGPoint(x: surface.pageFrames[0].midX, y: surface.pageFrames[0].midY)
        surface.canvas.handleGridClick(at: point, count: 1)
        XCTAssertNil(picked)
        surface.canvas.handleGridClick(at: point, count: 2)
        XCTAssertEqual(picked, 0)
    }

    /// A stopwatch, not a gate. `EDRAFT_GRID_BENCH=1 swift test --filter testGridOpenTime`.
    func testGridOpenTimeOnAHundredPageScript() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["EDRAFT_GRID_BENCH"] == "1",
            "a stopwatch: run with EDRAFT_GRID_BENCH=1"
        )
        var elements: [ScriptElement] = []
        var index = 0
        let target = 120 * 18
        while elements.count < target {
            elements.append(ScriptElement(type: .scene, text: "INT. LOCATION \(index) - DAY"))
            elements.append(ScriptElement(
                type: .action,
                text: "The room is quiet. A long action line that runs past sixty characters so it wraps onto a second line of the page."
            ))
            elements.append(ScriptElement(type: .character, text: "CHARACTER \(index % 40)"))
            elements.append(ScriptElement(
                type: .dialogue,
                text: "A line of dialogue, measured and calm, that also runs long enough to wrap across the measure of the page."
            ))
            elements.append(ScriptElement(type: .dialogue, text: "A shorter reply."))
            elements.append(ScriptElement(type: .action, text: "They wait. Nothing moves."))
            index += 1
        }
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 1400, height: 900)
        surface.render(elements)
        let t0 = CACurrentMediaTime()
        surface.setArrangement(.grid)
        surface.scrollView.layoutSubtreeIfNeeded()
        let elapsed = CACurrentMediaTime() - t0
        print(String(format: "BENCH grid-open: %.3fs pages=%d", elapsed, surface.pageFrames.count))
        XCTAssertGreaterThanOrEqual(surface.pageFrames.count, 100)
    }
}
