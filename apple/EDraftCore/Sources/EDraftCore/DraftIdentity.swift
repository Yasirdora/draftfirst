import EDraftEngine
import Foundation

extension ScriptElement {
  /// Transfer/duplicate boundary: neither the surface UUID nor document ID travels.
  public nonisolated func copyForInsertion() -> ScriptElement {
    var copy = self
    copy.id = UUID()
    copy.draftID = nil
    copy.draftIdentityOwner = nil
    return copy
  }

  /// Persistent ownership follows the RFC's first-half rule even when the
  /// surface keeps its UUID/type on the second half to preserve choreography.
  nonisolated mutating func inheritDraftIdentity(from other: ScriptElement) {
    draftID = other.draftID
    draftIdentityOwner = other.draftIdentityOwner
  }
  nonisolated mutating func clearDraftIdentity() {
    draftID = nil
    draftIdentityOwner = nil
  }
}

/// Session ownership is not serialized. A decoded or foreign element cannot
/// impersonate one of this document's undo snapshots, even with the same ID.
/// The allocator lives here, outside EditorSnapshot and native ModelUndoState.
internal struct DocumentIdentity {
  let owner = UUID()
  var allocator = DraftIDAllocator()

  mutating func reconcile(_ elements: [ScriptElement]) throws -> [ScriptElement] {
    var candidate = allocator
    var claimed = Set<DraftElementID>()
    var copies = elements
    for i in copies.indices {
      if copies[i].type == .note {
        copies[i].clearDraftIdentity()
        continue
      }
      if copies[i].draftIdentityOwner == owner, let id = copies[i].draftID,
        claimed.insert(id).inserted
      {
        continue
      }
      let id = try candidate.mint()
      copies[i].draftID = id
      copies[i].draftIdentityOwner = owner
      claimed.insert(id)
    }
    allocator = candidate
    return copies
  }

  mutating func reopen(_ model: EDraftEngine.Screenplay) throws -> Screenplay {
    let restored = try DraftIdentity.restoring(model)
    var copy = Screenplay(engineModel: restored)
    let candidate = try DraftIDAllocator(
      nextId: restored.nextId!, reserved: restored.elements.compactMap(\.id))
    for i in copy.elements.indices where copy.elements[i].type != .note {
      copy.elements[i].draftIdentityOwner = owner
    }
    allocator = candidate
    return copy
  }
}
