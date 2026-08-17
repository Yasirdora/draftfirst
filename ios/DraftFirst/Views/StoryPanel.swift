import SwiftUI

/// A compact view of the screenplay's structure — scenes and cast. The way
/// home is the chrome's back button; this panel is structure, not navigation.
struct StoryPanel: View {
    let editor: EditorState

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .scenes

    enum Tab: String, CaseIterable, Identifiable {
        case scenes = "Scenes"
        case cast = "Cast"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Story", selection: $tab) {
                        ForEach(Tab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }

                Section {
                    if tab == .scenes {
                        sceneRows
                    } else {
                        castRows
                    }
                } header: {
                    Text(tab.rawValue)
                } footer: {
                    // Document health, demoted to a footnote: present for the
                    // writer who wants it, never in the way of the one who
                    // does not.
                    Text(statsSummary)
                        .padding(.top, 4)
                }
            }
            // Rows are content, not hyperlinks: keep the whole list
            // monochrome so blue is reserved for the system's own chrome.
            .tint(.primary)
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
