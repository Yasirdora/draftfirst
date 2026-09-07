import CoreGraphics
import Foundation
import os
import EDraftEngine

nonisolated private let modelLog = Logger(subsystem: "xyz.edraft.ios", category: "ScreenplayModels")

public enum ScreenplayKind: String, Codable, CaseIterable, Identifiable, Sendable {
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
    case note
    case section
    case synopsis
    case pagebreak

    public var id: String { rawValue }

    /// The matching kind in the native `EDraftEngine` package. Both
    /// enums carry the identical fourteen raw values (pinned by the
    /// engine's conformance corpus), so a miss means a careless rename —
    /// a bug to catch in debug, never a reason to crash a writer's app.
    public var engineKind: ElementKind {
        guard let kind = ElementKind(rawValue: rawValue) else {
            assertionFailure("ScreenplayKind.\(rawValue) has no ElementKind counterpart")
            modelLog.fault("ScreenplayKind.\(self.rawValue, privacy: .public) has no ElementKind counterpart; fell back to action")
            return .action
        }
        return kind
    }

    nonisolated public init(engineKind: ElementKind) {
        guard let kind = ScreenplayKind(rawValue: engineKind.rawValue) else {
            assertionFailure("ElementKind.\(engineKind.rawValue) has no ScreenplayKind counterpart")
            modelLog.fault("ElementKind.\(engineKind.rawValue, privacy: .public) has no ScreenplayKind counterpart; fell back to action")
            self = .action
            return
        }
        self = kind
    }

    public var title: String {
        switch self {
        case .scene: "Scene Heading"
        case .action: "Action"
        case .character: "Character"
        case .dialogue: "Dialogue"
        case .parenthetical: "Parenthetical"
        case .transition: "Transition"
        case .shot: "Shot"
        case .general: "General"
        case .centered: "Centered"
        case .lyrics: "Lyrics"
        case .note: "Note"
        case .section: "Section"
        case .synopsis: "Synopsis"
        case .pagebreak: "Page Break"
        }
    }

    public var shortTitle: String {
        switch self {
        case .scene: "Scene"
        default: title
        }
    }

    public var symbol: String {
        switch self {
        case .scene: "film.stack"
        case .action: "text.alignleft"
        case .character: "person.crop.circle"
        case .dialogue: "quote.bubble"
        case .parenthetical: "textformat"
        case .transition: "arrow.right"
        case .shot: "camera.viewfinder"
        case .general: "pencil.line"
        case .centered: "text.aligncenter"
        case .lyrics: "music.note"
        case .note: "note.text"
        case .section: "list.bullet.indent"
        case .synopsis: "text.quote"
        case .pagebreak: "doc.append"
        }
    }

    /// Whether this kind is written in capitals.
    ///
    /// Asked of the engine rather than answered here, so the editor's live
    /// casing, the conversion rule and the importer that repairs a Final Draft
    /// file cannot come to different conclusions about what a cue looks like.
    public var uppercasesInput: Bool {
        Normalize.uppercaseKinds.contains(engineKind)
    }

    public static let editorKinds: [ScreenplayKind] = [
        .scene, .action, .character, .parenthetical, .dialogue,
        .transition, .shot, .general, .centered
    ]
}

public struct ScriptElement: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var type: ScreenplayKind
    public var text: String
    public var dual: Bool?
    public var sceneNumber: String?
    /// Section depth (`#` count). Carried losslessly even though the editor
    /// has no section UI yet — a collaborator's outline must survive a
    /// round-trip through eDraft untouched.
    public var depth: Int?

    nonisolated public init(
        id: UUID = UUID(),
        type: ScreenplayKind,
        text: String,
        dual: Bool? = nil,
        sceneNumber: String? = nil,
        depth: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.dual = dual
        self.sceneNumber = sceneNumber
        self.depth = depth
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, dual, sceneNumber, depth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        type = try container.decode(ScreenplayKind.self, forKey: .type)
        text = try container.decode(String.self, forKey: .text)
        dual = try container.decodeIfPresent(Bool.self, forKey: .dual)
        sceneNumber = try container.decodeIfPresent(String.self, forKey: .sceneNumber)
        depth = try container.decodeIfPresent(Int.self, forKey: .depth)
    }
}

public struct TitlePageEntry: Codable, Equatable, Sendable {

    nonisolated public init(key: String, values: [String]) {
        self.key = key
        self.values = values
    }
    public var key: String
    public var values: [String]
}

public struct Screenplay: Codable, Equatable, Sendable {

    nonisolated public init(titlePage: [TitlePageEntry] = [], elements: [ScriptElement] = []) {
        self.titlePage = titlePage
        self.elements = elements
    }
    public var titlePage: [TitlePageEntry]
    public var elements: [ScriptElement]

