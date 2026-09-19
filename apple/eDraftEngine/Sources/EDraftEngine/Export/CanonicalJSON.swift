import Foundation

/// A JSON value as the .draft format holds it (docs/RFC-DRAFT-FORMAT.md §5.1):
/// I-JSON, integers only, objects with their members in the order they were
/// read — so a member this version does not know survives a read and a write
/// in its place. Mirrors the TypeScript engine's `JsonValue`.
public indirect enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    public var objectValue: JSONObject? {
        if case .object(let object) = self { return object }
        return nil
    }
    public var arrayValue: [JSONValue]? {
        if case .array(let array) = self { return array }
        return nil
    }
    public var stringValue: String? {
        if case .string(let string) = self { return string }
        return nil
    }
    public var intValue: Int64? {
        if case .int(let int) = self { return int }
        return nil
    }
    public var boolValue: Bool? {
        if case .bool(let bool) = self { return bool }
        return nil
    }
}

/// A JSON object whose members keep their order.
public struct JSONObject: Equatable, Sendable {
    public struct Member: Equatable, Sendable {
        public var name: String
        public var value: JSONValue
        public init(name: String, value: JSONValue) {
            self.name = name
            self.value = value
        }
    }

    public private(set) var members: [Member]

    public init(_ members: [(String, JSONValue)] = []) {
        self.members = members.map { Member(name: $0.0, value: $0.1) }
    }

    public var names: [String] { members.map(\.name) }
    public var isEmpty: Bool { members.isEmpty }

    public func has(_ name: String) -> Bool { members.contains { $0.name == name } }

    /// The member's value; setting keeps an existing member in its place and
    /// appends a new one; setting nil removes it.
    public subscript(_ name: String) -> JSONValue? {
        get { members.first { $0.name == name }?.value }
        set {
            if let index = members.firstIndex(where: { $0.name == name }) {
                if let newValue { members[index].value = newValue } else { members.remove(at: index) }
            } else if let newValue {
                members.append(Member(name: name, value: newValue))
            }
        }
    }
}

/// Strict I-JSON in, the canonical form and RFC 8785 out.
public enum CanonicalJSON {

    public struct ParseError: Error, Equatable, Sendable {
        public let reason: String
    }

    static let maxDepth = 64

    /// Parse I-JSON (RFC 7493) strictly: integers only, no duplicate names,
    /// no lone surrogates, no byte-order mark, at most 64 levels deep. Reads
    /// UTF-16 code units, as the TypeScript engine does.
    public static func parse(_ text: String) throws -> JSONValue {
        var parser = Parser(units: Array(text.utf16))
        if parser.units.first == 0xFEFF { throw ParseError(reason: "byte-order mark") }
        let value = try parser.value(depth: 1)
        parser.space()
        guard parser.at == parser.units.count else { throw ParseError(reason: "trailing characters") }
        return value
    }

    private struct Parser {
        let units: [UInt16]
        var at = 0

        init(units: [UInt16]) { self.units = units }

        func fail(_ why: String) -> ParseError { ParseError(reason: why) }

        func peek(_ offset: Int = 0) -> UInt16? {
            at + offset < units.count ? units[at + offset] : nil
        }

        mutating func space() {
            while let c = peek(), c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { at += 1 }
        }

        func startsWith(_ word: String) -> Bool {
            let w = Array(word.utf16)
            guard at + w.count <= units.count else { return false }
            return Array(units[at..<(at + w.count)]) == w
        }

        mutating func value(depth: Int) throws -> JSONValue {
            if depth > CanonicalJSON.maxDepth { throw fail("nested too deep") }
            space()
            guard let c = peek() else { throw fail("unexpected character") }
            switch c {
            case 0x7B: return .object(try object(depth: depth))
            case 0x5B: return .array(try array(depth: depth))
            case 0x22: return .string(try string())
            case 0x2D, 0x30...0x39: return .int(try number())
            default:
                if startsWith("true") { at += 4; return .bool(true) }
                if startsWith("false") { at += 5; return .bool(false) }
                if startsWith("null") { at += 4; return .null }
                throw fail("unexpected character")
            }
        }

        mutating func object(depth: Int) throws -> JSONObject {
            var out = JSONObject()
            at += 1
            space()
            if peek() == 0x7D { at += 1; return out }
            while true {
                space()
                guard peek() == 0x22 else { throw fail("expected a member name") }
                let name = try string()
                if out.has(name) { throw fail("duplicate member") }
                space()
                guard peek() == 0x3A else { throw fail("expected \":\"") }
                at += 1
                out[name] = try value(depth: depth + 1)
                space()
                if peek() == 0x2C { at += 1; continue }
                if peek() == 0x7D { at += 1; return out }
                throw fail("expected \",\" or \"}\"")
            }
        }

