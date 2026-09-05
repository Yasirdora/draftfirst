import Foundation

/// The blast-radius sentence shown before a character is renamed.
///
/// A writer renaming MARA wants it changed everywhere. A writer renaming
/// WILL does not want "will you come" rewritten. Only they can tell the
/// two apart, and only if shown the number first. Lives here so the
/// phone's character page and the Mac inspector cannot disagree.
public nonisolated enum CharacterRename {

    public static func warning(
        name: String, cues: Int, mentions: Int, merges: Bool
    ) -> String {
        let counted = cues == 1 ? "1 cue" : "\(cues) cues"
        let merge = merges ? " That name already speaks, so the two characters merge." : ""
        guard mentions > 0 else {
            return "Renames \(counted) for \(name).\(merge)"
        }
        let mentioned = mentions == 1 ? "once" : "\(mentions) times"
        return "Renames \(counted). \(name) is also named \(mentioned) in action and "
            + "dialogue.\(merge)"
    }
}
