import EDraftEngine
import XCTest
@testable import EDraftCore

/// Where each page begins in the flattened editor text. The surface asks
/// this instead of paginating a second time.
@MainActor
final class PageStartLocationTests: XCTestCase {

    func testLetterBottomMarginIsSixtyPointsNotASecondInch() {
        XCTAssertEqual(ScreenplayPageLayout.textBlockHeight(.letter), 660, accuracy: 0.01)
        XCTAssertEqual(ScreenplayPageLayout.textBottom(.letter), 60, accuracy: 0.01)
    }

    func testPageOneStartsAtTheFirstCharacter() throws {
        let elements = [
            ScriptElement(type: .action, text: "An opening image.")
        ]
        let pages = try XCTUnwrap(ScreenplayExporter.paginate(Screenplay(elements: elements)))
        XCTAssertEqual(
            ScreenplayPageLayout.pageStartLocations(elements: elements, pages: pages),
            [0]
        )
    }

    func testAKeepTogetherHeadingStartsThePageItWasPushedTo() throws {
        // 26 one-line actions: 1 + 25×(blank+line) = 51 printed rows.
        // A scene wants 2 blanks + itself + follow, which will not fit
        // in the 4 rows left, so the paginator pushes it. Page 2 must
        // open on that heading, not on "line 55 of the text view".
        var elements: [ScriptElement] = []
        for beat in 1...26 {
            elements.append(ScriptElement(type: .action, text: "Action line \(beat) sits on one row."))
        }
        elements.append(ScriptElement(type: .scene, text: "INT. PUSHED - DAY"))
        elements.append(ScriptElement(type: .action, text: "The heading was not left alone at the foot."))
        let pages = try XCTUnwrap(ScreenplayExporter.paginate(Screenplay(elements: elements)))
        XCTAssertEqual(pages.count, 2, "the heading should have been pushed to page 2, not wrapped onto page 1")

        let locations = ScreenplayPageLayout.pageStartLocations(elements: elements, pages: pages)
        XCTAssertEqual(locations.count, 2)

        let heading = try XCTUnwrap(elements.last { $0.type == .scene })
        let headingRange = try XCTUnwrap(
            ScreenplayEditPlanner.ranges(for: elements).first { $0.id == heading.id }
        )
        XCTAssertEqual(
            locations[1], headingRange.range.location,
            "page 2 should open on the heading the paginator pushed"
        )
        XCTAssertTrue(
            pages[1].lines.contains {
                $0.element >= 0 && elements.indices.contains($0.element)
                    && elements[$0.element].id == heading.id
            }
        )
    }

    func testASplitActionNamesTheCharacterWherePageTwoBegins() throws {
        let long = String(repeating: "The road holds its breath. ", count: 200)
        let elements = [ScriptElement(type: .action, text: long)]
        let pages = try XCTUnwrap(ScreenplayExporter.paginate(Screenplay(elements: elements)))
        XCTAssertGreaterThan(pages.count, 1, "the action must spill onto a second page")

        let locations = ScreenplayPageLayout.pageStartLocations(elements: elements, pages: pages)
        XCTAssertEqual(locations[0], 0)
        XCTAssertGreaterThan(locations[1], 0)
        XCTAssertLessThan(locations[1], (long as NSString).length)

        let wrapped = Paginator.wrapLines(long, width: Paginator.pageWidthChars)
        let consumed = pages[0].lines.filter { line in
            if line.element != 0 { return false }
            if case .element = line.type { return true }
            return false
        }.count
        XCTAssertEqual(locations[1], wrapped[consumed].utf16Start)
    }
}
