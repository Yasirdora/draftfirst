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
    // Structural elements (never paginate/print)
    case note
    case section
    case synopsis
    case pagebreak

    /// Elements that appear on the printed page (TypeScript `PRINTING_TYPES`).
    public var isPrinting: Bool {
        switch self {
        case .scene, .action, .character, .dialogue, .parenthetical,
             .transition, .shot, .general, .centered, .lyrics:
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

    public init(type: ElementKind, text: String, runs: [StyleRun]? = nil, dual: Bool? = nil,
                sceneNumber: String? = nil, depth: Int? = nil) {
        self.type = type
        self.text = text
        self.runs = runs
        self.dual = dual
        self.sceneNumber = sceneNumber
        self.depth = depth
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
public struct StyleRun: Codable, Equatable, Sendable {
    public var start: Int
    public var end: Int
    public var styles: StyleSet
    public var revisionID: Int?
    public var tagNumbers: [Int]?

    public init(start: Int, end: Int, styles: StyleSet,
                revisionID: Int? = nil, tagNumbers: [Int]? = nil) {
        self.start = start
        self.end = end
        self.styles = styles
        self.revisionID = revisionID
        self.tagNumbers = tagNumbers
    }
}

public struct TitlePageEntry: Codable, Equatable, Sendable {
    public var key: String
    public var values: [String]

    public init(key: String, values: [String]) {
        self.key = key
        self.values = values
    }
}

public struct Screenplay: Codable, Equatable, Sendable {
    public var titlePage: [TitlePageEntry]
    public var elements: [ScreenplayElement]

    public init(titlePage: [TitlePageEntry] = [], elements: [ScreenplayElement] = []) {
        self.titlePage = titlePage
        self.elements = elements
    }
}
