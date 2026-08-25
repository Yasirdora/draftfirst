import Foundation

/// A bounded, non-validating XML tokeniser for the FDX paragraph subset —
/// the Swift port of the TypeScript engine's `scanXml` and `parseTag`
/// (`fdx.ts`). Comments, processing instructions, and declarations are
/// skipped; external entities are never resolved. Malformed input produces
/// diagnostics and a best-effort parse, never a trap.
///
/// All scanning happens on UTF-16 code units so offsets and slicing match
/// the JavaScript string semantics the conformance corpus pins.
enum FdxXmlScanner {

    struct Tag {
        var name: String
        /// Insertion order preserved. Lookup returns the LAST value for a
        /// name, matching JavaScript `Map.set` overwrite semantics on
        /// duplicate attributes.
        var attributes: [(name: String, value: String)]
        var selfClosing: Bool

        func attribute(_ name: String) -> String? {
            attributes.last { $0.name == name }?.value
        }
    }

    struct Handlers {
        /// Return false from any handler to stop the scan (a parse limit).
        var start: (Tag, Int) -> Bool
        var end: (String, Int) -> Bool
        var text: (String, Bool) -> Bool
    }

    // MARK: - Scanner

    static func scan(_ source: String, handlers: Handlers, diagnostics: Fdx.DiagnosticCollector) {
        let units = Array(source.utf16)
        var cursor = 0
        while cursor < units.count {
            guard let opening = indexOf(units, "<", from: cursor) else {
                _ = handlers.text(string(units[cursor..<units.count]), false)
                return
            }
            if opening > cursor, !handlers.text(string(units[cursor..<opening]), false) { return }

            if startsWith(units, "<!--", at: opening) {
                guard let end = indexOf(units, "-->", from: opening + 4) else {
                    diagnostics.add(.init(
                        code: "FDX_UNTERMINATED_COMMENT", severity: .warning,
                        message: "An unterminated XML comment ended the import.",
                        offset: opening
                    ))
                    return
                }
                cursor = end + 3
                continue
            }

            if startsWith(units, "<![CDATA[", at: opening) {
                guard let end = indexOf(units, "]]>", from: opening + 9) else {
                    diagnostics.add(.init(
                        code: "FDX_UNTERMINATED_CDATA", severity: .warning,
                        message: "An unterminated CDATA section ended the import.",
                        offset: opening
                    ))
                    _ = handlers.text(string(units[(opening + 9)..<units.count]), true)
                    return
                }
                if !handlers.text(string(units[(opening + 9)..<end]), true) { return }
                cursor = end + 3
                continue
            }

            if startsWith(units, "<?", at: opening) {
                guard let end = indexOf(units, "?>", from: opening + 2) else {
                    diagnostics.add(.init(
                        code: "FDX_UNTERMINATED_PROCESSING_INSTRUCTION", severity: .warning,
                        message: "An unterminated XML processing instruction ended the import.",
                        offset: opening
                    ))
                    return
                }
                cursor = end + 2
                continue
            }

            if startsWith(units, "<!", at: opening) {
                guard let end = declarationEnd(of: units, from: opening + 2) else {
                    diagnostics.add(.init(
                        code: "FDX_UNTERMINATED_DECLARATION", severity: .warning,
                        message: "An unterminated XML declaration ended the import.",
                        offset: opening
                    ))
                    return
                }
                diagnostics.add(.init(
                    code: "FDX_DECLARATION_IGNORED", severity: .warning,
                    message: "An XML declaration such as DOCTYPE was ignored; external entities are never resolved.",
                    offset: opening
                ))
                cursor = end + 1
                continue
            }

            guard let end = tagEnd(of: units, from: opening + 1) else {
                diagnostics.add(.init(
                    code: "FDX_UNTERMINATED_TAG", severity: .warning,
                    message: "An unterminated XML tag ended the import.",
                    offset: opening
                ))
                return
            }
            let rawTag = units[(opening + 1)..<end]
            let trimmedStart = jsTrimmedStart(rawTag)
            if trimmedStart.first == 0x2F { // '/'
                let nameUnits = jsTrimmed(trimmedStart.dropFirst())
                var nameEnd = nameUnits.startIndex
                while nameEnd < nameUnits.endIndex && !JSWhitespace.matches(unit: nameUnits[nameEnd]) {
                    nameEnd = nameUnits.index(after: nameEnd)
                }
                let name = string(nameUnits[..<nameEnd]).lowercased()
                if !name.isEmpty, !handlers.end(name, opening) { return }
            } else if let tag = parseTag(rawTag, offset: opening, diagnostics: diagnostics) {
                if !handlers.start(tag, opening) { return }
                if tag.selfClosing, !handlers.end(tag.name, opening) { return }
            }
            cursor = end + 1
        }
    }

