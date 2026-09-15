import EDraftCore
import SwiftUI

/// The card a line's notes open into.
///
/// One card per line, holding every note left on that line, because that is
/// how a writer thinks about them — "what did I say about this moment", not
/// "show me note two of three". The first version put a mark in the margin
/// for each note and paged between them; three notes on one line became three
/// marks walking toward the edge of the sheet, and their words were readable
/// only one at a time.
///
/// Pages' comment card, minus the half that makes a comment a conversation.
/// No Reply, no author, no date: none of Fountain, Final Draft or the `.draft`
/// has anywhere to put them, and a field with nowhere honest to be stored is
/// one that disappears the first time the file is sent to someone.
struct NoteCard: View {
    let notes: [ScriptAside]
    /// Whose each note is, as a colour slot — the same slots the margin marks
    /// use, so the card explains the colour the writer just clicked.
    var authorSlots: [UUID: Int] = [:]
    /// The note the caret belongs in, or `nil` for a card being read rather
    /// than written in. Opening a line's notes to read them must not put the
    /// cursor in one of them; adding a note must put it in *that* note, which
    /// is the newest and not the first.
    let focused: UUID?

    /// A keystroke in one of the notes. Not a commit — the surface writes
    /// them when the card closes, or when Done is pressed.
    let onEdit: (UUID, String) -> Void
    let onDone: () -> Void
    let onDelete: (UUID) -> Void
    /// Another note on the same line.
    let onAdd: () -> Void

    /// What each note reads now, and what the model last took. Kept apart so
    /// Done knows whether there is anything to finish.
    @State private var drafts: [UUID: String] = [:]
    @State private var committed: [UUID: String] = [:]
    /// Which notes have more in them than their box shows.
    @State private var overflowing: Set<UUID> = []

    private var isEditing: Bool { drafts != committed }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The notes scroll as a group once there are more than the card
            // should stand. Capping the card is not only tidiness: a popover
            // taller than the room beside its mark is slid up the screen by
            // AppKit, and its arrow then sits at the very end of the edge,
            // cutting into the corner — which is what "the bubble looks
            // broken" was.
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(notes.enumerated()), id: \.element.id) { index, note in
                        if index > 0 { Divider().padding(.vertical, 8) }
                        row(note)
                    }
                }
            }
            .frame(maxHeight: Self.tallestStack)
            footer
        }
        .padding(12)
        .frame(width: 280)
        .onAppear(perform: seed)
        .onChange(of: notes.map(\.id)) { _, _ in seed() }
    }

    /// How tall the notes may stand before the card scrolls them.
    private static let tallestStack: CGFloat = 260

    /// One note: its words, whether there are more of them than fit, and the
    /// one thing you can do to it.
    private func row(_ note: ScriptAside) -> some View {
        HStack(alignment: .top, spacing: 6) {
            // A colour, not a name: the name is already the first thing in the
            // note's own words, and saying it twice on one row would only make
            // the writer wonder which of the two they are editing.
            Circle()
                .fill(Color(nsColor: .screenplayNoteTint(slot: authorSlots[note.id])))
                .frame(width: 6, height: 6)
                .padding(.top, 9)
            NoteTextView(
                text: Binding(
                    get: { drafts[note.id] ?? note.text },
                    set: { drafts[note.id] = $0; onEdit(note.id, $0) }
                ),
                placeholder: "Add a note",
                focusesOnAppear: note.id == focused,
                onOverflowChange: { overflows in
                    if overflows { overflowing.insert(note.id) }
                    else { overflowing.remove(note.id) }
                }
            )
            .frame(minHeight: 44, maxHeight: Self.tallestNote)
            // A note longer than its box fades out at the foot rather than
            // stopping mid-word, so the writer can see that it goes on.
            .overlay(alignment: .bottom) {
                if overflowing.contains(note.id) {
                    LinearGradient(
                        colors: [.clear, Color(nsColor: .windowBackgroundColor)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 18)
                    .allowsHitTesting(false)
                }
            }

            Button(role: .destructive) { onDelete(note.id) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Delete this note")
            .accessibilityLabel("Delete note")
        }
    }

    /// How tall one note may stand before it scrolls inside its own box.
    private static let tallestNote: CGFloat = 120

    /// Add on the left, finish on the right — the two directions this card
    /// goes, and never the destructive one, which belongs to a single note
    /// rather than to the card.
    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onAdd) {
                Label("Add", systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Another note on this line")

            Spacer(minLength: 8)

            if isEditing {
                Button("Done") {
                    committed = drafts
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.top, 8)
    }

    private func seed() {
        var seeded: [UUID: String] = [:]
        for note in notes { seeded[note.id] = note.text }
        drafts = seeded
        committed = seeded
    }
}
