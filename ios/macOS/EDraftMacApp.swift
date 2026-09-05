import EDraftCore
import EDraftMacSurface
import EDraftUI
import SwiftUI

/// eDraft on the Mac.
///
/// Deliberately almost nothing. The document is `EDraftDocument` from EDraftUI
/// — the same one the phone opens, so a script started on an iPhone opens here
/// with no conversion and no second format. The window is `ScriptWindow` from
/// EDraftMacSurface, and everything it does is under test there.
///
/// What belongs in this file is what only an app can own: the scene, the menu
/// bar, and the bridge between a document's text and the editor's model.
@main
struct EDraftMacApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: EDraftDocument()) { file in
            ScriptDocumentWindow(document: file.$document)
        }
        .commands {
            // Accepting a completion is an editing action, not a formatting
            // one — it belongs in Edit, after Paste, with the key equivalent
            // a writer already reaches for on the phone (⌘→).
            CommandGroup(after: .pasteboard) {
                AcceptSuggestionCommand()
            }
            // The nine element commands currently land in Edit too, because
            // `.textEditing` is an Edit-menu anchor. The design puts them in
            // Format (MACOS-DESIGN §3.4). That is a separate correction —
            // do not fold it into the ghost.
            CommandGroup(after: .textEditing) {
                Divider()
                ElementCommands()
            }
        }
    }
}

/// One document, bound to one editor.
///
/// The model is created from the document's text and writes back to it on every
/// change — the same arrangement the phone uses, for the same reason: the
/// document is the file, the editor is what a writer is doing to it, and only
/// one of those belongs in a `@Binding`.
struct ScriptDocumentWindow: View {
    @Binding private var document: EDraftDocument
    @State private var editor: EditorState

    init(document: Binding<EDraftDocument>) {
        _document = document
        _editor = State(initialValue: EditorState(source: document.wrappedValue.source))
    }

    var body: some View {
        ScriptWindow(editor: editor)
            .focusedSceneValue(\.editor, editor)
            .onAppear {
                editor.onSourceChange = { source in document.source = source }
            }
    }
}

/// Edit → Accept Suggestion, with ⌘→.
///
/// Routed through the model's own `acceptPrediction()` so the surface that
/// is bound to the frontmost window does the apply — casing, `becomes`,
/// and undo grouping all come along. A hint is not acceptable.
struct AcceptSuggestionCommand: View {
    @FocusedValue(\.editor) private var editor

    var body: some View {
        Button("Accept Suggestion") {
            editor?.acceptPrediction()
        }
        .keyboardShortcut(.rightArrow, modifiers: .command)
        .disabled(!canAccept)
    }

    private var canAccept: Bool {
        guard let editor,
              editor.currentPrediction?.hint != true,
              let suffix = editor.currentSuggestionSuffix,
              !suffix.isEmpty else { return false }
        return true
    }
}

/// Format → Element, with ⌘1–⌘9.
///
/// The conversion channel is the model's, the same one the phone's element
/// control and its ⌘1–9 already use — so casing memory, bracket handling and
/// undo grouping come along without being re-implemented for a menu.
struct ElementCommands: View {
    @FocusedValue(\.editor) private var editor

    /// The kinds a writer converts between, in the order the keys number them.
    private static let kinds: [(ScreenplayKind, KeyEquivalent)] = [
        (.scene, "1"), (.action, "2"), (.character, "3"), (.parenthetical, "4"),
        (.dialogue, "5"), (.transition, "6"), (.shot, "7"), (.general, "8"), (.lyrics, "9")
    ]

    var body: some View {
        ForEach(Self.kinds, id: \.0) { kind, key in
            Button(kind.title) {
                editor?.onChangeElementKind?(kind)
            }
            .keyboardShortcut(key, modifiers: .command)
            .disabled(editor == nil)
        }
    }
}

/// The editor of the frontmost window, so the menu bar can act on it.
struct EditorFocusKey: FocusedValueKey {
    typealias Value = EditorState
}

extension FocusedValues {
    var editor: EditorState? {
        get { self[EditorFocusKey.self] }
        set { self[EditorFocusKey.self] = newValue }
    }
}
