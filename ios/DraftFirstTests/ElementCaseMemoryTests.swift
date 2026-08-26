import XCTest
import UIKit
@testable import DraftFirst

/// The intelligent casing policy: converting TO an uppercase kind applies
/// caps, converting BACK restores the writer's own casing — and any edit
/// after the conversion wins over the memory.
@MainActor
final class ElementCaseMemoryTests: XCTestCase {

    private func element(
        _ text: String,
        type: ScreenplayKind = .action,
        id: UUID = UUID()
    ) -> ScriptElement {
        ScriptElement(id: id, type: type, text: text)
    }

    func testConvertingToUppercaseKindAppliesCaps() {
        var memory = ElementCaseMemory()
        let converted = memory.text(for: element("Mara"), convertedTo: .character)
        XCTAssertEqual(converted, "MARA")
    }

    func testConvertingBackRestoresOriginalCasing() {
        var memory = ElementCaseMemory()
        let id = UUID()
        let mara = element("Mara", id: id)
        let converted = memory.text(for: mara, convertedTo: .character)
        XCTAssertEqual(converted, "MARA")
        let restored = memory.text(
            for: element(converted, type: .character, id: id),
            convertedTo: .action
        )
        XCTAssertEqual(restored, "Mara")
    }

    func testChainedUppercaseConversionsKeepOldestOriginal() {
        var memory = ElementCaseMemory()
        let id = UUID()
        // action → character → scene → dialogue: the intermediate re-cased
        // forms must never replace "Mara" as the original.
        var current = memory.text(for: element("Mara", id: id), convertedTo: .character)
        current = memory.text(for: element(current, type: .character, id: id), convertedTo: .scene)
        XCTAssertEqual(current, "MARA")
        let restored = memory.text(
            for: element(current, type: .scene, id: id),
            convertedTo: .dialogue
        )
        XCTAssertEqual(restored, "Mara")
    }

    func testEditAfterConversionWinsOverMemory() {
        var memory = ElementCaseMemory()
        let id = UUID()
        let converted = memory.text(for: element("Mara", id: id), convertedTo: .character)
        // The writer keeps typing after the conversion — restoring "Mara"
        // over their edit would be data loss.
        let edited = converted + " (O.S.)"
        let result = memory.text(
            for: element(edited, type: .character, id: id),
            convertedTo: .action
        )
        XCTAssertEqual(result, "MARA (O.S.)")
    }

    func testEditedTextBecomesTheNewOriginal() {
        var memory = ElementCaseMemory()
        let id = UUID()
        _ = memory.text(for: element("Mara", id: id), convertedTo: .character)
        // Undo restored the pre-conversion state; the writer then rewrote
        // the line. The stale "Mara" must not shadow the new text.
        let reconverted = memory.text(for: element("Marcus", id: id), convertedTo: .character)
        XCTAssertEqual(reconverted, "MARCUS")
        let restored = memory.text(
            for: element(reconverted, type: .character, id: id),
            convertedTo: .action
        )
        XCTAssertEqual(restored, "Marcus")
    }

    func testExpandingCaseMappingIsLeftUntouched() {
        var memory = ElementCaseMemory()
        let id = UUID()
        // ß → SS changes the UTF-16 length; the model must stay verbatim.
        let converted = memory.text(for: element("straße", id: id), convertedTo: .scene)
        XCTAssertEqual(converted, "straße")
        let restored = memory.text(
            for: element(converted, type: .scene, id: id),
            convertedTo: .action
        )
        XCTAssertEqual(restored, "straße")
    }

    func testEmptyTextIsNotMemorized() {
        var memory = ElementCaseMemory()
        let id = UUID()
        let converted = memory.text(for: element("", id: id), convertedTo: .character)
        XCTAssertEqual(converted, "")
        let restored = memory.text(
            for: element("", type: .character, id: id),
            convertedTo: .action
        )
        XCTAssertEqual(restored, "")
    }

    func testAlreadyUppercaseTextRoundTrips() {
        var memory = ElementCaseMemory()
        let id = UUID()
        var current = memory.text(
            for: element("MARA", type: .character, id: id),
            convertedTo: .scene
        )
        current = memory.text(for: element(current, type: .scene, id: id), convertedTo: .character)
        XCTAssertEqual(current, "MARA")
    }

