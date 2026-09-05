import EDraftCore
import EDraftUI
import SwiftUI
import UIKit

struct EditorView: View {
    @Binding private var document: EDraftDocument
    /// The open document's file URL, from its document configuration —
    /// lets the editor detect that its file was deleted in Documents
    /// while this scene was away (see closeIfDocumentDeleted).
    private let fileURL: URL?
    @State private var editor: EditorState
    @State private var presentedPanel: EditorPanel?
    /// iOS silently drops a sheet requested while another sheet is still
    /// animating its dismissal — the "button reacts but nothing happens"
    /// report. Presents are gated until `onDismiss` confirms the way is clear.
    @State private var panelFullyDismissed = true
    /// Set when the file was deleted in Documents while this scene was
    /// suspended: the editor must close WITHOUT saving, or the next
    /// autosave recreates the deleted file.
    @State private var documentDeletedFromDisk = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    /// Closes the document back to the launch scene — used when the file
    /// was deleted in Documents while this scene was away.
    @Environment(\.dismiss) private var dismissEditor
    // The scheme itself is applied at scene level in EDraftApp (browser
    // and editor can never disagree); this binding is the menu's write path.
    @AppStorage(AppearancePreference.storageKey)
    private var appearance: AppearancePreference = .default

    init(document: Binding<EDraftDocument>, fileURL: URL? = nil, startsAtEnd: Bool = false) {
        _document = document
        self.fileURL = fileURL
        _editor = State(initialValue: EditorState(
            source: document.wrappedValue.source,
            startsAtEnd: startsAtEnd
        ))
    }

