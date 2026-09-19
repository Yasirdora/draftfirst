import Compression
import Foundation

/// ZIP, as much as the .draft file needs (docs/RFC-DRAFT-FORMAT.md §4):
/// a writer of stored entries, and a tolerant reader that keeps the bytes of
/// every entry it cannot read instead of refusing the archive. Mirrors the
/// TypeScript engine's `zipwrite.ts` and `readZipEntriesTolerant` in
/// `zip.ts`; `Fixtures/draft.json` pins both, byte for byte.
public enum Zip {

    public struct Entry: Equatable, Sendable {
        public var name: String
        public var data: [UInt8]
        public init(name: String, data: [UInt8]) {
            self.name = name
            self.data = data
        }
    }

    public struct TolerantEntry: Equatable, Sendable {
        /// The name as the archive spells it, decoded as UTF-8.
        public var name: String
        public var nameBytes: [UInt8]
        /// Uncompressed when the entry could be read; otherwise whatever
        /// bytes the archive holds for it.
        public var data: [UInt8]
        /// Why the entry could not be read whole — nil when it was.
        public var error: String?
    }

    public struct TolerantResult: Equatable, Sendable {
        public var entries: [TolerantEntry]
        /// "central", or "local" when the central directory is missing or
        /// damaged and the entries came from the local headers.
        public var directory: String
    }

    public struct FormatError: Error, Equatable, Sendable {
        public let message: String
    }

    public static let maxEntries = 512
    public static let maxEntryBytes = 64 * 1024 * 1024
    public static let maxTotalBytes = 128 * 1024 * 1024
    public static let maxRatio = 200

    private static let localSig: UInt32 = 0x0403_4B50
    private static let centralSig: UInt32 = 0x0201_4B50
    private static let endSig: UInt32 = 0x0605_4B50

    // MARK: - Writing

    /// A single-disk ZIP of stored entries. The defaults are the TypeScript
    /// writer's historic bytes; the .draft writer asks for 1980-01-01 and the
    /// UTF-8 flag (§4.1, §4.4).
    public static func writeStored(
        _ entries: [Entry], dosDate: UInt16 = 0, dosTime: UInt16 = 0, utf8Names: Bool = false
    ) -> [UInt8] {
        var out: [UInt8] = []
        var central: [UInt8] = []
        for entry in entries {
            let name = Array(entry.name.utf8)
            let crc = CRC32.checksum(entry.data)
            let flags: UInt16 = utf8Names && name.contains(where: { $0 > 0x7F }) ? 0x0800 : 0
            let offset = UInt32(out.count)
            out += le32(localSig) + le16(20) + le16(flags) + le16(0) + le16(dosTime) + le16(dosDate)
            out += le32(crc) + le32(UInt32(entry.data.count)) + le32(UInt32(entry.data.count))
            out += le16(UInt16(name.count)) + le16(0) + name + entry.data
            central += le32(centralSig) + le16(20) + le16(20) + le16(flags) + le16(0) + le16(dosTime) + le16(dosDate)
            central += le32(crc) + le32(UInt32(entry.data.count)) + le32(UInt32(entry.data.count))
            central += le16(UInt16(name.count)) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(offset) + name
        }
        let centralOffset = UInt32(out.count)
        out += central
        out += le32(endSig) + le16(0) + le16(0) + le16(UInt16(entries.count)) + le16(UInt16(entries.count))
        out += le32(UInt32(central.count)) + le32(centralOffset) + le16(0)
        return out
    }

    // MARK: - Reading

    /// Every entry that can be read, and the bytes of every entry that
    /// cannot. Only an archive that is not a ZIP, or holds more entries than
    /// allowed, is refused. A declared size is never trusted to allocate.
    public static func readTolerant(_ source: [UInt8]) throws -> TolerantResult {
        let central = centralRecords(source)
        if let central, central.count > maxEntries {
            throw FormatError(message: "archive holds \(central.count) entries — over the \(maxEntries) limit")
        }
        guard let records = try central ?? localRecords(source) else {
            throw FormatError(message: "not a ZIP archive")
        }
        var entries: [TolerantEntry] = []
        var total = 0
        for record in records {
            let entry = read(source, record, totalSoFar: total)
            if entry.error == nil { total += entry.data.count }
            entries.append(entry)
        }
        return TolerantResult(entries: entries, directory: central == nil ? "local" : "central")
    }

    private struct Record {
        var nameBytes: [UInt8]
        var flags: UInt16
        var method: UInt16
        var crc: UInt32
        var packedSize: Int
        var rawSize: Int
        var dataStart: Int
        var problem: String?
    }

