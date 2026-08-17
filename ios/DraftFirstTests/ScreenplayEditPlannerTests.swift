import Foundation
import UIKit
import XCTest
@testable import DraftFirst

final class ScreenplayEditPlannerTests: XCTestCase {
    @MainActor
    func testDeletingFirstCharacterIsNotAParagraphBoundaryEdit() throws {
        let characterID = UUID()
        let elements = [
            ScriptElement(id: characterID, type: .character, text: "ELENA")
        ]
        let source = ScreenplayEditPlanner.flattenedText(elements) as NSString
        let deletion = NSRange(location: 0, length: 1)

        XCTAssertFalse(
            ScreenplayEditPlanner.touchesParagraphBoundary(
                in: source,
                range: deletion,
                replacement: ""
            )
        )

        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: deletion,
            with: "",
            intent: .replacement,
            kindForNewElement: { _, _ in .action }
        ))

        XCTAssertEqual(plan.elements, [
            ScriptElement(id: characterID, type: .character, text: "LENA")
        ])
        XCTAssertEqual(plan.activeElementID, characterID)
        XCTAssertEqual(plan.activeOffset, 0)
        XCTAssertEqual(plan.selection, NSRange(location: 0, length: 0))
    }

    @MainActor
    func testBackspaceOverNewlineMergesParagraphsAndPreservesFollowingElement() throws {
        let actionID = UUID()
        let characterID = UUID()
        let followingID = UUID()
        let elements = [
            ScriptElement(id: actionID, type: .action, text: "Wait for "),
            ScriptElement(id: characterID, type: .character, text: "ELENA"),
            ScriptElement(id: followingID, type: .dialogue, text: "Come in.")
        ]
        let separator = (elements[0].text as NSString).length
        let deletion = NSRange(location: separator, length: 1)
        let source = ScreenplayEditPlanner.flattenedText(elements) as NSString

        XCTAssertTrue(
            ScreenplayEditPlanner.touchesParagraphBoundary(
                in: source,
                range: deletion,
                replacement: ""
            )
        )

        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: deletion,
            with: "",
            intent: .boundaryDeletion,
            kindForNewElement: { _, _ in .action }
        ))

        XCTAssertEqual(plan.elements.count, 2)
        XCTAssertEqual(plan.elements[0].id, actionID)
        XCTAssertEqual(plan.elements[0].type, .action)
        XCTAssertEqual(plan.elements[0].text, "Wait for ELENA")
        XCTAssertEqual(plan.elements[1].id, followingID)
        XCTAssertEqual(plan.elements[1].type, .dialogue)
        XCTAssertEqual(plan.elements[1].text, "Come in.")
        XCTAssertEqual(plan.selection, NSRange(location: separator, length: 0))
    }

    @MainActor
    func testForwardDeleteOverNewlineUsesTheSameStructuralMerge() throws {
        let sceneID = UUID()
        let actionID = UUID()
        let followingID = UUID()
        let elements = [
            ScriptElement(id: sceneID, type: .scene, text: "INT. LAB - NIGHT"),
            ScriptElement(id: actionID, type: .action, text: "Rain needles the glass."),
            ScriptElement(id: followingID, type: .character, text: "ELENA")
        ]
        let separator = (elements[0].text as NSString).length

        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: NSRange(location: separator, length: 1),
            with: "",
            intent: .boundaryDeletion,
            kindForNewElement: { _, _ in .action }
        ))

        XCTAssertEqual(plan.elements.count, 2)
        XCTAssertEqual(plan.elements[0].id, sceneID)
        XCTAssertEqual(plan.elements[0].type, .scene)
        XCTAssertEqual(plan.elements[0].text, "INT. LAB - NIGHTRAIN NEEDLES THE GLASS.")
        XCTAssertEqual(plan.elements[1].id, followingID)
        XCTAssertEqual(plan.elements[1].type, .character)
        XCTAssertEqual(plan.elements[1].text, "ELENA")
        XCTAssertEqual(plan.selection, NSRange(location: separator, length: 0))
    }

    @MainActor
    func testCrossElementDeletionKeepsUntouchedSuffixIdentityAndType() throws {
        let firstID = UUID()
        let secondID = UUID()
        let suffixSceneID = UUID()
        let suffixActionID = UUID()
        let elements = [
            ScriptElement(id: firstID, type: .action, text: "Alpha one"),
            ScriptElement(id: secondID, type: .dialogue, text: "Beta two"),
            ScriptElement(id: suffixSceneID, type: .scene, text: "EXT. ROAD - DAWN"),
            ScriptElement(id: suffixActionID, type: .action, text: "A car approaches.")
        ]
        let start = 6
        let endInsideSecond = (elements[0].text as NSString).length + 1 + 5

        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: NSRange(location: start, length: endInsideSecond - start),
            with: "",
            intent: .replacement,
            kindForNewElement: { _, _ in .action }
        ))

        XCTAssertEqual(plan.elements.count, 3)
        XCTAssertEqual(plan.elements[0].id, firstID)
        XCTAssertEqual(plan.elements[0].type, .action)
        XCTAssertEqual(plan.elements[0].text, "Alpha two")
        XCTAssertEqual(plan.elements[1].id, suffixSceneID)
        XCTAssertEqual(plan.elements[1].type, .scene)
        XCTAssertEqual(plan.elements[1].text, "EXT. ROAD - DAWN")
        XCTAssertEqual(plan.elements[2].id, suffixActionID)
        XCTAssertEqual(plan.elements[2].type, .action)
        XCTAssertEqual(plan.elements[2].text, "A car approaches.")
    }

    @MainActor
    func testReturnReplacingSameLineSelectionSplitsWithoutLosingOwner() throws {
        let characterID = UUID()
        let elements = [
            ScriptElement(id: characterID, type: .character, text: "ELENA")
        ]

        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: NSRange(location: 1, length: 3),
            with: "\n",
            intent: .returnKey,
            kindForNewElement: { previous, _ in
                previous?.type == .character ? .dialogue : .action
            }
        ))

        XCTAssertEqual(plan.elements.count, 2)
        XCTAssertEqual(plan.elements[0].id, characterID)
        XCTAssertEqual(plan.elements[0].type, .character)
        XCTAssertEqual(plan.elements[0].text, "E")
        XCTAssertEqual(plan.elements[1].type, .dialogue)
        XCTAssertEqual(plan.elements[1].text, "A")
        XCTAssertNotEqual(plan.elements[1].id, characterID)
        XCTAssertEqual(plan.selection, NSRange(location: 2, length: 0))
    }

    @MainActor
    func testReturnAtStartKeepsCharacterContentTypeAndIdentity() throws {
        let characterID = UUID()
        let elements = [
            ScriptElement(id: characterID, type: .character, text: "ELENA")
        ]

        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: NSRange(location: 0, length: 0),
            with: "\n",
            intent: .returnKey,
            kindForNewElement: { _, _ in .action }
        ))

        XCTAssertEqual(plan.elements.count, 2)
        XCTAssertEqual(plan.elements[0].type, .action)
        XCTAssertEqual(plan.elements[0].text, "")
        XCTAssertEqual(plan.elements[1].id, characterID)
        XCTAssertEqual(plan.elements[1].type, .character)
        XCTAssertEqual(plan.elements[1].text, "ELENA")
        XCTAssertEqual(plan.activeElementID, characterID)
        XCTAssertEqual(plan.activeOffset, 0)
        XCTAssertEqual(plan.selection, NSRange(location: 1, length: 0))
    }

    @MainActor
    func testMultilinePasteClassifiesInsertedLinesAndKeepsExistingSuffix() throws {
        let openingID = UUID()
        let suffixSceneID = UUID()
        let suffixActionID = UUID()
        let elements = [
            ScriptElement(id: openingID, type: .action, text: "The door opens."),
            ScriptElement(id: suffixSceneID, type: .scene, text: "INT. HALL - NIGHT"),
            ScriptElement(id: suffixActionID, type: .action, text: "Silence.")
        ]
        let insertion = (elements[0].text as NSString).length

        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: NSRange(location: insertion, length: 0),
            with: "\nELENA\nCome in.",
            intent: .multilinePaste,
            kindForNewElement: { previous, text in
                if text == text.uppercased(), !text.isEmpty { return .character }
                if previous?.type == .character { return .dialogue }
                return .action
            }
        ))

        XCTAssertEqual(plan.elements.count, 5)
        XCTAssertEqual(plan.elements[0].id, openingID)
        XCTAssertEqual(plan.elements[0].type, .action)
        XCTAssertEqual(plan.elements[0].text, "The door opens.")
        XCTAssertEqual(plan.elements[1].type, .character)
        XCTAssertEqual(plan.elements[1].text, "ELENA")
        XCTAssertEqual(plan.elements[2].type, .dialogue)
        XCTAssertEqual(plan.elements[2].text, "Come in.")
        XCTAssertEqual(plan.elements[3].id, suffixSceneID)
        XCTAssertEqual(plan.elements[3].type, .scene)
        XCTAssertEqual(plan.elements[3].text, "INT. HALL - NIGHT")
        XCTAssertEqual(plan.elements[4].id, suffixActionID)
        XCTAssertEqual(plan.elements[4].type, .action)
        XCTAssertEqual(plan.elements[4].text, "Silence.")
    }

    @MainActor
    func testSelectAllDeletionProducesOneEmptyAction() throws {
        let elements = [
            ScriptElement(type: .scene, text: "INT. LAB - NIGHT"),
            ScriptElement(type: .character, text: "ELENA"),
            ScriptElement(type: .dialogue, text: "We begin.")
        ]
        let source = ScreenplayEditPlanner.flattenedText(elements) as NSString

        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: NSRange(location: 0, length: source.length),
            with: "",
            intent: .replacement,
            kindForNewElement: { _, _ in .dialogue }
        ))

        XCTAssertEqual(plan.elements.count, 1)
        XCTAssertEqual(plan.elements[0].type, .action)
        XCTAssertEqual(plan.elements[0].text, "")
        XCTAssertEqual(plan.activeElementID, plan.elements[0].id)
        XCTAssertEqual(plan.activeOffset, 0)
        XCTAssertEqual(plan.selection, NSRange(location: 0, length: 0))
    }
}

