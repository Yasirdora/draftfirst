import EDraftCore
import SwiftUI

/// A compact view of the screenplay's structure — scenes, cast and notes. The
/// way home is the chrome's back button; this panel is structure, not
/// navigation.
///
/// The three tabs answer different questions and so behave differently. A
/// scene is a place: its row goes there. A note is a place too — it was left
/// on one line and belongs to no other — so its row goes there as well. A
/// character is not a place: a lead speaks two hundred times, and "go to the
/// character" has no honest destination, so its row opens the character's own
/// page instead, where every line is a real place and renaming can show what
/// it would rewrite.
public struct StoryPanel: View {
    let editor: EditorState

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab

    public init(editor: EditorState, initialTab: Tab = .scenes) {
        self.editor = editor
        _tab = State(initialValue: initialTab)
    }

    public enum Tab: String, CaseIterable, Identifiable {
        case scenes = "Scenes"
        case cast = "Cast"
        case notes = "Notes"

        public var id: String { rawValue }
    }

    // MARK: - Body

    /// The phone presents the Navigator as a sheet, so it brings its own
    /// navigation and its own way out. The Mac puts the same list in a
    /// sidebar, where a "Done" button would be nonsense — so the list itself
    /// is `StoryList`, and this is only the sheet around it.
    public var body: some View {
        NavigationStack {
            StoryList(editor: editor, tab: $tab) { element in
                editor.jump(to: element)
                dismiss()
            }
            .navigationTitle("Navigator")
            .compactTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Which navigator rows a query leaves visible.
///
/// This is matching against titles the model already classified as scenes —
/// it does not decide what a scene is. Empty query means every row.
public enum SceneListFilter {
    /// `setting` is nil for "every scene". A scene whose heading carries no
    /// intro token — a slug forced with a leading dot — belongs to no setting
    /// and so is hidden by any of them, which is the honest answer: the writer
    /// asked for interiors and it is not one.
    public static func included(
        _ scenes: [SceneRow], query: String, setting: SceneSetting? = nil
    ) -> [SceneRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return scenes.filter { scene in
            if let setting, scene.setting != setting { return false }
            guard !needle.isEmpty else { return true }
            return scene.title.localizedCaseInsensitiveContains(needle)
                || scene.label.localizedCaseInsensitiveContains(needle)
        }
    }
}

/// How the Cast list is ordered.
///
/// Lead is how much they speak — the same ranking `EditorState.cast` already
/// uses, most cues first and a name-tie broken alphabetically. Alphabetical
/// is the other way a writer looks for someone: by name, not by volume.
public enum CastListSort: String, CaseIterable, Identifiable, Sendable {
    case lead
    case alphabetical

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lead: "Lead"
        case .alphabetical: "Alphabetical"
        }
    }
}

/// Narrowing and ordering the Navigator's cast list.
///
/// Matching against names the model already assembled. Empty query means
/// every row. Lead re-applies the cue ranking so the filter is the
/// authority even when the incoming list was already in that order.
public enum CastListFilter {
    public static func included(
        _ cast: [CastRow], query: String, sort: CastListSort = .lead
    ) -> [CastRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var rows = needle.isEmpty
            ? cast
            : cast.filter { $0.name.localizedCaseInsensitiveContains(needle) }
        switch sort {
        case .lead:
            rows.sort { $0.cues == $1.cues ? $0.name < $1.name : $0.cues > $1.cues }
        case .alphabetical:
            rows.sort { $0.name < $1.name }
        }
        return rows
    }
}

/// One note as the Navigator lists it: what the writer wrote, and where they
/// left it.
///
/// Derived rather than stored, which is why it lives here and not beside
/// `SceneRow` in the model. A note already knows the line it sits on; what a
/// *list* of notes needs is the scene that line belongs to, and that is a
/// reading of the script rather than a property of the note.
public struct NoteRow: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The note's words, exactly as written.
    public let text: String
    /// The line it sits in front of — where a chosen row goes. Nil for a note
    /// written past the last line, which has nowhere to send anyone.
    public let anchor: UUID?
    /// Who left it, when the document is prepared to say — and the colour
    /// slot that name took. Both nil for a note nobody claimed, which keeps
    /// the yellow it has always had.
    public let author: String?
    public let slot: Int?
    /// The scene it falls in. Carried as an id as well as a title because two
    /// scenes may be called the same thing, and the footnote counts scenes.
    public let sceneID: UUID?
    public let scene: String?
    /// Where that scene opens, at the paper size currently set.
    public let page: Int?
    /// A note that came in a Final Draft file — read, never written — and the
    /// title it carried there, when it had one.
    public let isImported: Bool
    public let title: String?

    public init(
        id: UUID, text: String, anchor: UUID?,
        author: String? = nil, slot: Int? = nil,
        sceneID: UUID?, scene: String?, page: Int?,
        isImported: Bool = false, title: String? = nil
    ) {
        self.id = id
        self.text = text
        self.anchor = anchor
        self.author = author
        self.slot = slot
        self.sceneID = sceneID
        self.scene = scene
        self.page = page
        self.isImported = isImported
        self.title = title
    }

    /// Where the row says the note was left.
    ///
    /// A note always has a place, even when it has no scene — written before
    /// the first heading, or past the last line. Saying which is what tells a
    /// reader why one row in the list does not go anywhere. A note from Final
    /// Draft with no line was not written past the end: its line could not be
    /// found in this draft, and saying so is the honest version.
    public var place: String {
        if let scene { return scene }
        if anchor == nil { return isImported ? "Line not found in this draft" : "After the last line" }
        return "Before the first scene"
    }

    /// An untitled note is still a note. It reads as one rather than as a
    /// blank row, because a writer who pressed the shortcut and walked away
    /// needs to find their way back to the line they left open. A title from
    /// Final Draft leads, the way it heads the note there.
    public var display: String {
        guard let title, !title.isEmpty else { return text.isEmpty ? "Empty note" : text }
        return text.isEmpty ? title : "\(title) — \(text)"
    }
}

/// The notes list: every note in the order the page sets them, each tagged
/// with where it was left.
public enum NoteRows {
    /// The scene a note belongs to is the last heading passed before the line
    /// it sits on — the same reading `EditorState.activeSceneID` makes for the
    /// caret, so the list and the "you are here" mark can never disagree about
    /// which scene something is in.
    ///
    /// Ordered by the page rather than by when each note was written: a list
    /// of notes is a second reading of the script, and a reading goes in
    /// order. Two notes left on one line keep the order the line holds them
    /// in, which is the order the note card shows — `sorted(by:)` is not
    /// stable, so that tie is broken explicitly rather than left to it.
    ///
    /// Notes from a Final Draft file join the list in the same page order,
    /// after the writer's own on a shared line. Their author is the file's
    /// WriterName, so there is no prefix to take off their words.
    public static func rows(
        notes: [ScriptAside], elements: [ScriptElement], scenes: [SceneRow],
        roster: Set<String> = [], imported: [ImportedNote] = []
    ) -> [NoteRow] {
        var position: [UUID: Int] = [:]
        position.reserveCapacity(elements.count)
        for (index, element) in elements.enumerated() { position[element.id] = index }
        let slots = NoteAttribution.slots(for: roster)

        let fromFile = imported.enumerated().map { ordinal, note in
            let index = note.anchor.flatMap { position[$0] }
            let scene = index.flatMap { at in scenes.last { $0.elementIndex <= at } }
            let author = ImportedNotes.author(of: note, in: roster)
            return (
                order: index ?? Int.max,
                tie: notes.count + ordinal,
                row: NoteRow(
                    id: note.id,
                    text: note.text,
                    anchor: note.anchor,
                    author: author,
                    slot: author.flatMap { slots[$0] },
                    sceneID: scene?.id,
                    scene: scene?.title,
                    page: scene?.page,
                    isImported: true,
                    title: note.title
                )
            )
        }

        let placed = notes.enumerated().map { ordinal, note in
            let index = note.anchor.flatMap { position[$0] }
            let scene = index.flatMap { at in scenes.last { $0.elementIndex <= at } }
            // The prefix comes off the words here: the row shows the name as a
            // chip of its own, and printing it twice on one line is one fact
            // wearing two hats.
            let found = NoteAttribution.author(of: note.text, roster: roster)
            return (
                order: index ?? Int.max,
                tie: ordinal,
                row: NoteRow(
                    id: note.id,
                    text: found?.body ?? note.text,
                    anchor: note.anchor,
                    author: found?.name,
                    slot: found.flatMap { slots[$0.name] },
                    sceneID: scene?.id,
                    scene: scene?.title,
                    page: scene?.page
                )
            )
        }
        return (placed + fromFile).sorted { ($0.order, $0.tie) < ($1.order, $1.tie) }.map(\.row)
    }
}

