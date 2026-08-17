import Foundation
import Testing
import DraftFirstEngine

/// Regression: predicting inside the very first scene of a fresh document —
/// no earlier scene with a location exists — trapped in
/// `nextLocationCounts` (`1..<0` on an empty sequence) and took the app down
/// the moment a writer accepted the `INT. ` suggestion in a blank draft.
/// Device crash 2026-08-15, EXC_BREAKPOINT in
/// `PredictionEngine.nextLocationCounts(_:before:)`.
@Suite("First-scene prediction regression")
struct FirstScenePredictionRegressionTests {

    /// A blank draft whose only element is the scene being typed.
    private static func freshDraft(_ text: String) -> Screenplay {
        Screenplay(elements: [ScreenplayElement(type: .scene, text: text)])
    }

    @Test("scene predict with no prior scene", arguments: [
        "IN", "INT.", "INT. ", "INT. K", "INT. KI", "INT. KITCHEN",
        "INT. KITCHEN ", "INT. BED", "INT. BED ", "INT. LAB - ",
        "INT. LAB - D", "INT. LAB - DAY ", "EXT. FIELD - NIGHT",
        "INT./EXT. CAR - DAWN", "INT.",
    ])
    func scenePredictWithoutPriorScene(text: String) {
        let predictions = PredictionEngine.predict(
            Self.freshDraft(text), type: .scene, text: text, index: 0
        )
        for prediction in predictions {
            _ = PredictionEngine.ghostSuffix(
                candidate: prediction.text,
                blockText: text,
                hint: prediction.hint ?? false
            )
        }
    }

    @Test("action promotion with no prior scene", arguments: ["IN", "INT.", "INT. KITCHEN", "EXT. B"])
    func actionPromotionWithoutPriorScene(text: String) {
        let screenplay = Screenplay(elements: [ScreenplayElement(type: .action, text: text)])
        _ = PredictionEngine.predict(screenplay, type: .action, text: text, index: 0)
    }

    @Test("scene predict where earlier scenes carry no location")
    func scenePredictWithLocationlessScenes() {
        let screenplay = Screenplay(elements: [
            ScreenplayElement(type: .scene, text: "INT."),
            ScreenplayElement(type: .scene, text: "EXT."),
            ScreenplayElement(type: .scene, text: "INT. LAB - D"),
        ])
        _ = PredictionEngine.predict(screenplay, type: .scene, text: "INT. LAB - D", index: 2)
    }

    @Test("paginate an open first scene being typed", arguments: [
        "INT.", "INT. KITCHEN", "INT. KITCHEN ", "INT. LAB - DAY - ",
    ])
    func paginateOpenFirstScene(text: String) throws {
        _ = try Paginator.paginate(Self.freshDraft(text))
    }

    @Test("scene predict across typed prefixes with history")
    func scenePredictWithHistory() {
        let script = Screenplay(elements: [
            ScreenplayElement(type: .scene, text: "INT. KITCHEN - DAY"),
            ScreenplayElement(type: .action, text: "A quiet room."),
        ])
        for text in ["IN", "INT.", "INT. ", "INT. K", "INT. KITCHEN",
                     "INT. BED ", "INT. LAB - ", "INT. LAB - D", "INT. LAB - DAY "] {
            let predictions = PredictionEngine.predict(script, type: .scene, text: text, index: 2)
            for prediction in predictions {
                _ = PredictionEngine.ghostSuffix(
                    candidate: prediction.text,
                    blockText: text,
                    hint: prediction.hint ?? false
                )
            }
        }
    }
}