final class EditorStateMetadataTests: XCTestCase {
    @MainActor
    func testTitleWriterAndCreditPersistThroughTheSharedSerializer() throws {
        let editor = EditorState(source: """
        Title: Old Title
        Credit: written by
        Author: Old Writer

        FADE IN:
        """)
        var publishedSource: String?
        editor.onSourceChange = { publishedSource = $0 }

        editor.updateTitlePage(
            title: "The New Story",
            writer: "Elena Voss",
            credit: "Screenplay by"
        )

        XCTAssertEqual(editor.titlePageValue(for: "Title"), "The New Story")
        XCTAssertEqual(editor.titlePageValue(for: "Author"), "Elena Voss")
        XCTAssertEqual(editor.titlePageValue(for: "Credit"), "Screenplay by")
        let source = try XCTUnwrap(publishedSource)
        XCTAssertTrue(source.contains("Title: The New Story"))
        XCTAssertTrue(source.contains("Author: Elena Voss"))
        XCTAssertTrue(source.contains("Credit: Screenplay by"))
    }

    @MainActor
    func testUnchangedMetadataDoesNotCreateARevision() {
        let editor = EditorState(source: """
        Title: The New Story
        Credit: Screenplay by
        Author: Elena Voss

        FADE IN:
        """)
        let revision = editor.revision

        editor.updateTitlePage(
            title: " The New Story ",
            writer: "Elena Voss",
            credit: "Screenplay by"
        )

        XCTAssertEqual(editor.revision, revision)
    }
}

