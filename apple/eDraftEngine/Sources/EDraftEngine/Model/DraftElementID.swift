import Foundation

/// Opaque document-local identity. It is not a UUID or a paragraph index.
public struct DraftElementID: RawRepresentable, Hashable, Codable, Sendable {
  public let rawValue: String
  public init?(rawValue: String) {
    let bytes = Array(rawValue.utf8)
    guard (1...64).contains(bytes.count),
      bytes.allSatisfy({
        (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95
          || $0 == 45
      })
    else { return nil }
    self.rawValue = rawValue
  }
  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let value = try container.decode(String.self)
    guard let id = Self(rawValue: value) else { throw DraftIdentityError.invalidID }
    self = id
  }
  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue)
  }
}
public enum DraftIdentityError: Error, Equatable {
  case invalidID, invalidCounter, exhausted, missingID, duplicateID, missingCounter
}

/// Monotonic high-water mark. Keep this outside the document's undo snapshots.
/// String arithmetic matches TypeScript without integer-width limitations.
public struct DraftIDAllocator: Sendable {
  public private(set) var nextId: String = "1"
  public init() {}
  public init(nextId: String, reserved: [DraftElementID] = []) throws {
    try retain(nextId: nextId, reserved: reserved)
  }
  private static func isCounter(_ value: String) -> Bool {
    let bytes = Array(value.utf8)
    return (1...64).contains(bytes.count) && bytes.first != 48
      && bytes.allSatisfy {
        (48...57).contains($0) || (97...122).contains($0)
      }
  }
  private static func less(_ a: String, _ b: String) -> Bool {
    a.utf8.count == b.utf8.count ? a < b : a.utf8.count < b.utf8.count
  }
  private static func successor(_ value: String) throws -> String {
    var bytes = Array(value.utf8)
    for i in bytes.indices.reversed() {
      if bytes[i] != 122 {
        bytes[i] = bytes[i] == 57 ? 97 : bytes[i] + 1
        return String(decoding: bytes, as: UTF8.self)
      }
      bytes[i] = 48
    }
    guard bytes.count < 64 else { throw DraftIdentityError.exhausted }
    return "1" + String(decoding: bytes, as: UTF8.self)
  }
  public mutating func retain(nextId: String, reserved: [DraftElementID] = []) throws {
    guard Self.isCounter(nextId) else { throw DraftIdentityError.invalidCounter }
    var next = Self.less(self.nextId, nextId) ? nextId : self.nextId
    for id in reserved where Self.isCounter(id.rawValue) && !Self.less(id.rawValue, next) {
      next = try Self.successor(id.rawValue)
    }
    self.nextId = next
  }
  public mutating func mint() throws -> DraftElementID {
    let value = nextId
    nextId = try Self.successor(value)
    return DraftElementID(rawValue: value)!
  }
}

/// Explicit adoption versus restore keeps incoming document identity out of paste.
public enum DraftIdentity {
  public static func adopting(_ source: Screenplay) throws -> Screenplay {
    var allocator = DraftIDAllocator()
    return try adopting(source, allocator: &allocator)
  }
  public static func adopting(_ source: Screenplay, allocator: inout DraftIDAllocator) throws
    -> Screenplay
  {
    var candidate = allocator
    var copy = source
    for i in copy.elements.indices {
      copy.elements[i].id = copy.elements[i].type == .note ? nil : try candidate.mint()
    }
    copy.nextId = candidate.nextId
    allocator = candidate
    return copy
  }
  public static func restoring(_ source: Screenplay) throws -> Screenplay {
    guard let nextId = source.nextId else { throw DraftIdentityError.missingCounter }
    var seen = Set<DraftElementID>()
    for element in source.elements where element.type != .note {
      guard let id = element.id else { throw DraftIdentityError.missingID }
      guard seen.insert(id).inserted else { throw DraftIdentityError.duplicateID }
    }
    let allocator = try DraftIDAllocator(nextId: nextId, reserved: Array(seen))
    var copy = source
    copy.nextId = allocator.nextId
    return copy
  }
}