    private static func centralRecords(_ source: [UInt8]) -> [Record]? {
        guard source.count >= 22 else { return nil }
        var eocd = -1
        let scanFrom = max(0, source.count - 22 - 65535)
        var i = source.count - 22
        while i >= scanFrom {
            if u32(source, i) == endSig { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0, u16(source, eocd + 4) == 0, u16(source, eocd + 6) == 0 else { return nil }
        let count = Int(u16(source, eocd + 10))
        let centralOffset = u32(source, eocd + 16)
        guard count != 0xFFFF, centralOffset != 0xFFFF_FFFF else { return nil }
        var records: [Record] = []
        var at = Int(centralOffset)
        for _ in 0..<count {
            guard at + 46 <= source.count, u32(source, at) == centralSig else { return nil }
            let nameLength = Int(u16(source, at + 28))
            let extraLength = Int(u16(source, at + 30))
            let commentLength = Int(u16(source, at + 32))
            let localOffset = Int(u32(source, at + 42))
            guard at + 46 + nameLength <= source.count else { return nil }
            var record = Record(
                nameBytes: Array(source[(at + 46)..<(at + 46 + nameLength)]),
                flags: u16(source, at + 8),
                method: u16(source, at + 10),
                crc: u32(source, at + 16),
                packedSize: Int(u32(source, at + 20)),
                rawSize: Int(u32(source, at + 24)),
                dataStart: 0
            )
            if localOffset + 30 > source.count || u32(source, localOffset) != localSig {
                record.problem = "its local header is damaged"
            } else {
                record.dataStart = localOffset + 30 + Int(u16(source, localOffset + 26)) + Int(u16(source, localOffset + 28))
            }
            records.append(record)
            at += 46 + nameLength + extraLength + commentLength
        }
        return records
    }

    private static func localRecords(_ source: [UInt8]) throws -> [Record]? {
        guard source.count >= 30, u32(source, 0) == localSig else { return nil }
        var records: [Record] = []
        var at = 0
        while at + 30 <= source.count, u32(source, at) == localSig {
            if records.count == maxEntries {
                throw FormatError(message: "archive holds more than \(maxEntries) entries — over the limit")
            }
            let flags = u16(source, at + 6)
            let nameLength = Int(u16(source, at + 26))
            let extraLength = Int(u16(source, at + 28))
            let dataStart = at + 30 + nameLength + extraLength
            if dataStart > source.count { break }
            var record = Record(
                nameBytes: Array(source[(at + 30)..<(at + 30 + nameLength)]),
                flags: flags,
                method: u16(source, at + 8),
                crc: u32(source, at + 14),
                packedSize: Int(u32(source, at + 18)),
                rawSize: Int(u32(source, at + 22)),
                dataStart: dataStart
            )
            if flags & 0x8 != 0 {
                record.problem = "its sizes are only in a data descriptor"
                records.append(record)
                break
            }
            records.append(record)
            at = dataStart + record.packedSize
        }
        return records
    }

    private static func read(_ source: [UInt8], _ record: Record, totalSoFar: Int) -> TolerantEntry {
        let name = String(decoding: record.nameBytes, as: UTF8.self)
        let end = min(source.count, record.dataStart + record.packedSize)
        let packed = record.problem == nil && record.dataStart <= end ? Array(source[record.dataStart..<end]) : []
        func damaged(_ error: String) -> TolerantEntry {
            TolerantEntry(name: name, nameBytes: record.nameBytes, data: packed, error: error)
        }
        if let problem = record.problem { return damaged(problem) }
        if record.flags & 0x1 != 0 { return damaged("it is encrypted") }
        if record.dataStart + record.packedSize > source.count { return damaged("it is cut short") }
        if record.rawSize > maxEntryBytes {
            return damaged("it declares \(record.rawSize) bytes, over the \(maxEntryBytes) limit")
        }
        if totalSoFar + record.rawSize > maxTotalBytes {
            return damaged("the archive would expand past the \(maxTotalBytes)-byte limit")
        }
        var data: [UInt8]
        switch record.method {
        case 0:
            if record.rawSize != record.packedSize { return damaged("its sizes disagree") }
            data = packed
        case 8:
            if record.rawSize > max(1, record.packedSize) * maxRatio {
                return damaged("it declares a compression ratio over \(maxRatio):1")
            }
            guard let inflated = inflate(packed, declared: record.rawSize) else {
                return damaged("it could not be inflated")
            }
            if inflated.count != record.rawSize { return damaged("it inflated to a different size than it declares") }
            data = inflated
        default:
            return damaged("it uses compression method \(record.method)")
        }
        if CRC32.checksum(data) != record.crc {
            return TolerantEntry(name: name, nameBytes: record.nameBytes, data: data, error: "it failed its CRC-32 check")
        }
        return TolerantEntry(name: name, nameBytes: record.nameBytes, data: data, error: nil)
    }

    /// Raw DEFLATE into a buffer one byte larger than declared, so an entry
    /// that inflates past its record is caught at the record, never at the
    /// memory limit. Nil when the stream is not DEFLATE.
    private static func inflate(_ packed: [UInt8], declared: Int) -> [UInt8]? {
        if packed.isEmpty { return declared == 0 ? [] : nil }
        let capacity = declared + 1
        var out = [UInt8](repeating: 0, count: capacity)
        let written = out.withUnsafeMutableBufferPointer { dst in
            packed.withUnsafeBufferPointer { src in
                compression_decode_buffer(dst.baseAddress!, capacity, src.baseAddress!, packed.count, nil, COMPRESSION_ZLIB)
            }
        }
        if written == 0 && declared > 0 { return nil }
        return Array(out[0..<written])
    }

    // MARK: - Bytes

    private static func u16(_ b: [UInt8], _ at: Int) -> UInt16 {
        guard at + 2 <= b.count, at >= 0 else { return 0 }
        return UInt16(b[at]) | UInt16(b[at + 1]) << 8
    }

    private static func u32(_ b: [UInt8], _ at: Int) -> UInt32 {
        guard at + 4 <= b.count, at >= 0 else { return 0 }
        return UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24
    }

    private static func le16(_ v: UInt16) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8)] }

    private static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8(v >> 24)]
    }
}
