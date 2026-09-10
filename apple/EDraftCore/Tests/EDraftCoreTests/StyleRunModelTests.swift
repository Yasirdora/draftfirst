import EDraftEngine
import EDraftCore
import XCTest

/// The app model's side of RFC v2.1 Phase 0: style runs ride `ScriptElement`
/// through the saved document and across the engine conversion, and a
/// document that carries no styling is byte-for-byte the document it always
/// was.
@MainActor
final class StyleRunModelTests: XCTestCase {

    private let run = StyleRun(start: 6, end: 11, styles: [.bold, .italic])

    func testRunsSurviveTheSavedDocumentRoundTrip() throws {
        let screenplay = EDraftCore.Screenplay(elements: [
            ScriptElement(type: .action, text: "Mara *waits*.", runs: [run])
        ])

        let data = try JSONEncoder().encode(screenplay)
        let decoded = try JSONDecoder().decode(EDraftCore.Screenplay.self, from: data)

        XCTAssertEqual(decoded.elements.first?.runs, [run])
    }

    func testAnUnstyledElementWritesNoRunsKey() throws {
        let screenplay = EDraftCore.Screenplay(elements: [
            ScriptElement(type: .action, text: "Plain.")
        ])

        let data = try JSONEncoder().encode(screenplay)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        let elements = try XCTUnwrap(object["elements"] as? [[String: Any]])

        XCTAssertNil(elements.first?["runs"], "Documents without styling must not grow a key")
    }

    func testRunsCrossTheEngineModelInBothDirections() {
        let element = ScriptElement(type: .dialogue, text: "I _know_ that.", runs: [run])

        let across = EDraftCore.Screenplay(elements: [element]).engineModel.elements[0]
        XCTAssertEqual(across.runs, [run])

        let back = EDraftCore.Screenplay(
            engineModel: EDraftEngine.Screenplay(elements: [across])
        )
        XCTAssertEqual(back.elements.first?.runs, [run])
    }
}
