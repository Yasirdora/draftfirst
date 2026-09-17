import AppKit
import EDraftCore
import SwiftUI
import XCTest
@testable import EDraftMacSurface

/// A note is beside the page, not on it.
///
/// The point of every case here is that a writer's private aside must not be
/// set in Courier among the stage directions, must not take a line of a page
/// a production schedules against, and must still be findable — which is what
/// the mark in the margin and the wash on the line are for.
@MainActor
final class ScriptSurfaceNotesTests: XCTestCase {

    private func script() -> [ScriptElement] {
        [
            ScriptElement(type: .scene, text: "INT. LAB - DAY"),
            ScriptElement(type: .action, text: "She waits."),
            ScriptElement(type: .character, text: "MARA"),
            ScriptElement(type: .dialogue, text: "You're late.")
        ]
    }

    func testANoteIsNotOnThePage() {
        let elements = script()
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        editor.activeElementID = elements[1].id
        editor.addNote("Is this the same lab as scene 4?")
        surface.renderIfNeeded(editor)

        XCTAssertFalse(
            surface.textView.string.contains("Is this the same lab as scene 4?"),
            "the note was set into the script"
        )
        XCTAssertFalse(surface.textView.string.contains("[["), "the note's Fountain marks reached the page")
        XCTAssertTrue(surface.textView.string.contains("She waits."))
    }

    /// The outline shares the seam. It must not be set on the page either —
    /// and unlike a note it gets no mark in the margin, because an act heading
    /// belongs to the whole stretch under it, not to one line.
    func testTheOutlineIsNotOnThePageAndGetsNoMark() {
        let (editor, surface) = ScriptSurfaceHarness.bound(
            source: "# Act One\n\n= They meet.\n\nINT. LAB - DAY\n\nShe waits."
        )

        XCTAssertEqual(editor.outline.count, 2, "the outline did not come off the page")
        XCTAssertFalse(surface.textView.string.contains("Act One"), "an act heading was set on the page")
        XCTAssertFalse(surface.textView.string.contains("They meet."), "a summary was set on the page")
        XCTAssertFalse(surface.textView.string.contains("#"), "the Fountain marks reached the page")
        XCTAssertTrue(surface.textView.string.contains("INT. LAB - DAY"))
        XCTAssertTrue(surface.canvas.noteMarkerFrames.isEmpty, "the outline got a note's mark")
    }

    /// The mark is what says a note is there at all.
    func testEachNoteGetsAMarkInTheMargin() {
        let elements = script()
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        editor.activeElementID = elements[1].id
        editor.addNote("First.")
        editor.activeElementID = elements[3].id
        editor.addNote("Second.")
        surface.renderIfNeeded(editor)

        XCTAssertEqual(surface.canvas.noteMarkerFrames.count, 2)
    }

    func testAScriptWithNoNotesHasNoMarks() {
        let (editor, surface) = ScriptSurfaceHarness.bound(script())
        surface.renderIfNeeded(editor)
        XCTAssertTrue(surface.canvas.noteMarkerFrames.isEmpty)
    }

    /// The right margin: nothing printed reaches it, so the mark never lands
    /// on a word.
    func testTheMarkSitsBeyondTheLastColumnOfType() {
        let elements = script()
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        editor.activeElementID = elements[1].id
        editor.addNote("A note.")
        surface.renderIfNeeded(editor)

        let mark = try? XCTUnwrap(surface.canvas.noteMarkerFrames.first)
        let format = PageFormat.current
        let pageLeft = ((surface.canvas.frame.width - format.pageRect.width) / 2).rounded(.down)
        let textRight = pageLeft
            + ScreenplayPageLayout.textLeft
            + ScreenplayPageLayout.textBlockWidth(format)

        XCTAssertNotNil(mark)
        XCTAssertGreaterThanOrEqual(mark?.minX ?? 0, textRight, "the mark overlaps the text block")
        XCTAssertLessThanOrEqual(
            mark?.maxX ?? .greatestFiniteMagnitude,
            pageLeft + format.pageRect.width,
            "the mark fell off the page"
        )
    }

    /// The mark belongs beside the line it is about, not at the top of the
    /// document — this is the whole affordance.
    func testTheMarkIsLevelWithTheLineItIsAbout() {
        let elements = script()
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        editor.activeElementID = elements[3].id
        editor.addNote("About the dialogue.")
        surface.renderIfNeeded(editor)

        let mark = try? XCTUnwrap(surface.canvas.noteMarkerFrames.first)
        let line = ScriptLayout.boundingRect(
            of: ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
                .first { $0.id == elements[3].id }.map {
                    NSRange(location: $0.range.location, length: 1)
                } ?? NSRange(location: 0, length: 1),
            in: surface.textView
        )
        let inCanvas = line.map { surface.canvas.convert($0, from: surface.textView) }

        XCTAssertNotNil(mark)
        XCTAssertNotNil(inCanvas)
        XCTAssertEqual(
            mark?.midY ?? 0, inCanvas?.midY ?? -1, accuracy: 2,
            "the mark is not level with its line"
        )
    }

