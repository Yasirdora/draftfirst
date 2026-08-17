import Foundation
import os
import DraftFirstEngine

private let modelLog = Logger(subsystem: "xyz.draftfirst.ios", category: "ScreenplayModels")

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

    /// The matching kind in the native `DraftFirstEngine` package. Both
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

    init(
        id: UUID = UUID(),
        type: ScreenplayKind,
        text: String,
        dual: Bool? = nil,
        sceneNumber: String? = nil
    ) {
        self.id = id
        self.type = type
        self.text = text
        self.dual = dual
        self.sceneNumber = sceneNumber
    }

    private enum CodingKeys: String, CodingKey {
        case type, text, dual, sceneNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        type = try container.decode(ScreenplayKind.self, forKey: .type)
        text = try container.decode(String.self, forKey: .text)
        dual = try container.decodeIfPresent(Bool.self, forKey: .dual)
        sceneNumber = try container.decodeIfPresent(String.self, forKey: .sceneNumber)
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
            ScriptElement(type: .transition, text: "FADE IN:"),
            // A single empty Action, never an empty Scene: an invisible
            // uppercase kind under the caret would capitalize everything the
            // writer types. Scene promotion comes from the prediction engine.
            ScriptElement(type: .action, text: "")
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
    /// The engine package's identity-free model. Section depth has no app
    /// representation and is intentionally dropped, matching the behavior of
    /// the former JavaScript bridge (which decoded into `ScriptElement`).
    var engineModel: DraftFirstEngine.Screenplay {
        DraftFirstEngine.Screenplay(
            titlePage: titlePage.map {
                DraftFirstEngine.TitlePageEntry(key: $0.key, values: $0.values)
            },
            elements: elements.map {
                DraftFirstEngine.ScreenplayElement(
                    type: $0.type.engineKind,
                    text: $0.text,
                    dual: $0.dual,
                    sceneNumber: $0.sceneNumber
                )
            }
        )
    }

    /// A fresh app screenplay from the engine model; elements receive new
    /// identities, exactly as a JSON decode through the old bridge did.
    init(engineModel: DraftFirstEngine.Screenplay) {
        self.init(
            titlePage: engineModel.titlePage.map { TitlePageEntry(key: $0.key, values: $0.values) },
            elements: engineModel.elements.map {
                ScriptElement(
                    type: ScreenplayKind(engineKind: $0.type),
                    text: $0.text,
                    dual: $0.dual,
                    sceneNumber: $0.sceneNumber
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
    let number: Int
    let title: String
    let elementIndex: Int
}

struct CastRow: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let cues: Int
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
