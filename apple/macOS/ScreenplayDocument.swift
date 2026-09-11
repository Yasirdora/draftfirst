import AppKit
import EDraftCore
import EDraftMacSurface
import UniformTypeIdentifiers

/// A screenplay on disk, as AppKit's document architecture sees one.
///
/// Every decision about what may be read, what is written back and how bytes
/// become a screenplay belongs to `ScreenplayFile` in the core, where both
/// surfaces and the tests can reach it — this is the same file the phone's
/// `EDraftDocument` opens, so a script started on an iPhone opens here with no
/// conversion and no second format. What is left here is the conformance
/// itself: open, save, autosave, Duplicate, Rename, Revert, Versions and
/// window tabs, all of which `NSDocument` has done correctly for decades.
///
/// The model is created from the file's text and writes back to it on every
/// change: the document is the file, the editor is what a writer is doing to
/// it. The window is `ScriptWindowController`, from the surface package, and
/// everything it does is under test there.
@objc(ScreenplayDocument)
final class ScreenplayDocument: NSDocument {

    private(set) var editor: EditorState
    private var source: String

    /// The Final Draft file this document was opened from, when it was one.
    ///
    /// Carried so a save can edit it rather than rebuild it: a screenplay
    /// cannot hold revisions, locked pages, tags or the arc beats nested in a
    /// scene heading, and a writer who opens a locked shooting script, fixes a
    /// typo and saves must not lose them. See `ScreenplayFile.open`.
    private var origin: String?

    override init() {
        source = ScreenplayFile.blankSource
        editor = EditorState(source: source)
        super.init()
        bind(editor)
    }

    /// Versions, Duplicate, Rename and Move To all follow from this, and so
    /// does never losing an hour of work to a crash.
    override nonisolated class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        let controller = ScriptWindowController(editor: editor)
        controller.onBack = { [weak controller] in
            MacAppDelegate.shared.showLaunchWindow(replacing: controller?.window)
        }
        addWindowController(controller)
    }

    /// Declared nonisolated by AppKit; called on the main thread all the same,
    /// because this document does not opt into concurrent reading.
    override nonisolated func read(from data: Data, ofType typeName: String) throws {
        try MainActor.assumeIsolated {
            let opened = try ScreenplayFile.open(data, as: Self.contentType(typeName))
            source = opened.source
            origin = opened.origin
            if windowControllers.isEmpty {
                editor = EditorState(source: source)
                bind(editor)
            } else {
                // Revert To: the window stays, the text under it changes.
                editor.applyExternalSource(source)
            }
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        try ScreenplayFile.encode(source, as: Self.contentType(typeName), origin: origin)
    }

    /// Print is the exported PDF, so what leaves the printer is what leaves
    /// the app.
    override func printDocument(_ sender: Any?) {
        ScreenplayPageRenderer.runPrint(editor.screenplay)
    }

    private func bind(_ editor: EditorState) {
        editor.onSourceChange = { [weak self] source in
            guard let self else { return }
            self.source = source
            // The surface owns the text view's undo manager, so the document
            // cannot infer edits from its own; it is told instead. Told on
            // the clean-to-dirty transition only: every call re-syncs the
            // window's title, and on this platform a title re-sync replays
            // the toolbar's glass — an already-dirty document gains nothing
            // from hearing it again. Saving and Revert clear the count, as
            // they always did.
            guard !isDocumentEdited else { return }
            updateChangeCount(.changeDone)
        }
        // The surface offers the formats; writing the file is the app's,
        // because a save panel is not something a page knows about. Both the
        // toolbar menu and File → Export come here.
        editor.onExport = { [weak self] format in
            guard let self else { return }
            ScreenplayExportWriter.write(format, editor.screenplay, from: windowForSheet)
        }
    }

    private static func contentType(_ typeName: String) -> UTType {
        UTType(typeName) ?? .plainText
    }
}

/// Writes a screenplay to a file the writer chooses.
///
/// The formats are `ScreenplayExportFormat`, so the toolbar menu and File →
/// Export cannot drift apart; this is only the part that knows what a save
/// panel is, which is why it lives in the app and not in the surface.
enum ScreenplayExportWriter {

    static func write(
        _ format: ScreenplayExportFormat,
        _ screenplay: EDraftCore.Screenplay,
        from window: NSWindow?
    ) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [contentType(for: format)]
        panel.canCreateDirectories = true
        let base = screenplay.title.isEmpty ? "Screenplay" : screenplay.title
        panel.nameFieldStringValue = "\(base).\(format.fileExtension)"
        let contents = data(for: format, screenplay)
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            try? contents.write(to: url, options: .atomic)
        }
        // A sheet on the document, the way every document app on the
        // platform exports; free-floating only when there is nothing to
        // attach it to.
        if let window {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    private static func data(
        for format: ScreenplayExportFormat, _ screenplay: EDraftCore.Screenplay
    ) -> Data {
        switch format {
        case .pdf: ScreenplayPageRenderer.pdfData(screenplay)
        case .finalDraft: Data(ScreenplayExporter.fdxSource(screenplay).utf8)
        case .fountain: Data(ScreenplayExporter.fountainSource(screenplay).utf8)
        case .text: Data(ScreenplayExporter.plainText(screenplay).utf8)
        }
    }

    private static func contentType(for format: ScreenplayExportFormat) -> UTType {
        switch format {
        case .pdf: .pdf
        case .finalDraft: .finalDraftScreenplay
        case .fountain, .text: .plainText
        }
    }
}