/// Narrowing the Navigator's note list.
///
/// Matches the note's own words *and* the scene it sits in, because both are
/// how a writer remembers where they left one: "the thing about the kettle"
/// and "that note in the alley" are the same search asked two ways.
public enum NoteListFilter {
    /// `author` narrows to one person — the Notes tab's answer to the scene
    /// setting menu. Nil is everyone; it is a way of looking at the list, not
    /// a property of the document.
    public static func included(
        _ notes: [NoteRow], query: String, author: String? = nil
    ) -> [NoteRow] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.filter { note in
            if let author, note.author != author { return false }
            guard !needle.isEmpty else { return true }
            return note.text.localizedCaseInsensitiveContains(needle)
                || (note.author?.localizedCaseInsensitiveContains(needle) ?? false)
                || (note.scene?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }
}

/// An author's colour, in the Navigator.
///
/// The same six hues the page marks with, in the same order, read from the one
/// list in `EDraftCore` — so a name is the same colour in the list and in the
/// margin, and neither surface can drift from the other by editing its own
/// copy. Unattributed keeps the note yellow, which is what it has always been.
enum NoteAuthorInk {
    static func colour(slot: Int?) -> Color {
        guard let slot, NoteAttribution.paletteHues.indices.contains(slot) else {
            return .yellow
        }
        let hue = NoteAttribution.paletteHues[slot].paper
        return Color(.sRGB, red: hue.red, green: hue.green, blue: hue.blue)
    }
}

/// The Navigator itself: the scope switch, the rows, and the footnote — with
/// no chrome of its own.
///
/// This is what both platforms actually share. A phone wraps it in a sheet
/// with a Done button; a Mac drops it into a sidebar where it simply lives.
/// Neither arrangement is in here, which is the point: the list is the same
/// list, and only its surroundings differ.
public struct StoryList: View {
    let editor: EditorState
    @Binding var tab: StoryPanel.Tab
    /// What a row that names a place does when it is chosen. The sheet closes
    /// itself afterwards; the sidebar stays where it is.
    let open: (UUID) -> Void
    /// Mac Find Scene (⌘L): a filter sitting with the scope switch —
    /// Messages puts search in that same position. Scenes and Cast both
    /// use it; the menu beside the field is the one that differs. Off on
    /// the phone, which still opens this list as a sheet.
    var showsSceneFilter: Bool
    /// The Mac sidebar is destinations, never verbs (`MACOS-DESIGN` §1.1).
    /// Scene numbering is a Format-menu action there. The phone still
    /// carries the row — its Navigator is a sheet, not a sidebar.
    var showsSceneNumbering: Bool
    @Binding var sceneQuery: String
    var focusSceneFilter: Int
    var onFilterSubmit: ((UUID) -> Void)?
    /// A surface that shows the thread beside the cast rather than in place of
    /// it. The phone pushes — one column, no choice. The Mac hands the name
    /// outward so a column can open next to the list, the way Notes opens a
    /// note list beside its folders, and the writer keeps the cast in view.
    var onSelectCharacter: ((String) -> Void)?
    /// Which name that column is showing, so the row can read as chosen.
    var selectedCharacter: String?

    /// The height the row of controls is built on: what `NSSearchField` makes
    /// itself, and so what the filter button has to match to sit level with it.
    private static let controlHeight: CGFloat = 24

    @FocusState private var filterFocused: Bool
    /// Which setting the list is narrowed to, or nil for all of them. Local:
    /// it is a way of looking at the list, not a property of the document, and
    /// nothing outside needs to read it.
    @State private var sceneSetting: SceneSetting?
    @State private var castQuery = ""
    /// Lead is the list's own order. Alphabetical is a way of looking at it,
    /// not a property of the document.
    @State private var castSort: CastListSort = .lead
    @State private var noteQuery = ""
    /// Which author the note list is narrowed to, or nil for all of them.
    @State private var noteAuthor: String?

    public init(
        editor: EditorState,
        tab: Binding<StoryPanel.Tab>,
        showsSceneFilter: Bool = false,
        showsSceneNumbering: Bool = true,
        sceneQuery: Binding<String> = .constant(""),
        focusSceneFilter: Int = 0,
        onFilterSubmit: ((UUID) -> Void)? = nil,
        onSelectCharacter: ((String) -> Void)? = nil,
        selectedCharacter: String? = nil,
        open: @escaping (UUID) -> Void
    ) {
        self.editor = editor
        _tab = tab
        self.open = open
        self.showsSceneFilter = showsSceneFilter
        self.showsSceneNumbering = showsSceneNumbering
        _sceneQuery = sceneQuery
        self.focusSceneFilter = focusSceneFilter
        self.onFilterSubmit = onFilterSubmit
        self.onSelectCharacter = onSelectCharacter
        self.selectedCharacter = selectedCharacter
    }

    public var body: some View {
        VStack(spacing: 0) {
            tabPicker
            if showsSceneFilter {
                switch tab {
                case .scenes: sceneFilterField
                case .cast: castFilterField
                case .notes: noteFilterField
                }
            }
            list
        }
        .background(.ultraThinMaterial)
        .onChange(of: focusSceneFilter) { _, _ in
            filterFocused = true
        }
        // Pushed by name rather than by row, so a rename performed on the
        // character's page does not pull the page out from under itself
        // when the row it came from stops existing. Lives on the list, not
        // the phone's sheet, so the Mac sidebar can push the same thread.
        .navigationDestination(for: String.self) { name in
            CharacterThreadView(editor: editor, name: name, open: open)
        }
    }

