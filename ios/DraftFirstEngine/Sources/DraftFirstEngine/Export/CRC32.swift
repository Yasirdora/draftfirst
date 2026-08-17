import Foundation

/// CRC-32 (IEEE 802.3, polynomial 0xEDB88320) — used by the `.draft`
/// container checksum. Ported from the TypeScript engine's `crc32.ts`;
/// pinned by `Fixtures/crc32.json`.
public enum CRC32 {

    /// Lazily built lookup table, identical to the TS generator.
    private static let table: [UInt32] = {
        (0..<256).map { n -> UInt32 in
            var c = UInt32(n)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB8_8320 ^ (c >> 1)) : (c >> 1)
            }
            return c
        }
    }()

    /// Checksum of any byte sequence (string data must be UTF-8 encoded by
    /// the caller, matching the TS `TextEncoder` path).
    public static func checksum<S: Sequence<UInt8>>(_ bytes: S) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }

    /// Convenience for UTF-8 strings.
    public static func checksum(_ string: String) -> UInt32 {
        checksum(Array(string.utf8))
    }
}