    public static let blank = Screenplay(
        titlePage: [
            TitlePageEntry(key: "Title", values: ["Untitled Screenplay"]),
            TitlePageEntry(key: "Credit", values: ["written by"])
        ],
        elements: [
            // A truly blank page — no FADE IN:, no ritual — and Action,
            // because Action is what `ScenePromotion` calls "nobody has said
            // what this is yet", which is the honest state of a page nobody
            // has typed on.
            //
            // It used to open on an empty Scene, reasoning that a script
            // begins with a slug and the phone's keyboard would come up in
            // capitals for it. The cost was hidden in an asymmetry: promotion
            // only ever runs *towards* Scene, and deliberately, so that a
            // writer's own choice is never second-guessed. A blank document
            // starting on Scene looked exactly like such a choice — so a
            // writer who opened a new script and typed a line of prose got
            // it shouted back as a scene heading, with nothing to undo it but
            // finding the element menu.
            //
            // Starting on Action loses nothing: type a slug and promotion
            // makes it one, on the keystroke, which is the rule the rest of
            // the app already trusts.
            ScriptElement(type: .action, text: "")
        ]
    )

    public var title: String {
        titlePage.first(where: { $0.key.caseInsensitiveCompare("Title") == .orderedSame })?
            .values.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "Untitled Screenplay"
    }
}

// MARK: - Native engine model conversion

extension Screenplay {
    /// The engine package's identity-free model. Every field the engine
    /// carries — dual, sceneNumber, section depth — round-trips losslessly.
    public var engineModel: EDraftEngine.Screenplay {
        EDraftEngine.Screenplay(
            titlePage: titlePage.map {
                EDraftEngine.TitlePageEntry(key: $0.key, values: $0.values)
            },
            elements: elements.map {
                EDraftEngine.ScreenplayElement(
                    type: $0.type.engineKind,
                    text: $0.text,
                    dual: $0.dual,
                    sceneNumber: $0.sceneNumber,
                    depth: $0.depth
                )
            }
        )
    }

    /// A fresh app screenplay from the engine model; elements receive new
    /// identities, exactly as a JSON decode through the old bridge did.
    nonisolated public init(engineModel: EDraftEngine.Screenplay) {
        self.init(
            titlePage: engineModel.titlePage.map { TitlePageEntry(key: $0.key, values: $0.values) },
            elements: engineModel.elements.map {
                ScriptElement(
                    type: ScreenplayKind(engineKind: $0.type),
                    text: $0.text,
                    dual: $0.dual,
                    sceneNumber: $0.sceneNumber,
                    depth: $0.depth
                )
            }
        )
    }
}

public struct EnginePrediction: Codable, Equatable, Sendable {

    nonisolated public init(text: String, why: String, becomes: ScreenplayKind? = nil, hint: Bool? = nil) {
        self.text = text
        self.why = why
        self.becomes = becomes
        self.hint = hint
    }
    public var text: String
    public var why: String
    public var becomes: ScreenplayKind?
    public var hint: Bool?
}

public enum PredictionMode: String, CaseIterable, Identifiable, Sendable {
    case smart
    case formatOnly
    case off

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .smart: "Smart"
        case .formatOnly: "Format Only"
        case .off: "Off"
        }
    }

    public var detail: String {
        switch self {
        case .smart: "Characters, locations, structure, and formatting"
        case .formatOnly: "Screenplay shape without story suggestions"
        case .off: "No eDraft suggestions"
        }
    }

    public var symbol: String {
        switch self {
        case .smart: "sparkles"
        case .formatOnly: "textformat"
        case .off: "sparkles.slash"
        }
    }
}

public struct ScreenplayStats: Equatable, Sendable {

    nonisolated public init(
        pages: Int = 1, runtime: String = "~1 minute",
        words: Int = 0, scenePages: [Int: Int] = [:]
    ) {
        self.pages = pages
        self.runtime = runtime
        self.words = words
        self.scenePages = scenePages
    }
    public var pages: Int = 1
    public var runtime: String = "~1 minute"
    public var words: Int = 0
    /// The page each scene opens on, by element index — computed in the same
    /// pagination pass as the page count, so the Navigator and the PDF can
    /// never disagree about where a scene falls.
    public var scenePages: [Int: Int] = [:]
}

/// Paper size for pagination and PDF. US Letter is the Hollywood default;
/// A4 serves European productions. The choice changes the paginator's line
/// budget, which is why stats and exports read the same value.
public enum PageFormat: String, CaseIterable, Identifiable {
    case letter
    case a4

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .letter: "US Letter"
        case .a4: "A4"
        }
    }

    /// US Letter: 55 lines at 6 lines/inch with 1″ top and bottom margins.
    /// A4: the same margins leave 58 lines. Width stays a 60-character text
    /// block — Courier's pitch is fixed, so A4's right margin absorbs the
    /// difference, exactly as real A4 screenplay templates do.
    public var linesPerPage: Int {
        switch self {
        case .letter: 55
        case .a4: 58
        }
    }

    public var pageRect: CGRect {
        switch self {
        case .letter: CGRect(x: 0, y: 0, width: 612, height: 792)
        case .a4: CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        }
    }

    public var textTop: CGFloat { 72 }

    /// Right edge of the 60-character text block (1″ right margin on Letter).
    public var textRight: CGFloat {
        switch self {
        case .letter: 540
        case .a4: 540
        }
    }

    /// The app-wide choice, persisted under the "pageFormat" defaults key.
    public static var current: PageFormat {
        PageFormat(rawValue: UserDefaults.standard.string(forKey: "pageFormat") ?? "") ?? .letter
    }
}