final class ScreenplayEditPlannerAuditTests: XCTestCase {
    @MainActor
    func testBackspaceAtEmptyNonActionConvertsInPlaceAndPreservesIdentity() throws {
        let sceneID = UUID()
        let emptyCharacterID = UUID()
        let followingID = UUID()
        let elements = [
            ScriptElement(id: sceneID, type: .scene, text: "INT. LAB - NIGHT"),
            ScriptElement(id: emptyCharacterID, type: .character, text: ""),
            ScriptElement(id: followingID, type: .action, text: "The monitors hum.")
        ]
        let separatorBeforeEmptyElement = (elements[0].text as NSString).length

        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: NSRange(location: separatorBeforeEmptyElement, length: 1),
            with: "",
            intent: .backspaceAtElementStart,
            kindForNewElement: { _, _ in .action }
        ))

        XCTAssertEqual(plan.elements.count, 3)
        XCTAssertEqual(plan.elements[0], elements[0])
        XCTAssertEqual(plan.elements[1].id, emptyCharacterID)
        XCTAssertEqual(plan.elements[1].type, .action)
        XCTAssertEqual(plan.elements[1].text, "")
        XCTAssertEqual(plan.elements[2], elements[2])
        XCTAssertEqual(plan.activeElementID, emptyCharacterID)
        XCTAssertEqual(plan.activeOffset, 0)
        XCTAssertEqual(
            plan.selection,
            NSRange(location: separatorBeforeEmptyElement + 1, length: 0)
        )
    }

    @MainActor
    func testReturnOnWhitespaceOnlyNonActionNormalizesToEmptyAction() throws {
        let characterID = UUID()
        let whitespace = " \t "
        let editor = EditorState(source: "An opening image.")
        editor.screenplay = Screenplay(
            titlePage: [],
            elements: [ScriptElement(id: characterID, type: .character, text: whitespace)]
        )
        editor.activeElementID = characterID
        editor.selectionOffset = (whitespace as NSString).length

        let textView = ScreenplayTextView(usingTextLayoutManager: false)
        textView.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        let coordinator = ScriptTextView.Coordinator(editor: editor)
        coordinator.attach(to: textView)
        coordinator.renderModel(selecting: characterID, offset: editor.selectionOffset)

        let shouldApplyNatively = coordinator.textView(
            textView,
            shouldChangeTextIn: textView.selectedRange,
            replacementText: "\n"
        )

        XCTAssertFalse(shouldApplyNatively)
        XCTAssertEqual(editor.screenplay.elements.count, 1)
        XCTAssertEqual(editor.screenplay.elements[0].id, characterID)
        XCTAssertEqual(editor.screenplay.elements[0].type, .action)
        XCTAssertEqual(editor.screenplay.elements[0].text, "")
        XCTAssertEqual(editor.activeElementID, characterID)
        XCTAssertEqual(editor.selectionOffset, 0)
        XCTAssertEqual(textView.selectedRange, NSRange(location: 0, length: 0))
    }

    @MainActor
    func testReplacingNewlineWithNewlinePreservesBothOwnersAndSuffix() throws {
        let actionID = UUID()
        let characterID = UUID()
        let dialogueID = UUID()
        let elements = [
            ScriptElement(id: actionID, type: .action, text: "A door opens."),
            ScriptElement(id: characterID, type: .character, text: "ELENA"),
            ScriptElement(id: dialogueID, type: .dialogue, text: "Come in.")
        ]
        let separator = (elements[0].text as NSString).length

        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: NSRange(location: separator, length: 1),
            with: "\n",
            intent: .replacement,
            kindForNewElement: { _, _ in .action }
        ))

        XCTAssertEqual(plan.elements, elements)
        XCTAssertEqual(plan.activeElementID, characterID)
        XCTAssertEqual(plan.activeOffset, 0)
        XCTAssertEqual(plan.selection, NSRange(location: separator + 1, length: 0))
    }

    @MainActor
    func testMultilinePasteIntoEmptyActionClassifiesFirstAndFollowingLines() throws {
        let placeholderID = UUID()
        let elements = [
            ScriptElement(id: placeholderID, type: .action, text: "")
        ]
        let replacement = "INT. LAB - NIGHT\nELENA\nWe have to leave."

        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: NSRange(location: 0, length: 0),
            with: replacement,
            intent: .multilinePaste,
            kindForNewElement: simpleFountainClassifier
        ))

        XCTAssertEqual(plan.elements.map(\.type), [.scene, .character, .dialogue])
        XCTAssertEqual(
            plan.elements.map(\.text),
            ["INT. LAB - NIGHT", "ELENA", "We have to leave."]
        )
        XCTAssertEqual(plan.activeElementID, plan.elements[2].id)
        XCTAssertEqual(plan.activeOffset, (plan.elements[2].text as NSString).length)
    }

    @MainActor
    func testBlankFountainSeparatorsDoNotCreateEmptyScreenplayBlocks() throws {
        let elements = [ScriptElement(type: .action, text: "")]
        let replacement = "INT. LAB - NIGHT\n\nELENA\n\nWe have to leave."

        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: NSRange(location: 0, length: 0),
            with: replacement,
            intent: .multilinePaste,
            kindForNewElement: simpleFountainClassifier
        ))

        XCTAssertEqual(plan.elements.map(\.type), [.scene, .character, .dialogue])
        XCTAssertEqual(
            plan.elements.map(\.text),
            ["INT. LAB - NIGHT", "ELENA", "We have to leave."]
        )
        XCTAssertFalse(plan.elements.contains(where: { $0.text.isEmpty }))
        XCTAssertEqual(
            plan.selection.location,
            (ScreenplayEditPlanner.flattenedText(plan.elements) as NSString).length
        )
    }

    @MainActor
    func testMultilinePasteReplacesWhitespacePlaceholderCleanly() throws {
        let placeholderID = UUID()
        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: [ScriptElement(id: placeholderID, type: .character, text: "   ")],
            replacing: NSRange(location: 3, length: 0),
            with: "INT. LAB - NIGHT\nELENA\nCome in.",
            intent: .multilinePaste,
            kindForNewElement: simpleFountainClassifier
        ))

        XCTAssertEqual(plan.elements.map(\.type), [.scene, .character, .dialogue])
        XCTAssertEqual(plan.elements.map(\.text), ["INT. LAB - NIGHT", "ELENA", "Come in."])
        XCTAssertFalse(plan.elements.contains(where: { $0.id == placeholderID }))
    }

    @MainActor
    func testBlankMultilinePasteIsANoOp() throws {
        let element = ScriptElement(type: .action, text: "Keep this.")
        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: [element],
            replacing: NSRange(location: 4, length: 0),
            with: "\n  \n",
            intent: .multilinePaste,
            kindForNewElement: simpleFountainClassifier
        ))

        XCTAssertEqual(plan.elements, [element])
        XCTAssertEqual(plan.activeElementID, element.id)
        XCTAssertEqual(plan.activeOffset, 4)
        XCTAssertEqual(plan.selection, NSRange(location: 4, length: 0))
    }

    @MainActor
    func testNativeMultiElementReplacementRetainsAlignedInteriorOwners() throws {
        let actionID = UUID()
        let characterID = UUID()
        let parentheticalID = UUID()
        let dialogueID = UUID()
        let suffixSceneID = UUID()
        let elements = [
            ScriptElement(id: actionID, type: .action, text: "Rain falls."),
            ScriptElement(id: characterID, type: .character, text: "ELENA"),
            ScriptElement(id: parentheticalID, type: .parenthetical, text: "(quietly)"),
            ScriptElement(id: dialogueID, type: .dialogue, text: "Run."),
            ScriptElement(id: suffixSceneID, type: .scene, text: "EXT. ROAD - DAWN")
        ]
        let oldText = ScreenplayEditPlanner.flattenedText(elements)
        let newText = "Cold rain falls.\nELENA\n(quietly)\nRun now.\nEXT. ROAD - DAWN"
        let difference = try XCTUnwrap(
            ScreenplayEditPlanner.replacementBetween(oldText, newText)
        )

        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: difference.0,
            with: difference.1,
            intent: .replacement,
            kindForNewElement: simpleFountainClassifier
        ))

        XCTAssertEqual(ScreenplayEditPlanner.flattenedText(plan.elements), newText)
        let preservedCharacter = try XCTUnwrap(
            plan.elements.first(where: { $0.text == "ELENA" })
        )
        let preservedParenthetical = try XCTUnwrap(
            plan.elements.first(where: { $0.text == "(quietly)" })
        )
        let preservedDialogue = try XCTUnwrap(
            plan.elements.first(where: { $0.text == "Run now." })
        )
        let preservedSuffix = try XCTUnwrap(
            plan.elements.first(where: { $0.text == "EXT. ROAD - DAWN" })
        )
        XCTAssertEqual(preservedCharacter.id, characterID)
        XCTAssertEqual(preservedCharacter.type, .character)
        XCTAssertEqual(preservedParenthetical.id, parentheticalID)
        XCTAssertEqual(preservedParenthetical.type, .parenthetical)
        XCTAssertEqual(preservedDialogue.id, dialogueID)
        XCTAssertEqual(preservedDialogue.type, .dialogue)
        XCTAssertEqual(preservedSuffix.id, suffixSceneID)
        XCTAssertEqual(preservedSuffix.type, .scene)
    }

    @MainActor
    func testUTF16DifferenceExpandsAcrossAnEntireEmojiScalar() throws {
        let difference = try XCTUnwrap(
            ScreenplayEditPlanner.replacementBetween("A😀B", "A😃B")
        )

        XCTAssertEqual(difference.0, NSRange(location: 1, length: 2))
        XCTAssertEqual(difference.1, "😃")

        let rebuilt = ("A😀B" as NSString).replacingCharacters(
            in: difference.0,
            with: difference.1
        )
        XCTAssertEqual(rebuilt, "A😃B")
    }

    @MainActor
    private func simpleFountainClassifier(
        previous: ScriptElement?,
        text: String
    ) -> ScreenplayKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let uppercase = trimmed.uppercased()
        if uppercase.hasPrefix("INT.") || uppercase.hasPrefix("EXT.") { return .scene }
        if trimmed.hasPrefix("(") { return .parenthetical }
        if previous?.type == .character || previous?.type == .parenthetical { return .dialogue }
        if !trimmed.isEmpty, trimmed == uppercase { return .character }
        return .action
    }
}

