import EDraftEngine
import Foundation
import XCTest

@testable import EDraftCore

@MainActor final class DraftElementIdentityTests: XCTestCase {
  private func ids(_ editor: EditorState) -> [String] {
    editor.screenplay.elements.compactMap { $0.draftID?.rawValue }
  }
  private func edit(
    _ editor: EditorState, _ range: NSRange, _ replacement: String,
    _ intent: ScreenplayEditPlanner.Intent
  ) throws {
    let plan = try XCTUnwrap(
      ScreenplayEditPlanner.plan(
        elements: editor.screenplay.elements, replacing: range, with: replacement, intent: intent,
        kindForNewElement: { _, _, _, _ in .action }))
    editor.replaceAllElements(
      plan.elements, activeID: plan.activeElementID, offset: plan.activeOffset, structural: true)
  }
  func testTypingAndStyleKeepIdentity() {
    let editor = EditorState(source: "Alpha Beta")
    let initial = ids(editor)
    let id = editor.screenplay.elements[0].id
    editor.replaceElementText(id: id, text: "Alpha Better", structural: true)
    editor.screenplay.elements[0].runs = [StyleRun(start: 0, end: 5, styles: .bold)]
    editor.applyLiveText(
      id: id, text: "Alpha Best", selectionOffset: 10, replaced: NSRange(location: 6, length: 6),
      insertedLength: 4)
    XCTAssertEqual(ids(editor), initial)
    XCTAssertEqual(editor.screenplay.nextId, "2")
  }
  func testReturnAtStartMiddleAndEndAllocatesExactlyOneAndKeepsFirstIdentity() throws {
    for offset in [0, 5, 10] {
      let editor = EditorState(source: "Alpha Beta")
      try edit(editor, NSRange(location: offset, length: 0), "\n", .returnKey)
      XCTAssertEqual(ids(editor), ["1", "2"], "offset \(offset)")
      XCTAssertEqual(editor.screenplay.nextId, "3")
    }
  }
  func testUndoRedoAndDivergentSplitNeverRewindCounter() throws {
    let editor = EditorState(source: "Alpha Beta")
    try edit(editor, NSRange(location: 5, length: 0), "\n", .returnKey)
    XCTAssertEqual(ids(editor), ["1", "2"])
    editor.undo()
    XCTAssertEqual(ids(editor), ["1"])
    XCTAssertEqual(editor.screenplay.nextId, "3")
    editor.redo()
    XCTAssertEqual(ids(editor), ["1", "2"])
    XCTAssertEqual(editor.screenplay.nextId, "3")
    editor.undo()
    try edit(editor, NSRange(location: 2, length: 0), "\n", .returnKey)
    XCTAssertEqual(ids(editor), ["1", "3"])
    XCTAssertEqual(editor.screenplay.nextId, "4")
  }
  func testMergeRetiresSecondAndUndoRestoresIt() throws {
    let editor = EditorState(source: "Alpha\n\nBeta")
    XCTAssertEqual(ids(editor), ["1", "2"])
    try edit(editor, NSRange(location: 5, length: 1), "", .boundaryDeletion)
    XCTAssertEqual(ids(editor), ["1"])
    XCTAssertEqual(editor.screenplay.nextId, "3")
    editor.undo()
    XCTAssertEqual(ids(editor), ["1", "2"])
    editor.redo()
    XCTAssertEqual(ids(editor), ["1"])
  }
  func testPasteAndForeignElementsCannotBringIdentityEvenWithMatchingSpelling() throws {
    let destination = EditorState(source: "Here")
    let foreign = EditorState(source: "Elsewhere")
    destination.replaceAllElements(
      destination.screenplay.elements + foreign.screenplay.elements, activeID: nil, offset: 0,
      structural: true)
    XCTAssertEqual(ids(destination), ["1", "2"])
    let duplicate = destination.screenplay.elements[0].copyForInsertion()
    destination.replaceAllElements(
      destination.screenplay.elements + [duplicate], activeID: nil, offset: 0, structural: true)
    XCTAssertEqual(ids(destination), ["1", "2", "3"])
    let paste = EditorState(source: "")
    let retired = ids(paste)
    try edit(
      paste, NSRange(location: 0, length: 0), "Fresh paragraph.\n\nAnother paragraph.",
      .multilinePaste)
    XCTAssertTrue(Set(ids(paste)).isDisjoint(with: retired))
    XCTAssertEqual(Set(ids(paste)).count, ids(paste).count)
  }
  func testReopenAndUndoPreserveRetiredHighWater() throws {
    var model = try DraftIdentity.adopting(Fountain.parse("Alpha\n\nBeta"))
    model.nextId = "20"
    let editor = try EditorState(identifiedScreenplay: model)
    try edit(editor, NSRange(location: 5, length: 0), "\n", .returnKey)
    XCTAssertEqual(ids(editor), ["1", "20", "2"])
    editor.undo()
    let saved = try DraftFile.fromIdentifiedScreenplay(editor.identifiedDocumentModel)
    let reopened = try DraftFile.toIdentifiedScreenplay(saved).screenplay
    XCTAssertEqual(reopened.nextId, "21")
    XCTAssertEqual(reopened.elements.compactMap { $0.id?.rawValue }, ["1", "2"])
    let next = try EditorState(identifiedScreenplay: reopened)
    try edit(next, NSRange(location: 5, length: 0), "\n", .returnKey)
    XCTAssertEqual(ids(next), ["1", "21", "2"])
  }
  func testStructuralElementsShareTheDocumentCounterButNotesDoNot() {
    let editor = EditorState(source: "# Act one\n\nAlpha\n\n[[Note.]]\n\nBeta")
    let model = editor.identifiedDocumentModel
    XCTAssertEqual(
      model.elements.filter { $0.type != .note }.compactMap { $0.id?.rawValue }, ["1", "2", "3"])
    XCTAssertTrue(model.elements.filter { $0.type == .note }.allSatisfy { $0.id == nil })
    XCTAssertEqual(model.nextId, "4")
  }
  func testFountainSessionsAreIndependentAndStableDuringExternalAlignment() {
    let editor = EditorState(source: "Alpha\n\nBeta")
    let before = ids(editor)
    editor.applyExternalSource("Alpha\n\nBeta\n\nGamma")
    XCTAssertEqual(Array(ids(editor).prefix(2)), before)
    XCTAssertEqual(ids(editor), ["1", "2", "3"])
  }
}

extension DraftElementIdentityTests {
  func testDecodedCoreModelRetainsStoredIDsButTransferRemints() throws {
    let original = EditorState(source: "Alpha")
    let encoded = try JSONEncoder().encode(original.screenplay)
    let decoded = try JSONDecoder().decode(EDraftCore.Screenplay.self, from: encoded)
    XCTAssertEqual(decoded.elements.first?.draftID?.rawValue, "1")
    XCTAssertEqual(decoded.nextId, "2")
    original.replaceAllElements(
      original.screenplay.elements + decoded.elements, activeID: nil, offset: 0, structural: true)
    XCTAssertEqual(ids(original), ["1", "2"])
  }
  func testCounterExhaustionRejectsEditWithoutChangingIdentityOrCounter() throws {
    var model = try DraftIdentity.adopting(Fountain.parse("Alpha"))
    model.nextId = String(repeating: "z", count: 64)
    let editor = try EditorState(identifiedScreenplay: model)
    let before = editor.screenplay
    try edit(editor, NSRange(location: 2, length: 0), "\n", .returnKey)
    XCTAssertEqual(editor.screenplay, before)
  }
}
