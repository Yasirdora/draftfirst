import EDraftCore
import EDraftUI
import SwiftUI

/// One screenplay, in one window.
///
/// The structure on the left, the page in the middle. A properties column
/// on the right is reserved for comments and notes — something to read
/// *alongside* the page. Title page, scene facts and a character rename
/// are transient, and a transient thing is a sheet or a destination in
/// the sidebar, not a pane.
///
/// The sidebar is `StoryList`, the same Navigator the phone shows in a sheet.
/// It is visible by default, because on a Mac the sidebar *is* the organisation
/// panel and a window that opens without one reads as a ported iPad app.
/// Distraction-free writing is a mode, not a default.
public struct ScriptWindow: View {
    private let editor: EditorState

    @State private var tab: StoryPanel.Tab = .scenes
    @State private var columns: NavigationSplitViewVisibility = .all
    @State private var sceneQuery = ""
    @State private var focusSceneFilter = 0
    @State private var showingTitlePage = false

    public init(editor: EditorState) {
        self.editor = editor
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            NavigationStack {
                StoryList(
                    editor: editor,
                    tab: $tab,
                    showsSceneFilter: true,
                    showsSceneNumbering: false,
                    sceneQuery: $sceneQuery,
                    focusSceneFilter: focusSceneFilter,
                    onFilterSubmit: { id in
                        editor.jump(to: id)
                        editor.beginEditing()
                    }
                ) { element in
                    // The sidebar stays where it is: a Mac reader keeps their
                    // place in the list while the page moves beside it, which is
                    // exactly what a sidebar is for. The character thread uses
                    // this same `open` — a speech reveals the line, the thread
                    // remains.
                    editor.jump(to: element)
                }
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 360)
        } detail: {
            ScriptPageView(editor: editor)
                .replaceDisabled()
                .background(Color(nsColor: .underPageBackgroundColor))
                .navigationTitle(editor.screenplay.title)
                .navigationSubtitle(subtitle)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        ElementModeControl(editor: editor)
                    }
                }
        }
        .sheet(isPresented: $showingTitlePage) {
            TitlePageSheet(editor: editor)
        }
        .focusedSceneValue(\.onShowTitlePage, { showingTitlePage = true })
        .onAppear {
            editor.onFindScene = { findScene() }
        }
    }

    /// ⌘L: the sidebar is the destination list. Reveal it, show Scenes,
    /// focus the filter. Not a Spotlight overlay — those are forbidden.
    private func findScene() {
        columns = .all
        tab = .scenes
        focusSceneFilter += 1
    }

    /// What the window's title bar says under the name: the two numbers a
    /// writer actually watches.
    private var subtitle: String {
        let pages = editor.stats.pages
        return "\(pages) \(pages == 1 ? "page" : "pages") · \(editor.stats.runtime)"
    }
}

/// So File → Title Page… can present the same sheet the phone uses.
public struct ShowTitlePageKey: FocusedValueKey {
    public typealias Value = () -> Void
}

extension FocusedValues {
    public var onShowTitlePage: (() -> Void)? {
        get { self[ShowTitlePageKey.self] }
        set { self[ShowTitlePageKey.self] = newValue }
    }
}
