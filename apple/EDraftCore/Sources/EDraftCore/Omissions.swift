import EDraftEngine
import Foundation

/// The scenes a production has omitted, as the surface needs them —
/// RFC-DRAFT-PRODUCTION §7.3.
///
/// The engine reads an FDX `<OmittedScene>` into `Screenplay.omissions`, a
/// span of element *indices* (IL-0071). Indices are fine inside one reading
/// of one file and useless afterwards: the writer types a line above the
/// span and every index below it is wrong. So the span is converted here,
/// once, into the `DraftElementID`s of the elements it covers (M1,
/// IL-0073), and the surface asks about elements, never about positions.
///
/// The file says what was omitted when the document opens; after that the
/// writer does, through `EditorState.omitScene` and `restoreScene` (IL-0087),
/// and the save writes what the writer decided (`OmissionSpans`).
/// One scene the production cut: the card that stands in for it, the body
/// behind the card, and how much page it took.
public nonisolated struct OmittedScene: Equatable, Sendable {
    /// The OMITTED card — the Scene Heading Final Draft nests the block
    /// inside, which still prints and still holds the scene number.
    public let card: DraftElementID?
    /// The body, in script order. Collapsed, none of it is laid out.
    public let elements: [DraftElementID]
    /// The production's number for the scene, off the card.
    public let sceneNumber: String?
    /// Eighths of a page, as `SceneProperties Length` recorded them, when
    /// the file recorded one. Nil when the length had to be computed.
    public let eighths: Int?
    /// What the pill says: pages, to one decimal place.
    public let pages: Double

    public init(
        card: DraftElementID?, elements: [DraftElementID],
        sceneNumber: String?, eighths: Int?, pages: Double
    ) {
        self.card = card
        self.elements = elements
        self.sceneNumber = sceneNumber
        self.eighths = eighths
        self.pages = pages
    }

    /// `0.3 pgs CUT`. One place, because a quarter page and a third of one
    /// are the same decision to a reader and two different numbers to a
    /// formatter. Eighths are the file's unit and are never shown.
    public var pillText: String { "\(Self.pageText(pages)) pgs CUT" }

    /// What VoiceOver says about it, which a strike or a pill cannot.
    public func spoken(collapsed: Bool) -> String {
        "\(spokenName), omitted, \(Self.pageText(pages)) pages cut, \(collapsed ? "collapsed" : "expanded")"
    }

    /// What VoiceOver announces the moment the writer omits or restores it —
    /// the result, in the words the card already speaks: "Scene 21 omitted,
    /// 0.3 pages cut", "Scene 21 restored".
    public func announcement(for action: SceneAction) -> String {
        switch action {
        case .omit: return "\(spokenName) omitted, \(Self.pageText(pages)) pages cut"
        case .restore: return "\(spokenName) restored"
        }
    }

    private var spokenName: String { sceneNumber.map { "Scene \($0)" } ?? "Scene" }

    /// What names this span in the surface's expansion set. The body's
    /// first element, which always exists — a card does not.
    public var key: DraftElementID { elements[0] }

    /// One decimal place, rounded half away from zero.
    ///
    /// Explicit, because `%.1f` rounds half to even and a quarter page —
    /// `2/8`, the commonest cut length there is — came out as "0.2". A pill
    /// that understates what was cut is worse than one that rounds up: the
    /// number is read by someone deciding whether the day still fits.
    static func pageText(_ pages: Double) -> String {
        let tenths = (pages * 10).rounded(.toNearestOrAwayFromZero) / 10
        return String(format: "%.1f", tenths)
    }
}

