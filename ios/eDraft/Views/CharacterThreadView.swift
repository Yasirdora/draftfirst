import EDraftCore
import SwiftUI

/// One character's thread through the script — every scene they speak in, and
/// what they say while they are there.
///
/// This is a reading surface, not a filtered editor. Hiding most of a document
/// while leaving it editable would let a writer type into a version of their
/// script that does not exist; the safe form of "show me only her" is a place
/// you go to read and come back from.
///
/// It answers both questions a writer asks about a character. Read down the
/// speeches and you hear whether she sounds like one person across a hundred
/// pages. Read down the headings and you see her shape in the story — where
/// she enters, how often she returns, and the stretch in the second act where
/// she disappears. Every row goes somewhere real, so noticing something and
/// fixing it are one tap apart.
///
/// Renaming lives here rather than on the cast row because this is the only
/// screen that shows what a rename would rewrite: the cue count, the mentions,
/// and the lines themselves.
struct CharacterThreadView: View {
    let editor: EditorState
    /// Moves the caret to an element and closes the Navigator behind it.
    /// Passed in because dismissing a pushed view would only pop the push.
    let open: (UUID) -> Void

    /// Who this page is about — held in state rather than read back from the
    /// cast list, because renaming from here has to leave the page standing.
    /// The moment the rename lands, the row this was pushed from is gone.
    @State private var name: String

    @State private var isRenaming = false
    @State private var draftName = ""
    /// How often the character is named outside their cues, counted when the
    /// rename opens so the writer sees the blast radius before choosing.
    @State private var mentionCount = 0

    init(editor: EditorState, name: String, open: @escaping (UUID) -> Void) {
        self.editor = editor
        self.open = open
        _name = State(initialValue: name)
    }

    private var appearances: [CharacterAppearance] { editor.appearances(of: name) }
    private var cues: Int { editor.cast.first { $0.name == name }?.cues ?? 0 }

    var body: some View {
        List {
            Section {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button(action: beginRename) {
                    Label("Rename Character", systemImage: "pencil")
                }
            }

            if appearances.isEmpty {
                Section {
                    Text("\(name) is cued but never speaks.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(appearances) { appearance in
                Section {
                    ForEach(appearance.lines) { line in
                        Button { open(line.id) } label: { SpeechRow(line: line) }
                            .accessibilityHint("Moves the insertion point to this line")
                    }
                } header: {
                    // The heading goes somewhere too: reading down her scenes
                    // and reading down her speeches are different errands, and
                    // the one that starts "where does she come in" wants the
                    // top of the scene, not her first word inside it.
                    Button { open(appearance.id) } label: {
                        SceneHeader(appearance: appearance)
                    }
                    .accessibilityHint("Moves the insertion point to this scene")
                }
            }
        }
        .tint(.primary)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Rename Character", isPresented: $isRenaming) {
            // Typed as prose, not shouted: cues uppercase themselves, and
            // action wants "Elena crosses", not "ELENA crosses".
            TextField("New name", text: $draftName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            if mentionCount > 0 {
                Button("Rename Everywhere") { rename(includingMentions: true) }
                Button("Cues Only") { rename() }
            } else {
                Button("Rename") { rename() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(renameWarning)
        }
    }

    /// Presence in one line: how much they speak, across how much of the
    /// script, and where they run from and to.
    private var summary: String {
        var facts = [
            "\(cues) \(cues == 1 ? "cue" : "cues")",
            "\(appearances.count) \(appearances.count == 1 ? "scene" : "scenes")"
        ]
        let pages = appearances.compactMap(\.page)
        if let first = pages.min(), let last = pages.max() {
            facts.append(first == last ? "page \(first)" : "pages \(first)–\(last)")
        }
        return facts.joined(separator: " · ")
    }

    // MARK: - Renaming

    private func beginRename() {
        draftName = name.capitalized
        mentionCount = editor.characterMentions(name)
        isRenaming = true
    }

    /// Renames, then follows the character rather than the name: the page
    /// stays open on the same person under what they are now called.
    private func rename(includingMentions: Bool = false) {
        let changed = editor.renameCharacter(
            name, to: draftName, includingMentions: includingMentions
        )
        guard changed > 0 else { return }
        name = EditorState.canonicalCharacterName(draftName)
    }

    /// States the blast radius before anything moves.
    ///
    /// A writer renaming MARA wants it changed everywhere and would be right
    /// to expect that. A writer renaming WILL does not want "will you come"
    /// rewritten, and no amount of pattern matching can tell the two apart —
    /// only the writer can, and only if shown the number first.
    private var renameWarning: String {
        let counted = cues == 1 ? "1 cue" : "\(cues) cues"
        let merges = editor.characterExists(draftName)
            && EditorState.canonicalCharacterName(draftName) != name
        let merge = merges ? " That name already speaks, so the two characters merge." : ""

        guard mentionCount > 0 else {
            return "Renames \(counted) for \(name).\(merge)"
        }
        let mentions = mentionCount == 1 ? "once" : "\(mentionCount) times"
        return "Renames \(counted). \(name) is also named \(mentions) in action and "
            + "dialogue.\(merge)"
    }
}

// MARK: - Scene header

/// Where a stretch of speech happens: the scene's own address, its heading,
/// and the page to turn to.
private struct SceneHeader: View {
    let appearance: CharacterAppearance

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(appearance.label)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(appearance.heading)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let page = appearance.page {
                Spacer(minLength: 8)
                Text(page.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .textCase(nil)
        .contentShape(.rect)
    }
}

// MARK: - Speech

/// A single speech, set the way the page sets it: the direction above the
/// words, quieter than them.
private struct SpeechRow: View {
    let line: SpokenLine

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let parenthetical = line.parenthetical {
                Text(parenthetical)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
            Text(line.text)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
