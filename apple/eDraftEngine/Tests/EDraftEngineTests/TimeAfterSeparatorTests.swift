import Testing
@testable import EDraftEngine

/// Completing the time on a scene heading, which is where a writer spends the
/// most keystrokes and where a missing suggestion is felt immediately.
///
/// Reported on both surfaces: write two headings, select the time on one and
/// start rewriting it, and nothing is offered. Both surfaces run this engine,
/// so if the fault is shared it is here.
@Suite("Time after the separator")
struct TimeAfterSeparatorTests {

    private func script(_ texts: [String]) -> Screenplay {
        Screenplay(
            titlePage: [],
            elements: texts.map { ScreenplayElement(type: .scene, text: $0) }
        )
    }

    @Test("a bare separator offers the times")
    func bareSeparatorOffersTimes() {
        let model = script(["INT. PARKING LOT - ", "INT. KIOSK - CONTINUOUS"])
        let out = PredictionEngine.predict(
            model, type: .scene, text: "INT. PARKING LOT - ", index: 0
        )
        #expect(!out.isEmpty, "a heading ending in the separator should offer times")
    }

    @Test("a separator with no trailing space still offers the times")
    func tightSeparatorOffersTimes() {
        let model = script(["INT. PARKING LOT -", "INT. KIOSK - CONTINUOUS"])
        let out = PredictionEngine.predict(
            model, type: .scene, text: "INT. PARKING LOT -", index: 0
        )
        #expect(!out.isEmpty, "the trailing space is gone but the dash still asks for a time")
    }

    @Test("one typed letter completes to a time")
    func oneLetterCompletes() {
        let model = script(["INT. PARKING LOT - E", "INT. KIOSK - CONTINUOUS"])
        let out = PredictionEngine.predict(
            model, type: .scene, text: "INT. PARKING LOT - E", index: 0
        )
        #expect(out.contains { $0.text == "EVENING" }, "E should complete to EVENING; got \(out.map(\.text))")
    }

    @Test("and on the last heading too")
    func onTheLastHeading() {
        let model = script(["INT. KIOSK - CONTINUOUS", "INT. PARKING LOT - E"])
        let out = PredictionEngine.predict(
            model, type: .scene, text: "INT. PARKING LOT - E", index: 1
        )
        #expect(out.contains { $0.text == "EVENING" }, "got \(out.map(\.text))")
    }
}