    /// The wash is how a reader tells which line a mark belongs to.
    func testTheNotedLineIsWashedAndTheRestIsNot() {
        let elements = script()
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        editor.activeElementID = elements[1].id
        editor.addNote("About the action.")
        surface.renderIfNeeded(editor)

        let layoutManager = try? XCTUnwrap(surface.textView.layoutManager)
        let ranges = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
        let action = try? XCTUnwrap(ranges.first { $0.id == elements[1].id })
        let heading = try? XCTUnwrap(ranges.first { $0.id == elements[0].id })

        let onAction = layoutManager?.temporaryAttribute(
            .backgroundColor, atCharacterIndex: action?.range.location ?? 0, effectiveRange: nil
        )
        let onHeading = layoutManager?.temporaryAttribute(
            .backgroundColor, atCharacterIndex: heading?.range.location ?? 0, effectiveRange: nil
        )

        XCTAssertNotNil(onAction, "the noted line was not marked")
        XCTAssertNil(onHeading, "a line with no note on it was marked")
    }

    /// A colour written into the text storage would follow the writer's words
    /// into a copy, a paste and the PDF. It has to be the layout manager's.
    func testTheWashIsNotInTheDocumentsOwnAttributes() {
        let elements = script()
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        editor.activeElementID = elements[1].id
        editor.addNote("About the action.")
        surface.renderIfNeeded(editor)

        let action = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
            .first { $0.id == elements[1].id }
        let stored = surface.textView.textStorage?.attribute(
            .backgroundColor, at: action?.range.location ?? 0, effectiveRange: nil
        )
        XCTAssertNil(stored, "the wash was written into the script itself")
    }

    /// Deleting the note takes the mark and the wash with it.
    func testRemovingTheNoteRemovesTheMarkAndTheWash() {
        let elements = script()
        let (editor, surface) = ScriptSurfaceHarness.bound(elements)
        editor.activeElementID = elements[1].id
        let note = editor.addNote("Going away.")
        surface.renderIfNeeded(editor)
        XCTAssertEqual(surface.canvas.noteMarkerFrames.count, 1)

        editor.deleteNote(id: try! XCTUnwrap(note).id)
        surface.renderIfNeeded(editor)

        XCTAssertTrue(surface.canvas.noteMarkerFrames.isEmpty)
        let action = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
            .first { $0.id == elements[1].id }
        XCTAssertNil(
            surface.textView.layoutManager?.temporaryAttribute(
                .backgroundColor, atCharacterIndex: action?.range.location ?? 0, effectiveRange: nil
            ),
            "the wash outlived the note"
        )
    }
}

/// Notes from a Final Draft file, on the page.
///
/// Marked and washed like the writer's own, coloured by whoever the file says
/// wrote them, and read in the card without an editor: eDraft never writes one.
@MainActor
final class ScriptSurfaceImportedNotesTests: XCTestCase {

