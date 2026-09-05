import EDraftEngine
import XCTest
@testable import EDraftCore

/// The Mac and the phone paginate the same file identically — same page
/// count, same page breaks, same line breaks — because both ask
/// `ScreenplayExporter.paginate`, which is the engine's `Paginator`. If
/// this fails, the extraction that was supposed to share that arithmetic
/// is wrong.
@MainActor
final class PaginationParityTests: XCTestCase {

    func testExporterPaginateMatchesTheEnginePaginator() throws {
        let screenplay = try Self.feature()
        let exported = try XCTUnwrap(ScreenplayExporter.paginate(screenplay))
        let engine = try Paginator.paginate(
            screenplay.engineModel,
            linesPerPage: PageFormat.current.linesPerPage
        )
        XCTAssertEqual(exported.count, engine.count, "page count drifted")
        XCTAssertGreaterThan(exported.count, 1, "the fixture must actually paginate")
        for (page, counterpart) in zip(exported, engine) {
            XCTAssertEqual(page.number, counterpart.number)
            XCTAssertEqual(page.continuedTop, counterpart.continuedTop)
            XCTAssertEqual(page.continuedBottom, counterpart.continuedBottom)
            XCTAssertEqual(page.lines.count, counterpart.lines.count, "line breaks drifted on page \(page.number)")
            XCTAssertEqual(page.lines, counterpart.lines)
        }
    }

    func testLayoutRunsFollowThePaginatorsRows() throws {
        let screenplay = try Self.feature()
        let pages = try XCTUnwrap(ScreenplayExporter.paginate(screenplay))
        let widthOf: (String) -> CGFloat = { CGFloat(($0 as NSString).length) * 7.2 }
        for page in pages {
            let runs = ScreenplayPageLayout.scriptPageRuns(
                page, sceneNumbers: [:], format: PageFormat.current,
                showPageNumbers: true, widthOf: widthOf
            )
            for (index, line) in page.lines.enumerated() where line.type != .blank {
                let text = ScreenplayExporter.renderedText(for: line)
                let run = try XCTUnwrap(
                    runs.first { $0.text == text && $0.origin.y == PageFormat.current.textTop + CGFloat(index) * ScreenplayPageLayout.lineHeight },
                    "page \(page.number) line \(index) (“\(text)”) was not placed on its paginator row"
                )
                XCTAssertEqual(
                    run.origin.y,
                    PageFormat.current.textTop + CGFloat(index) * ScreenplayPageLayout.lineHeight,
                    accuracy: 0.01
                )
            }
        }
    }

    /// A script long enough that wrapping, scene-heading widows and a
    /// dialogue split all fire — the cases where two paginators would
    /// first disagree.
    private static func feature() throws -> EDraftCore.Screenplay {
        var source = "Title: Parity\nCredit: written by\nAuthor: A. Writer\n\n"
        for beat in 1...40 {
            source += """
            INT. ROOM \(beat) - DAY

            The action on this beat is long enough that it must wrap across the sixty-character text block rather than sitting on a single line of the page.

            MARA
            A speech that is also long enough to wrap, so a page break mid-dialogue has to emit (MORE) and a CONT'D cue rather than orphan the rest.

            """
        }
        return EDraftCore.Screenplay(engineModel: try Fountain.parse(source))
    }
}
