import Foundation

/// Version of the native engine package, reported in the app's Settings
/// panel where the JavaScriptCore bundle's version used to appear.
public enum EngineInfo {
    public static let version = "eDraft Engine 0.1.0 (Swift)"
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
    public var text: String
    /// Dual-dialogue marker (character block): `MARA ^` in Fountain.
    public var dual: Bool?
    /// Forced scene number (scene elements).
    public var sceneNumber: String?
    /// Section depth (section elements).
    public var depth: Int?

    public init(type: ElementKind, text: String, dual: Bool? = nil,
                sceneNumber: String? = nil, depth: Int? = nil) {
        self.type = type
        self.text = text
        self.dual = dual
        self.sceneNumber = sceneNumber
        self.depth = depth
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
