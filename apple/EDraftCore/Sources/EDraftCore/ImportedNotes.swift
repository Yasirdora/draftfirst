import EDraftEngine
import Foundation

/// A note that arrived in a Final Draft file — a ScriptNote — shown beside the
/// writer's own and never written.
///
/// Final Draft keeps these outside the script, in a `<ScriptNotes>` container
/// that points back into it with a character Range, and they carry what a
/// Fountain `[[note]]` has nowhere to put: who wrote it, a title, a date. So
/// they are not `ScriptAside`s. An aside is part of the document — it saves
/// into Fountain, it exports — and a ScriptNote folded into one would be
/// written into the file a second time, beside the original the save already
/// keeps byte for byte. These stay a reading of the file the document was
/// opened from: shown, never edited, never saved.
public nonisolated struct ImportedNote: Identifiable, Equatable, Sendable {
    /// Minted when the file is read. Stable for as long as the document is
    /// open, which is as long as anything refers to it.
    public let id: UUID
    /// `WriterName`, as the file gives it. Nil when the file names nobody —
    /// and then nobody is inferred: the note keeps the yellow an unclaimed
    /// note has always had.
    public let author: String?
    /// `Name`: a title, or a thread's "Re: …". Nil when the file leaves it empty.
    public let title: String?
    /// `Type` — free text Final Draft calls a type ("Producer", "Alt Scenes").
    /// A kind of note, not a role.
    public let category: String?
    /// `DateTime`, read as the local time Final Draft wrote it in.
    public let created: Date?
    /// The note's words, paragraph by paragraph.
    public let text: String
    /// The line it is about. Nil when the file's Range lands on no line this
    /// document can vouch for — see `ImportedNotes.resolve`.
    public let anchor: UUID?

    public init(
        id: UUID = UUID(), author: String? = nil, title: String? = nil,
        category: String? = nil, created: Date? = nil, text: String, anchor: UUID?
    ) {
        self.id = id
        self.author = author
        self.title = title
        self.category = category
        self.created = created
        self.text = text
        self.anchor = anchor
    }
}

public nonisolated enum ImportedNotes {

    /// Each ScriptNote, placed on a line of the document as it stands at open.
    ///
    /// The engine says where a note's Range lands as an index into the
    /// elements it imported; the editor's lines are the same file carried
    /// through Fountain, with identities of their own. Measured on a real
    /// feature, the two agree index for index — so a note takes the identity
    /// of the element at its index, once, and keeps it through every edit
    /// that follows.
    ///
    /// Only when the texts agree. A file Fountain cannot carry line for line
    /// would shift every index after the first disagreement, and a note put on
    /// the wrong line says something about a moment nobody commented on. So a
    /// disagreement leaves the note without a line — listed, and honest about
    /// it — rather than guessed. A Range on a line that does not print moves
    /// to the next line that does, as a writer's own note does.
    public static func resolve(
        _ notes: [Fdx.ScriptNote],
        imported: [EDraftEngine.ScreenplayElement],
        document: [ScriptElement]
    ) -> [ImportedNote] {
        notes.map { note in
            ImportedNote(
                author: note.author,
                title: note.title,
                category: note.category,
                created: date(note.created),
                text: note.text,
                anchor: anchor(of: note, imported: imported, document: document)
            )
        }
    }

    private static func anchor(
        of note: Fdx.ScriptNote,
        imported: [EDraftEngine.ScreenplayElement],
        document: [ScriptElement]
    ) -> UUID? {
        guard let index = note.anchor?.start.element,
              imported.indices.contains(index), document.indices.contains(index) else { return nil }
        let theirs = imported[index]
        guard Normalize.canonicalCasing(kind: theirs.type, text: theirs.text) == document[index].text
        else { return nil }
        return document[index...].first { $0.type.isPrinting }?.id
    }

    /// Everyone a document's notes may be attributed to: the names the
    /// writer's own notes earned, and every writer the file names.
    ///
    /// A `WriterName` needs no second note to count. The two-note rule is
    /// there to stop a one-off `TODO:` being taken for a person; a WriterName
    /// is a person by the file's own word. One person is one name however it
    /// is cased, and the file's spelling wins — it is the one Final Draft
    /// shows — so `[[Joe Jarvis: …]]` written here and a note Joe Jarvis left
    /// in Final Draft share a single colour.
    public static func roster(_ own: Set<String>, adding notes: [ImportedNote]) -> Set<String> {
        var byKey: [String: String] = [:]
        for author in notes.compactMap(\.author) where byKey[author.lowercased()] == nil {
            byKey[author.lowercased()] = author
        }
        for name in own where byKey[name.lowercased()] == nil {
            byKey[name.lowercased()] = name
        }
        return Set(byKey.values)
    }

    /// The roster's spelling of a note's author, so its colour slot is found.
    public static func author(of note: ImportedNote, in roster: Set<String>) -> String? {
        guard let author = note.author else { return nil }
        return roster.first { $0.lowercased() == author.lowercased() }
    }

    /// Final Draft's `20201213T214959`: no zone, so the local one.
    static func date(_ stamp: String?) -> Date? {
        guard let stamp else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss"
        return formatter.date(from: stamp)
    }
}
