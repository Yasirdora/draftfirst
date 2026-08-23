import XCTest
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
