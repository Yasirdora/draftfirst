import SwiftUI

/// A compact view of the screenplay's structure — scenes and cast. The way
/// home is the chrome's back button; this panel is structure, not navigation.
///
/// The two tabs answer different questions and so behave differently. A scene
/// is a place: its row goes there. A character is not a place — a lead speaks
/// two hundred times, and "go to the character" has no honest destination — so
/// its row opens the character's own page instead, where every line is a real
/// place and renaming can show what it would rewrite.
struct StoryPanel: View {
    let editor: EditorState

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab

    init(editor: EditorState, initialTab: Tab = .scenes) {
        self.editor = editor
        _tab = State(initialValue: initialTab)
    }

    enum Tab: String, CaseIterable, Identifiable {
        case scenes = "Scenes"
        case cast = "Cast"

        var id: String { rawValue }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                tabPicker
                list
            }
            .navigationTitle("Navigator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // Pushed by name rather than by row, so a rename performed on the
            // character's page does not pull the page out from under itself
            // when the row it came from stops existing.
            .navigationDestination(for: String.self) { name in
                CharacterThreadView(editor: editor, name: name) { element in
                    editor.jump(to: element)
                    dismiss()
                }
            }
        }
    }

    /// The Scenes/Cast switch is a full-width row of its own, pinned between
    /// the bar and the list — the App Store idiom. Never a list row (the
    /// grouped style wraps it in a card), never squeezed between bar buttons.
    private var tabPicker: some View {
        Picker("Story", selection: $tab) {
            ForEach(Tab.allCases) { tab in
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
            if tab == .scenes {
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
        // Rows are content, not hyperlinks: keep the whole list monochrome so
        // blue is reserved for the system's own chrome.
        .tint(.primary)
    }

    // MARK: - Rows

    @ViewBuilder
    private var rows: some View {
        switch tab {
        case .scenes:
            if editor.scenes.isEmpty {
                EmptyListRow(
                    title: "No Scenes Yet",
                    detail: "Start a line with INT. or EXT. to build the navigator.",
                    symbol: "film.stack"
                )
            } else {
                ForEach(editor.scenes) { scene in
                    SceneListRow(scene: scene) {
                        editor.jump(to: scene.id)
                        dismiss()
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
                    CastListRow(person: person)
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

// MARK: - Scene row

/// A scene, its address, and where to turn to find it.
private struct SceneListRow: View {
    let scene: SceneRow
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // A production number is not a digit count: "12A" and "112"
                // both have to fit without truncating, so the column grows to
                // the widest rather than being pinned to two figures.
                Text(scene.label)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 30, alignment: .trailing)

                Text(scene.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                // Where it falls, at the paper size currently set — read out
                // of the same pagination the PDF prints, so the two can never
                // disagree. A scene number says which scene; a page number
                // says where to turn.
                if let page = scene.page {
                    Spacer(minLength: 8)
                    Text(page.formatted())
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Moves the insertion point to this scene")
    }

    private var accessibilityLabel: String {
        guard let page = scene.page else { return "Scene \(scene.label), \(scene.title)" }
        return "Scene \(scene.label), \(scene.title), page \(page)"
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
private struct CastListRow: View {
    let person: CastRow

    var body: some View {
        NavigationLink(value: person.name) {
            HStack {
                // Stated, not inherited. The list's tint reaches the rows
                // present when it is applied; rows realized later — the ones
                // a writer scrolls into view — came up in the accent colour
                // instead, so a cast list read half black and half blue.
                Label(person.name, systemImage: "person.crop.circle.fill")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(person.cues) \(person.cues == 1 ? "cue" : "cues")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Empty state

private struct EmptyListRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
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

    var body: some View {
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
        .navigationBarTitleDisplayMode(.inline)
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
