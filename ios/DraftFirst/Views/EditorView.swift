import SwiftUI

struct EditorView: View {
    @Binding private var document: DraftFirstDocument
    @State private var editor: EditorState
    @State private var presentedPanel: EditorPanel?
    /// iOS silently drops a sheet requested while another sheet is still
    /// animating its dismissal — the "button reacts but nothing happens"
    /// report. Presents are gated until `onDismiss` confirms the way is clear.
    @State private var panelFullyDismissed = true
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
            // The page extends under the transparent navigation bar, so
            // scrolling lines pass beneath the platform's glass the way
            // they do in Apple's own apps; the bar's safe-area inset keeps
            // the resting first line clear of it.
            ScriptTextView(editor: editor)
                .ignoresSafeArea(.container, edges: .top)
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
        // transparent glass — with our UIKit controls placed per slot (see
        // EditorChrome). The leading close button is the system's own:
        // DocumentGroup installs a custom leading item that
        // navigationBarBackButtonHidden cannot retire, and a second chevron
        // beside it reads as a bug. The flush our button used to guarantee
        // happens in onDisappear instead, so no keystroke is lost on the
        // way out, whichever path closes the document.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                ElementToolbarControl(chrome: chrome)
            }
            // Two separate trailing items, never one merged capsule: iOS 26
            // fuses adjacent trailing controls into a single glass cluster,
            // and a fixed spacer is the system's own seam between them.
            ToolbarItem(placement: .topBarTrailing) {
                UndoToolbarControl(chrome: chrome)
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                SettingsToolbarControl(chrome: chrome)
            }
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
        .onDisappear {
            // The close button belongs to the system, so disappearance is
            // the last guaranteed moment to land debounced work — keyboard
            // dismissal, backgrounding, and close all pass through here.
            editor.flushPendingWork()
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
            canRedo: editor.canRedo
        )
    }

    private func wire(_ editor: EditorState) {
        editor.onSourceChange = { source in
            document.source = source
        }
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