    // MARK: - Tag parsing

    private static func parseTag(
        _ rawTag: ArraySlice<UInt16>,
        offset: Int,
        diagnostics: Fdx.DiagnosticCollector
    ) -> Tag? {
        var raw = Array(jsTrimmed(rawTag))
        var selfClosing = false
        if raw.last == 0x2F { // '/'
            selfClosing = true
            raw = Array(jsTrimmedEnd(raw.dropLast()))
        }

        var cursor = 0
        while cursor < raw.count && JSWhitespace.matches(unit: raw[cursor]) { cursor += 1 }
        let nameStart = cursor
        while cursor < raw.count && !JSWhitespace.matches(unit: raw[cursor]) && raw[cursor] != 0x3D {
            cursor += 1
        }
        guard cursor > nameStart else {
            diagnostics.add(.init(
                code: "FDX_MALFORMED_TAG", severity: .warning,
                message: "An XML tag without a name was ignored.",
                offset: offset
            ))
            return nil
        }

        let name = String(decoding: raw[nameStart..<cursor], as: UTF16.self).lowercased()
        var attributes: [(name: String, value: String)] = []
        while cursor < raw.count {
            while cursor < raw.count && JSWhitespace.matches(unit: raw[cursor]) { cursor += 1 }
            if cursor >= raw.count { break }

            let attributeStart = cursor
            while cursor < raw.count && !JSWhitespace.matches(unit: raw[cursor]) && raw[cursor] != 0x3D {
                cursor += 1
            }
            let attributeName = String(decoding: raw[attributeStart..<cursor], as: UTF16.self).lowercased()
            while cursor < raw.count && JSWhitespace.matches(unit: raw[cursor]) { cursor += 1 }
            if attributeName.isEmpty || cursor >= raw.count || raw[cursor] != 0x3D { // '='
                diagnostics.add(.init(
                    code: "FDX_MALFORMED_ATTRIBUTE", severity: .warning,
                    message: "A malformed attribute on <\(name)> was ignored.",
                    offset: offset
                ))
                while cursor < raw.count && !JSWhitespace.matches(unit: raw[cursor]) { cursor += 1 }
                continue
            }

            cursor += 1
            while cursor < raw.count && JSWhitespace.matches(unit: raw[cursor]) { cursor += 1 }
            let value: String
            if cursor < raw.count && (raw[cursor] == 0x22 || raw[cursor] == 0x27) { // '"' '\''
                let quote = raw[cursor]
                cursor += 1
                let valueStart = cursor
                while cursor < raw.count && raw[cursor] != quote { cursor += 1 }
                value = String(decoding: raw[valueStart..<cursor], as: UTF16.self)
                if cursor < raw.count {
                    cursor += 1
                } else {
                    diagnostics.add(.init(
                        code: "FDX_UNTERMINATED_ATTRIBUTE", severity: .warning,
                        message: "An unterminated attribute on <\(name)> was imported best-effort.",
                        offset: offset
                    ))
                }
            } else {
                let valueStart = cursor
                while cursor < raw.count && !JSWhitespace.matches(unit: raw[cursor]) { cursor += 1 }
                value = String(decoding: raw[valueStart..<cursor], as: UTF16.self)
                diagnostics.add(.init(
                    code: "FDX_UNQUOTED_ATTRIBUTE", severity: .warning,
                    message: "Unquoted attribute \"\(attributeName)\" on <\(name)> was accepted best-effort.",
                    offset: offset
                ))
            }
            attributes.append((attributeName, Fdx.decodeXmlEntities(value)))
        }

        return Tag(name: name, attributes: attributes, selfClosing: selfClosing)
    }

