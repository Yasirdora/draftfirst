import Foundation

/// Session-scoped memory of an element's verbatim text before a conversion
/// into an uppercase kind re-cased it.
///
/// Screenplay convention is unambiguous: scene headings, characters,
/// transitions, and shots are set in caps; action and dialogue keep the
/// writer's own casing. Converting an element should honor that convention —
/// but a naive uppercase is irreversible, and converting "MARA" back to
/// action must not strand the writer with shouting action lines.
///
/// Fountain is plain text with no element-metadata channel, so the original
/// casing can only survive inside the editing session. That covers the flow
/// that matters: an accidental conversion — or a deliberate experiment —
/// followed by converting back. The memory is consulted on every conversion:
///
/// - Converting TO an uppercase kind applies caps and remembers the verbatim
///   text. Chained conversions between uppercase kinds (action → character →
///   scene) keep the oldest original rather than memorizing the re-cased
///   intermediate.
/// - Converting BACK to a non-uppercase kind restores the original — but
///   only when the text is untouched since the conversion. Once the writer
///   edits the re-cased text, their edit wins and the memory is dropped:
///   restoring over fresh typing would be data loss.
public struct ElementCaseMemory {

    public init() {}

    private struct Entry {
        /// The text exactly as the writer had it before the first re-case.
        let original: String
        /// The text as the conversion left it. Compared against the current
        /// text to detect "untouched since conversion".
        let converted: String
    }

    private var entries: [UUID: Entry] = [:]

    /// The text `element` should carry after conversion to `kind`.
    public mutating func text(for element: ScriptElement, convertedTo kind: ScreenplayKind) -> String {
        if kind.uppercasesInput {
            let converted = EditorState.normalizedText(element.text, for: kind)
            // Nothing worth remembering about an empty element — and no
            // visible change either, since caps of "" is "".
            guard !element.text.isEmpty else { return converted }
            if let existing = entries[element.id], element.text == existing.converted {
                // Untouched since our last re-case: keep the oldest original,
                // refresh the marker for the new kind.
                entries[element.id] = Entry(original: existing.original, converted: converted)
            } else {
                // First conversion, or the writer edited the text since —
                // either way the current text is the original worth keeping.
                entries[element.id] = Entry(original: element.text, converted: converted)
            }
            return converted
        }
        guard let entry = entries.removeValue(forKey: element.id) else { return element.text }
        return element.text == entry.converted ? entry.original : element.text
    }

    /// Drops memories for elements that no longer exist, so the map can
    /// never grow past the document itself.
    public mutating func prune(toAlive ids: Set<UUID>) {
        entries = entries.filter { ids.contains($0.key) }
    }
}