/// The scenes a production has omitted, as the surface needs them —
/// RFC-DRAFT-PRODUCTION §7.3.
public nonisolated struct OmittedScenes: Equatable, Sendable {

    /// Each cut scene, in script order.
    public private(set) var scenes: [OmittedScene]
    /// Every element inside an omitted span, for the one question the
    /// layout, the caret and the paginator all ask.
    public private(set) var elements: Set<DraftElementID>
    /// The cards, which are not omitted: a card is what the omission looks
    /// like on the page (§7.3, "the span prints as an OMITTED card").
    public private(set) var cards: Set<DraftElementID>

    public init(scenes: [OmittedScene] = []) {
        self.scenes = scenes
        self.elements = Set(scenes.flatMap(\.elements))
        self.cards = Set(scenes.compactMap(\.card))
    }

    public var isEmpty: Bool { elements.isEmpty }

    /// Whether this element is inside an omitted span — out of the layout
    /// when collapsed, and closed to the caret either way.
    public func contains(_ element: ScriptElement) -> Bool {
        guard let id = element.draftID else { return false }
        return elements.contains(id)
    }

    /// Whether this element is the OMITTED card in front of a span.
    public func isCard(_ element: ScriptElement) -> Bool {
        guard let id = element.draftID else { return false }
        return cards.contains(id)
    }

    /// The scene whose card this is, or whose body this element is in.
    public func scene(for element: ScriptElement) -> OmittedScene? {
        guard let id = element.draftID else { return nil }
        return scenes.first { $0.card == id || $0.elements.contains(id) }
    }
}

/// A production action on one scene — what a Navigator row offers on hover,
/// what the page's context menu and the menu bar offer where the caret is.
///
/// One list, so the three doors cannot disagree about what a scene allows.
/// Only actions whose model exists are cases here: Lock Scene and Scene
/// Status join when page locks (RFC-DRAFT-PRODUCTION §7.2) are built, and
/// the row, the menus and VoiceOver take them from this type unchanged.
public nonisolated enum SceneAction: String, CaseIterable, Sendable {
    case omit
    case restore

    /// The command's name, and the name Undo gives it ("Undo Omit Scene").
    public var title: String {
        switch self {
        case .omit: return "Omit Scene"
        case .restore: return "Restore Scene"
        }
    }

    /// The SF Symbol a row shows for it: the pill's own word is CUT.
    public var symbol: String {
        switch self {
        case .omit: return "scissors"
        case .restore: return "arrow.uturn.backward"
        }
    }
}

/// Where the save should write each omitted scene: spans of element indices
/// over the document as its Fountain source reads back, and how many
/// elements that reading must have for the spans to mean anything.
///
/// Published with the source, from the same model at the same moment, so the
/// two cannot describe different documents (`EditorState.publishedOmissions`).
public nonisolated struct OmissionSpans: Equatable, Sendable {
    public let spans: [EDraftEngine.Omission]
    public let elementCount: Int

    public init(spans: [EDraftEngine.Omission], elementCount: Int) {
        self.spans = spans
        self.elementCount = elementCount
    }
}

