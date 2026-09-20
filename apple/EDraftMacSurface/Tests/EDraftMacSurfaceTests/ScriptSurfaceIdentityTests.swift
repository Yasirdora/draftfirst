import AppKit
import EDraftCore
import XCTest

@testable import EDraftMacSurface

@MainActor final class ScriptSurfaceIdentityTests: XCTestCase {
  private func ids(_ editor: EditorState) -> [String] {
    editor.screenplay.elements.compactMap { $0.draftID?.rawValue }
  }
  func testNativeStructuralUndoRedoAndBranchPreserveIdentity() {
    let (editor, surface) = ScriptSurfaceHarness.bound(source: "Alpha Beta")
    ScriptSurfaceHarness.type("\n", into: surface, at: NSRange(location: 5, length: 0))
    XCTAssertEqual(ids(editor), ["1", "2"])
    editor.undo()
    XCTAssertEqual(ids(editor), ["1"])
    XCTAssertEqual(editor.screenplay.nextId, "3")
    editor.redo()
    XCTAssertEqual(ids(editor), ["1", "2"])
    editor.undo()
    ScriptSurfaceHarness.type("\n", into: surface, at: NSRange(location: 2, length: 0))
    XCTAssertEqual(ids(editor), ["1", "3"])
    XCTAssertEqual(editor.screenplay.nextId, "4")
  }
  func testNativeReturnAtStartAndMergeRetainFirstPersistentID() throws {
    let (editor, surface) = ScriptSurfaceHarness.bound(source: "Alpha Beta")
    let undo = try XCTUnwrap(surface.undoManager(for: surface.textView))
    // Give each simulated key event its own group. No run-loop event is
    // delivered between these synchronous harness calls.
    undo.groupsByEvent = false
    undo.beginUndoGrouping()
    ScriptSurfaceHarness.type("\n", into: surface, at: NSRange(location: 0, length: 0))
    undo.endUndoGrouping()
    XCTAssertEqual(ids(editor), ["1", "2"])
    undo.beginUndoGrouping()
    ScriptSurfaceHarness.type("", into: surface, at: NSRange(location: 0, length: 1))
    undo.endUndoGrouping()
    XCTAssertEqual(ids(editor), ["1"])
    editor.undo()
    XCTAssertEqual(ids(editor), ["1", "2"])
    editor.redo()
    XCTAssertEqual(ids(editor), ["1"])
    XCTAssertEqual(editor.screenplay.nextId, "3")
  }
  func testInsertPagesRemintsSourceAndDuplicateIdentity() {
    let (editor, surface) = ScriptSurfaceHarness.bound(source: "Alpha")
    defer { withExtendedLifetime(surface) {} }
    let source = editor.screenplay.elements
    editor.onInsertElements?(source)
    XCTAssertEqual(ids(editor), ["1", "2"])
    XCTAssertEqual(Set(editor.screenplay.elements.map(\.id)).count, 2)
    editor.undo()
    XCTAssertEqual(ids(editor), ["1"])
    editor.redo()
    XCTAssertEqual(ids(editor), ["1", "2"])
  }
}