    /// A four-line scene. Paragraph starts, as a ScriptNote Range counts them:
    /// heading 0, action 15, cue 26, dialogue 31; the script ends at 43.
    private func opened(notes: [String]) throws -> (EditorState, ScriptSurface) {
        let fdx = """
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        <Paragraph Type="Scene Heading"><Text>INT. LAB - DAY</Text></Paragraph>
        <Paragraph Type="Action"><Text>She waits.</Text></Paragraph>
        <Paragraph Type="Character"><Text>MARA</Text></Paragraph>
        <Paragraph Type="Dialogue"><Text>You're late.</Text></Paragraph>
        </Content>
        <ScriptNotes>\(notes.joined())</ScriptNotes>
        </FinalDraft>
        """
        let file = try ScreenplayFile.open(Data(fdx.utf8), as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        return (editor, surface)
    }

    private func note(_ range: String, by author: String?, _ text: String) -> String {
        let writer = author.map { " WriterName=\"\($0)\"" } ?? ""
        return "<ScriptNote Range=\"\(range)\"\(writer)><Paragraph><Text>\(text)</Text></Paragraph></ScriptNote>"
    }

    private func line(_ editor: EditorState, _ text: String) throws -> UUID {
        try XCTUnwrap(editor.screenplay.elements.first { $0.text == text }?.id)
    }

    func testEachLineAFinalDraftNoteIsAboutGetsOneMark() throws {
        let (editor, surface) = try opened(notes: [
            note("15,25", by: "Writer A", "Why is she waiting?"),
            note("31,43", by: "Writer B", "Softer."),
            note("31,43", by: "Writer A", "Or louder."),
            note("0,14", by: nil, "Which lab?")
        ])
        XCTAssertEqual(editor.importedNotes.count, 4)
        XCTAssertEqual(surface.canvas.noteMarkerFrames.count, 3, "one mark per noted line")
    }

    func testAMarkTakesItsAuthorsColourOrStaysNeutralWhenAuthorsMix() throws {
        let (editor, surface) = try opened(notes: [
            note("15,25", by: "Writer A", "Why is she waiting?"),
            note("31,43", by: "Writer B", "Softer."),
            note("31,43", by: "Writer A", "Or louder."),
            note("0,14", by: nil, "Which lab?")
        ])
        let slots = NoteAttribution.slots(for: editor.noteRoster)
        let byNote = Dictionary(uniqueKeysWithValues: editor.importedNotes.map { ($0.text, $0.id) })
        func mark(_ text: String) throws -> NoteMarker {
            try XCTUnwrap(surface.canvas.noteMarker(for: try XCTUnwrap(byNote[text])) as? NoteMarker)
        }

        XCTAssertEqual(try mark("Why is she waiting?").authorSlot, slots["Writer A"])
        XCTAssertNotNil(slots["Writer A"])
        XCTAssertNil(try mark("Softer.").authorSlot, "one mark cannot say two people's names")
        XCTAssertNil(try mark("Which lab?").authorSlot, "a note nobody signed stays yellow")
        XCTAssertNotEqual(slots["Writer A"], slots["Writer B"])
    }

    func testTheLineAFinalDraftNoteIsAboutIsWashed() throws {
        let (editor, surface) = try opened(notes: [note("15,25", by: "Writer A", "Why is she waiting?")])
        let layoutManager = try XCTUnwrap(surface.textView.layoutManager)
        let ranges = ScreenplayEditPlanner.ranges(for: editor.screenplay.elements)
        let action = try XCTUnwrap(ranges.first { $0.id == (try? line(editor, "She waits.")) })
        let heading = try XCTUnwrap(ranges.first { $0.id == (try? line(editor, "INT. LAB - DAY")) })

        XCTAssertNotNil(layoutManager.temporaryAttribute(
            .backgroundColor, atCharacterIndex: action.range.location, effectiveRange: nil
        ))
        XCTAssertNil(layoutManager.temporaryAttribute(
            .backgroundColor, atCharacterIndex: heading.range.location, effectiveRange: nil
        ))
    }

    func testANoteWhoseLineWasNotFoundGetsNoMark() throws {
        let (editor, surface) = try opened(notes: [note("900,910", by: "Writer A", "Somewhere else.")])
        XCTAssertEqual(editor.importedNotes.count, 1)
        XCTAssertNil(editor.importedNotes.first?.anchor)
        XCTAssertTrue(surface.canvas.noteMarkerFrames.isEmpty, "a lost note was pinned to a line it is not about")
    }

    func testTheWritersOwnNoteSharesTheLineWithFinalDrafts() throws {
        let (editor, surface) = try opened(notes: [note("15,25", by: "Writer A", "Why is she waiting?")])
        editor.addNote("Because he is late.", to: try line(editor, "She waits."))
        surface.renderIfNeeded(editor)
        XCTAssertEqual(surface.canvas.noteMarkerFrames.count, 1, "two notes on one line are one mark")
    }

    // MARK: - The card

    private func editableTextViews(in view: NSView) -> [NSTextView] {
        let own = (view as? NSTextView).map { $0.isEditable ? [$0] : [] } ?? []
        return own + view.subviews.flatMap(editableTextViews)
    }

    private func hosted(_ card: NoteCard) -> NSView {
        let host = NSHostingView(rootView: card)
        host.frame = NSRect(x: 0, y: 0, width: 280, height: 400)
        host.layoutSubtreeIfNeeded()
        return host
    }

    func testTheCardReadsAFinalDraftNoteWithoutAnEditor() {
        let imported = ImportedNote(author: "Writer A", title: "Re: Gold Key", text: "Let's try it.", anchor: UUID())
        let readOnly = hosted(NoteCard(
            notes: [], imported: [imported], focused: nil,
            onEdit: { _, _ in }, onDone: {}, onDelete: { _ in }, onAdd: {}
        ))
        XCTAssertTrue(editableTextViews(in: readOnly).isEmpty, "a Final Draft note was offered for editing")

        // The control: the writer's own note on the same card is editable.
        let own = ScriptAside(element: ScriptElement(type: .note, text: "Mine."), anchor: imported.anchor)
        let mixed = hosted(NoteCard(
            notes: [own], imported: [imported], focused: nil,
            onEdit: { _, _ in }, onDone: {}, onDelete: { _ in }, onAdd: {}
        ))
        XCTAssertEqual(editableTextViews(in: mixed).count, 1)
    }

    func testTheCardSaysWhoWroteItWhereAndWhen() {
        var parts = DateComponents()
        parts.year = 2020; parts.month = 12; parts.day = 13
        let created = Calendar.current.date(from: parts)
        let note = ImportedNote(author: "Writer A", created: created, text: "Love this.", anchor: nil)
        let caption = NoteCard.caption(note)
        XCTAssertTrue(caption.hasPrefix("Writer A · Final Draft · "))
        XCTAssertTrue(caption.contains("2020"))
        XCTAssertEqual(NoteCard.caption(ImportedNote(text: "Unsigned.", anchor: nil)), "Unsigned · Final Draft")
    }
}
