import Foundation

/// Shared Fountain detectors used by both the parser and the serializer,
/// ported from the duplicated tables in the TypeScript engine's `parse.ts`
/// and `serialise.ts`. Every check here is deliberately ASCII-exact where the
/// JS regexes are (`[A-Z]`, `[a-z]`, explicit character classes) — Unicode
/// case folding must not change classification.
enum FountainDetect {

    // MARK: - Scene headings

    /// `SCENE_DETECT` = `/^(INT|EXT|EST|INT\.\/EXT|INT\/EXT|I\/E)([. ]|\.\/)/i`
    private static let scenePrefixes = ["INT./EXT", "INT/EXT", "I/E", "INT", "EXT", "EST"]

    /// ECMAScript `/i` **without** the `/u` flag never folds a non-ASCII code
    /// point onto an ASCII one (the Canonicalize step returns the character
    /// unchanged when `ch >= 128` but `cu < 128`). So `ınt. house` (U+0131
    /// dotless i) and `eſt. house` (U+017F long s) are NOT scene headings in
    /// the TypeScript engine. `uppercased()` performs full Unicode mapping and
    /// would accept both — fold ASCII only.
    private static func asciiUppercased(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x61, scalar.value <= 0x7A,
               let upper = Unicode.Scalar(scalar.value - 32) {
                result.unicodeScalars.append(upper)
            } else {
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func isSceneHeading(_ line: String) -> Bool {
        let up = asciiUppercased(line)
        for prefix in scenePrefixes where up.hasPrefix(prefix) {
            let rest = up.dropFirst(prefix.count)
            if rest.hasPrefix(".") || rest.hasPrefix(" ") || rest.hasPrefix("./") {
                return true
            }
        }
        return false
    }

    // MARK: - Transitions

    /// `TRANSITION_DETECT` = `/^[A-Z0-9 '()&.,/-]+ TO:$/`
    private static let transitionHeadCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 '()&.,/-"
    )

    static func isTransition(_ line: String) -> Bool {
        guard line.hasSuffix(" TO:") else { return false }
        let head = line.dropLast(4)
        guard !head.isEmpty else { return false }
        return head.unicodeScalars.allSatisfy { transitionHeadCharacters.contains($0) }
    }

    /// `FADE_OPENER` = `/^FADE (IN|OUT|TO BLACK|TO WHITE)[.:]?$/`
    static func isFadeOpener(_ line: String) -> Bool {
        for base in ["FADE IN", "FADE OUT", "FADE TO BLACK", "FADE TO WHITE"] {
            if line == base || line == base + "." || line == base + ":" {
                return true
            }
        }
        return false
    }

    // MARK: - Uppercase checks (ASCII, matching the JS regexes)

    /// `/[A-Z]/.test(text)` — JS scans UTF-16 code units, so these must scan
    /// scalars, not `Character`s. A decomposed `é` (U+0065 U+0301) is a single
    /// non-ASCII grapheme cluster whose *base scalar* is an ASCII `e`: JS sees
    /// the `e` and matches `[a-z]`, while `Character.isASCII` is false and
    /// would miss it. That flipped `RENé` from action to a character cue.
    static func hasUpper(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value >= 0x41 && $0.value <= 0x5A }
    }

    /// `/[a-z]/.test(text)` — see `hasUpper` for why this scans scalars.
    static func hasLower(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value >= 0x61 && $0.value <= 0x7A }
    }

    /// `isUpperCue` / `isUpper`: has an uppercase ASCII letter and no
    /// lowercase ASCII letter.
    static func isUpper(_ text: String) -> Bool {
        hasUpper(text) && !hasLower(text)
    }

    // MARK: - Shot language

    static let shotLeads = [
        "ANGLE ON", "CLOSE ON", "CLOSEUP ON", "CLOSEUP", "POV", "INSERT",
        "WIDE SHOT", "TWO SHOT", "TRACKING SHOT", "AERIAL SHOT", "CRANE SHOT",
        "STEADICAM SHOT", "HANDHELD SHOT",
    ]

    static func looksLikeShot(_ text: String) -> Bool {
        guard isUpper(text) else { return false }
        let up = text.uppercased()
        if shotLeads.contains(where: { up == $0 || up.hasPrefix($0 + " ") }) {
            return true
        }
        return up.hasSuffix(" SHOT")
    }

    // MARK: - Misc shared helpers

    /// `expandActionTabs`: each tab becomes four spaces.
    static func expandTabs(_ text: String) -> String {
        text.replacingOccurrences(of: "\t", with: "    ")
    }

    /// Forced-scene marker: `/^\.[\p{L}\p{N}]/u` — a dot followed by a
    /// Unicode letter or number. (This check IS Unicode-aware in JS.)
    static func hasForcedSceneMarker(_ line: String) -> Bool {
        guard line.hasPrefix("."), let next = line.dropFirst().first else { return false }
        return next.isLetter || next.isNumber
    }

    /// `/^[.@!~>#=([]/` — a leading character that forces another element.
    static func startsWithForcedMarker(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        return ".@!~>#=([".contains(first)
    }
}
