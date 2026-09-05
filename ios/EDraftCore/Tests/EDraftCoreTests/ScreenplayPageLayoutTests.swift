import EDraftEngine
import XCTest
@testable import EDraftCore

/// Where a line sits on the page is shared, so a Mac PDF and an iPhone PDF
/// cannot disagree about it. These pin the arithmetic both surfaces draw.
@MainActor
final class ScreenplayPageLayoutTests: XCTestCase {

    /// Courier's pitch at 12pt. The surfaces measure the real font; the
    /// arithmetic is what we pin, so the callback is the constant.
    private let pitch: CGFloat = 7.2
    private var widthOf: (String) -> CGFloat {
        { [pitch] text in CGFloat((text as NSString).length) * pitch }
    }

    private let format = PageFormat.letter

    func testAnActionLineSitsAtTheLeftMarginOnItsRow() throws {
        let page = try oneLinePage(.action, "She waits.")
        let run = try XCTUnwrap(bodyRun(on: page, text: "She waits."))
        XCTAssertEqual(run.origin.x, ScreenplayPageLayout.textLeft, accuracy: 0.01)
        XCTAssertEqual(run.origin.y, format.textTop, accuracy: 0.01)
    }

    func testDialogueIsIndentedTenCharacters() throws {
        let page = try oneLinePage(.dialogue, "A line she says.")
        let run = try XCTUnwrap(bodyRun(on: page, text: "A line she says."))
        XCTAssertEqual(
            run.origin.x,
            ScreenplayPageLayout.textLeft + 10 * pitch,
            accuracy: 0.01
        )
    }

    func testATransitionIsFlushToTheRightEdge() throws {
        let page = try oneLinePage(.transition, "CUT TO:")
        let run = try XCTUnwrap(bodyRun(on: page, text: "CUT TO:"))
        XCTAssertEqual(run.origin.x, format.textRight - widthOf("CUT TO:"), accuracy: 0.01)
    }

    func testCenteredTextSitsOnThePageCentre() throws {
        let page = try oneLinePage(.centered, "THE END")
        let run = try XCTUnwrap(bodyRun(on: page, text: "THE END"))
        XCTAssertEqual(
            run.origin.x,
            (format.pageRect.width - widthOf("THE END")) / 2,
            accuracy: 0.01
        )
    }

    func testABlankLineStillOccupiesItsRow() throws {
        let page = EDraftEngine.ScriptPage(
            number: 1,
            lines: [
                PageLine(text: "INT. ROOM - DAY", type: .element(.scene), indent: 0, element: 0),
                PageLine(text: "", type: .blank, indent: 0, element: -1),
                PageLine(text: "She waits.", type: .element(.action), indent: 0, element: 1)
            ],
            continuedTop: false,
            continuedBottom: false
        )
        let run = try XCTUnwrap(bodyRun(on: page, text: "She waits."))
        XCTAssertEqual(run.origin.y, format.textTop + 2 * ScreenplayPageLayout.lineHeight, accuracy: 0.01)
    }

    func testSceneNumbersSitInBothMargins() throws {
        let page = EDraftEngine.ScriptPage(
            number: 1,
            lines: [
                PageLine(text: "INT. ROOM - DAY", type: .element(.scene), indent: 0, element: 0)
            ],
            continuedTop: false,
            continuedBottom: false
        )
        let runs = ScreenplayPageLayout.scriptPageRuns(
            page, sceneNumbers: [0: "12A"], format: format,
            showPageNumbers: true, widthOf: widthOf
        )
        let numbers = runs.filter { $0.text == "12A" }
        XCTAssertEqual(numbers.count, 2)
        let gap = pitch * 2
        XCTAssertEqual(numbers[0].origin.x, ScreenplayPageLayout.textLeft - gap - widthOf("12A"), accuracy: 0.01)
        XCTAssertEqual(numbers[1].origin.x, format.textRight + gap, accuracy: 0.01)
        XCTAssertEqual(numbers[0].origin.y, numbers[1].origin.y)
    }

