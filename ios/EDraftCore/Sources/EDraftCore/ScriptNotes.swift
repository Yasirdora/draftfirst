import Foundation

/// A note the writer left in the script, and where it belongs.
///
/// Final Draft calls it a Note; Fountain writes it `[[like this]]`. Both mean
/// the same thing — a line in the script that does not print — and neither
/// gives it an author, a colour or a timestamp. Neither does this: a `.draft`
/// is Fountain, and a field with nowhere honest to be stored is a field that
/// quietly disappears the first time the writer sends the file to someone.
public nonisolated struct ScriptNote: Identifiable, Equatable, Sendable {
    /// The note element's own id, carried through so editing the note edits
    /// the element rather than replacing it.
    public let id: UUID
    public var text: String
    /// The element the note sits in front of — `nil` when it trails the
    /// script, which is where a note written after the last line goes.
    public let anchor: UUID?

    public init(id: UUID, text: String, anchor: UUID?) {
        self.id = id
        self.text = text
        self.anchor = anchor
    }
}

/// The document, split into the part the page sets and the notes beside it.
///
/// A note is in the document — it saves, it exports, it round-trips — but it
/// is not on the page. Leaving it in the text view printed a writer's private
/// aside as though it were a stage direction, and counted it toward the page
/// count that a production schedules against.
///
/// The split is anchored by element id rather than by matching the text of
/// the line that follows, which is what the web engine's `structural.ts` has
/// to do: the web editor's stream has no stable identity, and ours does.
/// An id cannot rot when the writer retypes the heading above their note.
public nonisolated enum ScriptNotes {

    /// The elements the page sets, and the notes lifted out of them.
    public nonisolated struct Split: Equatable, Sendable {
        public var page: [ScriptElement]
        public var notes: [ScriptNote]

        public init(page: [ScriptElement], notes: [ScriptNote]) {
            self.page = page
            self.notes = notes
        }
    }

    /// Lifts the notes out of a document.
    ///
    /// Only notes. Sections, synopses and page breaks are non-printing too,
    /// and they stay on the page until they have a place of their own to be —
    /// a writer who cannot see their own act breaks has lost more than they
    /// gained.
    public static func split(_ elements: [ScriptElement]) -> Split {
        var page: [ScriptElement] = []
        var notes: [ScriptNote] = []
        var pending: [(id: UUID, text: String)] = []

        for element in elements {
            guard element.type == .note else {
                page.append(element)
                notes.append(
                    contentsOf: pending.map { ScriptNote(id: $0.id, text: $0.text, anchor: element.id) }
                )
                pending.removeAll(keepingCapacity: true)
                continue
            }
            pending.append((element.id, element.text))
        }
        // Whatever is still pending followed the last line of the script.
        notes.append(contentsOf: pending.map { ScriptNote(id: $0.id, text: $0.text, anchor: nil) })
        return Split(page: page, notes: notes)
    }

    /// Puts the notes back, in front of the elements they belong to.
    ///
    /// A note whose anchor is gone — the writer deleted the line it was
    /// about — is not deleted with it. It goes to the end of the script,
    /// where the writer can see it and decide. Losing someone's note because
    /// they rewrote the scene it was about is not a trade the app gets to make
    /// on their behalf.
    public static func merge(page: [ScriptElement], notes: [ScriptNote]) -> [ScriptElement] {
        guard !notes.isEmpty else { return page }

        var byAnchor: [UUID: [ScriptNote]] = [:]
        var trailing: [ScriptNote] = []
        for note in notes {
            guard let anchor = note.anchor else {
                trailing.append(note)
                continue
            }
            byAnchor[anchor, default: []].append(note)
        }

        var out: [ScriptElement] = []
        out.reserveCapacity(page.count + notes.count)
        var placed = Set<UUID>()
        for element in page {
            for note in byAnchor[element.id] ?? [] {
                out.append(paragraph(for: note))
                placed.insert(note.id)
            }
            out.append(element)
        }
        for note in notes where !placed.contains(note.id) && note.anchor != nil {
            out.append(paragraph(for: note))
        }
        out.append(contentsOf: trailing.map(paragraph(for:)))
        return out
    }

    private static func paragraph(for note: ScriptNote) -> ScriptElement {
        ScriptElement(id: note.id, type: .note, text: note.text)
    }
}
