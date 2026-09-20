import EDraftEngine
import Foundation
import Testing

@Suite("Persistent draft identity") struct DraftIdentityConformanceTests {
  @Test func bridgePreservesIdentity() throws {
    let data = Data(
      #"{"titlePage":[],"elements":[{"type":"action","text":"Alpha","id":"a"},{"type":"action","text":"Beta","id":"z"}],"nextId":"20"}"#
        .utf8)
    let model = try JSONDecoder().decode(Screenplay.self, from: data)
    let document = DraftFile.fromScreenplay(model)
    #expect(
      document.script["elements"]?.arrayValue?.compactMap { $0.objectValue?["id"]?.stringValue }
        == ["a", "z"])
    #expect(document.script["nextId"]?.stringValue == "20")
  }
}

private struct IdentityCorpus: Decodable {
  struct Allocation: Decodable {
    struct Event: Decodable {
      let mint: Int?
      let retain: String?
    }
    struct Step: Decodable, Equatable {
      let ids: [String]
      let nextId: String
    }
    let name: String
    let nextId: String
    let reserved: [String]
    let events: [Event]
    let trace: [Step]
  }
  struct Document: Decodable {
    let name: String
    let model: Screenplay
    let script: String
    let zip: String
  }
  let allocations: [Allocation]
  let documents: [Document]
  let invalidCounters: [String]
  let invalidIDs: [String]
}
extension DraftIdentityConformanceTests {
  @Test func allocatorConformance() throws {
    let corpus = try FixtureStore.load("identity.json", as: IdentityCorpus.self)
    for c in corpus.allocations {
      var allocator = try DraftIDAllocator(
        nextId: c.nextId, reserved: c.reserved.compactMap(DraftElementID.init(rawValue:)))
      var trace: [IdentityCorpus.Allocation.Step] = []
      for event in c.events {
        if let next = event.retain { try allocator.retain(nextId: next) }
        var ids: [String] = []
        for _ in 0..<(event.mint ?? 0) { ids.append(try allocator.mint().rawValue) }
        trace.append(.init(ids: ids, nextId: allocator.nextId))
      }
      #expect(trace == c.trace, "\(c.name)")
    }
  }
  @Test func byteIdenticalDocumentRoundTrips() throws {
    let corpus = try FixtureStore.load("identity.json", as: IdentityCorpus.self)
    for c in corpus.documents {
      let model = try DraftIdentity.restoring(c.model)
      let document = try DraftFile.fromIdentifiedScreenplay(model)
      #expect(CanonicalJSON.canonical(.object(document.script)) == c.script, "\(c.name)")
      #expect(try DraftFile.toIdentifiedScreenplay(document).screenplay == model)
    }
  }
  @Test func malformedAndExhaustedIdentity() throws {
    let corpus = try FixtureStore.load("identity.json", as: IdentityCorpus.self)
    for value in corpus.invalidCounters {
      #expect(throws: DraftIdentityError.self) { try DraftIDAllocator(nextId: value) }
    }
    for value in corpus.invalidIDs { #expect(DraftElementID(rawValue: value) == nil) }
    var exhausted = try DraftIDAllocator(nextId: String(repeating: "z", count: 64))
    #expect(throws: DraftIdentityError.exhausted) { try exhausted.mint() }
    #expect(exhausted.nextId == String(repeating: "z", count: 64))
    #expect(throws: DraftIdentityError.missingCounter) { try DraftIdentity.restoring(Screenplay()) }
    #expect(throws: DraftIdentityError.missingID) {
      try DraftIdentity.restoring(
        Screenplay(elements: [.init(type: .action, text: "a")], nextId: "2"))
    }
    let element = ScreenplayElement(type: .action, text: "a", id: DraftElementID(rawValue: "1"))
    #expect(throws: DraftIdentityError.duplicateID) {
      try DraftIdentity.restoring(Screenplay(elements: [element, element], nextId: "2"))
    }
  }
  @Test func adoptionUsesDestinationCounter() throws {
    var allocator = try DraftIDAllocator(nextId: "a")
    let foreign = Screenplay(elements: [
      .init(type: .action, text: "a", id: DraftElementID(rawValue: "1")),
      .init(type: .action, text: "b", id: DraftElementID(rawValue: "2")),
    ])
    let adopted = try DraftIdentity.adopting(foreign, allocator: &allocator)
    #expect(adopted.elements.compactMap { $0.id?.rawValue } == ["a", "b"])
    #expect(allocator.nextId == "c")
  }
}

extension DraftIdentityConformanceTests {
  @Test func realContainerPreservesIdentity() throws {
    let corpus = try FixtureStore.load("identity.json", as: IdentityCorpus.self)
    for c in corpus.documents {
      let document = try DraftFile.fromIdentifiedScreenplay(c.model)
      let bytes = try DraftFile.write(document, writerName: "identity", writerVersion: "1")
      #expect(bytes.map { String(format: "%02x", $0) }.joined() == c.zip)
      let reopened = try DraftFile.read(bytes)
      #expect(try DraftFile.toIdentifiedScreenplay(reopened.document).screenplay == c.model)
    }
  }
  @Test func failedAdoptionDoesNotPartiallyConsumeCounter() throws {
    let before = String(repeating: "z", count: 63) + "y"
    var allocator = try DraftIDAllocator(nextId: before)
    #expect(throws: DraftIdentityError.exhausted) {
      try DraftIdentity.adopting(
        Screenplay(elements: [.init(type: .action, text: "a"), .init(type: .action, text: "b")]),
        allocator: &allocator)
    }
    #expect(allocator.nextId == before)
  }
}
