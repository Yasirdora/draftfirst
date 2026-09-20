import Foundation

/// How an eDraft PDF carries its own Fountain source home.
///
/// Parsing arbitrary PDF text back into a screenplay is lossy. A PDF we
/// exported never needs parsing: its bytes carry the complete Fountain
/// source as a hex string in `/Keywords`, a field every viewer and print
/// pipeline preserves. Export stamps it; import scans for it. Perfect
/// fidelity, zero PDF-graph dependencies, and a foreign PDF simply has
/// no signal — a clean refusal.
///
/// The payload hex-encodes UTF-8 *bytes*, not UTF-16 code units — curly
/// quotes, em dashes, and every non-Latin script survive intact. Mirrors
/// `packages/edraft/src/pdfsignal.ts` byte for byte.
///
/// Two `/Keywords` spellings are read: a PDF hex string `<…>` (the web
/// exporter) and a PDF literal `(…)` (Core Graphics). Both live in the
/// Info dictionary. Bytes after `%%EOF` are not a field and are not how
/// we write.
public nonisolated enum PdfSignal {

    public static let markerPrefix = "EDRAFT_FOUNTAIN"
    public static let markerVersion = "1"

    /// Prefixes written before the eDraft rename. We read them forever and
    /// never write them again — those files are writers' backups. This list
    /// must never meet a find-and-replace: the rename once rewrote it to the
    /// CURRENT prefix and pre-rename PDFs silently stopped opening.
    public static let legacyMarkerPrefixes = ["DRAFT_FIRST_FOUNTAIN"]

    /// The hex string to stamp into `/Keywords` at export.
    public static func encode(_ fountain: String) -> String {
        hex(of: Array("\(markerPrefix):\(markerVersion)\n\(fountain)".utf8))
    }

    /// The Fountain source embedded in an eDraft PDF, or `nil` when the
    /// file carries no valid signal — a foreign PDF, a truncated write,
    /// or a newer format version this build does not understand.
    public static func extract(from pdf: Data) -> String? {
        let source = pdf
        let needle = Array("/Keywords".utf8)
        var i = 0
        outer: while i + needle.count <= source.count {
            for n in 0..<needle.count {
                if source[i + n] != needle[n] {
                    i += 1
                    continue outer
                }
            }
            if let hex = readKeywordsValue(source, from: i),
               let payload = decodePayload(hex) {
                return payload
            }
            i += 1
        }
        return nil
    }

    // MARK: - Internals

    private static func isKnownPrefix(_ prefix: String) -> Bool {
        prefix == markerPrefix || legacyMarkerPrefixes.contains(prefix)
    }

    /// Hex digits of a `/Keywords` value. Three spellings are read: a PDF
    /// hex string `<…>` (the web exporter), a PDF literal `(…)` (Core
    /// Graphics before macOS 27), and an indirect reference `N G R` naming
    /// an object that holds the string (Core Graphics on macOS 27, measured
    /// 2026-09-19: Quartz writes `/Keywords 6 0 R` with the literal in
    /// object 6, and PDFKit's rewrite keeps the indirection). The payload
    /// is hex either way, so all three sit in the Info dictionary and
    /// survive a viewer re-save.
    private static func readKeywordsValue(_ source: Data, from: Int) -> String? {
        let at = skipWhitespace(source, from: from + "/Keywords".utf8.count)
        guard at < source.count else { return nil }
        if source[at] == 0x3c || source[at] == 0x28 {
            return readStringHex(source, at: at)
        }
        if source[at] >= 0x30, source[at] <= 0x39 {
            return readIndirectStringHex(source, at: at)
        }
        return nil
    }

    private static func skipWhitespace(_ source: Data, from: Int) -> Int {
        var at = from
        while at < source.count {
            let b = source[at]
            if b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d {
                at += 1
                continue
            }
            break
        }
        return at
    }

    /// Follows one level of indirection: `N G R` resolves to the string
    /// inside `N G obj`. One level only — a reference to a reference is not
    /// a shape we write, and chasing one risks a loop.
    private static func readIndirectStringHex(_ source: Data, at: Int) -> String? {
        guard let (objectNumber, afterNumber) = readInteger(source, at: at) else { return nil }
        let genAt = skipWhitespace(source, from: afterNumber)
        guard let (generation, afterGen) = readInteger(source, at: genAt) else { return nil }
        let rAt = skipWhitespace(source, from: afterGen)
        guard rAt < source.count, source[rAt] == 0x52 /* 'R' */ else { return nil }

        let needle = Array("\(objectNumber) \(generation) obj".utf8)
        var i = 0
        outer: while i + needle.count <= source.count {
            for n in 0..<needle.count {
                if source[i + n] != needle[n] {
                    i += 1
                    continue outer
                }
            }
            // "6 0 obj" is a suffix of "26 0 obj" — the byte before the
            // match must not be a digit, or object 26 answers for object 6.
            if i > 0, source[i - 1] >= 0x30, source[i - 1] <= 0x39 {
                i += 1
                continue
            }
            let bodyAt = skipWhitespace(source, from: i + needle.count)
            if let hex = readStringHex(source, at: bodyAt) {
                return hex
            }
            i += 1
        }
        return nil
    }

    private static func readInteger(_ source: Data, at: Int) -> (Int, Int)? {
        var at = at
        var value = 0
        var digits = 0
        while at < source.count, source[at] >= 0x30, source[at] <= 0x39 {
            value = value * 10 + Int(source[at] - 0x30)
            digits += 1
            at += 1
        }
        return digits > 0 ? (value, at) : nil
    }

    /// Hex digits inside a PDF hex string `<…>` or literal `(…)` starting
    /// at `at`. `<<` is a dictionary, not a hex string.
    private static func readStringHex(_ source: Data, at: Int) -> String? {
        var at = at
        guard at < source.count else { return nil }
        let closer: UInt8
        if source[at] == 0x3c {
            if at + 1 < source.count, source[at + 1] == 0x3c { return nil }
            closer = 0x3e
        } else if source[at] == 0x28 {
            closer = 0x29
        } else {
            return nil
        }
        at += 1
        var hex = ""
        while at < source.count, source[at] != closer {
            let ch = Character(UnicodeScalar(source[at]))
            guard ch.isHexDigit else { return nil }
            hex.append(ch)
            at += 1
        }
        guard at < source.count, !hex.isEmpty, hex.count.isMultiple(of: 2) else { return nil }
        return hex
    }

    private static func decodePayload(_ hex: String) -> String? {
        guard let bytes = bytes(fromHex: hex),
              let payload = String(bytes: bytes, encoding: .utf8)
        else { return nil }
        guard let separator = payload.firstIndex(of: "\n") else { return nil }
        let header = payload[..<separator]
        let parts = header.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let prefix = String(parts[0])
        let version = String(parts[1])
        guard isKnownPrefix(prefix), version == markerVersion else { return nil }
        return String(payload[payload.index(after: separator)...])
    }

    private static func hex(of bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func bytes(fromHex hex: String) -> [UInt8]? {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }
}
