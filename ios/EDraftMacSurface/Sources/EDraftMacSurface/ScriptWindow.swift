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
            // No ground behind the chrome at all — the page runs to the top
            // of the window and AppKit's soft edge darkens and blurs it on
            // the way up. That is what Pages does: put a colour on its page
            // and the colour reaches the titlebar, dimmed, with the type
            // ghosted behind the controls. There is no opaque band anywhere.
            //
            // Hiding this was tried once before and was worse than the step
            // it removed: with no soft edge installed there was nothing left
            // to fade, so the script ran sharp into the controls. The edge
            // has to be asked for first — see `SoftScrollEdgeAccessory` —
            // and then this is what lets it be seen.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    ElementModeControl(editor: editor)
                }
                // The writer's side of the bar: what is done *to* the script
                // they can see. One capsule, because the system groups a
                // `ToolbarItemGroup` into one piece of glass, and these three
                // belong together — they change how the page looks or what
                // leaves the app with it.
                // Pushes them to the trailing edge, where the system puts
                // what acts on the document. Without it they crowd up against
                // the element selector on the left.
                ToolbarSpacer(.flexible, placement: .primaryAction)
                ToolbarItemGroup(placement: .primaryAction) {
                    PagePaperToggle()
                    Button {
                        showingTitlePage = true
                    } label: {
                        Label("Title Page", systemImage: "text.document")
                    }
                    .help("Title page")
                    ExportMenu(editor: editor)
                }
                // A spacer breaks the glass, so the overflow menu stands on
                // its own — the icons act, this one opens a list, and the two
                // are not the same kind of thing.
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    ScriptOverflowMenu(editor: editor)
                }
            }
        }
        // A tiny bit of blur along the top of the *window*, fading to
        // nothing.
        //
        // Edge to edge, which is the point: attached to the page it stopped
        // at the sidebar, and the seam that left down the Navigator's
        // trailing edge is the thing it was drawn to avoid. One band across
        // the whole width, over both columns, and there is nothing for the
        // two halves to disagree about.
        //
        // The page runs to the top of the window with the controls floating
        // on it, which is Pages' and Finder's arrangement, and
        // `NSScrollEdgeEffectStyle.soft` is asked for on the column the
        // documented way — see `SoftScrollEdgeAccessory`. It installs,
        // verified, and draws nothing here: measured flat from the top of the
        // window down. So the softening is this.
        //
        // The system's own material rather than a colour, masked to fade out,
        // so what happens to the script is a blur going progressively to
        // nothing rather than type tinted toward grey. Tinted with
        // `windowBackgroundColor` — the toolbar's own ground — so it is dark
        // under dark chrome and light under light without either being said.
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color(nsColor: .windowBackgroundColor).opacity(0.62))
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.9), location: 0),
                            .init(color: .black.opacity(0.55), location: 0.45),
                            .init(color: .black.opacity(0.2), location: 0.75),
                            .init(color: .clear, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(height: 38)
                // Decoration: the writer must still be able to click the line
                // it is drawn over, and the Navigator row under it.
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .top)
        }
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
