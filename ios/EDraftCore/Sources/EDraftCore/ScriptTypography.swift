import Foundation

/// How a screenplay is set on screen, as numbers rather than as attributes.
///
/// A script's shape *is* its grammar: a reader knows a cue from an action
/// before reading a word of either, because of where the line begins. If the
/// phone and the Mac each carried their own copy of those measurements they
/// would drift — not dramatically, but into two documents that look like
/// different drafts of the same page, which is the most visible drift there
/// is and the hardest to argue about after the fact.
///
/// So the measurements live here, and each surface turns them into whatever
/// its own text system calls a paragraph style. Nothing in this file knows
/// what a font is.
///
/// The indents are fractions of the measure rather than absolute points
/// because the surfaces are different widths and a screenplay's proportions,
/// not its inches, are what the eye reads.
public nonisolated enum ScriptTypography {

    /// Where a kind's lines begin and end, as fractions of the text measure.
    public struct Indents: Equatable, Sendable {
        /// Distance from the left edge to the first character.
        public let head: Double
        /// Distance from the right edge to the last, as a positive fraction.
        public let tail: Double

        public init(head: Double, tail: Double) {
            self.head = head
            self.tail = tail
        }
    }

    /// How a line sits across the measure, named without reference to any
    /// platform's alignment type.
    public enum Alignment: Sendable {
        case natural
        case right
        case centred
    }

    /// The indented block kinds. Scene, action and the rest run full measure.
    public static func indents(for kind: ScreenplayKind) -> Indents? {
        switch kind {
        case .character:     Indents(head: 0.38, tail: 0.14)
        case .parenthetical: Indents(head: 0.27, tail: 0.30)
        case .dialogue:      Indents(head: 0.17, tail: 0.17)
        default:             nil
        }
    }

    public static func alignment(for kind: ScreenplayKind) -> Alignment {
        switch kind {
        case .transition: .right
        case .centered:   .centred
        default:          .natural
        }
    }

    /// The air above a kind, in points at the base text size.
    ///
    /// Held as space *after* the preceding paragraph by both surfaces, so the
    /// insertion caret is drawn at the next baseline rather than stretched
    /// through screenplay whitespace.
    public static func spacing(before kind: ScreenplayKind) -> Double {
        switch kind {
        case .scene: 24
        case .action, .character, .transition, .shot, .general, .centered: 14
        case .dialogue, .parenthetical: 0
        default: 10
        }
    }

    /// A slug and a shot carry the weight; everything else is the plain face.
    public static func isEmphasised(_ kind: ScreenplayKind) -> Bool {
        kind == .scene || kind == .shot
    }

    /// The line box for a given font line height — never tighter than this,
    /// so a page keeps its rhythm when a reader enlarges the text.
    public static func lineHeight(forFontLineHeight height: Double) -> Double {
        max(22, (height * 1.1).rounded(.up))
    }
}