final class EditorStateEditingTests: XCTestCase {
    @MainActor
    func testNewStructuralEditInvalidatesRedoHistory() {
        let editor = EditorState(source: "An opening image.")
        let elementID = UUID()
        editor.screenplay = Screenplay(
            titlePage: [],
            elements: [ScriptElement(id: elementID, type: .action, text: "First")]
        )
        editor.activeElementID = elementID
        editor.selectionOffset = 5

        editor.replaceElementText(id: elementID, text: "Second", structural: true)
        editor.undo()
        XCTAssertEqual(editor.screenplay.elements[0].text, "First")
        XCTAssertTrue(editor.canRedo)

        editor.prepareForNativeEdit()
        editor.replaceAllElements(
            [ScriptElement(id: elementID, type: .action, text: "A new branch")],
            activeID: elementID,
            offset: 12,
            structural: true,
            recordsUndo: false
        )
        XCTAssertFalse(editor.canRedo)
        editor.redo()
        XCTAssertEqual(editor.screenplay.elements[0].text, "A new branch")
    }

    @MainActor
    func testElementTextEditsNormalizeUppercaseKinds() {
        let editor = EditorState(source: "An opening image.")
        let characterID = UUID()
        editor.screenplay = Screenplay(
            titlePage: [],
            elements: [ScriptElement(id: characterID, type: .character, text: "")]
        )
        editor.activeElementID = characterID

        editor.replaceElementText(id: characterID, text: "Elena", structural: false)

        XCTAssertEqual(editor.screenplay.elements[0].text, "ELENA")
        XCTAssertEqual(editor.activeElementID, characterID)
        XCTAssertEqual(editor.selectionOffset, 5)
    }

