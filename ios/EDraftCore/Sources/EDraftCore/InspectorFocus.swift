import Foundation

/// Which properties the inspector should show for a selection.
///
/// The pane is contextual to the caret. A view that decided this would
/// be a second copy of the taxonomy, and the two apps would disagree
/// about what a cue *is*. Title is the fallback when nothing on the
/// page has properties of its own.
public nonisolated enum InspectorFocus: String, Equatable, Sendable, CaseIterable {
    case title
    case scene
    case character

    /// What the caret proposes. The writer can still switch to Title —
    /// that is editing the title page without a sheet.
    public nonisolated static func proposed(for kind: ScreenplayKind?) -> InspectorFocus {
        switch kind {
        case .character, .parenthetical, .dialogue, .lyrics:
            return .character
        case nil, .note, .section, .synopsis, .pagebreak:
            return .title
        default:
            return .scene
        }
    }
}
