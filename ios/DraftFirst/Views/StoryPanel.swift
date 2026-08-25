import SwiftUI

/// A compact view of the screenplay's structure — scenes and cast. The way
/// home is the chrome's back button; this panel is structure, not navigation.
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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // The Scenes/Cast switch is a full-width row of its own,
                // pinned between the bar and the list — the App Store
                // idiom. Never a list row (the grouped style wraps it in a
                // card), never squeezed between bar buttons.
                Picker("Story", selection: $tab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

                List {
                    // The segment IS the label — no section header
                    // repeating it underneath.
                    Section {
                        if tab == .scenes {
                            sceneRows
                        } else {
                            castRows
                        }
                    } footer: {
                        // Glanceable, tab-aware context: document health on
                        // the first line, then the texture of whichever list
                        // is showing — structure for scenes, voice for cast.
                        VStack(alignment: .leading, spacing: 3) {
                            Text(statsSummary)
                            if !tabContext.isEmpty {
                                Text(tabContext)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                // Rows are content, not hyperlinks: keep the whole list
                // monochrome so blue is reserved for the system's own chrome.
                .tint(.primary)
            }
            .navigationTitle("Navigator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

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

    /// Voice at a glance: cast size, cue volume, and who carries the
    /// dialogue — hidden while a one-voice script would only state the
    /// obvious.
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

    @ViewBuilder
    private var sceneRows: some View {
        if editor.scenes.isEmpty {
            emptyRow(
                "No Scenes Yet",
                detail: "Start a line with INT. or EXT. to build the navigator.",
                symbol: "film.stack"
            )
        } else {
            ForEach(editor.scenes) { scene in
                Button {
                    editor.jump(to: scene.id)
                    dismiss()
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(scene.number)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 24, alignment: .trailing)
                        Text(scene.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                    }
                }
                .accessibilityHint("Moves the insertion point to this scene")
            }
        }
    }

    @ViewBuilder
    private var castRows: some View {
        if editor.cast.isEmpty {
            emptyRow(
                "No Cast Yet",
                detail: "Character cues appear here automatically as you write.",
                symbol: "person.2"
            )
        } else {
            ForEach(editor.cast) { person in
                HStack {
                    Label(person.name, systemImage: "person.crop.circle.fill")
                        .font(.body.weight(.medium))
                    Spacer()
                    Text("\(person.cues) \(person.cues == 1 ? "cue" : "cues")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func emptyRow(_ title: String, detail: String, symbol: String) -> some View {
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
