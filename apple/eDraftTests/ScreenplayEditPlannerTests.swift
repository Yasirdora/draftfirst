import EDraftCore
import Foundation
import UIKit
import XCTest
@testable import EDraftUIKitSurface

final class ScreenplayEditPlannerTests: XCTestCase {
    @MainActor
    func testReturnAtEndOfParentheticalClosesItAndOpensDialogue() throws {
        let id = UUID()
        let elements = [ScriptElement(id: id, type: .parenthetical, text: "(whispering)")]
        // The caret sits between the brackets, where a parenthetical puts it.
        let caret = NSRange(location: 11, length: 0)

        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: caret,
            with: "\n",
            intent: .returnKey,
            kindForNewElement: { _, _ in .dialogue }
        ))

        XCTAssertEqual(plan.elements.map(\.type), [.parenthetical, .dialogue])
        XCTAssertEqual(plan.elements[0].text, "(whispering)")
        XCTAssertEqual(plan.elements[1].text, "")
        XCTAssertEqual(plan.elements[0].id, id, "the direction keeps its identity")
        XCTAssertEqual(plan.activeElementID, plan.elements[1].id)
        XCTAssertEqual(plan.activeOffset, 0)
    }

    @MainActor
    func testReturnInsideAParentheticalKeepsBothHalvesAndItsBrackets() throws {
        let elements = [
            ScriptElement(type: .parenthetical, text: "(whispering to himself)")
        ]
        // After "whispering", with the rest of the direction still to come.
        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: elements,
            replacing: NSRange(location: 11, length: 0),
            with: "\n",
            intent: .returnKey,
            kindForNewElement: { _, _ in .dialogue }
        ))

        // Neither half is left holding half a bracket, and no words are lost.
        XCTAssertEqual(plan.elements.map(\.type), [.parenthetical, .dialogue])
        XCTAssertEqual(plan.elements[0].text, "(whispering)")
        XCTAssertEqual(plan.elements[1].text, "to himself")
    }

    @MainActor
    func testReturnOutsideTheBracketsLeavesTheDirectionWhole() throws {
        // Before the opener and after the closer both split cleanly on the
        // ordinary path; the parenthetical rule must not disturb them.
        for caret in [0, 12] {
            let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
                elements: [ScriptElement(type: .parenthetical, text: "(whispering)")],
                replacing: NSRange(location: caret, length: 0),
                with: "\n",
                intent: .returnKey,
                kindForNewElement: { _, _ in .dialogue }
            ))
            XCTAssertTrue(
                plan.elements.contains { $0.text == "(whispering)" },
                "a caret at \(caret) must leave the direction intact"
            )
        }
    }

    @MainActor
    func testReturnJustInsideTheOpenerLeavesNoEmptyBracket() throws {
        // The direction has not begun yet, so there is nothing to close.
        let plan = try XCTUnwrap(ScreenplayEditPlanner.plan(
            elements: [ScriptElement(type: .parenthetical, text: "(whispering)")],
            replacing: NSRange(location: 1, length: 0),
            with: "\n",
            intent: .returnKey,
            kindForNewElement: { _, _ in .dialogue }
        ))

        XCTAssertEqual(plan.elements.map(\.text), ["(whispering)", ""])
        XCTAssertEqual(plan.elements.map(\.type), [.parenthetical, .dialogue])
    }

    @MainActor
    func testCaretFollowsTheTextWhenAnElementBecomesAParenthetical() {
        // "whispering" with the caret at the end becomes "(whispering)" with
        // the caret still after the "g" — offset 11, not the 10 that carrying
        // the old offset across unchanged would leave.
        XCTAssertEqual(
            EditorState.caretAfterConversion(
                from: "whispering", to: "(whispering)", caret: 10, kind: .parenthetical
            ),
            11
        )
        // And never outside the closer, wherever it started.
        XCTAssertEqual(
            EditorState.caretAfterConversion(
                from: "whispering", to: "(whispering)", caret: 99, kind: .parenthetical
            ),
            11
        )
        // Converting back out sheds the opener and the caret sheds with it.
        XCTAssertEqual(
            EditorState.caretAfterConversion(
                from: "(beat)", to: "beat", caret: 5, kind: .dialogue
            ),
            4
        )
    }

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

    /// Return on a line with nothing on it changes what the line *is*, and
    /// what it becomes is the engine's to say — `Choreography.emptyLineEscape`,
    /// pinned by the conformance corpus. A cue nobody spoke under escapes to
    /// action: the oldest reflex in the craft, Return twice after a speech.
    /// This asserts the surface asks rather than deciding for itself, so the
    /// two can never drift apart in silence.
    @MainActor
    func testReturnOnWhitespaceOnlyCueEscapesToEmptyAction() throws {
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

        editor.applyLiveText(
            id: characterID, text: "ELena", selectionOffset: 5,
            replaced: NSRange(location: 2, length: 0), insertedLength: 3
        )
        XCTAssertEqual(editor.screenplay.elements[0].text, "ELENA")

        editor.applyLiveText(
            id: actionID, text: "The door stays quiet.", selectionOffset: 21,
            replaced: NSRange(location: 8, length: 0), insertedLength: 13
        )
        XCTAssertEqual(editor.screenplay.elements[1].text, "The door stays quiet.")
    }

    @MainActor
    func testLiveTypingShoutsExpandingCaseMappings() {
        // This used to assert the opposite, and said why: the text storage
        // left ß alone because SS is a different UTF-16 length, "so the model
        // must too". That had the authority backwards — a text view's range
        // arithmetic deciding what a screenplay says — and it made the two
        // surfaces store different files for one keystroke once the Mac began
        // capitalising at the input boundary. The model states the rule now,
        // and the surface redraws when the answer is not the length it typed.
        let editor = EditorState(source: "An opening image.")
        let characterID = UUID()
        editor.screenplay = Screenplay(
            titlePage: [],
            elements: [ScriptElement(id: characterID, type: .character, text: "")]
        )

        editor.applyLiveText(
            id: characterID, text: "straße", selectionOffset: 6,
            replaced: NSRange(location: 0, length: 0), insertedLength: 6
        )
        XCTAssertEqual(editor.screenplay.elements[0].text, "STRASSE")
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



/// Characterisation of the keystroke path.
///
/// Every edit the writer makes reaches the model through
/// `ScreenplayEditPlanner.plan`, and the 1,300-line coordinator that calls it
/// is the least decomposed code in the app. These pin what the planner
/// currently decides across the whole surface — typing, splitting, merging,
/// pasting, deleting — so that coordinator can be refactored against evidence
/// instead of hope. Each expectation below was recorded from the running
/// implementation and then read for correctness; a diff here means behaviour
/// changed, which is either a bug or a decision worth making deliberately.
@MainActor
final class KeystrokePathCharacterisationTests: XCTestCase {

    /// Flattened: "INT. LAB - DAY\nMara waits.\nMARA\n(quietly)\nIt is time."
    ///             0              14 15         27 28   33 34    43 44
    private let script: [ScriptElement] = [
        ScriptElement(type: .scene, text: "INT. LAB - DAY"),
        ScriptElement(type: .action, text: "Mara waits."),
        ScriptElement(type: .character, text: "MARA"),
        ScriptElement(type: .parenthetical, text: "(quietly)"),
        ScriptElement(type: .dialogue, text: "It is time.")
    ]

    /// The plan as one readable line, so a failure diff names the change.
    private func characterise(
        _ range: NSRange, _ replacement: String, _ intent: ScreenplayEditPlanner.Intent
    ) -> String {
        let plan = ScreenplayEditPlanner.plan(
            elements: script, replacing: range, with: replacement, intent: intent,
            kindForNewElement: { previous, text in
                EditorState(source: "").kindForInsertedElement(after: previous, text: text)
            }
        )
        guard let plan else { return "nil" }
        let body = plan.elements.map { "\($0.type.rawValue):\"\($0.text)\"" }.joined(separator: " | ")
        let caret = plan.elements.firstIndex { $0.id == plan.activeElementID }.map(String.init) ?? "?"
        return "\(body)  <caret \(caret)@\(plan.activeOffset)>"
    }

    func testTheScriptIsTheLengthTheOffsetsAssume() {
        XCTAssertEqual((ScreenplayEditPlanner.flattenedText(script) as NSString).length, 53)
    }

    func testTypingInsideAnElementTouchesOnlyThatElement() {
        XCTAssertEqual(
            characterise(NSRange(location: 4, length: 0), "X", .replacement),
            #"scene:"INT.X LAB - DAY" | action:"Mara waits." | character:"MARA" | parenthetical:"(quietly)" | dialogue:"It is time."  <caret 0@5>"#
        )
    }

    /// After a slug comes action — the new paragraph is typed, not chosen.
    func testReturnAtTheEndOfASceneOpensAction() {
        XCTAssertEqual(
            characterise(NSRange(location: 14, length: 0), "\n", .returnKey),
            #"scene:"INT. LAB - DAY" | action:"" | action:"Mara waits." | character:"MARA" | parenthetical:"(quietly)" | dialogue:"It is time."  <caret 1@0>"#
        )
    }

    func testReturnMidParagraphSplitsAtTheCaret() {
        XCTAssertEqual(
            characterise(NSRange(location: 20, length: 0), "\n", .returnKey),
            #"scene:"INT. LAB - DAY" | action:"Mara " | action:"waits." | character:"MARA" | parenthetical:"(quietly)" | dialogue:"It is time."  <caret 2@0>"#
        )
    }

    /// The caret follows the words, not the blank line left above them.
    func testReturnAtAParagraphStartKeepsTheCaretWithTheText() {
        XCTAssertEqual(
            characterise(NSRange(location: 15, length: 0), "\n", .returnKey),
            #"scene:"INT. LAB - DAY" | action:"" | action:"Mara waits." | character:"MARA" | parenthetical:"(quietly)" | dialogue:"It is time."  <caret 2@0>"#
        )
    }

    func testReturnAfterACueOpensSpeech() {
        XCTAssertEqual(
            characterise(NSRange(location: 31, length: 0), "\n", .returnKey),
            #"scene:"INT. LAB - DAY" | action:"Mara waits." | character:"MARA" | dialogue:"" | parenthetical:"(quietly)" | dialogue:"It is time."  <caret 3@0>"#
        )
    }

    /// After a speech, the next thing a writer types is usually another
    /// speaker — the engine's choreography, pinned to its conformance corpus.
    func testReturnAfterSpeechOpensTheNextCue() {
        XCTAssertEqual(
            characterise(NSRange(location: 53, length: 0), "\n", .returnKey),
            #"scene:"INT. LAB - DAY" | action:"Mara waits." | character:"MARA" | parenthetical:"(quietly)" | dialogue:"It is time." | character:""  <caret 5@0>"#
        )
    }

    /// Merging into an uppercase lane re-cases what arrives: the action text
    /// becomes part of a slug, so it is a slug's casing now.
    func testBackspaceAtAParagraphStartMergesAndRecases() {
        XCTAssertEqual(
            characterise(NSRange(location: 14, length: 1), "", .backspaceAtElementStart),
            #"scene:"INT. LAB - DAYMARA WAITS." | character:"MARA" | parenthetical:"(quietly)" | dialogue:"It is time."  <caret 0@14>"#
        )
    }

    /// Forward delete over the same boundary must land in the same place —
    /// the direction the writer approached from is not a semantic difference.
    func testForwardDeleteOverABoundaryMatchesBackspace() {
        XCTAssertEqual(
            characterise(NSRange(location: 14, length: 1), "", .boundaryDeletion),
            characterise(NSRange(location: 14, length: 1), "", .backspaceAtElementStart)
        )
    }

    func testASelectionSpanningElementsCollapsesIntoTheFirst() {
        XCTAssertEqual(
            characterise(NSRange(location: 10, length: 10), "Z", .replacement),
            #"scene:"INT. LAB -ZWAITS." | character:"MARA" | parenthetical:"(quietly)" | dialogue:"It is time."  <caret 0@11>"#
        )
    }

    /// Pasted lines are classified by what they look like, so a short line of
    /// capitals arrives as a cue rather than as action.
    func testPastedLinesAreClassifiedNotInherited() {
        XCTAssertEqual(
            characterise(NSRange(location: 15, length: 0), "A\nB", .multilinePaste),
            #"scene:"INT. LAB - DAY" | character:"A" | action:"BMara waits." | character:"MARA" | parenthetical:"(quietly)" | dialogue:"It is time."  <caret 2@1>"#
        )
    }

    /// A document is never empty: deleting everything leaves one blank action
    /// for the caret to live in.
    func testDeletingEverythingLeavesOneBlankAction() {
        XCTAssertEqual(
            characterise(NSRange(location: 0, length: 53), "", .replacement),
            #"action:""  <caret 0@0>"#
        )
    }
}


/// Numbering runs through the editor, not around it: it must reach the text
/// view's undo registration, and it must not disturb element identity — the
/// caret, the undo timeline and the case memory are all keyed on it.
@MainActor
final class SceneNumberingIntegrationTests: XCTestCase {

    private let source = "INT. A - DAY\n\nMara waits.\n\nEXT. B - NIGHT\n\nWind.\n"

    func testNumberingReachesTheEditorAndKeepsEveryIdentity() throws {
        let editor = EditorState(source: source)
        var applied: [ScriptElement]?
        var undoName: String?
        editor.onApplyElements = { elements, name in applied = elements; undoName = name }
        let identities = editor.screenplay.elements.map(\.id)

        XCTAssertEqual(editor.applySceneNumbering(.newScenesOnly), 2)

        let result = try XCTUnwrap(applied)
        XCTAssertEqual(result.compactMap(\.sceneNumber), ["1", "2"])
        XCTAssertEqual(result.map(\.id), identities)
        XCTAssertEqual(undoName, "Number Scenes")
    }

    /// Re-running it changes nothing, so it must not push an empty step onto
    /// the undo stack.
    func testNumberingAnAlreadyNumberedScriptIsANoOp() {
        let editor = EditorState(source: source)
        var applications = 0
        editor.onApplyElements = { elements, _ in
            applications += 1
            editor.replaceAllElements(
                elements, activeID: elements.first?.id, offset: 0, structural: true
            )
        }
        XCTAssertEqual(editor.applySceneNumbering(.newScenesOnly), 2)
        XCTAssertEqual(editor.applySceneNumbering(.newScenesOnly), 0)
        XCTAssertEqual(applications, 1, "no undoable step for a change that changed nothing")
    }

    /// Before the text view has wired itself up there is nowhere to register
    /// an undoable edit, so the operation declines rather than writing the
    /// model behind UIKit's back.
    func testNumberingDeclinesWithoutTheEditorSurface() {
        XCTAssertEqual(EditorState(source: source).applySceneNumbering(.all), 0)
    }
}


/// The Navigator's cast list is navigation, not a poster: a row has to go
/// somewhere. It went nowhere until 3 September — the rows rendered as plain
/// stacks while the scene rows were buttons.
@MainActor
final class CastNavigationTests: XCTestCase {

    private let source = [
        "INT. LAB - DAY", "", "MARA", "First.", "",
        "DAVID", "Hello.", "", "MARA (V.O.)", "Again."
    ].joined(separator: "\n")

    func testEachCastRowPointsAtThatCharactersFirstCue() throws {
        let editor = EditorState(source: source)
        let cues = editor.screenplay.elements.filter { $0.type == .character }
        let mara = try XCTUnwrap(editor.cast.first { $0.name == "MARA" })

        // Two cues, one of them carrying an extension, collapse onto one row.
        XCTAssertEqual(mara.cues, 2)
        XCTAssertEqual(mara.firstCueID, cues.first?.id, "the first appearance, not the last")
        XCTAssertNotEqual(mara.firstCueID, cues.last?.id)
    }

    func testEveryCastRowResolvesToARealElement() {
        let editor = EditorState(source: source)
        let ids = Set(editor.screenplay.elements.map(\.id))
        XCTAssertFalse(editor.cast.isEmpty)
        for person in editor.cast {
            XCTAssertTrue(ids.contains(person.firstCueID), "\(person.name) points nowhere")
        }
    }

    func testJumpingFromACastRowMovesTheCaretThere() throws {
        let editor = EditorState(source: source)
        let david = try XCTUnwrap(editor.cast.first { $0.name == "DAVID" })
        editor.jump(to: david.firstCueID)
        XCTAssertEqual(editor.activeElementID, david.firstCueID)
    }
}


/// Renaming a character is the operation a cast list actually exists for.
/// It must reach every cue, keep each cue's extension, and stop at prose.
@MainActor
final class CharacterRenameTests: XCTestCase {

    private let source = [
        "INT. LAB - DAY", "",
        "MARA", "First.", "",
        "Mara crosses to the window.", "",
        "DAVID", "Hello.", "",
        "MARA (V.O.)", "Again."
    ].joined(separator: "\n")

    private func rename(_ from: String, to: String) -> [ScriptElement] {
        let editor = EditorState(source: source)
        var applied: [ScriptElement] = editor.screenplay.elements
        editor.onApplyElements = { elements, _ in applied = elements }
        editor.renameCharacter(from, to: to)
        return applied
    }

    func testEveryCueIsRenamedAndItsExtensionKept() {
        let cues = rename("MARA", to: "Elena").filter { $0.type == .character }.map(\.text)
        XCTAssertEqual(cues, ["ELENA", "DAVID", "ELENA (V.O.)"])
    }

    /// Cues only is the conservative default: prose is untouched unless the
    /// writer asks for it, having been shown how much prose there is.
    func testProseIsLeftAloneUnlessAsked() {
        let actions = rename("MARA", to: "Elena").filter { $0.type == .action }.map(\.text)
        XCTAssertTrue(actions.contains("Mara crosses to the window."), "\(actions)")
    }

    func testRenamingRegistersOneUndoableStepUnderItsOwnName() {
        let editor = EditorState(source: source)
        var name: String?
        var applications = 0
        editor.onApplyElements = { _, actionName in name = actionName; applications += 1 }
        XCTAssertEqual(editor.renameCharacter("MARA", to: "Elena"), 2)
        XCTAssertEqual(name, "Rename Character")
        XCTAssertEqual(applications, 1)
    }

    func testRenamingOntoAnExistingNameMergesTheCharacters() {
        let cues = rename("MARA", to: "DAVID").filter { $0.type == .character }.map(\.text)
        XCTAssertEqual(cues, ["DAVID", "DAVID", "DAVID (V.O.)"])
    }

    func testTheMergeIsAnnouncedBeforeItHappens() {
        let editor = EditorState(source: source)
        XCTAssertTrue(editor.characterExists("david"), "matched regardless of casing")
        XCTAssertFalse(editor.characterExists("ELENA"))
    }

    func testAnEmptyOrUnchangedNameDoesNothing() {
        let editor = EditorState(source: source)
        editor.onApplyElements = { _, _ in XCTFail("nothing should be applied") }
        XCTAssertEqual(editor.renameCharacter("MARA", to: "   "), 0)
        XCTAssertEqual(editor.renameCharacter("MARA", to: "mara"), 0)
        XCTAssertEqual(editor.renameCharacter("NOBODY", to: "Elena"), 0)
    }

    func testTheExtensionIsWhatTheCanonicaliserStrips() {
        XCTAssertEqual(EditorState.cueExtension("MARA (V.O.)"), " (V.O.)")
        XCTAssertEqual(EditorState.cueExtension("MARA (V.O.) (CONT'D)"), " (V.O.) (CONT'D)")
        XCTAssertEqual(EditorState.cueExtension("MARA"), "")
    }
}


/// Renaming across prose is what a writer means by "her name is Elena now" —
/// a script with ELENA in the cues and "Mara" in the action is broken. The
/// danger is not the rename, it is the pattern: a name is also a word.
@MainActor
final class CharacterRenameAcrossProseTests: XCTestCase {

    private let source = [
        "INT. LAB - DAY", "",
        "MARA", "First.", "",
        "Mara crosses to the window. A MARAUDER waits outside.", "",
        "DAVID", "Elena said MARA would come.", "",
        "MARA (V.O.)", "Again."
    ].joined(separator: "\n")

    private func editor() -> EditorState { EditorState(source: source) }

    private func rename(includingMentions: Bool) -> [ScriptElement] {
        let editor = editor()
        var applied = editor.screenplay.elements
        editor.onApplyElements = { elements, _ in applied = elements }
        editor.renameCharacter("MARA", to: "Elena", includingMentions: includingMentions)
        return applied
    }

    /// Twice: once in action, once inside another character's dialogue.
    /// MARAUDER contains the name and is not a mention of it.
    func testMentionsAreCountedByWholeWordOnly() {
        XCTAssertEqual(editor().characterMentions("MARA"), 2)
    }

    func testRenamingEverywhereRewritesProse() {
        let texts = rename(includingMentions: true).map(\.text)
        XCTAssertTrue(
            texts.contains("Elena crosses to the window. A MARAUDER waits outside."),
            "\(texts)"
        )
        XCTAssertTrue(texts.contains("Elena said Elena would come."), "\(texts)")
    }

    /// The reason whole-word matching exists.
    func testALongerWordContainingTheNameIsNeverTouched() {
        let joined = rename(includingMentions: true).map(\.text).joined(separator: " ")
        XCTAssertTrue(joined.contains("MARAUDER"))
        XCTAssertFalse(joined.contains("ELENAUDER"))
        XCTAssertFalse(joined.contains("Elenauder"))
    }

    /// Cues shout because their lane does; prose takes the name as typed.
    func testCuesUppercaseWhileProseKeepsTheTypedCasing() {
        let elements = rename(includingMentions: true)
        XCTAssertEqual(
            elements.filter { $0.type == .character }.map(\.text),
            ["ELENA", "DAVID", "ELENA (V.O.)"]
        )
        XCTAssertTrue(elements.contains { $0.type == .action && $0.text.hasPrefix("Elena ") })
    }

    func testCuesOnlyLeavesEveryMentionStanding() {
        let texts = rename(includingMentions: false).map(\.text)
        XCTAssertTrue(texts.contains("Mara crosses to the window. A MARAUDER waits outside."))
        XCTAssertTrue(texts.contains("Elena said MARA would come."))
    }

    /// A name carrying regex characters must be matched literally, or the
    /// pattern silently means something else.
    func testANameWithPunctuationIsMatchedLiterally() {
        let editor = EditorState(source: [
            "INT. LAB - DAY", "",
            "MR. O'BRIEN", "Hello.", "",
            "Mr. O'Brien waits. MR X waits too."
        ].joined(separator: "\n"))
        XCTAssertEqual(editor.characterMentions("MR. O'BRIEN"), 1)
    }
}


/// A character's thread: the scenes they speak in and what they say there.
/// One walk has to answer both "does she sound like one person" and "where
/// is she in this story", and every row it produces has to be a real place.
@MainActor
final class CharacterThreadTests: XCTestCase {

    private let source = [
        "INT. LAB - DAY", "",
        "MARA", "(quietly)", "First.", "Second.", "",
        "DAVID", "Not me.", "",
        "EXT. ROOF - NIGHT", "",
        "DAVID", "Alone here.", "",
        "INT. CAR - LATER", "",
        "MARA", "Third."
    ].joined(separator: "\n")

    func testOnlyTheScenesWhereTheySpeakAreListed() {
        let appearances = EditorState(source: source).appearances(of: "MARA")
        XCTAssertEqual(appearances.map(\.heading), ["INT. LAB - DAY", "INT. CAR - LATER"])
    }

    func testEverySpeechIsKeptInOrderUnderItsScene() {
        let appearances = EditorState(source: source).appearances(of: "MARA")
        XCTAssertEqual(appearances[0].lines.map(\.text), ["First.", "Second."])
        XCTAssertEqual(appearances[1].lines.map(\.text), ["Third."])
    }

    /// A direction belongs to the speech it introduces, and to no other.
    func testAParentheticalAttachesToTheLineBeneathIt() {
        let lines = EditorState(source: source).appearances(of: "MARA")[0].lines
        XCTAssertEqual(lines[0].parenthetical, "(quietly)")
        XCTAssertNil(lines[1].parenthetical, "the direction does not carry on to the next line")
    }

    func testAnotherCharactersLinesAreNeverIncluded() {
        let spoken = EditorState(source: source)
            .appearances(of: "MARA")
            .flatMap(\.lines)
            .map(\.text)
        XCTAssertFalse(spoken.contains("Not me."))
        XCTAssertFalse(spoken.contains("Alone here."))
    }

    /// Every row navigates, so every id has to resolve.
    func testEveryRowPointsAtARealElement() {
        let editor = EditorState(source: source)
        let ids = Set(editor.screenplay.elements.map(\.id))
        for appearance in editor.appearances(of: "MARA") {
            XCTAssertTrue(ids.contains(appearance.id), "scene \(appearance.heading)")
            for line in appearance.lines {
                XCTAssertTrue(ids.contains(line.id), "line \(line.text)")
            }
        }
    }

    /// The scene's own address when the script carries one; its position when
    /// it does not.
    func testTheSceneLabelPrefersTheProductionNumber() {
        let numbered = EditorState(source: [
            "INT. LAB - DAY #7#", "", "MARA", "First."
        ].joined(separator: "\n"))
        XCTAssertEqual(numbered.appearances(of: "MARA").map(\.label), ["7"])
        XCTAssertEqual(EditorState(source: source).appearances(of: "MARA").map(\.label), ["1", "3"])
    }

    func testACharacterWhoNeverSpeaksHasNoThread() {
        let editor = EditorState(source: ["INT. LAB - DAY", "", "MARA", "", "She waits."]
            .joined(separator: "\n"))
        XCTAssertTrue(editor.appearances(of: "MARA").isEmpty)
    }
}
