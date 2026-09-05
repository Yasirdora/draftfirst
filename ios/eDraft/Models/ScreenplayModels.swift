import Foundation
import os
import EDraftEngine

private let modelLog = Logger(subsystem: "xyz.edraft.ios", category: "ScreenplayModels")

enum ScreenplayKind: String, Codable, CaseIterable, Identifiable, Sendable {
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

    var id: String { rawValue }

    /// The matching kind in the native `EDraftEngine` package. Both
    /// enums carry the identical fourteen raw values (pinned by the
    /// engine's conformance corpus), so a miss means a careless rename —
    /// a bug to catch in debug, never a reason to crash a writer's app.
    var engineKind: ElementKind {
        guard let kind = ElementKind(rawValue: rawValue) else {
            assertionFailure("ScreenplayKind.\(rawValue) has no ElementKind counterpart")
            modelLog.fault("ScreenplayKind.\(self.rawValue, privacy: .public) has no ElementKind counterpart; fell back to action")
            return .action
        }
        return kind
    }

    init(engineKind: ElementKind) {
        guard let kind = ScreenplayKind(rawValue: engineKind.rawValue) else {
            assertionFailure("ElementKind.\(engineKind.rawValue) has no ScreenplayKind counterpart")
            modelLog.fault("ElementKind.\(engineKind.rawValue, privacy: .public) has no ScreenplayKind counterpart; fell back to action")
            self = .action
            return
        }
        self = kind
    }

    var title: String {
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

    var shortTitle: String {
        switch self {
        case .scene: "Scene"
        default: title
        }
    }

    var symbol: String {
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

    var uppercasesInput: Bool {
        switch self {
        case .scene, .character, .transition, .shot: true
        default: false
        }
    }

    static let editorKinds: [ScreenplayKind] = [
        .scene, .action, .character, .parenthetical, .dialogue,
        .transition, .shot, .general, .centered
    ]
}

struct ScriptElement: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var type: ScreenplayKind
    var text: String
    var dual: Bool?
    var sceneNumber: String?
    /// Section depth (`#` count). Carried losslessly even though the editor
    /// has no section UI yet — a collaborator's outline must survive a
    /// round-trip through eDraft untouched.
    var depth: Int?

    init(
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        type = try container.decode(ScreenplayKind.self, forKey: .type)
        text = try container.decode(String.self, forKey: .text)
        dual = try container.decodeIfPresent(Bool.self, forKey: .dual)
        sceneNumber = try container.decodeIfPresent(String.self, forKey: .sceneNumber)
        depth = try container.decodeIfPresent(Int.self, forKey: .depth)
    }
}

struct TitlePageEntry: Codable, Equatable, Sendable {
    var key: String
    var values: [String]
}

struct Screenplay: Codable, Equatable, Sendable {
    var titlePage: [TitlePageEntry]
    var elements: [ScriptElement]

    static let blank = Screenplay(
        titlePage: [
            TitlePageEntry(key: "Title", values: ["Untitled Screenplay"]),
            TitlePageEntry(key: "Credit", values: ["written by"])
        ],
        elements: [
            // A truly blank page — no FADE IN:, no ritual — but a page that
            // knows what a screenplay opens with. The first line of a script
            // is a slug, so the caret starts on an empty Scene: the keyboard
            // comes up in capitals and the first thing typed is a heading,
            // which is what the writer was going to type anyway. The kind is
            // not invisible while it does this — the bar names it, and one
            // swipe leaves it for Action.
            ScriptElement(type: .scene, text: "")
        ]
    )

