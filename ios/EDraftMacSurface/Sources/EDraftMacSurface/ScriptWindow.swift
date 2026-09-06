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
    /// Whose thread is open beside the cast, if anyone's.
    @State private var selectedCharacter: String?

    public init(editor: EditorState) {
        self.editor = editor
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
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
                },
                onSelectCharacter: { name in
                    // Choosing the open one closes it. A column that appeared
                    // by being chosen should leave the same way, rather than
                    // growing a dismiss control of its own.
                    selectedCharacter = selectedCharacter == name ? nil : name
                },
                selectedCharacter: selectedCharacter
            ) { element in
                // The sidebar stays where it is: a Mac reader keeps their
                // place in the list while the page moves beside it, which is
                // exactly what a sidebar is for. The thread uses this same
                // `open` — a speech reveals the line, the thread remains.
                editor.jump(to: element)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 360)
            // Nothing sets the Navigator's background. A sidebar on this
            // system is glass, the system draws it, and the one thing that
            // has to be true of the desk beside it is that it is a neutral
            // grey rather than a colour that fights the glass — which is what
            // `screenplayDesk` is for.
        } detail: {
            HStack(spacing: 0) {
                // Sidebar, list, content — Notes' arrangement, and the Mac's.
                // Pushing the thread *inside* the sidebar hid the cast to show
                // one of them, which is losing your place to see your place.
                if let selectedCharacter {
                    CharacterThreadView(
                        editor: editor,
                        name: selectedCharacter,
                        chrome: .panel
                    ) { element in
                        editor.jump(to: element)
                    }
                    // The thread holds its own name so a rename performed
                    // inside it does not pull the view out from under itself.
                    // That means a different character needs a different view,
                    // not the same one asked to change its mind.
                    .id(selectedCharacter)
                    .frame(width: 260)
                    Divider()
                }
                ScriptPageView(editor: editor)
                    .replaceDisabled()
                    // The desk runs under the toolbar, and the page scrolls
                    // beneath it.
                    //
                    // A toolbar on this system is glass, and glass has to have
                    // something behind it or there is nothing to soften: stop
                    // the scroll view at the toolbar's lower edge and the
                    // header becomes a flat slab with a hard line under it.
                    // `NSScrollView` insets its own *content* below the
                    // toolbar while its background fills the frame, which is
                    // how TextEdit, Pages and Xcode all put a document under
                    // the chrome and still start the first line in the clear.
                    .ignoresSafeArea(edges: .top)
                    // Over the canvas, never over the page — §1.6. The corner
                    // furthest from the first line of dialogue.
                    .overlay(alignment: .bottomTrailing) {
                        PageZoomControl(editor: editor)
                    }
            }
            .navigationTitle(editor.screenplay.title)
            .navigationSubtitle(subtitle)
            // `navigationTitle` and `navigationSubtitle` still name the
            // window — "Untitled 3 – 1 page · ~1 minute" is what Mission
            // Control, the Window menu and a tab show — but the name is not
            // drawn over the page. A document's identity belongs to its
            // window; the leading edge of the toolbar is worth more to the
            // writer than a filename they chose, and it goes to the element
            // under the caret, which is the one thing they change while
            // writing.
            // The page fades under the chrome rather than meeting it at a
            // line.
            //
            // Nothing here states the toolbar's background, and that is a
            // decision rather than an omission.
            //
            // The system's own background is what carries
            // `NSScrollEdgeEffectStyle` — the script softening as it passes
            // under the chrome, which is the whole reason the page was given
            // the full height of the window. Hiding it removes the effect
            // along with the ground: measured, the script then runs sharp
            // into the controls, `INT. ROOM 8 - DAY` clipped against the
            // toolbar with no fade at all.
            //
            // What is left is a tonal step at the very top of a document that
            // has not been scrolled, because the toolbar's ground is
            // `windowBackgroundColor` and the desk is `screenplayDesk`. It is
            // the smaller of the two faults by a distance, and it is what
            // every Mac document window does.
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ElementModeControl(editor: editor)
                }
            }
        }
        // The desk is the window's ground, not just the detail column's.
        //
        // A sidebar on this system is an inset pane of glass floating over the
        // window rather than a slab filling a column, so the window shows
        // around it — down its outer edge, and in the rounded corners. That
        // ground was the plain window background while the desk beside it was
        // `screenplayDesk`, which is the border the Navigator appeared to
        // have: not a line drawn anywhere, but two grounds meeting. Giving the
        // window the same colour the desk uses makes it one surface from edge
        // to edge with the glass laid over it.
        .containerBackground(Color(nsColor: .screenplayDesk), for: .window)
        .onChange(of: tab) { _, tab in
            if tab != .cast { selectedCharacter = nil }
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