    @MainActor
    func testLiveTypingUppercasesOnlyUppercaseKinds() {
        // The keyboard never capitalizes (autocapitalizationType is .none);
        // the model owns casing on the live-typing path. Regression cover for
        // the stuck all-characters keyboard that capitalized every element.
        let editor = EditorState(source: "An opening image.")
        let characterID = UUID()
        let actionID = UUID()
        editor.screenplay = Screenplay(
            titlePage: [],
            elements: [
                ScriptElement(id: characterID, type: .character, text: "EL"),
                ScriptElement(id: actionID, type: .action, text: "The door")
            ]
        )

        editor.applyLiveText(id: characterID, text: "ELena", selectionOffset: 5)
        XCTAssertEqual(editor.screenplay.elements[0].text, "ELENA")

        editor.applyLiveText(id: actionID, text: "The door stays quiet.", selectionOffset: 21)
        XCTAssertEqual(editor.screenplay.elements[1].text, "The door stays quiet.")
    }

    @MainActor
    func testLiveTypingKeepsExpandingCaseMappingsInSyncWithStorage() {
        // ß→SS would change the UTF-16 length; the text storage intentionally
        // leaves such text untouched, so the model must too.
        let editor = EditorState(source: "An opening image.")
        let characterID = UUID()
        editor.screenplay = Screenplay(
            titlePage: [],
            elements: [ScriptElement(id: characterID, type: .character, text: "")]
        )

        editor.applyLiveText(id: characterID, text: "straße", selectionOffset: 6)
        XCTAssertEqual(editor.screenplay.elements[0].text, "straße")
    }

