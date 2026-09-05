import Foundation

/// Assigning scene numbers the way a production does.
///
/// Before a script is distributed its numbers mean nothing and can be handed
/// out afresh. After it is distributed they are addresses: a call sheet, a
/// shooting schedule and a script supervisor's notes all cite them, so an
/// existing number must never change under anyone. A scene added later takes
/// a letter against its neighbour instead — 12A sits between 12 and 13 — which
/// is why numbering is two operations rather than one.
public enum SceneNumbering {

    /// Numbers every scene from 1, discarding whatever was there.
    ///
    /// For a script that has not gone out yet. On one that has, this is the
    /// operation that renumbers somebody's schedule out from under them.
    public static func numberingAll(_ elements: [ScreenplayElement]) -> [ScreenplayElement] {
        var result = elements
        var next = 1
        for index in result.indices where result[index].type == .scene {
            result[index].sceneNumber = String(next)
            next += 1
        }
        return result
    }

    /// Keeps every existing number exactly and letters the scenes that have
    /// none — the locked behaviour a distributed script needs.
    ///
    /// A new scene after 12 becomes 12A, then 12B. New scenes ahead of the
    /// first number take the letter in front instead: A1 precedes 1. A script
    /// with no numbers at all has nothing to preserve, so it is numbered
    /// outright.
    public static func numberingNewScenes(_ elements: [ScreenplayElement]) -> [ScreenplayElement] {
        let scenes = elements.indices.filter { elements[$0].type == .scene }
        var used = Set(scenes.compactMap { elements[$0].sceneNumber }.filter { !$0.isEmpty })
        guard !used.isEmpty else { return numberingAll(elements) }

        var result = elements
        var run: [Int] = []
        var previous: String?

        /// Letters the pending run. `next` is the number the run runs up to,
        /// used only before the first numbered scene, where there is no
        /// predecessor to letter against.
        func flush(upTo next: String?) {
            guard !run.isEmpty else { return }
            var letter = 0
            for index in run {
                var candidate: String
                repeat {
                    let suffix = letters(letter)
                    letter += 1
                    // Never reuse a number already in the script: a letter can
                    // collide with one a previous pass or an import assigned.
                    candidate = previous.map { $0 + suffix } ?? suffix + (next ?? "1")
                } while used.contains(candidate)
                used.insert(candidate)
                result[index].sceneNumber = candidate
            }
            run.removeAll()
        }

        for index in scenes {
            if let number = elements[index].sceneNumber, !number.isEmpty {
                flush(upTo: number)
                previous = number
            } else {
                run.append(index)
            }
        }
        flush(upTo: nil)
        return result
    }

    /// Clears every scene number. Only safe before a script goes out.
    public static func cleared(_ elements: [ScreenplayElement]) -> [ScreenplayElement] {
        var result = elements
        for index in result.indices where result[index].type == .scene {
            result[index].sceneNumber = nil
        }
        return result
    }

    /// Whether any scene carries a number — what decides if a script is
    /// already addressed and must be added to rather than renumbered.
    public static func isNumbered(_ elements: [ScreenplayElement]) -> Bool {
        elements.contains { $0.type == .scene && !($0.sceneNumber ?? "").isEmpty }
    }

    /// A, B, … Z, AA, AB — spreadsheet order, so a scene split twenty times
    /// still lands on a number a production can read aloud.
    static func letters(_ index: Int) -> String {
        var remaining = index
        var out = ""
        repeat {
            out = String(UnicodeScalar(UInt8(65 + remaining % 26))) + out
            remaining = remaining / 26 - 1
        } while remaining >= 0
        return out
    }
}