    var body: some View {
        ZStack {
            Color.screenplayPaper.ignoresSafeArea()
            // The page extends under the transparent navigation bar, so
            // scrolling lines pass beneath the platform's glass the way
            // they do in Apple's own apps; the bar's safe-area inset keeps
            // the resting first line clear of it.
            ScriptTextView(editor: editor)
                .ignoresSafeArea(.container, edges: .top)
            // Zero-size anchor: applies our controls to the system
            // navigation bar as genuine UIBarButtonItems + a title view.
            EditorBarConfigurator(chrome: chrome)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        // Transient, non-modal notices — sync arrivals — one capsule just
        // under the navigation bar.
        .overlay(alignment: .top) {
            if let banner = editor.banner {
                Text(banner)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: editor.banner)
        // The header is the real navigation bar — the platform's own
        // transparent glass. Beyond the system's close button, everything
        // in it is configured on the navigation item directly (see
        // EditorChrome): genuine bar items with the system's own single
        // glass treatment, not a second layer of ours.
        .navigationBarTitleDisplayMode(.inline)
        // Declares this view the document editor (Pages' idiom) rather than
        // DocumentGroup's default browser role.
        .toolbarRole(.editor)
        .sheet(item: $presentedPanel, onDismiss: { panelFullyDismissed = true }) { panel in
            switch panel {
            case .story:
                StoryPanel(editor: editor, initialTab: Self.qaStoryInitialTab)
                    .presentationDetents(panelDetents)
                    .presentationDragIndicator(.visible)
            case .titlePage:
                TitlePageSheet(editor: editor)
                    .presentationDetents(panelDetents)
                    .presentationDragIndicator(.visible)
            case .settings:
                SettingsPanel(editor: editor)
                    .presentationDetents(panelDetents)
                    .presentationDragIndicator(.visible)
            }
        }
        .onAppear {
            // If a sheet was ever torn down without its onDismiss (scene
            // teardown reusing this view's state), the gate would stay
            // wedged shut and every panel button would look dead. Re-entering
            // the editor is proof no sheet is up — re-arm the gate.
            panelFullyDismissed = true
            // A screenplay the writer has only now created opens ready to
            // write; every other one opens to be read. See
            // EDraftDocument.isNewlyCreated.
            // A screenplay the writer has only now created opens ready to
            // write; every other one opens to be read. See
            // EDraftDocument.claimNewlyCreated.
            // A screenplay the writer has only now made opens ready to
            // write; every other one opens to be read. See DocumentArrival.
            if DocumentArrival.isNewlyCreated(at: fileURL) { editor.beginEditing() }
            // A scene restored after the file was deleted in Documents must
            // not live on: close it before any save can resurrect the file.
            closeIfDocumentDeleted()
            wire(editor)
#if EDITOR_PREVIEW
            if CommandLine.arguments.contains("-show-settings") {
                present(.settings)
            } else if CommandLine.arguments.contains("-show-story")
                        || CommandLine.arguments.contains("-show-story-cast") {
                present(.story)
            } else if CommandLine.arguments.contains("-show-titlepage") {
                present(.titlePage)
            }
#endif
        }
        .onDisappear {
            // Leaving the document ends the edit. Without this the surface
            // resigns focus somewhere inside its own teardown — after the
            // transition has begun — and the bar spends the pop still
            // dressed for writing, then dresses again on the way back.
            editor.endEditing()
            // The close button belongs to the system, so disappearance is
            // the last guaranteed moment to land debounced work — keyboard
            // dismissal, backgrounding, and close all pass through here.
            // A deleted document is the one exception: saving it back would
            // resurrect the file the writer just removed.
            if !documentDeletedFromDisk { editor.flushPendingWork() }
        }
        .onChange(of: document.source) { _, newSource in
            // A genuinely external change (conflict resolution, another
            // device) is applied in place: caret, scroll, and both undo
            // timelines survive. The echo of our own publish never does
            // this, and neither does an unchanged redelivery at launch —
            // that is what lastKnownSource is for.
            guard newSource != editor.lastKnownSource else { return }
            editor.applyExternalSource(newSource)
        }
        .onChange(of: scenePhase) { _, phase in
            // Backgrounding mid-keystroke must not strand the debounced
            // publish: flush so the document binding is always current.
            // Becoming active again is where a deleted document is caught.
            if phase == .active {
                closeIfDocumentDeleted()
            } else if !documentDeletedFromDisk {
                editor.flushPendingWork()
            }
        }
    }

    private func present(_ panel: EditorPanel) {
        guard panelFullyDismissed, presentedPanel == nil else { return }
        panelFullyDismissed = false
        presentedPanel = panel
    }

    /// QA-only tab selection for Navigator screenshots; production always
    /// opens on Scenes.
    private static var qaStoryInitialTab: StoryPanel.Tab {
#if EDITOR_PREVIEW
        if CommandLine.arguments.contains("-show-story-cast") { return .cast }
#endif
        return .scenes
    }

    /// The toolbar controls' shared input. Built in body so every tracked
    /// read (active kind, undo availability, …) invalidates the controls
    /// through SwiftUI's normal update pass.
    private var chrome: EditorChrome {
        EditorChrome(
            editor: editor,
            showStory: { present(.story) },
            showTitlePage: { present(.titlePage) },
            showSettings: { present(.settings) },
            setAppearance: { appearance = $0 },
            activeKind: editor.activeKind,
            contextualKinds: editor.contextualKinds,
            canUndo: editor.canUndo,
            canRedo: editor.canRedo,
            isEditing: editor.isEditing
        )
    }

    private func wire(_ editor: EditorState) {
        editor.onSourceChange = { source in
            document.source = source
        }
    }

    /// The document can be deleted in Documents while this scene is
    /// suspended or restorable. Returning to an editor whose file is gone
    /// must close it immediately and never save again — otherwise the next
    /// autosave recreates the deleted file.
    private func closeIfDocumentDeleted() {
        guard let fileURL,
              !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        documentDeletedFromDisk = true
        dismissEditor()
    }

    private var panelDetents: Set<PresentationDetent> {
        dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]
    }
}

/// How the app picks its appearance. Following the device is the default and
/// the first option, as the HIG expects: a writer whose phone turns dark at
/// sunset should not have to tell us twice. Light and Dark stay available for
/// writers who want the page to hold still regardless of the hour.
enum AppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    /// What an unset or unrecognised preference means. Writers who never
    /// opened the menu follow their device; an explicit choice is stored and
    /// therefore survives this fallback.
    static let `default`: AppearancePreference = .system

    static let storageKey = "appearance"

    /// The stored preference, or the default when nothing valid is stored.
    /// One reader for every call site, so the fallback can never drift.
    static var stored: AppearancePreference {
        AppearancePreference(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "")
            ?? .default
    }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    /// `.unspecified` is how a window is told to follow the device — the
    /// whole point of the System option.
    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

private enum EditorPanel: String, Identifiable {
    case story
    case titlePage
    case settings

    var id: String { rawValue }
}
