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
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

    var body: some Scene {
        // Declared before the DocumentGroup so a launch with nothing open
        // greets the writer instead of presenting a file dialog. The phone
        // uses `DocumentGroupLaunchScene` for this; that API is
        // `@available(macOS, unavailable)`, so the Mac draws its own window
        // on the same ground. See `LaunchIdentity`.
        Window("eDraft", id: MacAppDelegate.launchWindowID) {
            LaunchWindowHost()
        }
        .defaultSize(width: 660, height: 460)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        // No title bar. The window's name is the first thing written on it,
        // and a chrome strip repeating it above the word "eDraft" is a second
        // title. Xcode's welcome window and Pages' chooser do the same.
        .windowStyle(.hiddenTitleBar)

        DocumentGroup(newDocument: EDraftDocument()) { file in
            ScriptDocumentWindow(document: file.$document)
        }
        // Wide enough to hold a page at a size a person can read.
        //
        // The system default is 900 points, and a 240-point Navigator leaves
        // 660 for a 612-point page plus its margins — so the page fits at
        // exactly its own metrics and no larger, which on this class of
        // display is under half life size. Fitting the page to the window
        // then has nothing to work with. 1280 leaves 1040, which draws the
        // page at about 1.5×; the writer can still make the window smaller,
        // and the page scrolls rather than shrinking when they do.
        .defaultSize(width: 1280, height: 860)
        .defaultPosition(.center)
        // One row of chrome, not two.
        //
        // A `DocumentGroup` defaults to the expanded toolbar style, which is
        // the old Mac document window: a title row, and a separate toolbar
        // row beneath it. Two rows is 30 points of header before the page
        // starts, and this window puts nothing in the title row — the name
        // is `.toolbar(removing: .title)`'d away, because the leading edge
        // belongs to the element under the caret. So the first row was
        // empty height. Pages, Numbers and Keynote are all unified.
        .windowToolbarStyle(.unified)
        .commands {
            // Accepting a completion is an editing action, not a formatting
            // one — it belongs in Edit, after Paste, with the key equivalent
            // a writer already reaches for on the phone (⌘→).
            CommandGroup(after: .pasteboard) {
                AcceptSuggestionCommand()
                Divider()
                FindCommands()
            }
            CommandGroup(after: .sidebar) {
                ZoomCommands()
                Divider()
                PagePaperCommand()
            }
            CommandGroup(after: .textFormatting) {
                ElementCommands()
                Divider()
                SceneNumbersCommands()
            }
            CommandGroup(after: .saveItem) {
                TitlePageCommand()
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

/// View → what the page is made of.
///
/// Only meaningful in dark mode, where it decides whether the script darkens
/// with the app or stays paper. It is offered in both, because a writer who
/// sets it in daylight should still find it set at night, and a control that
/// disappears is harder to find than one that is simply not doing anything
/// yet.
struct PagePaperCommand: View {
    @State private var paper = PagePaper.stored

    var body: some View {
        Picker("Page", selection: $paper) {
            ForEach(PagePaper.allCases, id: \.self) { choice in
                Text(choice.title).tag(choice)
            }
        }
        .pickerStyle(.inline)
        .onChange(of: paper) { _, choice in
            // The surfaces are watching `UserDefaults`; writing it is the
            // whole of the command. Every open window restyles, which is what
            // a document-wide appearance choice should do.
            PagePaper.store(choice)
        }
    }
}

/// View → how large the page is drawn.
///
/// A screenplay's measurements are absolute: 612 points is 8½ inches, because
/// a typographic point is 1/72 of one. A *screen* point is not — on a 13.6-inch
/// laptop it measures about 0.0067 inches, so a page drawn at its own metrics
/// comes out under half life size and 12-point Courier reads as under six. The
/// metrics are right and the page still looks wrong, which is a display
/// question rather than a document one.
///
/// A document opens at its own metrics and these are how a writer asks for
/// something else. ⌘0 resets to 100%, which is both the default and what
/// Preview binds it to.
struct ZoomCommands: View {
    @FocusedValue(\.editor) private var editor

    var body: some View {
        Button("Zoom In") { editor?.onZoom?(.zoomIn) }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(!isAvailable(.zoomIn))

        Button("Zoom Out") { editor?.onZoom?(.zoomOut) }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(!isAvailable(.zoomOut))

        // ⌘0 is "put it back", and a document opens at its own metrics, so
        // back is 100% — the same binding Preview uses, for the same reason.
        Button("Actual Size") { editor?.onZoom?(.actualSize) }
            .keyboardShortcut("0", modifiers: .command)
            .disabled(!isAvailable(.actualSize))

        Button("Zoom to Fit") { editor?.onZoom?(.fit) }
            .keyboardShortcut("9", modifiers: .command)
            .disabled(editor == nil)
    }

    /// Grey rather than silent: a command that would change nothing should say
    /// so before it is chosen.
    private func isAvailable(_ command: PageZoom.Command) -> Bool {
        guard let editor else { return false }
        return PageZoom.isAvailable(command, at: editor.zoom)
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

/// Format → Scene Numbers. A verb, so it does not live in the sidebar
/// (`MACOS-DESIGN` §1.1). The same three operations the phone's numbering
/// page offers; Number All and Remove confirm, because they change
/// addresses a schedule may already cite.
struct SceneNumbersCommands: View {
    @FocusedValue(\.editor) private var editor

    var body: some View {
        Menu("Scene Numbers") {
            Button("Number New Scenes") {
                _ = editor?.applySceneNumbering(.newScenesOnly)
            }
            .disabled(editor == nil)

            Button("Number All Scenes") {
                confirm(
                    title: "Renumber Every Scene?",
                    body: "Every scene is numbered again from 1. Any number already in use changes, including ones a schedule or call sheet may already cite.",
                    action: "Renumber"
                ) {
                    _ = editor?.applySceneNumbering(.all)
                }
            }
            .disabled(editor == nil)

            Button("Remove Scene Numbers") {
                confirm(
                    title: "Remove Every Scene Number?",
                    body: "The script keeps its scenes; it loses the numbers people cite them by.",
                    action: "Remove"
                ) {
                    _ = editor?.applySceneNumbering(.clear)
                }
            }
            .disabled(!(editor?.isSceneNumbered ?? false))
        }
    }

    private func confirm(title: String, body: String, action: String, run: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            run()
        }
    }
}

/// File → Title Page…. The same sheet the phone presents — not a second form.
struct TitlePageCommand: View {
    @FocusedValue(\.onShowTitlePage) private var show

    var body: some View {
        Button("Title Page…") {
            show?()
        }
        .disabled(show == nil)
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

/// What only the application object can answer.
///
/// A document app launches into one of two things: a file dialog, or a new
/// untitled document. Neither is a greeting, and neither says what this app is.
/// Refusing the untitled file leaves the launch window as the thing a writer
/// meets — the same choice the phone makes with `DocumentGroupLaunchScene`.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    static let launchWindowID = "launch"

    /// No untitled document at launch. A writer who wants one presses ⌘N,
    /// which the launch window puts in front of them.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    /// Reopening from the Dock with nothing on screen means the same thing as
    /// launching: show the window that says what this is.
    ///
    /// Returning `flag` here was a bug — with no visible windows it answers
    /// "I handled it" and then handles nothing, leaving a running app with no
    /// window and no way back except the Window menu.
    func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows flag: Bool
    ) -> Bool {
        if flag { return true }
        LaunchWindowOpener.shared.open?()
        return false
    }
}

/// The one thing a `Window` scene cannot do for itself: come back.
///
/// `openWindow` is a SwiftUI environment action, readable only from inside a
/// view, and the application delegate is not one. So the action is captured
/// while a view exists and held here for the moment there are no views left —
/// which is exactly the moment it is needed.
@MainActor
final class LaunchWindowOpener {
    static let shared = LaunchWindowOpener()
    var open: (() -> Void)?
    private init() {}
}

/// The launch window's contents, with the app's own doors wired to it.
///
/// `LaunchWindow` is in `EDraftMacSurface` and knows nothing about documents;
/// opening one is the app's job, and `newDocument`/`openDocument` are the
/// SwiftUI actions for it. Recents come from `NSDocumentController`, which has
/// kept that list correctly for thirty years — there is no reason to keep a
/// second one.
struct LaunchWindowHost: View {
    @Environment(\.newDocument) private var newDocument
    @Environment(\.openDocument) private var openDocument
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openWindow) private var openWindow

    @State private var recents: [RecentScript] = []

    var body: some View {
        LaunchWindow(
            recents: recents,
            onNew: {
                newDocument(EDraftDocument())
                close()
            },
            onOpen: { openViaPanel() },
            onPick: { url in open(url) }
        )
        .onAppear {
            refresh()
            LaunchWindowOpener.shared.open = { openWindow(id: MacAppDelegate.launchWindowID) }
        }
        // The list is stale the moment a document is saved under a new name,
        // so it is re-read whenever this window comes back to the front.
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in refresh() }
    }

    private func refresh() {
        recents = LaunchModel.rows(from: NSDocumentController.shared.recentDocumentURLs)
    }

    private func close() {
        dismissWindow(id: MacAppDelegate.launchWindowID)
    }

    private func open(_ url: URL) {
        Task {
            // A recent that has gone since the list was read is the writer's
            // answer, not a crash: leave the window up and drop the row.
            do {
                try await openDocument(at: url)
                close()
            } catch {
                refresh()
            }
        }
    }

    /// A sheet on the launch window rather than an application-modal panel.
    ///
    /// `runModal()` blocks the main run loop and floats the panel free of any
    /// window; `beginSheetModal(for:)` attaches it to the window the writer
    /// clicked, which is what every document app on the platform does.
    private func openViaPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.edraftScreenplay, .plainText, .finalDraftScreenplay]
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"

        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else {
            // No window to hang it on is not a reason to refuse the writer.
            if panel.runModal() == .OK, let url = panel.url { open(url) }
            return
        }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            open(url)
        }
    }
}
