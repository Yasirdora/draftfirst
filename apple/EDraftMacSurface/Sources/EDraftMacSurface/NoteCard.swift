import EDraftCore
import SwiftUI

/// The card a note opens into.
///
/// Pages' comment card, minus the half of it that makes a comment a
/// conversation. There is no Reply and no thread: a note is something a
/// writer leaves for themself in the margin, and Final Draft, Fountain and
/// the `.draft` file all agree — none of the three has anywhere to put a
/// second voice, an author or a date, and a field with nowhere to be stored
/// is a field that disappears the first time the file is sent to someone.
///
/// So: the words, a way to be rid of one beside the title, and at the foot
/// either the way through the rest of them or — while the writer is in the
/// middle of changing this one — the way to be finished with it. The counter
/// steps aside for Done rather than sitting beside it: mid-sentence, where
/// this note falls among the others is not what the writer is thinking about.
struct NoteCard: View {
    let note: ScriptAside
    /// Where this note falls among all of them, for the counter and to grey
    /// out an arrow at either end.
    let position: Int
    let total: Int

    /// Every keystroke, told to whoever is holding the card open.
    ///
    /// Not a commit — the model is written by the surface that opened this,
    /// on Done or when the card closes. `onDisappear` was the obvious place
    /// for the latter and does not reliably run when an `NSPopover` closes:
    /// measured, a note edited and dismissed kept its old text on disk.
    let onEdit: (String) -> Void
    /// Write it now, without closing the card.
    let onDone: () -> Void
    let onDelete: () -> Void
    let onMove: (Int) -> Void

    @State private var text: String
    /// What the model last took. Not `note.text`: that is the note as it was
    /// when the card opened, so comparing against it would leave Done showing
    /// forever after the first commit.
    @State private var committed: String
    @FocusState private var writing: Bool

    init(
        note: ScriptAside,
        position: Int,
        total: Int,
        onEdit: @escaping (String) -> Void,
        onDone: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onMove: @escaping (Int) -> Void
    ) {
        self.note = note
        self.position = position
        self.total = total
        self.onEdit = onEdit
        self.onDone = onDone
        self.onDelete = onDelete
        self.onMove = onMove
        _text = State(initialValue: note.text)
        _committed = State(initialValue: note.text)
    }

    private var isEditing: Bool { text != committed }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            // The note itself. A `TextEditor` rather than a `TextField`,
            // because a note is a paragraph — "she has already said this in
            // scene 4, and it lands better there" is one sentence too many
            // for a single line that scrolls sideways.
            //
            // No placeholder. One sat here reading "Note", which the title
            // above it already says, and it could not be made to line up with
            // the caret: a `TextEditor`'s text origin is its own — container
            // inset plus line-fragment padding — and an overlay can only
            // guess at it. The guess was visibly out by a few points in both
            // directions. An empty card with a caret in it is not ambiguous.
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .focused($writing)
                .frame(minHeight: 54, maxHeight: 140)
            footer
        }
        .padding(12)
        .frame(width: 260)
        .onChange(of: text) { _, edited in onEdit(edited) }
        .onAppear { writing = true }
    }

    /// The title, and the one destructive thing, kept apart from everything
    /// the writer does while they are working.
    private var header: some View {
        HStack(spacing: 8) {
            Label("Note", systemImage: "bubble.fill")
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(nsColor: .screenplayNoteTint))

            Spacer(minLength: 8)

            Button(role: .destructive) { onDelete() } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Delete note")
            .accessibilityLabel("Delete note")
        }
    }

    /// The foot of the card: Done while there is something to finish, and
    /// otherwise the way through the other notes.
    private var footer: some View {
        HStack(spacing: 2) {
            Spacer(minLength: 0)
            if isEditing {
                Button("Done") {
                    committed = text
                    onDone()
                    // Focus leaves with the writing: the card settles back to
                    // the counter, which is the point of the swap.
                    writing = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            } else if total > 1 {
                Text("\(position) of \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button { onMove(-1) } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(position <= 1)
                .help("Previous note")

                Button { onMove(1) } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(position >= total)
                .help("Next note")
            }
        }
        .buttonStyle(.borderless)
        .imageScale(.medium)
    }
}
