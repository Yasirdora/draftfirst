import AppKit
import EDraftCore
import EDraftMacSurface
import EDraftUI
import SwiftUI
import UniformTypeIdentifiers

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
                Divider()
                FindCommands()
            }
            // The nine element commands currently land in Edit too, because
            // `.textEditing` is an Edit-menu anchor. The design puts them in
            // Format (MACOS-DESIGN §3.4). That is a separate correction —
            // do not fold it into export.
            CommandGroup(after: .textEditing) {
                Divider()
                ElementCommands()
            }
            CommandGroup(after: .saveItem) {
                ExportCommands()
            }
            CommandGroup(replacing: .printItem) {
                PrintCommand()
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

/// Edit → Find, Find Next/Previous, Find Scene.
///
/// Find is the system bar, Replace omitted: `NSTextView.replaceCharacters`
/// does not go through the planner (see `TextFinderMeasurementTests`).
/// Find Scene is go-to-scene, not a second text search.
struct FindCommands: View {
    @FocusedValue(\.editor) private var editor

    var body: some View {
        Button("Find…") {
            editor?.onShowFind?()
        }
        .keyboardShortcut("f", modifiers: .command)
        .disabled(editor == nil)

        Button("Find Next") {
            editor?.onFindNext?()
        }
        .keyboardShortcut("g", modifiers: .command)
        .disabled(editor == nil)

        Button("Find Previous") {
            editor?.onFindPrevious?()
        }
        .keyboardShortcut("g", modifiers: [.command, .shift])
        .disabled(editor == nil)

        Divider()

        Button("Find Scene") {
            editor?.onFindScene?()
        }
        .keyboardShortcut("l", modifiers: .command)
        .disabled(editor == nil)
    }
}

/// File → Export: PDF · FDX · Fountain · Text. Print is the exported PDF.
struct ExportCommands: View {
    @FocusedValue(\.editor) private var editor

    var body: some View {
        Menu("Export") {
            Button("PDF…") { export(ext: "pdf", type: .pdf, contents: pdf()) }
            Button("Final Draft…") { export(ext: "fdx", type: .finalDraftScreenplay, contents: fdx()) }
            Button("Fountain…") { export(ext: "fountain", type: .plainText, contents: fountain()) }
            Button("Text…") { export(ext: "txt", type: .plainText, contents: text()) }
        }
        .disabled(editor == nil)
    }

    private func pdf() -> Data {
        ScreenplayPageRenderer.pdfData(screenplay)
    }

    private func fdx() -> Data {
        Data(ScreenplayExporter.fdxSource(screenplay).utf8)
    }

    private func fountain() -> Data {
        Data(ScreenplayExporter.fountainSource(screenplay).utf8)
    }

    private func text() -> Data {
        Data(ScreenplayExporter.plainText(screenplay).utf8)
    }

    private var screenplay: EDraftCore.Screenplay {
        editor?.screenplay ?? EDraftCore.Screenplay()
    }

    private func export(ext: String, type: UTType, contents: Data) {
        guard editor != nil else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        let base = screenplay.title.isEmpty ? "Screenplay" : screenplay.title
        panel.nameFieldStringValue = "\(base).\(ext)"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? contents.write(to: url, options: .atomic)
        }
    }
}

struct PrintCommand: View {
    @FocusedValue(\.editor) private var editor

    var body: some View {
        Button("Print…") {
            guard let editor else { return }
            ScreenplayPageRenderer.runPrint(editor.screenplay)
        }
        .keyboardShortcut("p", modifiers: .command)
        .disabled(editor == nil)
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
