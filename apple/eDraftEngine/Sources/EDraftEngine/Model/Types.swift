import Foundation

/// Version of the native engine package, reported in the app's Settings
/// panel where the JavaScriptCore bundle's version used to appear.
public enum EngineInfo {
    public static let version = "eDraft Engine 0.2.0 (Swift)"
}

/// The canonical screenplay element vocabulary, mirroring the TypeScript
/// engine's `ElementType | StructuralType` union one-to-one. Raw values are
/// the wire strings used by the `.draft` format — do not rename cases.
public enum ElementKind: String, Codable, Sendable, CaseIterable {
    // Printing elements
    case scene
    case action
    case character
    case dialogue
    case parenthetical
    case transition
    case shot
    case general
    case centered
    case lyrics
    /// The card that opens an act. Its page break is a rule of the type (the
    /// paginator forces one), and the act's end is derived — the next
    /// actbreak or the document's end — never stored. RFC-ACT-BREAK §2.
    case actbreak
    // Structural elements (never paginate/print)
    case note
    case section
    case synopsis
    case pagebreak

    /// Elements that appear on the printed page (TypeScript `PRINTING_TYPES`).
    public var isPrinting: Bool {
        switch self {
        case .scene, .action, .character, .dialogue, .parenthetical,
             .transition, .shot, .general, .centered, .lyrics, .actbreak:
            return true
        case .note, .section, .synopsis, .pagebreak:
            return false
        }
    }

    /// Dialogue-flow elements — character, parenthetical, dialogue
    /// (TypeScript `DIALOGUE_FLOW`).
    public var isDialogueFlow: Bool {
        self == .character || self == .parenthetical || self == .dialogue
    }
}

public struct ScreenplayElement: Codable, Equatable, Sendable {
    public var type: ElementKind
    /// Marker-free content text when `runs` is present; emphasis markers are
    /// boundary artefacts, not model text (TypeScript `ScreenplayElement.text`).
    public var text: String
    /// Styled spans of `text` (TypeScript `runs`). Canonical: sorted,
    /// non-overlapping, merged where identical, clamped, never empty.
    public var runs: [StyleRun]?
    /// Dual-dialogue marker (character block): `MARA ^` in Fountain.
    public var dual: Bool?
    /// Forced scene number (scene elements).
    public var sceneNumber: String?
    /// Section depth (section elements).
    public var depth: Int?
    /// Notes only: the words this note is pinned to, within the paragraph
    /// that follows it (RFC-NOTES-SYSTEM §5.2). Absent means the whole
    /// paragraph (TypeScript `ScreenplayElement.anchor`).
    public var anchor: NoteAnchor?

    public init(type: ElementKind, text: String, runs: [StyleRun]? = nil, dual: Bool? = nil,
                sceneNumber: String? = nil, depth: Int? = nil, anchor: NoteAnchor? = nil) {
        self.type = type
        self.text = text
        self.runs = runs
        self.dual = dual
        self.sceneNumber = sceneNumber
        self.depth = depth
        self.anchor = anchor
    }
}

/// Offset within one element's marker-free content text, in UTF-16 code
/// units — the same coordinate space as `NSRange` and the TypeScript
/// engine's string offsets, so the editor and both engines share it exactly
/// (TypeScript `ContentIndex` brand).
public struct ContentIndex: Comparable, Codable, Equatable, Sendable {
    public let value: Int
    public init(_ value: Int) { self.value = value }
    public static func < (lhs: ContentIndex, rhs: ContentIndex) -> Bool { lhs.value < rhs.value }
}

/// Offset in Fountain source text. Exists transiently inside the parser and
/// serialiser; never stored, never crosses the engine boundary.
public struct FountainIndex: Comparable, Codable, Equatable, Sendable {
    public let value: Int
    public init(_ value: Int) { self.value = value }
    public static func < (lhs: FountainIndex, rhs: FountainIndex) -> Bool { lhs.value < rhs.value }
}

/// The complete Style vocabulary of the FDX corpus — the six tokens Final
/// Draft puts on a `<Text>` run (TypeScript `StyleToken`).
///
/// `allCaps` is display casing: Final Draft stores what the writer typed and
/// applies capitals in the view, so casing is never an edit. `hiddenText` is
/// invisible on the printed page. Neither has a Fountain spelling — the
/// Fountain serialiser drops them (a recorded fidelity-contract loss; FDX
/// carries them natively).
public struct StyleSet: OptionSet, Equatable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let bold = StyleSet(rawValue: 1 << 0)
    public static let italic = StyleSet(rawValue: 1 << 1)
    public static let underline = StyleSet(rawValue: 1 << 2)
    public static let strikeout = StyleSet(rawValue: 1 << 3)
    public static let allCaps = StyleSet(rawValue: 1 << 4)
    public static let hiddenText = StyleSet(rawValue: 1 << 5)
}