    // MARK: - Unit-level helpers

    /// `tagEndOf`: the closing `>` outside any quote, or nil.
    private static func tagEnd(of units: [UInt16], from start: Int) -> Int? {
        var quote: UInt16 = 0
        var index = start
        while index < units.count {
            let unit = units[index]
            if quote != 0 {
                if unit == quote { quote = 0 }
            } else if unit == 0x22 || unit == 0x27 { // '"' '\''
                quote = unit
            } else if unit == 0x3E { // '>'
                return index
            }
            index += 1
        }
        return nil
    }

    /// `declarationEndOf`: like `tagEnd`, but a `[ ... ]` internal subset
    /// defers the closing `>` (DOCTYPE declarations).
    private static func declarationEnd(of units: [UInt16], from start: Int) -> Int? {
        var quote: UInt16 = 0
        var subsetDepth = 0
        var index = start
        while index < units.count {
            let unit = units[index]
            if quote != 0 {
                if unit == quote { quote = 0 }
                index += 1
                continue
            }
            if unit == 0x22 || unit == 0x27 { quote = unit } // '"' '\''
            else if unit == 0x5B { subsetDepth += 1 } // '['
            else if unit == 0x5D, subsetDepth > 0 { subsetDepth -= 1 } // ']'
            else if unit == 0x3E, subsetDepth == 0 { return index } // '>'
            index += 1
        }
        return nil
    }

    private static func startsWith(_ units: [UInt16], _ literal: String, at index: Int) -> Bool {
        let needle = Array(literal.utf16)
        guard index + needle.count <= units.count else { return false }
        for (offset, unit) in needle.enumerated() where units[index + offset] != unit {
            return false
        }
        return true
    }

    private static func indexOf(_ units: [UInt16], _ literal: String, from start: Int) -> Int? {
        let needle = Array(literal.utf16)
        guard !needle.isEmpty else { return min(start, units.count) }
        var index = start
        while index + needle.count <= units.count {
            if startsWith(units, literal, at: index) { return index }
            index += 1
        }
        return nil
    }

    static func string(_ units: ArraySlice<UInt16>) -> String {
        String(decoding: units, as: UTF16.self)
    }

    // MARK: JavaScript `trim` semantics on code units (the JS `\s` set).

    static func jsTrimmed(_ units: ArraySlice<UInt16>) -> ArraySlice<UInt16> {
        jsTrimmedEnd(jsTrimmedStart(units))
    }

    static func jsTrimmedStart(_ units: ArraySlice<UInt16>) -> ArraySlice<UInt16> {
        var slice = units
        while let first = slice.first, JSWhitespace.matches(unit: first) { slice = slice.dropFirst() }
        return slice
    }

    static func jsTrimmedEnd(_ units: ArraySlice<UInt16>) -> ArraySlice<UInt16> {
        var slice = units
        while let last = slice.last, JSWhitespace.matches(unit: last) { slice = slice.dropLast() }
        return slice
    }
}

extension String {
    /// JavaScript `String.prototype.trim()` — the JS `\s` set, not Unicode
    /// White_Space (a NEL stays; a BOM trims).
    var jsTrimmed: String {
        var view = unicodeScalars[...]
        while let first = view.first, first.isJSWhitespace { view = view.dropFirst() }
        while let last = view.last, last.isJSWhitespace { view = view.dropLast() }
        return String(view)
    }
}
