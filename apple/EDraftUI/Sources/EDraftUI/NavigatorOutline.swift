import EDraftCore
import Foundation

/// The Navigator's Scenes tab as one outline: acts as the top-level entries
/// (RFC-ACT-BREAK §6), the scenes each act owns beneath them.
///
/// The merge is a pure derivation over two already-sorted lists — acts and
/// scenes both carry their element index, and document order is the only
/// order a map of the script can have — so it lives outside the view and
/// answers to a test without a pixel being drawn. A script with no acts
/// gets exactly the scene list it always had; the outline only appears
/// when there is structure to outline.
public enum NavigatorOutline {

    /// One line of the outline: an act card, or a scene.
    public enum Row: Identifiable, Equatable, Sendable {
        case act(ActRow)
        case scene(SceneRow)

        public var id: UUID {
            switch self {
            case .act(let act): act.id
            case .scene(let scene): scene.id
            }
        }

        /// Position in the element list — the merge's only sort key.
        var elementIndex: Int {
            switch self {
            case .act(let act): act.elementIndex
            case .scene(let scene): scene.elementIndex
            }
        }
    }

    /// Acts and scenes interleaved by document order. Both lists arrive
    /// sorted by element index from `EditorState`; a two-finger merge keeps
    /// it that way at O(n) rather than a sort's O(n log n) on every view
    /// pass — the sidebar rebuilds on each keystroke's revision.
    public static func rows(acts: [ActRow], scenes: [SceneRow]) -> [Row] {
        guard !acts.isEmpty else { return scenes.map(Row.scene) }
        var rows: [Row] = []
        rows.reserveCapacity(acts.count + scenes.count)
        var scene = scenes.startIndex
        for act in acts {
            while scene < scenes.endIndex, scenes[scene].elementIndex < act.elementIndex {
                rows.append(.scene(scenes[scene]))
                scene = scenes.index(after: scene)
            }
            rows.append(.act(act))
        }
        while scene < scenes.endIndex {
            rows.append(.scene(scenes[scene]))
            scene = scenes.index(after: scene)
        }
        return rows
    }
}