    /// Narrows the scene list. Return jumps to the first remaining row and
    /// hands the page back — the field is a destination filter, not a verb.
    private var sceneFilterField: some View {
        HStack(spacing: 8) {
            #if os(macOS)
            // The platform's own search field — magnifier, clear button, the
            // shape Finder and Mail give the same job. A plain text field read
            // as a place to type a scene, not a place to find one.
            SceneSearchField(
                text: $sceneQuery,
                prompt: "Scene",
                focusToken: focusSceneFilter,
                onSubmit: submitFilter
            )
            .accessibilityLabel("Find Scene")
            #else
            TextField("Scene", text: $sceneQuery)
                .textFieldStyle(.roundedBorder)
                .focused($filterFocused)
                .onSubmit { submitFilter() }
                .accessibilityLabel("Find Scene")
            #endif
            settingMenu
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Narrows the cast list. Return opens the first remaining name, the
    /// way Return on Scenes jumps to the first remaining heading.
    private var castFilterField: some View {
        HStack(spacing: 8) {
            #if os(macOS)
            SceneSearchField(
                text: $castQuery,
                prompt: "Character",
                focusToken: 0,
                onSubmit: submitCastFilter
            )
            .accessibilityLabel("Find Character")
            #else
            TextField("Character", text: $castQuery)
                .textFieldStyle(.roundedBorder)
                .focused($filterFocused)
                .onSubmit { submitCastFilter() }
                .accessibilityLabel("Find Character")
            #endif
            sortMenu
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Narrows the note list. Return goes to the first remaining note, the
    /// way Return on Scenes jumps to the first remaining heading.
    ///
    /// No menu beside it. Scenes have settings to sort by and cast have a
    /// running order; notes have only the order the script puts them in, and a
    /// control offering one way of looking at something is a control that
    /// says nothing.
    private var noteFilterField: some View {
        HStack(spacing: 8) {
            #if os(macOS)
            SceneSearchField(
                text: $noteQuery,
                prompt: "Note",
                focusToken: 0,
                onSubmit: submitNoteFilter
            )
            .accessibilityLabel("Find Note")
            #else
            TextField("Note", text: $noteQuery)
                .textFieldStyle(.roundedBorder)
                .focused($filterFocused)
                .onSubmit { submitNoteFilter() }
                .accessibilityLabel("Find Note")
            #endif
            authorMenu
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Whose notes. The same glass circle beside the field that Scenes and
    /// Cast hang their filters off — this tab had no menu at all while notes
    /// had nothing to be sorted or narrowed by, and an author is the thing
    /// that gives it one.
    ///
    /// Absent entirely while nobody is named: a filter offering one choice is
    /// a control that says nothing.
    @ViewBuilder
    private var authorMenu: some View {
        let authors = noteAuthors
        if !authors.isEmpty {
            #if os(macOS)
            NoteAuthorButton(author: $noteAuthor, authors: authors)
                .frame(width: Self.controlHeight, height: Self.controlHeight)
                .accessibilityLabel(noteAuthor.map { "Filter notes: \($0)" } ?? "Filter notes")
                .help("Show only one person's notes")
            #else
            Menu {
                Picker("", selection: $noteAuthor) {
                    Text("All Notes").tag(String?.none)
                    Divider()
                    ForEach(authors, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(noteAuthor.map { "Filter notes: \($0)" } ?? "Filter notes")
            #endif
        }
    }

    /// Everyone this document names, in the order their colours were dealt.
    private var noteAuthors: [String] {
        editor.noteRoster.sorted { $0.lowercased() < $1.lowercased() }
    }

    private var emptyFilterDetail: String {
        switch (sceneQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, sceneSetting) {
        case (true, let setting?): "This script has no \(setting.phrase) scenes."
        case (false, let setting?): "No \(setting.phrase) scene matches that search."
        default: "Nothing in the navigator matches that search."
        }
    }

    /// Interiors, exteriors, or the ones that cross between.
    ///
    /// A menu rather than a row of segments: the sidebar is 240 points at its
    /// narrowest and a segmented control would spend most of it, while the
    /// filled glyph already says the list is narrowed. It is also where the
    /// platform puts this — Mail, Photos and Finder all hang their filters off
    /// one control beside the search field.
    private var settingMenu: some View {
        #if os(macOS)
        SceneSettingButton(setting: $sceneSetting)
            .frame(width: Self.controlHeight, height: Self.controlHeight)
            .accessibilityLabel(
                sceneSetting.map { "Filter scenes: \($0.phrase)" } ?? "Filter scenes"
            )
            .help("Show only interiors, exteriors, or scenes that cross between")
        #else
        phoneSettingMenu
        #endif
    }

    private var phoneSettingMenu: some View {
        Menu {
            // No title at all: an inline picker inside a menu renders its
            // label as a section header, and a word above three items that
            // plainly say what they are is a word spent on nothing. The name
            // a screen reader needs is on the menu button itself.
            Picker("", selection: $sceneSetting) {
                Text("All Scenes").tag(SceneSetting?.none)
                Divider()
                ForEach(SceneSetting.allCases) { setting in
                    Label(setting.title, systemImage: setting.symbol)
                        .tag(SceneSetting?.some(setting))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            // The bare lines. The `.circle` variants drew a ring of their own
            // inside the button's, which is two circles saying one thing —
            // and neither of them round, since the button was 39 by 17.
            Image(systemName: "line.3.horizontal.decrease")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(
            sceneSetting.map { "Filter scenes: \($0.phrase)" } ?? "Filter scenes"
        )
        .help("Show only interiors, exteriors, or scenes that cross between")
    }

    private func submitFilter() {
        guard let first = SceneListFilter.included(
            editor.scenes, query: sceneQuery, setting: sceneSetting
        ).first
        else { return }
        if let onFilterSubmit {
            onFilterSubmit(first.id)
        } else {
            open(first.id)
        }
    }

    /// Lead, or A–Z. Same control as the scene setting menu: a glass circle
    /// beside the field, because a segmented control would spend the
    /// sidebar, and this is where Mail hangs the other way of looking.
    private var sortMenu: some View {
        #if os(macOS)
        CastSortButton(sort: $castSort)
            .frame(width: Self.controlHeight, height: Self.controlHeight)
            .accessibilityLabel("Sort cast: \(castSort.title)")
            .help("Sort by how much they speak, or alphabetically")
        #else
        phoneSortMenu
        #endif
    }

    private var phoneSortMenu: some View {
        Menu {
            Picker("", selection: $castSort) {
                ForEach(CastListSort.allCases) { sort in
                    Text(sort.title).tag(sort)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Sort cast: \(castSort.title)")
        .help("Sort by how much they speak, or alphabetically")
    }

    private func submitCastFilter() {
        guard let first = CastListFilter.included(
            editor.cast, query: castQuery, sort: castSort
        ).first else { return }
        onSelectCharacter?(first.name)
    }

    /// The first note the filter leaves, at the line it was left on. A note
    /// past the last line anchors to nothing, so there is nowhere to send
    /// anyone and the field does nothing rather than guessing.
    private func submitNoteFilter() {
        guard let anchor = NoteListFilter.included(
            noteRows, query: noteQuery, author: noteAuthor
        ).first?.anchor
        else { return }
        if let onFilterSubmit {
            onFilterSubmit(anchor)
        } else {
            open(anchor)
        }
    }

    /// The Scenes/Cast/Notes switch is a full-width row of its own, pinned between
    /// the bar and the list — the App Store idiom. Never a list row (the
    /// grouped style wraps it in a card), never squeezed between bar buttons.
    /// On the Mac it is `MacTabSwitch`, and nothing here may clip it: the
    /// press lift draws outside the control's own bounds by design, so a
    /// `.clipped()` here would cut the top and bottom off the very effect
    /// this switch exists for.
    private var tabPicker: some View {
        #if os(macOS)
        MacTabSwitch(tab: $tab)
            .frame(maxWidth: .infinity)
            .frame(height: MacTabSwitch.height)
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        #else
        Picker("Story", selection: $tab) {
            ForEach(StoryPanel.Tab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.large)
        .tint(.primary)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        #endif
    }

    private var list: some View {
        List {
            if tab == .scenes, showsSceneNumbering {
                // Numbering drills down rather than hiding behind a toolbar
                // glyph: the row names the state the script is in, and the
                // page it opens has room to say what each operation costs.
                // Settings' own idiom, one tap from the scenes it acts on.
                Section {
                    NavigationLink {
                        SceneNumbersView(editor: editor)
                    } label: {
                        LabeledContent(
                            "Scene Numbers",
                            value: editor.isSceneNumbered ? "Numbered" : "None"
                        )
                    }
                }
            }

            // The segment IS the label — no section header repeating it
            // underneath.
            Section {
                rows
            } footer: {
                // Glanceable, tab-aware context: document health on the first
                // line, then the texture of whichever list is showing —
                // structure for scenes, voice for cast.
                VStack(alignment: .leading, spacing: 3) {
                    Text(statsSummary)
                    if !tabContext.isEmpty {
                        Text(tabContext)
                    }
                }
                .padding(.top, 4)
            }
        }
        // The rows carry their own tint, so the list must not force one on
        // them — a stated tint here reached the rows present when it was
        // applied and missed the ones scrolled into view later, which is how
        // a cast list came out half black and half blue.
        .tint(.primary)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        switch tab {
        case .scenes:
            let visible = SceneListFilter.included(
                editor.scenes, query: sceneQuery, setting: sceneSetting
            )
            /// A scene filter answers "which scenes" — acts are not scenes,
            /// so the outline flattens back to rows while one is on.
            let filtering = !sceneQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || sceneSetting != nil
            if editor.scenes.isEmpty && editor.acts.isEmpty {
                EmptyListRow(
                    title: "No Scenes Yet",
                    detail: "Start a line with INT. or EXT. to build the navigator.",
                    symbol: "film.stack"
                )
            } else if visible.isEmpty && filtering {
                // Say which of the two narrowed it away, because the remedy
                // differs: clear the field, or widen the filter.
                EmptyListRow(
                    title: "No Matching Scenes",
                    detail: emptyFilterDetail,
                    symbol: sceneQuery.isEmpty ? "line.3.horizontal.decrease.circle" : "magnifyingglass"
                )
            } else if filtering || editor.acts.isEmpty {
                ForEach(visible) { scene in
                    SceneListRow(scene: scene, isCurrent: scene.id == editor.activeSceneID) {
                        open(scene.id)
                    }
                }
            } else {
                // The outline: acts as the top-level entries, the scenes each
                // one owns beneath it (RFC-ACT-BREAK §6). Unfiltered only —
                // a map is what you see when you are not searching it.
                ForEach(NavigatorOutline.rows(acts: editor.acts, scenes: editor.scenes)) { row in
                    switch row {
                    case .act(let act):
                        ActListRow(act: act, isCurrent: act.id == editor.activeActID) {
                            open(act.id)
                        }
                    case .scene(let scene):
                        SceneListRow(scene: scene, isCurrent: scene.id == editor.activeSceneID) {
                            open(scene.id)
                        }
                    }
                }
            }

        case .cast:
            let visible = CastListFilter.included(
                editor.cast, query: castQuery, sort: castSort
            )
            let searching = !castQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if editor.cast.isEmpty {
                EmptyListRow(
                    title: "No Cast Yet",
                    detail: "Character cues appear here automatically as you write.",
                    symbol: "person.2"
                )
            } else if visible.isEmpty && searching {
                EmptyListRow(
                    title: "No Matching Characters",
                    detail: "Nothing in the navigator matches that search.",
                    symbol: "magnifyingglass"
                )
            } else {
                ForEach(visible) { person in
                    if let onSelectCharacter {
                        let chosen = person.name == selectedCharacter
                        Button { onSelectCharacter(person.name) } label: {
                            CastRowLabel(person: person, isSelected: chosen)
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(SelectedRowMark(isOn: chosen))
                    } else {
                        CastListRow(person: person)
                    }
                }
            }

        case .notes:
            let all = noteRows
            let visible = NoteListFilter.included(all, query: noteQuery, author: noteAuthor)
            let searching = !noteQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || noteAuthor != nil
            if all.isEmpty {
                EmptyListRow(
                    title: "No Notes Yet",
                    detail: emptyNotesDetail,
                    symbol: "note.text"
                )
            } else if visible.isEmpty && searching {
                EmptyListRow(
                    title: "No Matching Notes",
                    detail: noteAuthor.map { "\($0) left no note matching that." }
                        ?? "Nothing in the navigator matches that search.",
                    symbol: noteQuery.isEmpty ? "line.3.horizontal.decrease.circle" : "magnifyingglass"
                )
            } else {
                ForEach(visible) { note in
                    NoteListRow(note: note) { anchor in open(anchor) }
                }
            }
        }
    }

    /// The note list, derived where it is read.
    ///
    /// `EditorState` caches scenes and cast because both are read on every
    /// keystroke, from the toolbar and the footnote as well as the list. This
    /// is read only while the Notes tab is showing, and a script carries tens
    /// of notes rather than thousands of elements — so it is a walk, not a
    /// cache to keep honest.
    private var noteRows: [NoteRow] {
        NoteRows.rows(
            notes: editor.notes,
            elements: editor.screenplay.elements,
            scenes: editor.scenes,
            roster: editor.noteRoster,
            imported: editor.importedNotes
        )
    }

    /// How a note gets made, said the way this platform makes one.
    private var emptyNotesDetail: String {
        #if os(macOS)
        return "Notes you leave on a line collect here. ⇧⌘K starts one."
        #else
        return "Notes you leave on a line collect here, and never print."
        #endif
    }

    // MARK: - Footnote

    private var statsSummary: String {
        let pages = "\(editor.stats.pages) \(editor.stats.pages == 1 ? "page" : "pages")"
        let words = "\(editor.stats.words) \(editor.stats.words == 1 ? "word" : "words")"
        return [pages, editor.stats.runtime, words].joined(separator: " · ")
    }

    /// The tab-specific second line of the footnote.
    private var tabContext: String {
        switch tab {
        case .scenes: sceneContext
        case .cast: castContext
        case .notes: noteContext
        }
    }

    /// Structure at a glance: act count when the script has acts, then scene
    /// and location counts plus the INT/EXT texture a production reads a
    /// script by.
    private var sceneContext: String {
        let stats = editor.storyStats
        let actCount = editor.acts.count
        guard stats.scenes > 0 || actCount > 0 else { return "" }
        var facts: [String] = []
        if actCount > 0 {
            facts.append("\(actCount) \(actCount == 1 ? "act" : "acts")")
        }
        if stats.scenes > 0 {
            facts += [
                "\(stats.scenes) \(stats.scenes == 1 ? "scene" : "scenes")",
                "\(stats.locations) \(stats.locations == 1 ? "location" : "locations")",
                "\(stats.interior) INT · \(stats.exterior) EXT"
            ]
        }
        return facts.joined(separator: " · ")
    }

    /// Voice at a glance: cast size, cue volume, and who carries the dialogue
    /// — hidden while a one-voice script would only state the obvious.
    private var castContext: String {
        let stats = editor.storyStats
        guard stats.characters > 0 else { return "" }
        var facts = [
            "\(stats.characters) \(stats.characters == 1 ? "character" : "characters")",
            "\(stats.cues) \(stats.cues == 1 ? "cue" : "cues")"
        ]
        if let lead = stats.leadingCharacter, stats.characters > 1 {
            facts.append("\(lead) leads (\(Int((stats.leadingShare * 100).rounded()))%)")
        }
        return facts.joined(separator: " · ")
    }

    /// The pass at a glance: how many notes, and how much of the script they
    /// touch — the count of scenes carrying at least one, which is what a
    /// writer wants to know before sitting down to clear them.
    ///
    /// Scenes are counted by id rather than by heading: two scenes may be
    /// called the same thing, and a script with three INT. KITCHEN - DAYs
    /// must not report one.
    private var noteContext: String {
        let rows = noteRows
        guard !rows.isEmpty else { return "" }
        var facts = ["\(rows.count) \(rows.count == 1 ? "note" : "notes")"]
        let marked = Set(rows.compactMap(\.sceneID)).count
        let total = editor.scenes.count
        if marked > 0, total > 0 {
            facts.append("in \(marked) of \(total) \(total == 1 ? "scene" : "scenes")")
        }
        // Only worth saying when there is more than one voice: "1 hand" on a
        // script the writer is alone on states the obvious.
        let hands = Set(rows.compactMap(\.author)).count
        if hands > 1 { facts.append("\(hands) hands") }
        return facts.joined(separator: " · ")
    }
}

// MARK: - The chosen row

/// The mark on the row the writer is in: a quiet inset pill, the way Finder
/// draws one.
///
/// Deliberately not the system's own source-list selection. That fills the
/// whole row with solid accent and white type the moment the list takes
/// focus, which is right for a file list you are arrowing through and far too
/// loud for a map of the script that sits on screen the entire time the
/// writer is typing somewhere else. Finder's own sidebar reads as a soft grey
/// pill with the label tinted — present when you look for it, silent when you
/// are not. That is what this is.
///
/// It also has to be drawn rather than asked for: `List(selection:)` hands
/// the appearance to AppKit, and the focused state cannot be toned down.
struct SelectedRowMark: View {
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color.primary.opacity(isOn ? 0.08 : 0))
            // Inset, so the pill is a mark *on* the list rather than a band
            // across it — the edge-to-edge fill was the single thing that
            // most made this not look like a sidebar.
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
    }
}

// MARK: - Act row

/// An act: the outline's top level, so the row speaks a shade stronger than
/// a master scene — the card text at semibold, its span where the scene
/// rows put their page. The glyph keeps the leading column the scene
/// numbers own, so card and heading titles align down the list.
struct ActRowLabel: View {
    let act: ActRow
    var isCurrent = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: ScreenplayKind.actbreak.symbol)
                .font(.caption)
                .foregroundStyle(isCurrent
                    ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .frame(minWidth: 18, alignment: .trailing)

            Text(act.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isCurrent
                    ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.foreground))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(act.title)

            if let range = act.pageRangeLabel {
                Text(range)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Spoken without the selection state, the way `SceneRowLabel` is.
    var spokenLabel: String {
        var label = act.title
        if let first = act.firstPage {
            if let last = act.lastPage, last > first {
                label += ", pages \(first) to \(last)"
            } else {
                label += ", page \(first)"
            }
        }
        return label
    }
}

/// The tappable act row — the same button-and-pill arrangement as the scene
/// row, because the card is a real place and choosing it goes there.
private struct ActListRow: View {
    let act: ActRow
    let isCurrent: Bool
    let open: () -> Void

    var body: some View {
        Button(action: open) { ActRowLabel(act: act, isCurrent: isCurrent) }
        .buttonStyle(.plain)
        .listRowBackground(SelectedRowMark(isOn: isCurrent))
        .accessibilityLabel(isCurrent
            ? ActRowLabel(act: act).spokenLabel + ", current act"
            : ActRowLabel(act: act).spokenLabel)
        .accessibilityHint("Moves the insertion point to the act's card")
    }
}

// MARK: - Scene row

/// A scene, its address, and where to turn to find it — with no opinion
/// about how it is chosen.
///
/// The Mac hands this straight to a `List(selection:)` and lets the source
/// list draw the pill, the accent and the focus ring, which is the whole of
/// what makes Finder's sidebar look like Finder's sidebar. The phone wraps it
/// in `SceneListRow` below, because a bare row in a plain list is not
/// tappable there.
/// How a Navigator row is drawn, as a value.
///
/// The view reads this and nothing else, so the rules — selected wins over
/// everything, a cut scene is struck and inked back, a secondary slug is a
/// shade lighter — live in one place and can be measured without rendering
/// a view. SwiftUI shape styles are not comparable, which is the other
/// reason the decision is a value and the colour is a lookup from it.
struct SceneRowStyle: Equatable {
    enum Ink: Equatable { case accent, omitted, secondary, primary }
    var ink: Ink
    var struckThrough: Bool

    /// RFC-DRAFT-PRODUCTION §7.3: an omitted scene keeps its number and its
    /// place, and says what it is the way the page says it.
    static func of(_ scene: SceneRow, isSelected: Bool) -> SceneRowStyle {
        SceneRowStyle(
            ink: isSelected ? .accent
                : scene.omitted ? .omitted
                : scene.isSecondary ? .secondary : .primary,
            struckThrough: scene.omitted
        )
    }
}

struct SceneRowLabel: View {
    let scene: SceneRow
    /// Tints the row's own type, which is how Finder says "this one" without
    /// raising its voice: the pill carries no colour, the label does.
    var isSelected = false

    public var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // A production number is not a digit count: "12A" and "112"
                // both have to fit without truncating, so the column grows to
                // the widest rather than being pinned to two figures. The
                // floor only stops single digits from jittering — set wide, it
                // spends the sidebar's width on empty space in front of every
                // heading, which is what a reader is actually here to read.
                Text(scene.label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isSelected
                        ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                    .frame(minWidth: 18, alignment: .trailing)

                // One line per scene, always. The list is a map of the
                // script, and a map reads by rows of even height — a heading
                // that wraps bends every row beneath it out of step. What
                // cannot fit ends in an ellipsis; the full text is a hover
                // away, and the page number keeps the right margin, so the
                // trailing column still lines up down the list.
                // Master scenes are the spine; a secondary slug names
                // somewhere inside one. Indented and a shade lighter, so a
                // reader running down the list sees the setups first and the
                // rooms within them second — which is how the script is
                // actually structured, and what turned this list from a
                // wall of headings into an outline. See `SceneRow.isSecondary`
                // for why this is emphasis and not a second element type.
                Text(scene.title)
                    .font(scene.isSecondary ? .subheadline : .body)
                    .strikethrough(style.struckThrough, color: .secondary)
                    // `.foreground` rather than `.primary`: it means "whatever
                    // the row's colour currently is", which is what the source
                    // list changes when the row is selected. `.primary` pins
                    // the type dark and leaves it dark on the accent pill.
                    .foregroundStyle(rowInk)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.leading, scene.isSecondary ? 14 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(scene.title)

                // Where it falls, at the paper size currently set — read out
                // of the same pagination the PDF prints, so the two can never
                // disagree. A scene number says which scene; a page number
                // says where to turn.
                if let page = scene.page {
                    Text(page.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
    }

    /// Accent when chosen; otherwise the outline's own two levels — a master
    /// slug at full strength, a secondary one a shade back.
    var style: SceneRowStyle { SceneRowStyle.of(scene, isSelected: isSelected) }

    private var rowInk: AnyShapeStyle {
        switch style.ink {
        case .accent: return AnyShapeStyle(Color.accentColor)
        case .omitted: return AnyShapeStyle(.tertiary)
        case .secondary: return AnyShapeStyle(.secondary)
        case .primary: return AnyShapeStyle(.foreground)
        }
    }

    /// Spoken without the selection state: on the Mac the list says "selected"
    /// itself, and on the phone `SceneListRow` adds "current scene".
    var spokenLabel: String {
        var label = "Scene \(scene.label), \(scene.title)"
        /* A strike through type is not spoken; an omitted scene has to say
           so out loud or a VoiceOver reader is told a cut scene is live. */
        if scene.omitted { label += ", omitted" }
        if let page = scene.page { label += ", page \(page)" }
        return label
    }
}

/// The phone's tappable scene row. The Mac does not use this: there the row
/// is chosen by the list, not by a button inside it — and a button inside a
/// source-list row suppresses the system's own selection highlight, which is
/// why this used to be drawn by hand.
private struct SceneListRow: View {
    let scene: SceneRow
    /// Whether the caret sits inside this scene — the "you are here" mark.
    let isCurrent: Bool
    let open: () -> Void

    public var body: some View {
        Button(action: open) { SceneRowLabel(scene: scene, isSelected: isCurrent) }
        // Without this the row takes the default button style, which centres
        // its label — which is why a heading long enough to wrap came out
        // looking like a title card.
        .buttonStyle(.plain)
        .listRowBackground(SelectedRowMark(isOn: isCurrent))
        .accessibilityLabel(isCurrent
            ? SceneRowLabel(scene: scene).spokenLabel + ", current scene"
            : SceneRowLabel(scene: scene).spokenLabel)
        .accessibilityHint("Moves the insertion point to this scene")
    }
}

// MARK: - Cast row

/// A character, how much they speak, and the way in to them.
///
/// The row leads to the character rather than into the script. Tapping a name
/// cannot honestly mean "go there" when the name occurs on every page, but it
/// can mean "show me her", and that page is where the arbitrary choice
/// disappears: every line in it is a real place.
///
/// One row, one meaning. A chevron and a menu side by side ask the writer to
/// choose between two doors before they know what is behind either; renaming
/// moves inside, onto the page that can show the cues it would rewrite.
/// One cast row, drawn once. Whether choosing it pushes a thread or opens a
/// column beside the list is the surface's business, not the row's.
private struct CastRowLabel: View {
    let person: CastRow
    var isSelected = false

    var body: some View {
        HStack {
            // Stated, not inherited. The list's tint reaches the rows
            // present when it is applied; rows realized later — the ones
            // a writer scrolls into view — came up in the accent colour
            // instead, so a cast list read half black and half blue.
            // Icon and name together, the way a Finder row tints: the symbol
            // is half of what the eye reads as "this one".
            Label(person.name, systemImage: "person.crop.circle.fill")
                .font(.body)
                .foregroundStyle(isSelected
                    ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.foreground))
            Spacer()
            Text("\(person.cues) \(person.cues == 1 ? "cue" : "cues")")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

private struct CastListRow: View {
    let person: CastRow

    public var body: some View {
        NavigationLink(value: person.name) { CastRowLabel(person: person) }
    }
}

// MARK: - Note row

/// A note, and where it was left.
///
/// The note's own words lead, because they are what the writer is scanning
/// for; the scene underneath is how they confirm they have the right one, not
/// how they find it. Two lines rather than the scene list's strict one: a
/// heading is a label and truncates cleanly, while a note is prose, and prose
/// cut to a single line is usually cut before it has said anything.
private struct NoteRowLabel: View {
    let note: NoteRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            // The column the scene numbers own, so notes and headings line up
            // down the list when a writer switches between the two tabs.
            // Tinted to whoever left it, so a run of notes reads as who said
            // what before a single word of it is read. Unattributed keeps the
            // note yellow it has always had.
            Image(systemName: "note.text")
                .font(.caption)
                .foregroundStyle(NoteAuthorInk.colour(slot: note.slot))
                .frame(minWidth: 18, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(note.display)
                    .font(.body)
                    .foregroundStyle(note.text.isEmpty
                        ? AnyShapeStyle(.secondary) : AnyShapeStyle(.foreground))
                    .lineLimit(2)
                    .truncationMode(.tail)
                HStack(spacing: 4) {
                    if let author = note.author {
                        Text(author)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(NoteAuthorInk.colour(slot: note.slot))
                            .lineLimit(1)
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    Text(note.place)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let page = note.page {
                Text(page.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .help(note.display)
    }

    var spokenLabel: String {
        var label = "Note, \(note.display)"
        if let author = note.author { label += ", by \(author)" }
        label += ", \(note.place)"
        if let page = note.page { label += ", page \(page)" }
        return label
    }
}

/// One note row. It goes to the line the note was left on and does nothing
/// else — editing a note happens on the page, in the card that already owns
/// it, where the writer can see the line they are talking about.
///
/// A note written past the last line anchors to nothing, so it is not a
/// button at all. A button that cannot act reads as a broken one; a row that
/// is plainly not a button, saying "After the last line" underneath itself,
/// reads as what it is.
private struct NoteListRow: View {
    let note: NoteRow
    let open: (UUID) -> Void

    @ViewBuilder
    var body: some View {
        if let anchor = note.anchor {
            Button { open(anchor) } label: { NoteRowLabel(note: note) }
                .buttonStyle(.plain)
                .accessibilityLabel(NoteRowLabel(note: note).spokenLabel)
                .accessibilityHint("Moves the insertion point to the line this note is on")
        } else {
            NoteRowLabel(note: note)
                .accessibilityLabel(NoteRowLabel(note: note).spokenLabel)
        }
    }
}

// MARK: - Empty state

private struct EmptyListRow: View {
    let title: String
    let detail: String
    let symbol: String

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Scene numbering

/// Scene numbering.
///
/// A page rather than a menu, because the two operations need room to say how
/// far apart they are. One hands out addresses that did not exist. The other
/// changes addresses a schedule, a call sheet and a script supervisor's notes
/// are already working from — which is why it is confirmed, and why clearing
/// is inert on a script that has nothing to clear.
private struct SceneNumbersView: View {
    let editor: EditorState

    @State private var confirmingRenumber = false
    @State private var confirmingClear = false
    @State private var outcome: String?

    public var body: some View {
        Form {
            Section {
                LabeledContent("Scenes", value: "\(editor.scenes.count)")
                LabeledContent("Numbered", value: editor.isSceneNumbered ? "Yes" : "No")
            }

            Section {
                Button("Number New Scenes") {
                    report(editor.applySceneNumbering(.newScenesOnly))
                }
            } footer: {
                Text("Keeps every existing number and letters the scenes that have none — "
                     + "a scene added after 12 becomes 12A. Safe on a script that has "
                     + "already gone out.")
            }

            Section {
                Button("Number All Scenes") { confirmingRenumber = true }
                Button("Remove Scene Numbers", role: .destructive) { confirmingClear = true }
                    .disabled(!editor.isSceneNumbered)
            } footer: {
                Text("Numbering from 1 and clearing both change addresses that a schedule "
                     + "or call sheet may already cite.")
            }

            if let outcome {
                Section { Text(outcome).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Scene Numbers")
        .compactTitle()
        .alert("Renumber Every Scene?", isPresented: $confirmingRenumber) {
            Button("Renumber", role: .destructive) { report(editor.applySceneNumbering(.all)) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every scene is numbered again from 1. Any number already in use changes, "
                 + "including ones a schedule or call sheet may already cite.")
        }
        .alert("Remove Every Scene Number?", isPresented: $confirmingClear) {
            Button("Remove", role: .destructive) { report(editor.applySceneNumbering(.clear)) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The script keeps its scenes; it loses the numbers people cite them by.")
        }
    }

    private func report(_ changed: Int) {
        outcome = changed == 0
            ? "Nothing to change."
            : "Updated \(changed == 1 ? "1 scene" : "\(changed) scenes")."
    }
}

#if os(macOS)
/// `NSSearchField`, for the Mac sidebar's scene filter. SwiftUI re-exports the
/// AppKit types this needs; a literal `import AppKit` would breach the
/// boundary this package keeps on purpose.
///
/// SwiftUI has no search field outside of `.searchable`, and `.searchable`
/// puts it in the toolbar, which is the one place the design says the filter
/// must not go (`MACOS-DESIGN` §1.2: scope lives at the top of the list it
/// scopes). Return submits; a change of `focusToken` — ⌘L — takes focus.
/// The scene filter, as the platform's own button.
///
/// `NSButton` rather than SwiftUI's `Menu`, because the look asked for is the
/// one the toolbar's Back button has, and that is a specific pair of AppKit
/// properties — `NSBezelStyleGlass` and `NSControlBorderShapeCircle` — with
/// no SwiftUI spelling. `Menu` was tried three ways first: `.buttonStyle(.glass)`
/// under `.menuStyle(.button)` draws a popup button's chrome instead of the
/// glass; `.glassEffect` under `.menuStyle(.borderlessButton)` renders
/// nothing at all on a dark sidebar; and neither an outer `.frame` nor inner
/// `.padding` could move the control off 21 points, because an AppKit control
/// inside a menu style sizes itself from its own metrics and ignores both.
///
/// Here the height is simply the height it is given.
/// Cast sort, as the same glass circle the scene filter uses.
///
/// Tinted when the list is not in its own order — Alphabetical is a way of
/// looking, and the accent is how the scene filter already says so.
private struct CastSortButton: NSViewRepresentable {
    @Binding var sort: CastListSort

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.title = ""
        button.bezelStyle = .glass
        button.borderShape = .circle
        button.isBordered = true
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.present(_:))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        let symbol = NSImage(
            systemSymbolName: "line.3.horizontal.decrease",
            accessibilityDescription: "Sort cast"
        )
        button.image = symbol?.withSymbolConfiguration(
            .init(pointSize: 12, weight: .medium)
        )
        button.contentTintColor = sort == .lead ? nil : .controlAccentColor
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: CastSortButton

        init(parent: CastSortButton) { self.parent = parent }

        @objc func present(_ sender: NSButton) {
            let menu = NSMenu()
            for option in CastListSort.allCases {
                menu.addItem(item(titled: option.title, for: option))
            }
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.maxY + 4),
                in: sender
            )
        }

        private func item(titled title: String, for option: CastListSort) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = parent.sort == option ? .on : .off
            return item
        }

        @objc private func choose(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String,
                  let option = CastListSort(rawValue: raw) else { return }
            parent.sort = option
        }
    }
}

/// Whose notes — the Notes tab's filter, built the way the other two are.
private struct NoteAuthorButton: NSViewRepresentable {
    @Binding var author: String?
    let authors: [String]

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.title = ""
        button.bezelStyle = .glass
        button.borderShape = .circle
        button.isBordered = true
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.present(_:))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        let symbol = NSImage(
            systemSymbolName: "line.3.horizontal.decrease",
            accessibilityDescription: "Filter notes"
        )
        button.image = symbol?.withSymbolConfiguration(
            .init(pointSize: 12, weight: .medium)
        )
        button.contentTintColor = author == nil ? nil : .controlAccentColor
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: NoteAuthorButton

        init(parent: NoteAuthorButton) { self.parent = parent }

        @objc func present(_ sender: NSButton) {
            let menu = NSMenu()
            menu.addItem(item(titled: "All Notes", for: nil))
            menu.addItem(.separator())
            for name in parent.authors { menu.addItem(item(titled: name, for: name)) }
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.maxY + 4),
                in: sender
            )
        }

        private func item(titled title: String, for name: String?) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            item.state = parent.author == name ? .on : .off
            return item
        }

        @objc private func choose(_ sender: NSMenuItem) {
            parent.author = sender.representedObject as? String
        }
    }
}

private struct SceneSettingButton: NSViewRepresentable {
    @Binding var setting: SceneSetting?

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.title = ""
        button.bezelStyle = .glass
        button.borderShape = .circle
        button.isBordered = true
        button.imagePosition = .imageOnly
        button.target = context.coordinator
        button.action = #selector(Coordinator.present(_:))
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        let symbol = NSImage(
            systemSymbolName: "line.3.horizontal.decrease",
            accessibilityDescription: "Filter scenes"
        )
        // Stated at the weight the toolbar's own glyphs are drawn at, so the
        // three lines carry the same ink as the chevron beside them.
        button.image = symbol?.withSymbolConfiguration(
            .init(pointSize: 12, weight: .medium)
        )
        // Filtering is said in colour, the accent the chosen row already
        // wears. `contentTintColor` nil hands the glyph back to the system.
        button.contentTintColor = setting == nil ? nil : .controlAccentColor
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    final class Coordinator: NSObject {
        var parent: SceneSettingButton

        init(parent: SceneSettingButton) { self.parent = parent }

        /// Built fresh each time rather than kept, so the ticks are right
        /// without anything having to remember to update them.
        @objc func present(_ sender: NSButton) {
            let menu = NSMenu()
            menu.addItem(item(titled: "All Scenes", for: nil))
            menu.addItem(.separator())
            for setting in SceneSetting.allCases {
                menu.addItem(item(titled: setting.title, for: setting))
            }
            // Under the button rather than at the pointer: the menu belongs to
            // the control, and a menu that opens where the mouse happened to
            // be reads as a context menu for the list behind it.
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.maxY + 4),
                in: sender
            )
        }

        private func item(titled title: String, for setting: SceneSetting?) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = setting
            item.state = parent.setting == setting ? .on : .off
            if let setting {
                item.image = NSImage(systemSymbolName: setting.symbol, accessibilityDescription: nil)
            }
            return item
        }

        @objc private func choose(_ sender: NSMenuItem) {
            parent.setting = sender.representedObject as? SceneSetting
        }
    }
}

private struct SceneSearchField: NSViewRepresentable {
    @Binding var text: String
    var prompt: String
    var focusToken: Int
    var onSubmit: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = prompt
        field.delegate = context.coordinator
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.focusToken != focusToken {
            context.coordinator.focusToken = focusToken
            field.window?.makeFirstResponder(field)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: SceneSearchField
        /// The token the field last acted on, so a rebuilt view does not take
        /// focus from the page on its first update.
        var focusToken: Int

        init(parent: SceneSearchField) {
            self.parent = parent
            self.focusToken = parent.focusToken
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.onSubmit()
            return true
        }
    }
}

/// The Scenes/Cast switch: a recessed groove and one raised chip.
///
/// Find My's scope bar is the reference. It is two appearances, not one: in
/// dark the chip is a wafer slightly lighter than the groove, in light an
/// opaque white capsule, and in both every label is the same weight and the
/// chip alone says which tab is selected.
///
/// `NSSegmentedControl` cannot be that chip — its selected segment is
/// accent-tinted whenever the window is key. `NSGlassEffectView` can,
/// because it is the only glass here with a `tintColor`, which tints the
/// material instead of covering it. The numbers behind both claims are in
/// MACOS-EXECUTION under "Scenes/Cast scope bar"; they are not repeated
/// here.
///
/// This re-implements a segmented control, which §7 otherwise rules out.
/// The justification is only that no system control renders the reference,
/// so the cost is this file owning selection, layout and motion.
private struct MacTabSwitch: NSViewRepresentable {
    /// Matches the reference's bar. The chip insets 3pt inside it.
    static let height: CGFloat = 28

    @Binding var tab: StoryPanel.Tab

    func makeNSView(context: Context) -> MacScopeBar {
        let bar = MacScopeBar()
        bar.tab = tab
        bar.onChange = { context.coordinator.tab.wrappedValue = $0 }
        return bar
    }

    func updateNSView(_ bar: MacScopeBar, context: Context) {
        bar.onChange = { context.coordinator.tab.wrappedValue = $0 }
        if bar.tab != tab { bar.tab = tab }
    }

    func makeCoordinator() -> Coordinator { Coordinator(tab: $tab) }

    final class Coordinator: NSObject {
        let tab: Binding<StoryPanel.Tab>
        init(tab: Binding<StoryPanel.Tab>) { self.tab = tab }
    }
}

/// Recessed groove, labels that stay put, one glass chip that slides.
private final class MacScopeBar: NSView {
    var onChange: ((StoryPanel.Tab) -> Void)?

    var tab: StoryPanel.Tab = .scenes {
        didSet {
            guard oldValue != tab else { return }
            moveChip(animated: window != nil)
            applyLabelColors()
            setAccessibilityValue(tab.rawValue)
        }
    }

    /// The chip insets this far inside the groove, and grows by the same
    /// amount on press so the lift clears the channel.
    private static let inset: CGFloat = 3

    private let track = NSView()
    private let container = NSGlassEffectContainerView()
    /// The container sizes and owns its `contentView`, so the chip cannot BE
    /// it — it has to be a descendant, or the container stretches it to fill
    /// the bar and disappears.
    private let glassHost = NSView()
    private let chip = NSGlassEffectView()
    private var labels: [NSTextField] = []
    private var isPressed = false
    private var isAnimating = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // The lift draws outside these bounds; clipping is how it was lost.
        layer?.masksToBounds = false
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Story")
        setAccessibilityValue(tab.rawValue)

        track.wantsLayer = true
        track.layer?.masksToBounds = true
        addSubview(track)

        chip.style = .regular
        glassHost.wantsLayer = true
        glassHost.layer?.masksToBounds = false
        glassHost.addSubview(chip)
        container.contentView = glassHost
        container.wantsLayer = true
        container.layer?.masksToBounds = false
        addSubview(container)

        for tab in StoryPanel.Tab.allCases {
            let label = NSTextField(labelWithString: tab.rawValue)
            label.alignment = .center
            label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize + 1, weight: .medium)
            label.isEnabled = false
            label.isSelectable = false
            label.drawsBackground = false
            label.isBezeled = false
            labels.append(label)
            addSubview(label)
        }
        applyTrackFill()
        applyLabelColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: MacTabSwitch.height)
    }

    override var fittingSize: NSSize { NSSize(width: 200, height: MacTabSwitch.height) }

    /// Every subview here is decoration — the groove, the glass and the
    /// labels. If any of them answered a hit the control would have dead
    /// zones, which is exactly what made the first version feel broken.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTrackFill()
        applyLabelColors()
    }

    override func layout() {
        super.layout()
        track.frame = bounds
        track.layer?.cornerRadius = bounds.height / 2
        container.frame = bounds
        glassHost.frame = bounds
        let cell = bounds.width / CGFloat(max(labels.count, 1))
        for (index, label) in labels.enumerated() {
            label.frame = NSRect(
                x: CGFloat(index) * cell,
                y: (bounds.height - 16) / 2,
                width: cell,
                height: 16
            )
        }
        // A resize must not fight a slide that is already running.
        if !isAnimating { moveChip(animated: false) }
    }

    // MARK: - Interaction

    /// Press lifts, release commits. Selecting on mouse-up is both what the
    /// reference does and why the motion reads as one gesture: the earlier
    /// version lifted and slid from the same `mouseDown`, so two animations
    /// ran on one view at once.
    override func mouseDown(with event: NSEvent) {
        isPressed = true
        moveChip(animated: true)
    }

    override func mouseUp(with event: NSEvent) {
        isPressed = false
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            select(at: point)
        }
        moveChip(animated: true)
    }

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let key = event.charactersIgnoringModifiers?.unicodeScalars.first else {
            return super.keyDown(with: event)
        }
        switch Int(key.value) {
        case NSLeftArrowFunctionKey: step(-1)
        case NSRightArrowFunctionKey: step(1)
        default: super.keyDown(with: event)
        }
    }

    private func step(_ delta: Int) {
        let all = StoryPanel.Tab.allCases
        guard let current = all.firstIndex(of: tab) else { return }
        let next = min(all.count - 1, max(0, current + delta))
        guard next != current else { return }
        tab = all[next]
        onChange?(all[next])
    }

    private func select(at point: NSPoint) {
        let all = StoryPanel.Tab.allCases
        guard bounds.width > 1, !all.isEmpty else { return }
        let index = min(all.count - 1, max(0, Int(point.x / (bounds.width / CGFloat(all.count)))))
        guard all[index] != tab else { return }
        tab = all[index]
        onChange?(all[index])
    }

    // MARK: - The chip

    /// Where the chip sits. `container` is exactly `bounds`, so this needs no
    /// coordinate translation — the earlier version offset by twice a lift
    /// constant and was impossible to reason about.
    private func chipFrame() -> NSRect {
        let all = StoryPanel.Tab.allCases
        let cell = bounds.width / CGFloat(max(all.count, 1))
        let index = CGFloat(all.firstIndex(of: tab) ?? 0)
        let seat = NSRect(
            x: index * cell + Self.inset,
            y: Self.inset,
            width: cell - Self.inset * 2,
            height: bounds.height - Self.inset * 2
        )
        return isPressed ? seat.insetBy(dx: -Self.inset, dy: -Self.inset) : seat
    }

    private func moveChip(animated: Bool) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let frame = chipFrame()
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animated, !reduce, window != nil else {
            chip.frame = frame
            chip.cornerRadius = frame.height / 2
            return
        }
        isAnimating = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)
            context.allowsImplicitAnimation = true
            chip.animator().frame = frame
            chip.cornerRadius = frame.height / 2
        }, completionHandler: { [weak self] in
            self?.isAnimating = false
        })
    }

    // MARK: - Appearance

    private var isDark: Bool {
        effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private func applyTrackFill() {
        track.layer?.backgroundColor = isDark
            ? NSColor.black.withAlphaComponent(0.22).cgColor
            : NSColor.black.withAlphaComponent(0.05).cgColor
        // Tinting the material is not painting over it: the rim and the
        // refraction survive, which `bezelColor` destroyed.
        chip.tintColor = isDark
            ? NSColor.white.withAlphaComponent(0.16)
            : NSColor.white
    }

    private func applyLabelColors() {
        for (index, label) in labels.enumerated() {
            let selected = StoryPanel.Tab.allCases[index] == tab
            label.textColor = selected ? .labelColor : .secondaryLabelColor
        }
    }
}

#endif
