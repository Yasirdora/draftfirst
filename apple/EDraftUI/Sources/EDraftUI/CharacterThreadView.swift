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
public struct CharacterThreadView: View {
    let editor: EditorState
    /// Moves the caret to an element and closes the Navigator behind it.
    /// Passed in because dismissing a pushed view would only pop the push.
    let open: (UUID) -> Void
    private let chrome: Chrome

    /// Who this page is about — held in state rather than read back from the
    /// cast list, because renaming from here has to leave the page standing.
    /// The moment the rename lands, the row this was pushed from is gone.
    @State private var name: String

    @State private var isRenaming = false
    @State private var draftName = ""
    /// How often the character is named outside their cues, counted when the
    /// rename opens so the writer sees the blast radius before choosing.
    @State private var mentionCount = 0

    public init(
        editor: EditorState,
        name: String,
        chrome: Chrome = .pushed,
        open: @escaping (UUID) -> Void
    ) {
        self.editor = editor
        self.open = open
        self.chrome = chrome
        _name = State(initialValue: name)
    }

    /// How the thread is framed, which is the only thing that differs between
    /// the two surfaces.
    ///
    /// The phone pushes it, so the name is a navigation title and Rename is a
    /// row in the list. The Mac shows it as a column beside the cast, so the
    /// name is a header and Rename lives under the `…` at its end — where
    /// Notes and Mail put the actions for the thing a column is showing.
    /// Same thread either way; a second copy of it would be two threads.
    public enum Chrome: Sendable { case pushed, panel }

    private var appearances: [CharacterAppearance] { editor.appearances(of: name) }
    private var cues: Int { editor.cast.first { $0.name == name }?.cues ?? 0 }

    public var body: some View {
        VStack(spacing: 0) {
            if chrome == .panel { panelHeader }
            thread
        }
    }

    /// The column's own head: who this is, and the actions for them.
    private var panelHeader: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.headline)
            Spacer(minLength: 8)
            Menu {
                Button("Rename Character…", action: beginRename)
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("Character actions")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var thread: some View {
        List {
            Section {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if chrome == .pushed {
                    Button(action: beginRename) {
                        Label("Rename Character", systemImage: "pencil")
                    }
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
        .navigationTitle(chrome == .pushed ? name : "")
        .compactTitle()
        .alert("Rename Character", isPresented: $isRenaming) {
            // Typed as prose, not shouted: cues uppercase themselves, and
            // action wants "Elena crosses", not "ELENA crosses".
            TextField("New name", text: $draftName)
                .titleCasedInput()
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
        CharacterRename.warning(
            name: name,
            cues: cues,
            mentions: mentionCount,
            merges: editor.characterExists(draftName)
                && EditorState.canonicalCharacterName(draftName) != name
        )
    }
}

// MARK: - Scene header

/// Where a stretch of speech happens: the scene's own address, its heading,
/// and the page to turn to.
private struct SceneHeader: View {
    let appearance: CharacterAppearance

    public var body: some View {
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

    public var body: some View {
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
