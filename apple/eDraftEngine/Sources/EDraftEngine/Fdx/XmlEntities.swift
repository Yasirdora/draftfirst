import Foundation

/// XML entity and character handling for the FDX codec — the Swift port of
/// the TypeScript engine's entity section (`fdx.ts`). Behaviour is pinned
/// byte-for-byte by `Fixtures/fdx.json`; every rule below exists because the
/// TypeScript original does it exactly this way.
extension Fdx {

    // MARK: - Character legality

    /// The XML 1.0 Char production: tab, LF, CR, then everything from space
    /// up, excluding surrogates and the U+FFFE/U+FFFF non-characters.
    static func isLegalXmlCodePoint(_ codePoint: UInt32) -> Bool {
        codePoint == 0x09 || codePoint == 0x0A || codePoint == 0x0D
            || (codePoint >= 0x20 && codePoint <= 0xD7FF)
            || (codePoint >= 0xE000 && codePoint <= 0xFFFD)
            || (codePoint >= 0x10000 && codePoint <= 0x10FFFF)
    }

    /// Replace illegal XML code points with U+FFFD, counting the repairs.
    /// Iterates scalars, which matches JavaScript's for-of code-point
    /// iteration for every well-formed string.
    static func sanitiseXmlCharacters(_ text: String) -> (text: String, replacements: Int) {
        var clean = String()
        clean.reserveCapacity(text.count)
        var replacements = 0
        for scalar in text.unicodeScalars {
            if isLegalXmlCodePoint(scalar.value) {
                clean.unicodeScalars.append(scalar)
            } else {
                clean.append("\u{FFFD}")
                replacements += 1
            }
        }
        return (clean, replacements)
    }

    // MARK: - Decoding

    /// Decode each entity exactly once. Invalid numeric entities remain
    /// unchanged — `decodeXmlEntities("&amp;lt;")` is `"&lt;"`, never `"<"`.
    public static func decodeXmlEntities(_ text: String) -> String {
        let units = Array(text.utf16)
        var out: [UInt16] = []
        out.reserveCapacity(units.count)
        var index = 0
        while index < units.count {
            if units[index] == 0x26, // '&'
               let entity = decodeEntity(in: units, at: index) {
                out.append(contentsOf: entity.decoded)
                index += entity.length
            } else {
                out.append(units[index])
                index += 1
            }
        }
        return String(decoding: out, as: UTF16.self)
    }

    /// Match the TypeScript pattern
    /// `/&(?:#(?:x|X)[0-9a-fA-F]+|#[0-9]+|lt|gt|quot|apos|amp);/` anchored at
    /// `amp`. The longest legal entity is ten units (`&#x10FFFF;`); the scan
    /// window is capped at 32 so a `&` with no nearby `;` costs O(1) — any
    /// body longer than that cannot match, and staying verbatim is exactly
    /// what the regex produces for it.
    private static func decodeEntity(in units: [UInt16], at amp: Int) -> (decoded: [UInt16], length: Int)? {
        var semicolon = amp + 1
        let limit = min(amp + 33, units.count)
        while semicolon < limit && units[semicolon] != 0x3B { semicolon += 1 } // ';'
        guard semicolon < limit, semicolon > amp + 1 else { return nil }
        let body = ArraySlice(units[(amp + 1)..<semicolon])
        let length = semicolon - amp + 1

        switch String(decoding: body, as: UTF16.self) {
        case "lt": return ([0x3C], length)   // <
        case "gt": return ([0x3E], length)   // >
        case "quot": return ([0x22], length) // "
        case "apos": return ([0x27], length) // '
        case "amp": return ([0x26], length)  // &
        default: break
        }

        guard body.first == 0x23 else { return nil } // '#'
        var radix = 10
        var digits = body.dropFirst()
        if let first = digits.first, first == 0x78 || first == 0x58 { // 'x' 'X'
            radix = 16
            digits = digits.dropFirst()
        }
        guard !digits.isEmpty else { return nil }
        let isDigit: (UInt16) -> Bool = radix == 16
            ? { unit in
                (0x30...0x39).contains(unit) || (0x41...0x46).contains(unit) || (0x61...0x66).contains(unit)
            }
            : { unit in (0x30...0x39).contains(unit) }
        guard digits.allSatisfy(isDigit) else { return nil }
        // Overflow or an out-of-range value is the TypeScript
        // `!Number.isSafeInteger(...) || !isLegalXmlCodePoint(...)` path:
        // the entity stays verbatim.
        guard let value = UInt32(String(decoding: digits, as: UTF16.self), radix: radix),
              isLegalXmlCodePoint(value),
              let scalar = Unicode.Scalar(value) else { return nil }
        return (Array(String(scalar).utf16), length)
    }

    // MARK: - Encoding

    /// Encode the five predefined entities after repairing illegal code
    /// points. Single pass — equivalent to the TypeScript chain of five
    /// ordered replacements, which is careful to encode `&` first.
    public static func encodeXmlEntities(_ text: String) -> String {
        encodePreserved(sanitiseXmlCharacters(text).text)
    }

    /// Encode for output, reporting any character repairs. `context` names
    /// the value in the diagnostic message ("paragraph text", a scene number,
    /// a title-page key); `elementIndex` is set for body elements only.
    static func encodeXmlValue(
        _ value: String,
        diagnostics: DiagnosticCollector,
        context: String,
        elementIndex: Int? = nil
    ) -> String {
        let sanitised = sanitiseXmlCharacters(value)
        if sanitised.replacements > 0 {
            diagnostics.add(Diagnostic(
                code: "FDX_INVALID_XML_CHARACTER_REPLACED",
                severity: .warning,
                message: "\(sanitised.replacements) illegal XML character(s) in \(context) were replaced with U+FFFD.",
                elementIndex: elementIndex,
                count: sanitised.replacements
            ))
        }
        return encodePreserved(sanitised.text)
    }

    private static func encodePreserved(_ text: String) -> String {
        var out = String()
        out.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&apos;"
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }
}