    var title: String {
        titlePage.first(where: { $0.key.caseInsensitiveCompare("Title") == .orderedSame })?
            .values.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty ?? "Untitled Screenplay"
    }
}

// MARK: - Native engine model conversion

extension Screenplay {
    /// The engine package's identity-free model. Every field the engine
    /// carries — dual, sceneNumber, section depth — round-trips losslessly.
    var engineModel: EDraftEngine.Screenplay {
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
    init(engineModel: EDraftEngine.Screenplay) {
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

struct EnginePrediction: Codable, Equatable, Sendable {
    var text: String
    var why: String
    var becomes: ScreenplayKind?
    var hint: Bool?
}

enum PredictionMode: String, CaseIterable, Identifiable, Sendable {
    case smart
    case formatOnly
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: "Smart"
        case .formatOnly: "Format Only"
        case .off: "Off"
        }
    }

    var detail: String {
        switch self {
        case .smart: "Characters, locations, structure, and formatting"
        case .formatOnly: "Screenplay shape without story suggestions"
        case .off: "No eDraft suggestions"
        }
    }

    var symbol: String {
        switch self {
        case .smart: "sparkles"
        case .formatOnly: "textformat"
        case .off: "sparkles.slash"
        }
    }
}

struct ScreenplayStats: Equatable, Sendable {
    var pages: Int = 1
    var runtime: String = "~1 minute"
    var words: Int = 0
    /// The page each scene opens on, by element index — computed in the same
    /// pagination pass as the page count, so the Navigator and the PDF can
    /// never disagree about where a scene falls.
    var scenePages: [Int: Int] = [:]
}

/// Paper size for pagination and PDF. US Letter is the Hollywood default;
/// A4 serves European productions. The choice changes the paginator's line
/// budget, which is why stats and exports read the same value.
enum PageFormat: String, CaseIterable, Identifiable {
    case letter
    case a4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .letter: "US Letter"
        case .a4: "A4"
        }
    }

    /// US Letter: 55 lines at 6 lines/inch with 1″ top and bottom margins.
    /// A4: the same margins leave 58 lines. Width stays a 60-character text
    /// block — Courier's pitch is fixed, so A4's right margin absorbs the
    /// difference, exactly as real A4 screenplay templates do.
    var linesPerPage: Int {
        switch self {
        case .letter: 55
        case .a4: 58
        }
    }

    var pageRect: CGRect {
        switch self {
        case .letter: CGRect(x: 0, y: 0, width: 612, height: 792)
        case .a4: CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
        }
    }

    var textTop: CGFloat { 72 }

    /// Right edge of the 60-character text block (1″ right margin on Letter).
    var textRight: CGFloat {
        switch self {
        case .letter: 540
        case .a4: 540
        }
    }

    /// The app-wide choice, persisted under the "pageFormat" defaults key.
    static var current: PageFormat {
        PageFormat(rawValue: UserDefaults.standard.string(forKey: "pageFormat") ?? "") ?? .letter
    }
}

struct SceneRow: Identifiable, Equatable, Sendable {
    let id: UUID
    /// Position in the script, counting from 1.
    let number: Int
    /// The page it opens on, at the paper size currently set. Nil only before
    /// the first pagination has settled.
    let page: Int?
    /// The production's own number, once the script carries them — the
    /// address a call sheet or a schedule cites, which after an insert is no
    /// longer the same as the position (12A is the thirteenth scene).
    let sceneNumber: String?
    let title: String
    let elementIndex: Int

    /// What the Navigator shows: the production's number when there is one,
    /// otherwise where the scene falls.
    var label: String { sceneNumber ?? String(number) }
}

/// The Navigator's per-tab context line: structure and voice at a glance.
/// Scene side echoes Final Draft's Scene/Location Reports (counts, INT/EXT
/// texture); cast side echoes Highland's dialogue-share analysis without
/// requiring any metadata entry from the writer.
struct StoryStats: Equatable, Sendable {
    var scenes = 0
    var locations = 0
    var interior = 0
    var exterior = 0
    var characters = 0
    var cues = 0
    /// The cast's loudest voice and its share of all cues (0…1).
    var leadingCharacter: String?
    var leadingShare: Double = 0
}

/// One speech: what was said, and how it was marked to be said.
struct SpokenLine: Identifiable, Equatable, Sendable {
    /// The dialogue element itself, so the line is a place the caret can go.
    let id: UUID
    let parenthetical: String?
    let text: String
}

/// A character's presence in one scene — where they are, and what they say
/// while they are there.
struct CharacterAppearance: Identifiable, Equatable, Sendable {
    /// The scene heading element, so the row can open the scene itself.
    let id: UUID
    /// The scene's own number when the script carries them, else its position.
    let label: String
    let heading: String
    let page: Int?
    let lines: [SpokenLine]
}

struct CastRow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let cues: Int
    /// The character's first cue — where tapping the row goes. A name is not
    /// a place in the script, so the row has to carry one.
    let firstCueID: UUID
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