    @MainActor
    func testOpenPositionsCaretAtEndOnlyWhenAsked() {
        let source = "FADE IN:\n\nA quiet room.\n\nELENA\nHello."
        let atStart = EditorState(source: source)
        XCTAssertEqual(atStart.opensAtEnd, false)
        XCTAssertEqual(atStart.activeElementIndex, 0)
        XCTAssertEqual(atStart.selectionOffset, 0)

        let atEnd = EditorState(source: source, startsAtEnd: true)
        XCTAssertEqual(atEnd.opensAtEnd, true)
        XCTAssertEqual(atEnd.activeElementIndex, atEnd.screenplay.elements.count - 1)
        let lastTextLength = (atEnd.screenplay.elements.last?.text ?? "") as NSString
        XCTAssertEqual(atEnd.selectionOffset, lastTextLength.length)
    }
}

final class EditorStateCastTests: XCTestCase {
    @MainActor
    func testCanonicalCharacterNameStripsTrailingExtensionsAndWhitespace() {
        XCTAssertEqual(EditorState.canonicalCharacterName("MARIA (CONT'D)"), "MARIA")
        XCTAssertEqual(EditorState.canonicalCharacterName("MARIA (CONT'D) "), "MARIA")
        XCTAssertEqual(EditorState.canonicalCharacterName("MARIA (CONT’D)\u{00A0}"), "MARIA")
        XCTAssertEqual(EditorState.canonicalCharacterName("MARIA (V.O.) (CONT'D)"), "MARIA")
        XCTAssertEqual(EditorState.canonicalCharacterName("david (o.s.)"), "DAVID")
        XCTAssertEqual(EditorState.canonicalCharacterName("  ELENA  "), "ELENA")
        XCTAssertEqual(EditorState.canonicalCharacterName("(V.O.)"), "")
    }

    @MainActor
    func testCastMergesCueExtensionsIntoOneEntryPerCharacter() {
        let editor = EditorState(source: "An opening image.")
        editor.screenplay = Screenplay(
            titlePage: [],
            elements: [
                ScriptElement(id: UUID(), type: .character, text: "MARIA"),
                ScriptElement(id: UUID(), type: .character, text: "MARIA (CONT'D) "),
                ScriptElement(id: UUID(), type: .character, text: "MARIA (V.O.)"),
                ScriptElement(id: UUID(), type: .character, text: "DAVID"),
                ScriptElement(id: UUID(), type: .character, text: "DAVID (CONT'D)"),
            ]
        )

        let cast = editor.cast
        XCTAssertEqual(cast.count, 2)
        XCTAssertEqual(cast.first?.name, "MARIA")
        XCTAssertEqual(cast.first?.cues, 3)
        XCTAssertEqual(cast.last?.name, "DAVID")
        XCTAssertEqual(cast.last?.cues, 2)
    }
}