    func testPageTwoCarriesAPageNumberAndPageOneDoesNot() throws {
        let first = try oneLinePage(.action, "One.", number: 1)
        let second = try oneLinePage(.action, "Two.", number: 2)
        XCTAssertFalse(ScreenplayPageLayout.scriptPageRuns(
            first, sceneNumbers: [:], format: format,
            showPageNumbers: true, widthOf: widthOf
        ).contains { $0.text == "1." })
        let number = try XCTUnwrap(ScreenplayPageLayout.scriptPageRuns(
            second, sceneNumbers: [:], format: format,
            showPageNumbers: true, widthOf: widthOf
        ).first { $0.text == "2." })
        XCTAssertEqual(number.origin.y, ScreenplayPageLayout.pageNumberY, accuracy: 0.01)
        XCTAssertEqual(number.origin.x, format.textRight - widthOf("2."), accuracy: 0.01)
    }

    func testTheTitleSitsAThirdOfTheWayDownThePage() throws {
        let screenplay = EDraftCore.Screenplay(
            titlePage: [TitlePageEntry(key: "Title", values: ["The Last Light"])],
            elements: []
        )
        let run = try XCTUnwrap(ScreenplayPageLayout.titlePageRuns(
            screenplay, format: format, widthOf: widthOf
        ).first { $0.text == "THE LAST LIGHT" })
        XCTAssertEqual(run.origin.y, format.pageRect.height * 0.32, accuracy: 0.01)
    }

    func testContactSitsBottomLeft() throws {
        let screenplay = EDraftCore.Screenplay(
            titlePage: [TitlePageEntry(key: "Contact", values: ["Mara", "mara@x"])],
            elements: []
        )
        let runs = ScreenplayPageLayout.titlePageRuns(
            screenplay, format: format, widthOf: widthOf
        )
        let mara = try XCTUnwrap(runs.first { $0.text == "Mara" })
        XCTAssertEqual(mara.origin.x, ScreenplayPageLayout.textLeft, accuracy: 0.01)
        XCTAssertEqual(
            mara.origin.y,
            format.pageRect.height - 72 - ScreenplayPageLayout.lineHeight,
            accuracy: 0.01
        )
    }

    func testEditorIndentsMatchThePaginator() throws {
        let measure = ScreenplayPageLayout.textBlockWidth(format)
        let dialogue = try XCTUnwrap(ScreenplayPageLayout.indents(
            for: .dialogue, measure: measure, characterWidth: pitch
        ))
        XCTAssertEqual(dialogue.head, 10 * pitch, accuracy: 0.01)
        let cue = try XCTUnwrap(ScreenplayPageLayout.indents(
            for: .character, measure: measure, characterWidth: pitch
        ))
        XCTAssertEqual(cue.head, 22 * pitch, accuracy: 0.01)
        XCTAssertGreaterThan(cue.head, dialogue.head)
        XCTAssertNil(ScreenplayPageLayout.indents(
            for: .scene, measure: measure, characterWidth: pitch
        ))
    }

    func testSpacingBeforeASceneIsTwoBlankLines() {
        XCTAssertEqual(ScreenplayPageLayout.spacing(before: .scene), 24)
        XCTAssertEqual(ScreenplayPageLayout.spacing(before: .action), 12)
        XCTAssertEqual(ScreenplayPageLayout.spacing(before: .dialogue), 0)
    }

    // MARK: -

    private func oneLinePage(
        _ kind: ElementKind, _ text: String, number: Int = 1
    ) throws -> EDraftEngine.ScriptPage {
        EDraftEngine.ScriptPage(
            number: number,
            lines: [PageLine(text: text, type: .element(kind), indent: Paginator.geometry[kind]?.indent ?? 0, element: 0)],
            continuedTop: false,
            continuedBottom: false
        )
    }

    private func bodyRun(on page: EDraftEngine.ScriptPage, text: String) -> ScreenplayPageLayout.Run? {
        ScreenplayPageLayout.scriptPageRuns(
            page, sceneNumbers: [:], format: format,
            showPageNumbers: true, widthOf: widthOf
        ).first { $0.text == text }
    }
}
