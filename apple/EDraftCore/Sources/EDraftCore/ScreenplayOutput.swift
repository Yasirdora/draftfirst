import EDraftEngine
import Foundation

/// What leaves eDraft, decided in one place.
///
/// Print, PDF, Plain Text, RTF, Export ▸ Fountain and Export ▸ Final Draft
/// were each handed the page alone. The page holds none of the notes or the
/// outline, and it does not know which scenes are omitted. Every output now
/// takes this, built from the editor's whole state.
public nonisolated struct ScreenplayOutput: Sendable {

    /// The page, each omitted scene reduced to its OMITTED card. PDF, Print,
    /// Plain Text and RTF draw this (MACOS-DESIGN §3.2).
    public let printed: Screenplay

    /// Export ▸ Fountain, and the copy a PDF carries home: notes and outline
    /// in place, each omitted scene as its card alone. Fountain cannot spell
    /// an omission, so the body is not written as script.
    public let fountain: String

    /// The Fountain a .draft save publishes today. The zip container is a
    /// later change; until then an eDraft Document export is this text.
    public let document: String

    /// The editor's live script, runs included. Save and Export ▸ Final Draft
    /// write this. Fountain cannot spell a highlight, so a save that re-parsed
    /// `document` would drop one.
    let script: EDraftEngine.Screenplay

    let omissions: OmissionSpans?
    let origin: String?

    /// Export ▸ Final Draft: the bytes Save writes.
    public func finalDraft() throws -> Data {
        try ScreenplayFile.encode(script, as: .finalDraftScreenplay, origin: origin, omissions: omissions)
    }
}

extension EditorState {

    /// What every output of this document carries. `origin` is the Final Draft
    /// file the document was opened from; the document keeps it, not the editor.
    public func output(origin: String?) -> ScreenplayOutput {
        let cut = omittedScenes
        var printed = screenplay
        printed.elements = screenplay.elements.filter { !cut.contains($0) }
        let finalDraftNotes = importedNotes.map { note in
            ScriptAside(
                element: ScriptElement(
                    type: .note,
                    text: note.author.map { NoteAttribution.signed(note.text, as: $0) } ?? note.text
                ),
                anchor: note.anchor
            )
        }
        var exported = screenplay
        exported.elements = ScriptAsides.merge(page: screenplay.elements, asides: asides + finalDraftNotes)
            .filter { !cut.contains($0) }
        return ScreenplayOutput(
            printed: printed,
            fountain: Fountain.serialise(exported.engineModel),
            document: serializedSource(),
            script: documentModel,
            omissions: omissionsToWrite(),
            origin: origin
        )
    }
}
