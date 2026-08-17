import SwiftUI

struct EditorView: View {
    @Binding private var document: DraftFirstDocument
    @State private var editor: EditorState
    @State private var presentedPanel: EditorPanel?
    /// iOS silently drops a sheet requested while another sheet is still
    /// animating its dismissal — the "button reacts but nothing happens"
    /// report. Presents are gated until `onDismiss` confirms the way is clear.
    @State private var panelFullyDismissed = true
    @Environment(\.dismiss) private var dismissEditor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    // The scheme itself is applied at scene level in DraftFirstApp (browser
    // and editor can never disagree); this binding is the menu's write path.
    @AppStorage("appearance") private var appearance: AppearancePreference = .dark

    init(document: Binding<DraftFirstDocument>, startsAtEnd: Bool = false) {
        _document = document
        _editor = State(initialValue: EditorState(
            source: document.wrappedValue.source,
            startsAtEnd: startsAtEnd
        ))
    }

    var body: some View {
        ZStack {
            Color.screenplayPaper.ignoresSafeArea()
            ScriptTextView(editor: editor)
        }
        // Transient, non-modal notices — element toasts on swipe, sync
        // arrivals — one capsule just under the chrome row.
        .overlay(alignment: .top) {
            if let banner = editor.banner {
                Text(banner)
                    .font(.footnote.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 56)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.18), value: editor.banner)
        // DocumentGroupLaunchScene retires the system document chrome; keep
        // the navigation bar hidden so no system back button or title can
        // reappear. The chrome row below is UIKit-hosted (see EditorChrome):
        // its menus present through the system window-level path, so they
        // morph from their source and capture input while open.
        .toolbarVisibility(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            EditorChrome(
                editor: editor,
                closeDocument: closeDocument,
                showStory: { present(.story) },
                showTitlePage: { present(.titlePage) },
                showSettings: { present(.settings) },
                setAppearance: { appearance = $0 },
                activeKind: editor.activeKind,
                contextualKinds: editor.contextualKinds,
                canUndo: editor.canUndo,
                canRedo: editor.canRedo
            )
            .padding(.horizontal, 16)
        }
        .sheet(item: $presentedPanel, onDismiss: { panelFullyDismissed = true }) { panel in
            switch panel {
            case .story:
                StoryPanel(editor: editor)
                    .presentationDetents(panelDetents)
                    .presentationDragIndicator(.visible)
            case .titlePage:
                TitlePageSettings(editor: editor)
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
            wire(editor)
#if EDITOR_PREVIEW
            if CommandLine.arguments.contains("-show-settings") {
                present(.settings)
            } else if CommandLine.arguments.contains("-show-story") {
                present(.story)
            }
#endif
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
            if phase != .active { editor.flushPendingWork() }
        }
    }

    private func present(_ panel: EditorPanel) {
        guard panelFullyDismissed, presentedPanel == nil else { return }
        panelFullyDismissed = false
        presentedPanel = panel
    }

    private func wire(_ editor: EditorState) {
        editor.onSourceChange = { source in
            document.source = source
        }
    }

    private func closeDocument() {
        editor.flushPendingWork()
        dismissEditor()
    }

    private var panelDetents: Set<PresentationDetent> {
        dynamicTypeSize.isAccessibilitySize ? [.large] : [.medium, .large]
    }
}

enum AppearancePreference: String, CaseIterable, Identifiable {
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
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
