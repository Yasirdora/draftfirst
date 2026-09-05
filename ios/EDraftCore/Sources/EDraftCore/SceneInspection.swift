import Foundation

/// What the inspector reports about a scene: who speaks, how long it
/// runs, where it falls. Derived from the same elements the Navigator
/// lists, so the pane and the list cannot disagree about the heading.
public struct SceneInspection: Equatable, Sendable {
    public let row: SceneRow
    /// Canonical cue names, in the order they first speak.
    public let characters: [String]
    /// Printing elements in the scene, heading included.
    public let lines: Int
    public let startPage: Int?
    public let endPage: Int?

    public init(
        row: SceneRow, characters: [String], lines: Int,
        startPage: Int?, endPage: Int?
    ) {
        self.row = row
        self.characters = characters
        self.lines = lines
        self.startPage = startPage
        self.endPage = endPage
    }
}

extension EditorState {

    /// The scene the caret is in, walking back to the last heading.
    public func sceneInspection(containing id: UUID) -> SceneInspection? {
        guard let index = screenplay.elements.firstIndex(where: { $0.id == id })
        else { return nil }
        return sceneInspection(at: index)
    }

    public func sceneInspection(at index: Int) -> SceneInspection? {
        let elements = screenplay.elements
        guard elements.indices.contains(index) else { return nil }
        var start = index
        while start > 0, elements[start].type != .scene {
            start -= 1
        }
        guard elements[start].type == .scene else { return nil }
        var end = start + 1
        while end < elements.count, elements[end].type != .scene {
            end += 1
        }
        guard let row = scenes.first(where: { $0.id == elements[start].id })
        else { return nil }

        var seen: [String] = []
        var seenSet: Set<String> = []
        var lines = 0
        var lastPrinting = start
        for i in start..<end {
            let element = elements[i]
            if element.type.engineKind.isPrinting { lines += 1; lastPrinting = i }
            guard element.type == .character else { continue }
            let name = Self.canonicalCharacterName(element.text)
            guard !name.isEmpty, !seenSet.contains(name) else { continue }
            seenSet.insert(name)
            seen.append(name)
        }
        return SceneInspection(
            row: row,
            characters: seen,
            lines: lines,
            startPage: stats.scenePages[start],
            endPage: stats.scenePages[lastPrinting] ?? stats.scenePages[start]
        )
    }

    /// The cue that owns this line, walking back to the last character
    /// before a scene boundary. Nil on action, a heading, or empty.
    public func enclosingCharacterName(for id: UUID) -> String? {
        guard let index = screenplay.elements.firstIndex(where: { $0.id == id })
        else { return nil }
        var i = index
        while i >= 0 {
            let element = screenplay.elements[i]
            if element.type == .scene { return nil }
            if element.type == .character {
                let name = Self.canonicalCharacterName(element.text)
                return name.isEmpty ? nil : name
            }
            i -= 1
        }
        return nil
    }
}
