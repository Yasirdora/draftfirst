import EDraftCore
import SwiftUI

/// A compact view of the screenplay's structure — scenes and cast. The way
/// home is the chrome's back button; this panel is structure, not navigation.
///
/// The two tabs answer different questions and so behave differently. A scene
/// is a place: its row goes there. A character is not a place — a lead speaks
/// two hundred times, and "go to the character" has no honest destination — so
/// its row opens the character's own page instead, where every line is a real
/// place and renaming can show what it would rewrite.
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
    /// Mac Find Scene (⌘L): a filter on the Scenes tab, sitting with the
    /// scope switch — Messages puts search in that same position. Off on
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
            if showsSceneFilter, tab == .scenes {
                sceneFilterField
            }
            list
        }
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

    /// The Scenes/Cast switch is a full-width row of its own, pinned between
    /// the bar and the list — the App Store idiom. Never a list row (the
    /// grouped style wraps it in a card), never squeezed between bar buttons.
    private var tabPicker: some View {
        Picker("Story", selection: $tab) {
            ForEach(StoryPanel.Tab.allCases) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
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
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        switch tab {
        case .scenes:
            let visible = SceneListFilter.included(
                editor.scenes, query: sceneQuery, setting: sceneSetting
            )
            if editor.scenes.isEmpty {
                EmptyListRow(
                    title: "No Scenes Yet",
                    detail: "Start a line with INT. or EXT. to build the navigator.",
                    symbol: "film.stack"
                )
            } else if visible.isEmpty {
                // Say which of the two narrowed it away, because the remedy
                // differs: clear the field, or widen the filter.
                EmptyListRow(
                    title: "No Matching Scenes",
                    detail: emptyFilterDetail,
                    symbol: sceneQuery.isEmpty ? "line.3.horizontal.decrease.circle" : "magnifyingglass"
                )
            } else {
                ForEach(visible) { scene in
                    SceneListRow(scene: scene, isCurrent: scene.id == editor.activeSceneID) {
                        open(scene.id)
                    }
                }
            }

        case .cast:
            if editor.cast.isEmpty {
                EmptyListRow(
                    title: "No Cast Yet",
                    detail: "Character cues appear here automatically as you write.",
                    symbol: "person.2"
                )
            } else {
                ForEach(editor.cast) { person in
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
        }
    }

    // MARK: - Footnote

    private var statsSummary: String {
        let pages = "\(editor.stats.pages) \(editor.stats.pages == 1 ? "page" : "pages")"
        let words = "\(editor.stats.words) \(editor.stats.words == 1 ? "word" : "words")"
        return [pages, editor.stats.runtime, words].joined(separator: " · ")
    }

    /// The tab-specific second line of the footnote.
    private var tabContext: String {
        tab == .scenes ? sceneContext : castContext
    }

    /// Structure at a glance: scene and location counts plus the INT/EXT
    /// texture a production reads a script by.
    private var sceneContext: String {
        let stats = editor.storyStats
        guard stats.scenes > 0 else { return "" }
        return [
            "\(stats.scenes) \(stats.scenes == 1 ? "scene" : "scenes")",
            "\(stats.locations) \(stats.locations == 1 ? "location" : "locations")",
            "\(stats.interior) INT · \(stats.exterior) EXT"
        ].joined(separator: " · ")
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

// MARK: - Scene row

/// A scene, its address, and where to turn to find it — with no opinion
/// about how it is chosen.
///
/// The Mac hands this straight to a `List(selection:)` and lets the source
/// list draw the pill, the accent and the focus ring, which is the whole of
/// what makes Finder's sidebar look like Finder's sidebar. The phone wraps it
/// in `SceneListRow` below, because a bare row in a plain list is not
/// tappable there.
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
    private var rowInk: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Color.accentColor) }
        return scene.isSecondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.foreground)
    }

    /// Spoken without the selection state: on the Mac the list says "selected"
    /// itself, and on the phone `SceneListRow` adds "current scene".
    var spokenLabel: String {
        var label = "Scene \(scene.label), \(scene.title)"
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
#endif