public nonisolated enum Omissions {

    /// The words that make a heading an OMITTED card already (§7.3,
    /// `SceneNumbering`'s own spellings). Such a line is not a scene to omit.
    public static func isCardText(_ text: String) -> Bool {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return key == "OMIT" || key == "OMITTED"
    }

    /// The span a scene covers, in the document (page and asides merged):
    /// its heading through its last printing line before the next heading
    /// or act break.
    ///
    /// Asides count as they are anchored. One that stands in front of a line
    /// of the scene is inside it; one that stands in front of the next
    /// heading belongs to that heading, and is not cut with this scene —
    /// an act or sequence marker opening what follows must not vanish with
    /// the scene before it.
    public static func sceneSpan(at heading: Int, in document: [ScriptElement]) -> Range<Int> {
        var last = heading
        var at = heading + 1
        while at < document.count {
            let element = document[at]
            if element.type.isPrinting {
                if element.type == .scene || element.type == .actbreak { break }
                last = at
            }
            at += 1
        }
        return heading..<(last + 1)
    }

    /// Each omitted scene as a span over the document, for the save.
    ///
    /// A scene whose card or body cannot be found — deleted, or broken up —
    /// is left out rather than guessed at: the save then writes its lines
    /// live, where nothing is lost.
    public static func spans(of omitted: OmittedScenes, in document: [ScriptElement]) -> [EDraftEngine.Omission] {
        var position: [DraftElementID: Int] = [:]
        for (at, element) in document.enumerated() {
            if let id = element.draftID { position[id] = at }
        }
        var spans: [EDraftEngine.Omission] = []
        for scene in omitted.scenes {
            guard let card = scene.card.flatMap({ position[$0] }) else { continue }
            let body = scene.elements.compactMap { position[$0] }
            guard body.count == scene.elements.count, let start = body.min(), let end = body.max(),
                  start == card + 1 else { continue }
            /* Contiguous: nothing in between but the body and the notes a
               writer left on it, which carry no identity of their own. */
            let members = Set(body)
            guard (start...end).allSatisfy({ members.contains($0) || document[$0].type == .note }) else { continue }
            spans.append(EDraftEngine.Omission(start: start, end: end + 1))
        }
        return spans.sorted { $0.start < $1.start }
    }

    /// The spans applied to a script parsed from the published source, when
    /// they describe it: same element count, and each card still a heading.
    /// Nil otherwise — the save then lets the file's structure decide.
    public static func applying(_ published: OmissionSpans?, to script: EDraftEngine.Screenplay) -> EDraftEngine.Screenplay {
        guard let published, script.elements.count == published.elementCount,
              published.spans.allSatisfy({ span in
                  span.start > 0 && span.start < span.end && span.end <= script.elements.count
                      && script.elements[span.start - 1].type == .scene
              })
        else { return script }
        var script = script
        script.omissions = published.spans
        return script
    }

    /// The omitted spans of a Final Draft file, placed on the document as it
    /// stands at open.
    ///
    /// The engine says which elements of *its* reading are omitted; the
    /// editor's lines are the same file carried through Fountain, with
    /// identities of their own. The two agree index for index — the same
    /// correspondence `ImportedNotes.resolve` relies on, and the reason both
    /// are attached at open, from the same parse, before any edit has moved
    /// anything. A span that cannot be placed is dropped rather than guessed
    /// at: a mis-placed span would grey out a scene the writer is working in.
    public static func resolve(
        _ omissions: [EDraftEngine.Omission],
        imported: [EDraftEngine.ScreenplayElement],
        document: [ScriptElement],
        recorded: [Int?] = [],
        measuring pagesOf: (Range<Int>) -> Double = { _ in 0 }
    ) -> OmittedScenes {
        guard !omissions.isEmpty, imported.count == document.count else {
            return OmittedScenes()
        }
        var scenes: [OmittedScene] = []
        for (at, omission) in omissions.enumerated() {
            guard omission.start > 0, omission.start < omission.end,
                  omission.end <= document.count else { continue }
            /* The card is the element the block is nested in — the one
               before the span (§7.3). Without it the span is still omitted;
               it just has no card to stand in for it. */
            let card = document[omission.start - 1]
            let body = (omission.start..<omission.end).compactMap { document[$0].draftID }
            guard !body.isEmpty else { continue }
            /* The file's own measure when it has one, and the paginator's
               when it does not — a scene eDraft omitted itself, or a file
               whose SceneProperties carried no Length. */
            let eighths = at < recorded.count ? recorded[at] : nil
            let pages = eighths.map { Double($0) / 8 } ?? pagesOf(omission.start..<omission.end)
            scenes.append(OmittedScene(
                card: card.draftID,
                elements: body,
                sceneNumber: card.sceneNumber,
                eighths: eighths,
                pages: pages
            ))
        }
        return OmittedScenes(scenes: scenes)
    }

    // MARK: - How much page was cut

    /// Eighths of a page, as each `<OmittedScene>`'s own scene heading
    /// records them, in document order — `nil` for a block whose heading
    /// carries no `Length`.
    ///
    /// **A layering compromise, taken deliberately.** An FDX attribute
    /// belongs to the engine, and the engine does not model this one:
    /// `SceneProperties Length` is paragraph metadata, preserved in the
    /// origin's bytes and never read into `ScreenplayElement`. Rather than
    /// widen the engine for a pill, the value is read here, out of the
    /// origin string this document already holds and already parses. The
    /// scan is deliberately narrow — the first `Length` inside each
    /// `<OmittedScene>`, nothing else — and it retires the day the engine
    /// models the attribute. Recorded as a follow-up in
    /// docs/MACOS-EXECUTION.md.
    public static func recordedEighths(inOrigin origin: String) -> [Int?] {
        var found: [Int?] = []
        var rest = Substring(origin)
        while let open = rest.range(of: "<OmittedScene>") {
            let after = rest[open.upperBound...]
            let close = after.range(of: "</OmittedScene>")
            let block = close.map { after[..<$0.lowerBound] } ?? after
            found.append(eighths(inFirstSceneProperties: block))
            rest = close.map { after[$0.upperBound...] } ?? Substring("")
        }
        return found
    }

    private static func eighths(inFirstSceneProperties block: Substring) -> Int? {
        guard let properties = block.range(of: "<SceneProperties") else { return nil }
        let tail = block[properties.upperBound...]
        guard let tagEnd = tail.firstIndex(of: ">"),
              let lengthAt = tail[..<tagEnd].range(of: "Length=\"") else { return nil }
        let value = tail[lengthAt.upperBound...]
        guard let quote = value.firstIndex(of: "\"") else { return nil }
        return eighths(inLength: String(value[..<quote]))
    }

    /// Final Draft writes a scene's length in eighths of a page: `2/8`, or
    /// `1 3/8` past a page, or `0` for a card that takes no room. Anything
    /// this does not recognise is no measurement at all rather than a
    /// number invented from it.
    static func eighths(inLength value: String) -> Int? {
        let parts = value.split(separator: " ")
        guard !parts.isEmpty, parts.count <= 2 else { return nil }
        var total = 0
        for (at, part) in parts.enumerated() {
            if let whole = Int(part), !part.contains("/") {
                /* A bare number is whole pages — except a lone `0`, which
                   is Final Draft saying "no measurable height". */
                guard at == 0 else { return nil }
                total += whole * 8
                continue
            }
            let fraction = part.split(separator: "/")
            guard fraction.count == 2,
                  let numerator = Int(fraction[0]), let denominator = Int(fraction[1]),
                  denominator > 0, numerator >= 0 else { return nil }
            total += Int((Double(numerator) / Double(denominator) * 8).rounded())
        }
        return total
    }

    /// The same script with the omitted elements taken out, for the
    /// paginator.
    ///
    /// *Measured on `finaldraft-sample02.fdx`, the file Final Draft 13.4
    /// wrote:* the OMITTED card records `Length="0" Page="17"`, and the
    /// scene nested inside the block records `Page="1"` while the script's
    /// 35 live scenes run monotonically from page 1 to page 25. `Page="1"`
    /// is not a place in a 25-page script — that scene was never paginated
    /// in situ. So Final Draft does not count an omitted scene toward page
    /// numbers, the card holds its place at no measurable height, and this
    /// does the same.
    /// `kept` maps each index of the returned model back to its index in the
    /// script, so page numbers land on the right lines afterwards.
    public static func paginable(
        _ model: EDraftEngine.Screenplay,
        document: [ScriptElement],
        omitted: OmittedScenes
    ) -> (model: EDraftEngine.Screenplay, kept: [Int]) {
        guard !omitted.isEmpty, model.elements.count == document.count else {
            return (model, Array(model.elements.indices))
        }
        var elements: [EDraftEngine.ScreenplayElement] = []
        var kept: [Int] = []
        for (at, pair) in zip(model.elements, document).enumerated() where !omitted.contains(pair.1) {
            elements.append(pair.0)
            kept.append(at)
        }
        var paginable = model
        paginable.elements = elements
        return (paginable, kept)
    }

    /// Page numbers, keyed by the script's own element indices again.
    /// An omitted element is on no page and appears nowhere here.
    public static func restored(_ pages: [Int: Int], through kept: [Int]) -> [Int: Int] {
        var out: [Int: Int] = [:]
        out.reserveCapacity(pages.count)
        for (at, page) in pages where at >= 0 && at < kept.count { out[kept[at]] = page }
        return out
    }
}
