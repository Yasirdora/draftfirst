import Foundation

/// The exact JavaScript `/\s/` set — written as escapes so every member
/// stays visible in review and survives editor normalisation:
/// `[\t \n \v \f \r SP U+00A0 U+1680 U+2000...U+200A U+2028 U+2029
///   U+202F U+205F U+3000 U+FEFF]`.
///
/// This is NOT Unicode's `White_Space` property: JS excludes U+0085 (NEL) and
/// includes U+FEFF. The engine's word wrapping and scene-heading dash splitting
/// mirror JS regexes, so they must split on exactly this set — the torture
/// corpus pins the difference (a NEL must stay inside its word; a BOM must act
/// as a separator).
///
/// Every member is in the BMP and none is a surrogate, so the UTF-16 form is
/// exact: a code unit is a separator if and only if it is one of these.
enum JSWhitespace {

    static func matches(scalarValue value: UInt32) -> Bool {
        switch value {
        case 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20,
             0xA0, 0x1680, 0x2000...0x200A,
             0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    /// Exact, because no JS whitespace character is astral or a surrogate.
    static func matches(unit: UInt16) -> Bool {
        matches(scalarValue: UInt32(unit))
    }
}

extension Unicode.Scalar {
    var isJSWhitespace: Bool { JSWhitespace.matches(scalarValue: value) }
}

extension Character {
    /// True only for a single-scalar cluster in the JS `\s` set.
    ///
    /// A multi-scalar cluster such as `" " + U+0301` is deliberately NOT
    /// whitespace here. JS scans code units: it would split on the space and
    /// keep the combining mark as the start of the next word — a distinction
    /// grapheme-level scanning cannot express at all. Code that must match JS
    /// exactly therefore scans UTF-16 (see `Paginator.wrapText`); this
    /// Character form is for scanners where the surrounding grammar rules
    /// such clusters out.
    var isJSWhitespace: Bool {
        var iterator = unicodeScalars.makeIterator()
        guard let scalar = iterator.next(), iterator.next() == nil else { return false }
        return scalar.isJSWhitespace
    }
}