extension StyleSet: Codable {
    /// Canonical wire order — the TypeScript engine's `STYLE_ORDER`, which is
    /// also the order of the FDX Style attribute's '+'-joined form.
    private static let wireOrder: [(set: StyleSet, token: String)] = [
        (.bold, "Bold"), (.italic, "Italic"), (.underline, "Underline"),
        (.strikeout, "Strikeout"), (.allCaps, "AllCaps"), (.hiddenText, "HiddenText")
    ]

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Self.wireOrder.compactMap { contains($0.set) ? $0.token : nil })
    }

    public init(from decoder: Decoder) throws {
        let tokens = try decoder.singleValueContainer().decode([String].self)
        var set: StyleSet = []
        for token in tokens {
            /* Unknown tokens from a newer Final Draft are dropped rather than
               failing the document: a style is a view concern; the text stays. */
            if let match = Self.wireOrder.first(where: { $0.token == token }) {
                set.insert(match.set)
            }
        }
        self = set
    }
}

/// One span of content sharing identical presentation (TypeScript
/// `StyleRun`). `start`/`end` are a half-open ContentIndex range into the
/// owning element's marker-free text.
///
/// `revisionID` and `tagNumbers` live on the run because FDX puts
/// RevisionID and TagNumber on `<Text>` next to Style — one span mechanism,
/// and the model can never express a span the format cannot hear.
/// Highlight colors. v1 is yellow alone; the field is a value, not a
/// flag, so a palette is an additive UI change and never a format
/// migration (docs/RFC-HIGHLIGHTER.md, D7).
public enum HighlightColor: String, Codable, Equatable, Sendable {
    case yellow
}

public struct StyleRun: Codable, Equatable, Sendable {
    public var start: Int
    public var end: Int
    public var styles: StyleSet
    public var revisionID: Int?
    public var tagNumbers: [Int]?
    /// The attention mark (docs/RFC-HIGHLIGHTER.md): one color in v1,
    /// carried on the run beside styles like `revisionID`.
    public var highlight: HighlightColor?

    public init(start: Int, end: Int, styles: StyleSet,
                revisionID: Int? = nil, tagNumbers: [Int]? = nil,
                highlight: HighlightColor? = nil) {
        self.start = start
        self.end = end
        self.styles = styles
        self.revisionID = revisionID
        self.highlight = highlight
        self.tagNumbers = tagNumbers
    }
}

/// Where a title-page line sits across the measure. Absent means centred.
public enum TitlePageAlignment: String, Codable, Sendable {
    case left
    case center
    case right
}

/// One line of the title page (docs/RFC-TITLE-PAGE.md, D1): text, its own
/// alignment and styled runs — and the blank lines between, which carry the
/// vertical rhythm and are therefore real lines in the model, never
/// recomputed at render. `key` is an annotation a guided editor may leave
/// on a line it created; nothing requires it and nothing invents it.
public struct TitlePageLine: Codable, Equatable, Sendable {
    public var text: String
    public var alignment: TitlePageAlignment?
    public var runs: [StyleRun]?
    public var key: String?

    public init(text: String, alignment: TitlePageAlignment? = nil,
                runs: [StyleRun]? = nil, key: String? = nil) {
        self.text = text
        self.alignment = alignment
        self.runs = runs
        self.key = key
    }
}

/// A scene the production has omitted — RFC-DRAFT-PRODUCTION §7.3.
///
/// An omission is a *record*, not a deletion: the elements stay in the
/// script with their text, and this names the contiguous span that no
/// longer prints. Removing the record restores the scene.
///
/// `start` is inclusive and `end` exclusive, as every other span in this
/// model is; the span begins at a scene heading. §7.3 addresses its span by
/// DraftElementID, which this model has no equivalent for — ids are
/// `.draft`'s script.json (RFC-DRAFT-FORMAT §6.1) — so the span is by
/// element index, and the scene number stays on the OMITTED card element
/// that precedes it (TypeScript `Omission`).
public struct Omission: Codable, Equatable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

public struct Screenplay: Codable, Equatable, Sendable {
    public var titlePage: [TitlePageLine]
    public var elements: [ScreenplayElement]
    /// Scenes the production has omitted (§7.3). Absent when there are none,
    /// so a script without omissions encodes exactly as it always has.
    public var omissions: [Omission]?

    public init(titlePage: [TitlePageLine] = [], elements: [ScreenplayElement] = [],
                omissions: [Omission]? = nil) {
        self.titlePage = titlePage
        self.elements = elements
        self.omissions = omissions
    }
}