    func testNonUppercaseToNonUppercaseLeavesTextAlone() {
        var memory = ElementCaseMemory()
        let converted = memory.text(for: element("Mara"), convertedTo: .dialogue)
        XCTAssertEqual(converted, "Mara")
    }

    func testPruneDropsDeadElements() {
        var memory = ElementCaseMemory()
        let dead = UUID()
        let alive = UUID()
        _ = memory.text(for: element("Mara", id: dead), convertedTo: .character)
        memory.prune(toAlive: [alive])
        // The element is gone from the document; if its id ever resurfaces
        // (a sync merge), no stale memory may re-case it.
        let result = memory.text(
            for: element("MARA", type: .character, id: dead),
            convertedTo: .action
        )
        XCTAssertEqual(result, "MARA")
    }
}

/// The full conversion composition at the EditorState door: casing memory
/// plus the parenthetical lane's brackets. The wrapper sheds before the
/// memory runs, so round trips restore the writer's words — never brackets,
/// never locked caps.
@MainActor
final class ElementConversionTests: XCTestCase {

    private func editor(with element: ScriptElement) -> EditorState {
        let editor = EditorState(source: "An opening image.")
        editor.screenplay = Screenplay(titlePage: [], elements: [element])
        return editor
    }

    func testConvertingIntoParentheticalWraps() {
        let element = ScriptElement(type: .dialogue, text: "beat")
        let editor = editor(with: element)
        XCTAssertEqual(
            editor.textForKindConversion(of: element, to: .parenthetical),
            "(beat)"
        )
    }

    func testConvertingOutOfParentheticalShedsTheWrapper() {
        let element = ScriptElement(type: .parenthetical, text: "(beat)")
        let editor = editor(with: element)
        XCTAssertEqual(
            editor.textForKindConversion(of: element, to: .dialogue),
            "beat"
        )
    }

    func testSeveralDirectionsKeepTheirBrackets() {
        let element = ScriptElement(type: .parenthetical, text: "(beat) (sotto)")
        let editor = editor(with: element)
        XCTAssertEqual(
            editor.textForKindConversion(of: element, to: .dialogue),
            "(beat) (sotto)"
        )
    }

    func testPartialParentheticalShedsTheStrayBracket() {
        let element = ScriptElement(type: .parenthetical, text: "(beat")
        let editor = editor(with: element)
        XCTAssertEqual(
            editor.textForKindConversion(of: element, to: .action),
            "beat"
        )
    }

    func testParentheticalToCharacterShedsThenCaps() {
        let element = ScriptElement(type: .parenthetical, text: "(Mara)")
        let editor = editor(with: element)
        XCTAssertEqual(
            editor.textForKindConversion(of: element, to: .character),
            "MARA"
        )
    }

    func testCharacterToParentheticalRestoresCaseThenWraps() {
        let id = UUID()
        let action = ScriptElement(id: id, type: .action, text: "Mara")
        let editor = editor(with: action)
        // Memorize "Mara" on the way to character…
        let capped = editor.textForKindConversion(of: action, to: .character)
        XCTAssertEqual(capped, "MARA")
        // …then converting on to parenthetical restores and wraps.
        let character = ScriptElement(id: id, type: .character, text: capped)
        XCTAssertEqual(
            editor.textForKindConversion(of: character, to: .parenthetical),
            "(Mara)"
        )
    }

    func testParentheticalCharacterParentheticalRoundTripsExactly() {
        let id = UUID()
        let paren = ScriptElement(id: id, type: .parenthetical, text: "(Mara)")
        let editor = editor(with: paren)
        let capped = editor.textForKindConversion(of: paren, to: .character)
        XCTAssertEqual(capped, "MARA")
        let character = ScriptElement(id: id, type: .character, text: capped)
        XCTAssertEqual(
            editor.textForKindConversion(of: character, to: .parenthetical),
            "(Mara)"
        )
    }
}

/// The Navigator footer's context numbers: scenes, locations, INT/EXT
/// texture, and the dialogue leader — derived through the same scenes/cast
/// the panel lists, so the footnote can never disagree with the rows.
final class StoryStatsTests: XCTestCase {

