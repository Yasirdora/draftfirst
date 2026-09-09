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
    /// never write them again — those files are writers' backups.
    public static let legacyMarkerPrefixes = ["EDRAFT_FOUNTAIN"]

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

    /// Hex digits of a `/Keywords` value. Accepts a PDF hex string `<…>`
    /// (the web exporter) and a PDF literal `(…)` (Core Graphics
    /// `kCGPDFContextKeywords`). The payload is hex either way, so both
    /// sit in the Info dictionary and survive a viewer re-save.
    private static func readKeywordsValue(_ source: Data, from: Int) -> String? {
        var at = from + "/Keywords".utf8.count
        while at < source.count {
            let b = source[at]
            if b == 0x20 || b == 0x09 || b == 0x0a || b == 0x0d {
                at += 1
                continue
            }
            break
        }
        guard at < source.count else { return nil }
        let closer: UInt8
        if source[at] == 0x3c {
            // `<<` is a dictionary, not a hex string.
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