        mutating func array(depth: Int) throws -> [JSONValue] {
            var out: [JSONValue] = []
            at += 1
            space()
            if peek() == 0x5D { at += 1; return out }
            while true {
                out.append(try value(depth: depth + 1))
                space()
                if peek() == 0x2C { at += 1; continue }
                if peek() == 0x5D { at += 1; return out }
                throw fail("expected \",\" or \"]\"")
            }
        }

        mutating func string() throws -> String {
            at += 1
            var out: [UInt16] = []
            while true {
                guard let c = peek() else { throw fail("unterminated string") }
                if c == 0x22 { at += 1; break }
                if c < 0x20 { throw fail("unescaped control character") }
                if c == 0x5C {
                    guard let next = peek(1) else { throw fail("bad escape") }
                    at += 2
                    switch next {
                    case 0x22: out.append(0x22)
                    case 0x5C: out.append(0x5C)
                    case 0x2F: out.append(0x2F)
                    case 0x62: out.append(0x08)
                    case 0x66: out.append(0x0C)
                    case 0x6E: out.append(0x0A)
                    case 0x72: out.append(0x0D)
                    case 0x74: out.append(0x09)
                    case 0x75:
                        guard at + 4 <= units.count,
                              let code = UInt16(String(decoding: units[at..<(at + 4)], as: UTF16.self), radix: 16),
                              units[at..<(at + 4)].allSatisfy({ CanonicalJSON.isHexDigit($0) })
                        else { throw fail("bad \\u escape") }
                        out.append(code)
                        at += 4
                    default: throw fail("bad escape")
                    }
                    continue
                }
                out.append(c)
                at += 1
            }
            guard CanonicalJSON.isWellFormed(out) else { throw fail("lone surrogate") }
            return String(decoding: out, as: UTF16.self)
        }

        mutating func number() throws -> Int64 {
            let start = at
            if peek() == 0x2D { at += 1 }
            guard let first = peek(), (0x30...0x39).contains(first) else { throw fail("bad number") }
            if first == 0x30 {
                at += 1
            } else {
                while let d = peek(), (0x30...0x39).contains(d) { at += 1 }
            }
            if let after = peek(), after == 0x2E || after == 0x65 || after == 0x45 { throw fail("not an integer") }
            guard at - start <= 17,
                  let n = Int64(String(decoding: units[start..<at], as: UTF16.self)),
                  n.magnitude <= 9_007_199_254_740_991
            else { throw fail("integer out of range") }
            return n
        }
    }

    static func isHexDigit(_ c: UInt16) -> Bool {
        (0x30...0x39).contains(c) || (0x41...0x46).contains(c) || (0x61...0x66).contains(c)
    }

    static func isWellFormed(_ units: [UInt16]) -> Bool {
        var i = 0
        while i < units.count {
            let c = units[i]
            if (0xD800...0xDBFF).contains(c) {
                guard i + 1 < units.count, (0xDC00...0xDFFF).contains(units[i + 1]) else { return false }
                i += 2
                continue
            }
            if (0xDC00...0xDFFF).contains(c) { return false }
            i += 1
        }
        return true
    }

    /// A string quoted as ECMAScript's JSON.stringify quotes it.
    static func quote(_ text: String) -> String {
        var out = "\""
        for unit in text.unicodeScalars {
            switch unit.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case let v where v < 0x20:
                let hex = String(v, radix: 16)
                out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: out.unicodeScalars.append(unit)
            }
        }
        return out + "\""
    }

    /// The canonical form (§5.1): two-space indents, members in their order,
    /// and a final newline — what `JSON.stringify(value, null, 2)` writes.
    public static func canonical(_ value: JSONValue) -> String {
        pretty(value, indent: "") + "\n"
    }

    private static func pretty(_ value: JSONValue, indent: String) -> String {
        let inner = indent + "  "
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let n): return String(n)
        case .string(let s): return quote(s)
        case .array(let items):
            if items.isEmpty { return "[]" }
            return "[\n" + items.map { inner + pretty($0, indent: inner) }.joined(separator: ",\n") + "\n" + indent + "]"
        case .object(let object):
            if object.isEmpty { return "{}" }
            return "{\n" + object.members.map { inner + quote($0.name) + ": " + pretty($0.value, indent: inner) }
                .joined(separator: ",\n") + "\n" + indent + "}"
        }
    }

    /// RFC 8785 (JCS): no whitespace, members sorted by UTF-16 code units.
    public static func jcs(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let n): return String(n)
        case .string(let s): return quote(s)
        case .array(let items): return "[" + items.map(jcs).joined(separator: ",") + "]"
        case .object(let object):
            let sorted = object.members.sorted { $0.name.utf16.lexicographicallyPrecedes($1.name.utf16) }
            return "{" + sorted.map { quote($0.name) + ":" + jcs($0.value) }.joined(separator: ",") + "}"
        }
    }
}