public struct SceneRow: Identifiable, Equatable, Sendable {

    nonisolated public init(
        id: UUID, number: Int, page: Int?, sceneNumber: String?,
        title: String, elementIndex: Int
    ) {
        self.id = id
        self.number = number
        self.page = page
        self.sceneNumber = sceneNumber
        self.title = title
        self.elementIndex = elementIndex
    }
    /// Inside, outside, or crossing between — read from the heading through
    /// the engine, so a writer's spelling of `I/E` does not decide whether
    /// their scene answers a filter. Nil for a slug forced with a leading dot,
    /// which carries no intro token to read.
    public var setting: SceneSetting? { SceneSetting(heading: title) }

    /// Whether this reads as a secondary slug rather than a master scene.
    ///
    /// A master scene heading opens with `INT.`, `EXT.` or one of the crossing
    /// forms. It is a new setup: it takes a scene number, it appears on a
    /// schedule, and it is what a first AD breaks the day down by. A secondary
    /// slug — `LATER`, `BACK TO SCENE`, `DOWN THE SLOPE` — names somewhere
    /// inside that setup and takes none of those things. Both are typed as
    /// headings, and both should be, so this is a reading of the line rather
    /// than a second element type.
    ///
    /// It is used for emphasis in the Navigator and nowhere else. The document
    /// does not change, the numbering does not change, and a writer who forces
    /// `.BLACK SCREEN` as a real scene is only shown it a shade lighter — the
    /// same information Final Draft has about that line, presented as a
    /// suggestion instead of a decision.
    public var isSecondary: Bool { setting == nil }

    public let id: UUID
    /// Position in the script, counting from 1.
    public let number: Int
    /// The page it opens on, at the paper size currently set. Nil only before
    /// the first pagination has settled.
    public let page: Int?
    /// The production's own number, once the script carries them — the
    /// address a call sheet or a schedule cites, which after an insert is no
    /// longer the same as the position (12A is the thirteenth scene).
    public let sceneNumber: String?
    public let title: String
    public let elementIndex: Int

    /// What the Navigator shows: the production's number when there is one,
    /// otherwise where the scene falls.
    public var label: String { sceneNumber ?? String(number) }
}

/// The Navigator's per-tab context line: structure and voice at a glance.
/// Scene side echoes Final Draft's Scene/Location Reports (counts, INT/EXT
/// texture); cast side echoes Highland's dialogue-share analysis without
/// requiring any metadata entry from the writer.
public struct StoryStats: Equatable, Sendable {

    nonisolated public init(
        scenes: Int = 0, locations: Int = 0, interior: Int = 0, exterior: Int = 0,
        characters: Int = 0, cues: Int = 0,
        leadingCharacter: String? = nil, leadingShare: Double = 0
    ) {
        self.scenes = scenes
        self.locations = locations
        self.interior = interior
        self.exterior = exterior
        self.characters = characters
        self.cues = cues
        self.leadingCharacter = leadingCharacter
        self.leadingShare = leadingShare
    }
    public var scenes = 0
    public var locations = 0
    public var interior = 0
    public var exterior = 0
    public var characters = 0
    public var cues = 0
    /// The cast's loudest voice and its share of all cues (0…1).
    public var leadingCharacter: String?
    public var leadingShare: Double = 0
}

/// One speech: what was said, and how it was marked to be said.
public struct SpokenLine: Identifiable, Equatable, Sendable {

    nonisolated public init(id: UUID, parenthetical: String?, text: String) {
        self.id = id
        self.parenthetical = parenthetical
        self.text = text
    }
    /// The dialogue element itself, so the line is a place the caret can go.
    public let id: UUID
    public let parenthetical: String?
    public let text: String
}

/// A character's presence in one scene — where they are, and what they say
/// while they are there.
public struct CharacterAppearance: Identifiable, Equatable, Sendable {

    nonisolated public init(id: UUID, label: String, heading: String, page: Int?, lines: [SpokenLine]) {
        self.id = id
        self.label = label
        self.heading = heading
        self.page = page
        self.lines = lines
    }
    /// The scene heading element, so the row can open the scene itself.
    public let id: UUID
    /// The scene's own number when the script carries them, else its position.
    public let label: String
    public let heading: String
    public let page: Int?
    public let lines: [SpokenLine]
}

public struct CastRow: Identifiable, Equatable, Sendable {

    nonisolated public init(id: String, name: String, cues: Int, firstCueID: UUID) {
        self.id = id
        self.name = name
        self.cues = cues
        self.firstCueID = firstCueID
    }
    public let id: String
    public let name: String
    public let cues: Int
    /// The character's first cue — where tapping the row goes. A name is not
    /// a place in the script, so the row has to carry one.
    public let firstCueID: UUID
}

private extension String {
    public var nonEmpty: String? { isEmpty ? nil : self }
}