    @MainActor
    private func stats(of source: String) -> StoryStats {
        EditorState(source: source).storyStats
    }

    @MainActor
    func testEmptyScreenplayHasNoContext() {
        let stats = stats(of: "Title: Untitled\nCredit: written by\n\n")
        XCTAssertEqual(stats.scenes, 0)
        XCTAssertEqual(stats.locations, 0)
        XCTAssertEqual(stats.characters, 0)
        XCTAssertNil(stats.leadingCharacter)
    }

    @MainActor
    func testSceneStructureAndTexture() {
        let stats = stats(of: """
        INT. LAB - DAY

        Hum.

        EXT. RIDGE - NIGHT

        Wind.

        INT./EXT. CAR - MOVING - DAY

        Engine.

        INT. LAB - DAY

        Back again.

        """)
        XCTAssertEqual(stats.scenes, 4)
        // LAB counts once: the location set, not the scene list.
        XCTAssertEqual(stats.locations, 3)
        XCTAssertEqual(stats.exterior, 1)
        // INT./EXT. carries interior work, so it reads as interior.
        XCTAssertEqual(stats.interior, 3)
    }

    @MainActor
    func testCastVoiceAndLeadingShare() {
        let stats = stats(of: """
        INT. LAB - DAY

        MARA
        One.

        MARA (CONT'D)
        Two.

        DAVID
        Three.

        """)
        XCTAssertEqual(stats.characters, 2)
        // Extensions modify delivery, never identity: MARA (CONT'D) is MARA.
        XCTAssertEqual(stats.cues, 3)
        XCTAssertEqual(stats.leadingCharacter, "MARA")
        XCTAssertEqual(stats.leadingShare, 2.0 / 3.0, accuracy: 0.0001)
    }

    /// A forced heading has no INT./EXT. prefix; it must not be counted as
    /// interior texture it never declared.
    @MainActor
    func testForcedHeadingSkipsInteriorExteriorCounts() {
        let stats = stats(of: ".A FORCED HEADING\n\nHum.\n")
        XCTAssertEqual(stats.scenes, 1)
        XCTAssertEqual(stats.interior, 0)
        XCTAssertEqual(stats.exterior, 0)
    }
}

/// Appearance follows the device unless the writer says otherwise. The old
/// build forced Dark on every window regardless of the system setting — a
/// HIG deviation that reads as the app ignoring you, in both directions.
@MainActor
final class AppearancePreferenceTests: XCTestCase {

    private let key = AppearancePreference.storageKey

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testSystemIsTheDefaultAndLeadsTheMenu() {
        XCTAssertEqual(AppearancePreference.default, .system)
        XCTAssertEqual(AppearancePreference.allCases.first, .system)
        XCTAssertEqual(AppearancePreference.allCases.count, 3)
    }

    /// The regression itself: nothing stored must mean "follow the device",
    /// never "dark".
    func testUnsetPreferenceFollowsTheDevice() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(AppearancePreference.stored, .system)
        XCTAssertEqual(AppearancePreference.stored.userInterfaceStyle, .unspecified)
    }

    func testGarbageValueFallsBackToSystem() {
        UserDefaults.standard.set("chartreuse", forKey: key)
        XCTAssertEqual(AppearancePreference.stored, .system)
    }

    /// An explicit choice is still absolute — that was the point of the
    /// window-level override in the first place.
    func testExplicitChoiceIsHonoured() {
        UserDefaults.standard.set(AppearancePreference.light.rawValue, forKey: key)
        XCTAssertEqual(AppearancePreference.stored, .light)
        XCTAssertEqual(AppearancePreference.stored.userInterfaceStyle, .light)

        UserDefaults.standard.set(AppearancePreference.dark.rawValue, forKey: key)
        XCTAssertEqual(AppearancePreference.stored, .dark)
        XCTAssertEqual(AppearancePreference.stored.userInterfaceStyle, .dark)
    }

    func testEveryOptionCarriesATitleAndSymbol() {
        for option in AppearancePreference.allCases {
            XCTAssertFalse(option.title.isEmpty, "\(option) has no title")
            XCTAssertNotNil(UIImage(systemName: option.symbol), "\(option) has no valid symbol")
        }
    }
}
