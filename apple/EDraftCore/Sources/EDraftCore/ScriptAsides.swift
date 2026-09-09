import Foundation

/// Something in the document that is not on the page.
///
/// Three kinds of thing arrive this way, and they have one property in common:
/// none of them prints, so none of them may occupy a line of a page a
/// production schedules against.
///
/// - A **note** is a writer's private aside. Final Draft calls it a Note,
///   Fountain writes it `[[like this]]`.
/// - A **section** is an act, a sequence or a beat — Final Draft's `Outline 1`,
///   `Outline 2`, `Outline 3`, Fountain's `#`, `##`, `###`.
/// - A **synopsis** is the prose under one. Final Draft calls it a Summary,
///   Fountain writes it `= like this`.
///
/// None of the three carries an author, a colour or a timestamp in any of the
/// three formats, so neither does this. A field with nowhere honest to be
/// stored is one that disappears the first time the file is sent to someone.
public nonisolated struct ScriptAside: Identifiable, Equatable, Sendable {
    /// The element itself, carried whole — so editing an aside edits the
    /// element rather than replacing it, and a section keeps its level.
    public var element: ScriptElement
    /// The page element this sits in front of — `nil` when it trails the
    /// script, which is where something written after the last line goes.
    public let anchor: UUID?

    public var id: UUID { element.id }
    public var kind: ScreenplayKind { element.type }
    public var text: String { element.text }
    /// An outline level: 1 for an act, 2 for a sequence, 3 for a beat.
    public var depth: Int? { element.depth }

    public init(element: ScriptElement, anchor: UUID?) {
        self.element = element
        self.anchor = anchor
    }
}

/// The document, split into the part the page sets and the part beside it.
///
/// **The page is the printing elements.** That is the whole rule, and it is
/// asked of `ScreenplayKind.isPrinting` rather than restated as a list here,
/// so a kind added later cannot be printing in one place and not in the other.
///
/// Everything else is in the document — it saves, it exports, it round-trips
/// through Final Draft — and is not on the page. Left in the text stream, a
/// writer's private aside was set in Courier among the stage directions, and
/// an act heading was counted toward the page count: four pages of outline
/// read as script on one of the two production drafts this was measured on.
///
/// The split is anchored by element id rather than by matching the text of the
/// line that follows, which is what the web engine's `structural.ts` has to
/// do: the web editor's stream has no stable identity, and ours does. An id
/// cannot rot when the writer retypes the heading above their note.
public nonisolated enum ScriptAsides {

    /// The elements the page sets, and what was lifted out from between them.
    public nonisolated struct Split: Equatable, Sendable {
        public var page: [ScriptElement]
        public var asides: [ScriptAside]

        public init(page: [ScriptElement], asides: [ScriptAside]) {
            self.page = page
            self.asides = asides
        }
    }

    /// Lifts everything that does not print out of a document.
    public static func split(_ elements: [ScriptElement]) -> Split {
        // The common case by a distance: a script with nothing beside it is
        // handed back whole rather than rebuilt element by element.
        guard elements.contains(where: { !$0.type.isPrinting }) else {
            return Split(page: elements, asides: [])
        }

        var page: [ScriptElement] = []
        var asides: [ScriptAside] = []
        var pending: [ScriptElement] = []
        page.reserveCapacity(elements.count)

        for element in elements {
            guard element.type.isPrinting else {
                pending.append(element)
                continue
            }
            page.append(element)
            asides.append(contentsOf: pending.map { ScriptAside(element: $0, anchor: element.id) })
            pending.removeAll(keepingCapacity: true)
        }
        // Whatever is still pending followed the last line of the script.
        asides.append(contentsOf: pending.map { ScriptAside(element: $0, anchor: nil) })
        return Split(page: page, asides: asides)
    }

    /// Puts them back, in front of the elements they belong to.
    ///
    /// An aside whose anchor is gone — the writer deleted the line it was
    /// about — is not deleted with it. It goes to the end of the script, where
    /// the writer can see it and decide. Losing someone's note because they
    /// rewrote the scene it was about is not a trade the app gets to make on
    /// their behalf.
    public static func merge(page: [ScriptElement], asides: [ScriptAside]) -> [ScriptElement] {
        guard !asides.isEmpty else { return page }

        var byAnchor: [UUID: [ScriptAside]] = [:]
        var trailing: [ScriptAside] = []
        for aside in asides {
            guard let anchor = aside.anchor else {
                trailing.append(aside)
                continue
            }
            byAnchor[anchor, default: []].append(aside)
        }

        var out: [ScriptElement] = []
        out.reserveCapacity(page.count + asides.count)
        var placed = Set<UUID>()
        for element in page {
            for aside in byAnchor[element.id] ?? [] {
                out.append(aside.element)
                placed.insert(aside.id)
            }
            out.append(element)
        }
        // Orphans keep their order among themselves, then the trailing ones.
        for aside in asides where aside.anchor != nil && !placed.contains(aside.id) {
            out.append(aside.element)
        }
        out.append(contentsOf: trailing.map(\.element))
        return out
    }
}
