import Foundation

/// A part carried byte for byte: an origin, an extension, a reserved or
/// unknown part, or a damaged one kept rather than lost
/// (docs/RFC-DRAFT-FORMAT.md §5.6, §7.2, §8.2).
public struct DraftPart: Equatable, Sendable {
    public var path: String
    public var data: [UInt8]
    /// The part failed a check on read; it is written back unchanged.
    public var damaged: Bool

    public init(path: String, data: [UInt8], damaged: Bool = false) {
        self.path = path
        self.data = data
        self.damaged = damaged
    }
}

/// A .draft document: its parts. `script` and `notes` are ordered JSON trees,
/// so every member this version does not know survives in its place.
public struct DraftDocument: Equatable, Sendable {
    public var title: String?
    public var script: JSONObject
    public var notes: JSONObject?
    public var revisions: JSONObject?
    public var production: JSONObject?
    public var parts: [DraftPart]
    public var manifestExtra: JSONObject?

    public init(title: String? = nil, script: JSONObject, notes: JSONObject? = nil,
                revisions: JSONObject? = nil, production: JSONObject? = nil,
                parts: [DraftPart] = [], manifestExtra: JSONObject? = nil) {
        self.title = title
        self.script = script
        self.notes = notes
        self.revisions = revisions
        self.production = production
        self.parts = parts
        self.manifestExtra = manifestExtra
    }
}

/// What a reader or a bridge noticed. Every rung below "all valid" says one.
public struct DraftDiagnostic: Codable, Equatable, Sendable {
    public var code: String
    public var path: String?
    public var thread: String?
    public var detail: String?

    public init(code: String, path: String? = nil, thread: String? = nil, detail: String? = nil) {
        self.code = code
        self.path = path
        self.thread = thread
        self.detail = detail
    }
}

public struct DraftReadResult: Equatable, Sendable {
    public var document: DraftDocument
    public var diagnostics: [DraftDiagnostic]
    /// The file needs a newer reader to edit it without loss (§8.1).
    public var readOnly: Bool
}

/// A file this version refuses, or a document the writer cannot write.
/// `code` is one of not-a-draft, over-limits, newer-major, no-script,
/// invalid-document.
public struct DraftFormatError: Error, Equatable, Sendable {
    public let code: String
    public let message: String
}

public enum DraftFormat: String, Sendable {
    case draft, pdf, fdx, text, unknown
}

/// The .draft 1.0 file (docs/RFC-DRAFT-FORMAT.md §4–§11). The Swift port of
/// the TypeScript engine's `draftfile.ts`: the same bytes out, the same
/// documents and diagnostics in; `Fixtures/draft.json` pins both. Entries are
/// stored until the compression decision (§16 O1) lands; readers accept both.
public enum DraftFile {

    public static let mediaType = "application/vnd.edraft.draft+zip"
    public static let formatVersion = "1.0"
    static let minReader = "1.0"
    static let dosDate1980: UInt16 = 0x0021
    static let maxElements = 100_000
    static let maxElementText = 1_000_000
    static let maxTitleLines = 100
    static let maxSectionDepth = 10
    static let maxFileBytes = 128 * 1024 * 1024
    static let contextUnits = 16

    static let elementTypes: Set<String> = [
        "scene", "action", "character", "dialogue", "parenthetical", "transition", "shot",
        "general", "centered", "lyrics", "actbreak", "section", "synopsis", "pagebreak"
    ]
    static let styleTokens: [(token: String, set: StyleSet)] = [
        ("Bold", .bold), ("Italic", .italic), ("Underline", .underline),
        ("Strikeout", .strikeout), ("AllCaps", .allCaps), ("HiddenText", .hiddenText)
    ]

    enum Order {
        static let manifest = ["format", "version", "minReader", "writer", "title", "parts", "fingerprints"]
        static let script = ["titlePage", "elements", "nextId"]
        static let titleLine = ["key", "text", "alignment", "runs"]
        static let element = ["id", "type", "text", "runs", "dual", "sceneNumber", "depth"]
        static let run = ["start", "end", "styles", "highlight", "revisionID", "tagNumbers"]
        static let notes = ["threads", "nextId"]
        static let thread = ["id", "anchor", "messages", "status"]
        static let anchor = ["element", "start", "end", "quote", "prefix", "suffix"]
        static let message = ["id", "by", "role", "at", "text", "source"]
        static let status = ["state", "by", "at"]
        static let revisions = ["sets", "nextId"]
        static let revisionSet = ["id", "colour", "mark", "name", "at", "snapshot"]
        static let production = ["state", "sceneNumbers", "pages", "omissions", "tags", "delivery"]
        static let sceneNumbers = ["locked"]
        static let pages = ["fingerprint", "locks"]
        static let fingerprint = ["paginator", "paper", "sha256"]
        static let pageLock = ["label", "start", "end"]
        static let pageAnchor = ["element", "offset"]
        static let omission = ["id", "number", "elements", "issued"]
        static let tag = ["id", "label"]
        static let delivery = ["moreAndContinueds", "sceneNumbersOnRight"]
    }

    // MARK: - Small helpers

    static func isID(_ value: JSONValue?) -> Bool {
        guard let s = value?.stringValue else { return false }
        let units = Array(s.utf16)
        return (1...64).contains(units.count) && units.allSatisfy {
            (0x30...0x39).contains($0) || (0x41...0x5A).contains($0) || (0x61...0x7A).contains($0) || $0 == 0x5F || $0 == 0x2D
        }
    }

    static func isVersion(_ value: JSONValue?) -> Bool {
        guard let s = value?.stringValue else { return false }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return parts.allSatisfy { part in
            let units = Array(part.utf8)
            guard (1...9).contains(units.count), units.allSatisfy({ (0x30...0x39).contains($0) }) else { return false }
            return units.count == 1 || units[0] != 0x30
        }
    }

    static func isHex64(_ value: JSONValue?) -> Bool {
        guard let s = value?.stringValue else { return false }
        let units = Array(s.utf8)
        return units.count == 64 && units.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }

    static func length(_ text: String) -> Int { text.utf16.count }

    /// The members of `object` in canonical order: known first, then the rest.
    static func ordered(_ object: JSONObject, _ order: [String]) -> JSONObject {
        var out = JSONObject()
        for name in order { if let value = object[name] { out[name] = value } }
        for member in object.members where !out.has(member.name) { out[member.name] = member.value }
        return out
    }

    static func mapObjects(_ value: JSONValue?, _ fn: (JSONObject) -> JSONObject) -> JSONValue? {
        guard let array = value?.arrayValue else { return value }
        return .array(array.map { item in
            if case .object(let object) = item { return .object(fn(object)) }
            return item
        })
    }

    static func canonicalScript(_ script: JSONObject) -> JSONObject {
        var out = ordered(script, Order.script)
        let withRuns: (JSONObject, [String]) -> JSONObject = { object, order in
            var o = ordered(object, order)
            if let runs = mapObjects(o["runs"], { ordered($0, Order.run) }) { o["runs"] = runs }
            return o
        }
        if let lines = mapObjects(out["titlePage"], { withRuns($0, Order.titleLine) }) { out["titlePage"] = lines }
        if let elements = mapObjects(out["elements"], { withRuns($0, Order.element) }) { out["elements"] = elements }
        return out
    }

    static func canonicalNotes(_ notes: JSONObject) -> JSONObject {
        var out = ordered(notes, Order.notes)
        if let threads = mapObjects(out["threads"], { thread in
            var t = ordered(thread, Order.thread)
            if let anchor = t["anchor"]?.objectValue { t["anchor"] = .object(ordered(anchor, Order.anchor)) }
            if let messages = mapObjects(t["messages"], { ordered($0, Order.message) }) { t["messages"] = messages }
            if let status = mapObjects(t["status"], { ordered($0, Order.status) }) { t["status"] = status }
            return t
        }) { out["threads"] = threads }
        return out
    }

    static func canonicalRevisions(_ revisions: JSONObject) -> JSONObject {
        var out = ordered(revisions, Order.revisions)
        if let sets = mapObjects(out["sets"], { ordered($0, Order.revisionSet) }) { out["sets"] = sets }
        return out
    }

    static func canonicalProduction(_ production: JSONObject) -> JSONObject {
        var out = ordered(production, Order.production)
        if let sceneNumbers = out["sceneNumbers"]?.objectValue {
            out["sceneNumbers"] = .object(ordered(sceneNumbers, Order.sceneNumbers))
        }
        if let pages = out["pages"]?.objectValue {
            var p = ordered(pages, Order.pages)
            if let fingerprint = p["fingerprint"]?.objectValue {
                p["fingerprint"] = .object(ordered(fingerprint, Order.fingerprint))
            }
            if let locks = mapObjects(p["locks"], { lock in
                var l = ordered(lock, Order.pageLock)
                if let start = l["start"]?.objectValue { l["start"] = .object(ordered(start, Order.pageAnchor)) }
                if let end = l["end"]?.objectValue { l["end"] = .object(ordered(end, Order.pageAnchor)) }
                return l
            }) { p["locks"] = locks }
            out["pages"] = .object(p)
        }
        if let omissions = mapObjects(out["omissions"], { ordered($0, Order.omission) }) { out["omissions"] = omissions }
        if let tags = mapObjects(out["tags"], { ordered($0, Order.tag) }) { out["tags"] = tags }
        if let delivery = out["delivery"]?.objectValue {
            out["delivery"] = .object(ordered(delivery, Order.delivery))
        }
        return out
    }

    // MARK: - Schema checks (§5.2–§5.4)

    static func checkRuns(_ runs: JSONValue?, textLength: Int) -> String? {
        guard let runs else { return nil }
        guard let array = runs.arrayValue else { return "runs is not an array" }
        var end: Int64 = 0
        for item in array {
            guard let run = item.objectValue else { return "a run is not an object" }
            guard let start = run["start"]?.intValue, let stop = run["end"]?.intValue,
                  start >= end, stop > start, stop <= Int64(textLength)
            else { return "a run is out of place" }
            end = stop
            guard let styles = run["styles"]?.arrayValue,
                  styles.allSatisfy({ s in s.stringValue.map { t in styleTokens.contains { $0.token == t } } ?? false })
            else { return "a run has unknown styles" }
            if Set(styles.compactMap(\.stringValue)).count != styles.count { return "a run repeats a style" }
            if let highlight = run["highlight"], highlight != .string("yellow") { return "a run has an unknown highlight" }
            if let revision = run["revisionID"], revision.intValue == nil { return "a run has a bad revisionID" }
            if let tags = run["tagNumbers"], !(tags.arrayValue?.allSatisfy { $0.intValue != nil } ?? false) {
                return "a run has bad tagNumbers"
            }
        }
        return nil
    }

    /// Problems with script.json, or nil when it is a valid script.
    public static func checkScript(_ value: JSONValue) -> String? {
        guard let script = value.objectValue else { return "script.json is not an object" }
        guard let titlePage = script["titlePage"]?.arrayValue else { return "titlePage is not an array" }
        if titlePage.count > maxTitleLines { return "too many title-page lines" }
        for item in titlePage {
            guard let line = item.objectValue, let text = line["text"]?.stringValue else { return "a title-page line has no text" }
            if let key = line["key"], key.stringValue == nil { return "a title-page key is not a string" }
            if let alignment = line["alignment"], !["left", "center", "right"].contains(alignment.stringValue ?? "\u{0}") {
                return "a title-page alignment is unknown"
            }
            if let problem = checkRuns(line["runs"], textLength: length(text)) { return problem }
        }
        guard let elements = script["elements"]?.arrayValue else { return "elements is not an array" }
        if elements.count > maxElements { return "too many elements" }
        var ids = Set<String>()
        for item in elements {
            guard let element = item.objectValue else { return "an element is not an object" }
            guard isID(element["id"]), let id = element["id"]?.stringValue else { return "an element id is malformed" }
            if ids.contains(id) { return "element id \(id) is used twice" }
            ids.insert(id)
            guard let type = element["type"]?.stringValue, elementTypes.contains(type) else { return "element \(id) has an unknown type" }
            guard let text = element["text"]?.stringValue else { return "element \(id) has no text" }
            if length(text) > maxElementText { return "element \(id) is too long" }
            if let problem = checkRuns(element["runs"], textLength: length(text)) { return "element \(id): \(problem)" }
            if let dual = element["dual"], dual.boolValue == nil { return "element \(id) has a bad dual" }
            if let sceneNumber = element["sceneNumber"], sceneNumber.stringValue == nil { return "element \(id) has a bad sceneNumber" }
            if let depth = element["depth"] {
                guard let d = depth.intValue, d >= 1, d <= Int64(maxSectionDepth) else { return "element \(id) has a bad depth" }
            }
        }
        if !isID(script["nextId"]) { return "nextId is malformed" }
        return nil
    }

    /// Problems with notes.json, or nil when it is valid.
    public static func checkNotes(_ value: JSONValue) -> String? {
        guard let notes = value.objectValue else { return "notes.json is not an object" }
        guard let threads = notes["threads"]?.arrayValue else { return "threads is not an array" }
        var ids = Set<String>()
        func claim(_ value: JSONValue?) -> String? {
            guard isID(value), let id = value?.stringValue else { return "a note id is malformed" }
            if ids.contains(id) { return "note id \(id) is used twice" }
            ids.insert(id)
            return nil
        }
        func optionalStrings(_ object: JSONObject, _ names: [String]) -> Bool {
            names.allSatisfy { object[$0] == nil || object[$0]?.stringValue != nil }
        }
        for item in threads {
            guard let thread = item.objectValue else { return "a thread is not an object" }
            if let problem = claim(thread["id"]) { return problem }
            if let anchorValue = thread["anchor"] {
                guard let anchor = anchorValue.objectValue else { return "an anchor is not an object" }
                if !isID(anchor["element"]) { return "an anchor names no element" }
                let start = anchor["start"], end = anchor["end"]
                if (start == nil) != (end == nil) { return "an anchor has only one end" }
                if start != nil {
                    guard let s = start?.intValue, let e = end?.intValue, s >= 0, e >= s else { return "an anchor range is malformed" }
                }
                if !optionalStrings(anchor, ["quote", "prefix", "suffix"]) { return "an anchor quote is not a string" }
            }
            guard let messages = thread["messages"]?.arrayValue, !messages.isEmpty else { return "a thread has no messages" }
            for m in messages {
                guard let message = m.objectValue else { return "a message is not an object" }
                if let problem = claim(message["id"]) { return problem }
                if message["text"]?.stringValue == nil { return "a message has no text" }
                if !optionalStrings(message, ["by", "role", "at"]) { return "a message field is not a string" }
                if let source = message["source"] {
                    guard let s = source.objectValue, s.members.allSatisfy({ $0.value.stringValue != nil }) else {
                        return "a message source is malformed"
                    }
                }
            }
            if let status = thread["status"] {
                guard let entries = status.arrayValue else { return "status is not an array" }
                for e in entries {
                    guard let entry = e.objectValue else { return "a status entry is not an object" }
                    if entry["state"] != .string("open") && entry["state"] != .string("resolved") { return "a status state is unknown" }
                    if !optionalStrings(entry, ["by", "at"]) { return "a status field is not a string" }
                }
            }
        }
        if !isID(notes["nextId"]) { return "nextId is malformed" }
        return nil
    }


    static let revisionColours: Set<String> = [
        "White", "Blue", "Pink", "Yellow", "Green", "Goldenrod", "Salmon", "Cherry", "Buff"
    ]

    static func isRevisionColour(_ value: JSONValue?) -> Bool {
        guard let s = value?.stringValue else { return false }
        if revisionColours.contains(s) { return true }
        for prefix in ["Double ", "Triple "] where s.hasPrefix(prefix) {
            if revisionColours.contains(String(s.dropFirst(prefix.count))) { return true }
        }
        return false
    }

    static func checkPageAnchor(_ value: JSONValue?, _ name: String) -> String? {
        guard let object = value?.objectValue else { return "a page lock \(name) is not an object" }
        if !isID(object["element"]) { return "a page lock \(name) names no element" }
        guard let offset = object["offset"]?.intValue, offset >= 0 else {
            return "a page lock \(name) offset is malformed"
        }
        return nil
    }

    static func checkRevisions(_ value: JSONValue) -> String? {
        guard let revisions = value.objectValue else { return "revisions.json is not an object" }
        guard let sets = revisions["sets"]?.arrayValue else { return "sets is not an array" }
        var ids = Set<String>()
        for item in sets {
            guard let set = item.objectValue else { return "a revision set is not an object" }
            guard isID(set["id"]), let id = set["id"]?.stringValue else { return "a revision set id is malformed" }
            if ids.contains(id) { return "revision set id \(id) is used twice" }
            ids.insert(id)
            if !isRevisionColour(set["colour"]) { return "a revision colour is unknown" }
            if let mark = set["mark"], mark.stringValue == nil { return "a revision mark is not a string" }
            if let name = set["name"], name.stringValue == nil { return "a revision name is not a string" }
            if let at = set["at"], at.stringValue == nil { return "a revision time is not a string" }
            guard let snapshot = set["snapshot"]?.stringValue, isValidPath(snapshot) else {
                return "a revision snapshot path is not allowed"
            }
        }
        if !isID(revisions["nextId"]) { return "nextId is malformed" }
        return nil
    }

    static func checkProduction(_ value: JSONValue) -> String? {
        guard let production = value.objectValue else { return "production.json is not an object" }
        let state = production["state"]?.stringValue
        if state != "development" && state != "prepared" && state != "issued" && state != "archived" {
            return "production state is unknown"
        }
        if let sceneNumbersValue = production["sceneNumbers"] {
            guard let sceneNumbers = sceneNumbersValue.objectValue else { return "sceneNumbers is not an object" }
            if let locked = sceneNumbers["locked"], locked.boolValue == nil { return "sceneNumbers.locked is not a boolean" }
        }
        if let pagesValue = production["pages"] {
            guard let pages = pagesValue.objectValue else { return "pages is not an object" }
            if let fingerprintValue = pages["fingerprint"] {
                guard let fingerprint = fingerprintValue.objectValue else { return "a layout fingerprint is not an object" }
                if fingerprint["paginator"]?.stringValue == nil { return "a layout fingerprint has no paginator" }
                if fingerprint["paper"]?.stringValue == nil { return "a layout fingerprint has no paper" }
                if !isHex64(fingerprint["sha256"]) { return "a layout fingerprint digest is malformed" }
            }
            if let locksValue = pages["locks"] {
                guard let locks = locksValue.arrayValue else { return "page locks is not an array" }
                for item in locks {
                    guard let lock = item.objectValue else { return "a page lock is not an object" }
                    if lock["label"]?.stringValue == nil { return "a page lock has no label" }
                    if let problem = checkPageAnchor(lock["start"], "start") { return problem }
                    if let problem = checkPageAnchor(lock["end"], "end") { return problem }
                }
            }
        }
        if let omissionsValue = production["omissions"] {
            guard let omissions = omissionsValue.arrayValue else { return "omissions is not an array" }
            var ids = Set<String>()
            for item in omissions {
                guard let row = item.objectValue else { return "an omission is not an object" }
                guard isID(row["id"]), let id = row["id"]?.stringValue else { return "an omission id is malformed" }
                if ids.contains(id) { return "omission id \(id) is used twice" }
                ids.insert(id)
                if row["number"]?.stringValue == nil { return "an omission has no scene number" }
                guard let elements = row["elements"]?.arrayValue, !elements.isEmpty,
                      elements.allSatisfy({ $0.stringValue.map { isID(.string($0)) } ?? false }) else {
                    return "an omission elements list is malformed"
                }
                if let issued = row["issued"], !isID(issued) { return "an omission issued set is malformed" }
            }
        }
        if let tagsValue = production["tags"] {
            guard let tags = tagsValue.arrayValue else { return "tags is not an array" }
            for item in tags {
                guard let tag = item.objectValue else { return "a tag is not an object" }
                guard let id = tag["id"]?.stringValue, !id.isEmpty else { return "a tag has no id" }
                if tag["label"]?.stringValue == nil { return "a tag has no label" }
            }
        }
        if let deliveryValue = production["delivery"] {
            guard let delivery = deliveryValue.objectValue else { return "delivery is not an object" }
            for name in ["moreAndContinueds", "sceneNumbersOnRight"] {
                if let flag = delivery[name], flag.boolValue == nil { return "delivery.\(name) is not a boolean" }
            }
        }
        return nil
    }

    static func checkManifest(_ value: JSONValue) -> String? {
        guard let manifest = value.objectValue else { return "manifest.json is not an object" }
        if manifest["format"] != .string("draft") { return "format is not \"draft\"" }
        for name in ["version", "minReader"] where !isVersion(manifest[name]) { return "\(name) is malformed" }
        guard let writer = manifest["writer"]?.objectValue, writer["name"]?.stringValue != nil, writer["version"]?.stringValue != nil
        else { return "writer is malformed" }
        if let title = manifest["title"], title.stringValue == nil { return "title is not a string" }
        guard let parts = manifest["parts"]?.arrayValue else { return "parts is not an array" }
        for item in parts {
            guard let part = item.objectValue, part["path"]?.stringValue != nil else { return "a part has no path" }
            if !isHex64(part["sha256"]) { return "a part digest is malformed" }
            guard let size = part["size"]?.intValue, size >= 0 else { return "a part size is malformed" }
        }
        guard let fingerprints = manifest["fingerprints"]?.objectValue else { return "fingerprints is missing" }
        if !isHex64(fingerprints["script"]) { return "the script fingerprint is malformed" }
        if let notes = fingerprints["notes"], !isHex64(notes) { return "the notes fingerprint is malformed" }
        return nil
    }

    /// §4.2's path rules.
    public static func isValidPath(_ path: String) -> Bool {
        let units = Array(path.utf16)
        if units.isEmpty || units.first == 0x2F || units.last == 0x2F || units.contains(0x5C) { return false }
        if units.contains(where: { $0 < 0x20 || $0 == 0x7F }) { return false }
        if units.count >= 2, units[1] == 0x3A, (0x41...0x5A).contains(units[0]) || (0x61...0x7A).contains(units[0]) { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    // MARK: - Anchors (§6.5)

    static func occurrences(_ haystack: [UInt16], _ needle: [UInt16]) -> [Int] {
        guard !needle.isEmpty, needle.count <= haystack.count else { return [] }
        var found: [Int] = []
        for at in 0...(haystack.count - needle.count) where Array(haystack[at..<(at + needle.count)]) == needle {
            found.append(at)
        }
        return found
    }

    static func refindAnchors(script: JSONObject, notes: inout JSONObject, diagnostics: inout [DraftDiagnostic], idsTrusted: Bool) {
        var order: [String] = []
        var texts: [String: [UInt16]] = [:]
        for item in script["elements"]?.arrayValue ?? [] {
            guard let e = item.objectValue, let id = e["id"]?.stringValue, let text = e["text"]?.stringValue else { continue }
            order.append(id)
            texts[id] = Array(text.utf16)
        }
        guard var threads = notes["threads"]?.arrayValue else { return }
        for index in threads.indices {
            guard var thread = threads[index].objectValue, let id = thread["id"]?.stringValue,
                  var anchor = thread["anchor"]?.objectValue, let element = anchor["element"]?.stringValue
            else { continue }
            let quote = anchor["quote"]?.stringValue.map { Array($0.utf16) }
            let prefix = Array((anchor["prefix"]?.stringValue ?? "").utf16)
            let suffix = Array((anchor["suffix"]?.stringValue ?? "").utf16)
            let start = anchor["start"]?.intValue.map(Int.init)
            let end = anchor["end"]?.intValue.map(Int.init)
            let text = idsTrusted ? texts[element] : nil
            let needle = quote.map { prefix + $0 + suffix }
            func place(_ at: Int) {
                anchor["start"] = .int(Int64(at + prefix.count))
                anchor["end"] = .int(Int64(at + prefix.count + (quote?.count ?? 0)))
            }
            func store() {
                thread["anchor"] = .object(anchor)
                threads[index] = .object(thread)
            }
            if let text {
                guard let quote else { continue }
                if let start, let end {
                    let s = min(max(start, 0), text.count), e = min(max(end, 0), text.count)
                    if s <= e, Array(text[s..<e]) == quote { continue }
                }
                let found = occurrences(text, needle!)
                if found.count == 1 {
                    place(found[0])
                    store()
                    continue
                }
                if let start, let end {
                    let s = min(start, text.count)
                    anchor["start"] = .int(Int64(s))
                    anchor["end"] = .int(Int64(max(s, min(end, text.count))))
                    store()
                }
                diagnostics.append(DraftDiagnostic(code: "anchor-words-changed", thread: id))
                continue
            }
            if let needle {
                var hits: [(String, Int)] = []
                for elementID in order {
                    for at in occurrences(texts[elementID]!, needle) { hits.append((elementID, at)) }
                }
                if hits.count == 1 {
                    anchor["element"] = .string(hits[0].0)
                    place(hits[0].1)
                    store()
                    diagnostics.append(DraftDiagnostic(code: "anchor-moved", thread: id))
                    continue
                }
            }
            thread["anchor"] = nil
            threads[index] = .object(thread)
            diagnostics.append(DraftDiagnostic(code: "anchor-detached", thread: id))
        }
        notes["threads"] = .array(threads)
    }

    /// JavaScript's \s, one UTF-16 unit at a time.
    static func isSpaceUnit(_ c: UInt16) -> Bool {
        (0x09...0x0D).contains(c) || c == 0x20 || c == 0xA0 || c == 0x1680 || (0x2000...0x200A).contains(c) ||
            c == 0x2028 || c == 0x2029 || c == 0x202F || c == 0x205F || c == 0x3000 || c == 0xFEFF
    }

    /// The words either side of a quote (§6.3): up to 16 UTF-16 units each
    /// side, the window's outer edge moved inward so it never cuts a word.
    public static func anchorContext(_ text: String, start: Int, end: Int) -> (prefix: String, suffix: String) {
        let units = Array(text.utf16)
        var from = max(0, start - contextUnits)
        if from > 0 && !isSpaceUnit(units[from - 1]) {
            while from < start && !isSpaceUnit(units[from]) { from += 1 }
            if from < start { from += 1 }
        }
        var to = min(units.count, end + contextUnits)
        if to < units.count && !isSpaceUnit(units[to]) {
            while to > end && !isSpaceUnit(units[to - 1]) { to -= 1 }
            if to > end { to -= 1 }
        }
        return (String(decoding: units[from..<start], as: UTF16.self), String(decoding: units[end..<to], as: UTF16.self))
    }

    // MARK: - Bridges to today's model

    static func runsToJSON(_ runs: [StyleRun]?) -> JSONValue? {
        guard let runs else { return nil }
        return .array(runs.map { run in
            var out = JSONObject([
                ("start", .int(Int64(run.start))),
                ("end", .int(Int64(run.end))),
                ("styles", .array(styleTokens.filter { run.styles.contains($0.set) }.map { .string($0.token) }))
            ])
            if let highlight = run.highlight { out["highlight"] = .string(highlight.rawValue) }
            if let revisionID = run.revisionID { out["revisionID"] = .int(Int64(revisionID)) }
            if let tags = run.tagNumbers { out["tagNumbers"] = .array(tags.map { .int(Int64($0)) }) }
            return .object(out)
        })
    }

    static func runsFromJSON(_ value: JSONValue?) -> [StyleRun]? {
        guard let array = value?.arrayValue else { return nil }
        return array.compactMap { item in
            guard let run = item.objectValue else { return nil }
            var styles: StyleSet = []
            for token in run["styles"]?.arrayValue ?? [] {
                if let match = styleTokens.first(where: { $0.token == token.stringValue }) { styles.insert(match.set) }
            }
            return StyleRun(
                start: Int(run["start"]?.intValue ?? 0),
                end: Int(run["end"]?.intValue ?? 0),
                styles: styles,
                revisionID: run["revisionID"]?.intValue.map(Int.init),
                tagNumbers: run["tagNumbers"]?.arrayValue?.compactMap { $0.intValue.map(Int.init) },
                highlight: run["highlight"]?.stringValue.flatMap(HighlightColor.init(rawValue:))
            )
        }
    }

    /// A document from today's model (§6.6): counter ids, and every note
    /// element a thread anchored to the whole element after it. A note after
    /// the last element is about no line: it is a detached thread.
    public static func fromScreenplay(_ screenplay: Screenplay, title: String? = nil) -> DraftDocument {
        var elements: [JSONValue] = []
        var pending: [String] = []
        var threads: [JSONValue] = []
        var nextNote = 1
        func anchorPending(_ element: String?) {
            for text in pending {
                var thread = JSONObject([("id", .string(String(nextNote, radix: 36)))])
                nextNote += 1
                if let element { thread["anchor"] = .object(JSONObject([("element", .string(element))])) }
                thread["messages"] = .array([.object(JSONObject([("id", .string(String(nextNote, radix: 36))), ("text", .string(text))]))])
                nextNote += 1
                threads.append(.object(thread))
            }
            pending.removeAll()
        }
        for element in screenplay.elements {
            if element.type == .note {
                pending.append(element.text)
                continue
            }
            let id = String(elements.count + 1, radix: 36)
            var out = JSONObject([("id", .string(id)), ("type", .string(element.type.rawValue)), ("text", .string(element.text))])
            if let runs = runsToJSON(element.runs) { out["runs"] = runs }
            if let dual = element.dual { out["dual"] = .bool(dual) }
            if let sceneNumber = element.sceneNumber { out["sceneNumber"] = .string(sceneNumber) }
            if let depth = element.depth { out["depth"] = .int(Int64(depth)) }
            elements.append(.object(out))
            anchorPending(id)
        }
        anchorPending(nil)
        let titlePage: [JSONValue] = screenplay.titlePage.map { line in
            var out = JSONObject()
            if let key = line.key { out["key"] = .string(key) }
            out["text"] = .string(line.text)
            if let alignment = line.alignment { out["alignment"] = .string(alignment.rawValue) }
            if let runs = runsToJSON(line.runs) { out["runs"] = runs }
            return .object(out)
        }
        var document = DraftDocument(
            title: title,
            script: JSONObject([
                ("titlePage", .array(titlePage)),
                ("elements", .array(elements)),
                ("nextId", .string(String(elements.count + 1, radix: 36)))
            ])
        )
        if !threads.isEmpty {
            document.notes = JSONObject([("threads", .array(threads)), ("nextId", .string(String(nextNote, radix: 36)))])
        }
        return document
    }

    /// Today's model from a document: each thread a note element in front
    /// of its element, one line per message as "Name (Role): text". A word
    /// anchor degrades to its line; a detached thread goes to the end.
    public static func toScreenplay(_ document: DraftDocument) -> (screenplay: Screenplay, diagnostics: [DraftDiagnostic]) {
        var diagnostics: [DraftDiagnostic] = []
        var notesFor: [String: [String]] = [:]
        var detached: [String] = []
        for item in document.notes?["threads"]?.arrayValue ?? [] {
            guard let thread = item.objectValue else { continue }
            let id = thread["id"]?.stringValue
            let text = (thread["messages"]?.arrayValue ?? []).compactMap(\.objectValue).map { message -> String in
                let body = message["text"]?.stringValue ?? ""
                guard let by = message["by"]?.stringValue else { return body }
                if let role = message["role"]?.stringValue { return "\(by) (\(role)): \(body)" }
                return "\(by): \(body)"
            }.joined(separator: "\n")
            guard let anchor = thread["anchor"]?.objectValue, let element = anchor["element"]?.stringValue else {
                detached.append(text)
                diagnostics.append(DraftDiagnostic(code: "anchor-detached", thread: id))
                continue
            }
            if anchor["start"] != nil || anchor["quote"] != nil {
                diagnostics.append(DraftDiagnostic(code: "anchor-degraded", thread: id))
            }
            notesFor[element, default: []].append(text)
        }
        var elements: [ScreenplayElement] = []
        for item in document.script["elements"]?.arrayValue ?? [] {
            guard let e = item.objectValue, let id = e["id"]?.stringValue else { continue }
            for text in notesFor[id] ?? [] { elements.append(ScreenplayElement(type: .note, text: text)) }
            elements.append(ScreenplayElement(
                type: ElementKind(rawValue: e["type"]?.stringValue ?? "") ?? .action,
                text: e["text"]?.stringValue ?? "",
                runs: runsFromJSON(e["runs"]),
                dual: e["dual"]?.boolValue,
                sceneNumber: e["sceneNumber"]?.stringValue,
                depth: e["depth"]?.intValue.map(Int.init)
            ))
        }
        for text in detached { elements.append(ScreenplayElement(type: .note, text: text)) }
        let titlePage: [TitlePageLine] = (document.script["titlePage"]?.arrayValue ?? []).compactMap(\.objectValue).map { line in
            TitlePageLine(
                text: line["text"]?.stringValue ?? "",
                alignment: line["alignment"]?.stringValue.flatMap(TitlePageAlignment.init(rawValue:)),
                runs: runsFromJSON(line["runs"]),
                key: line["key"]?.stringValue
            )
        }
        return (Screenplay(titlePage: titlePage, elements: elements), diagnostics)
    }

    // MARK: - Recognising a file by its first bytes (§11.1)

    static func startsWith(_ bytes: [UInt8], _ at: Int, _ ascii: [UInt8]) -> Bool {
        guard at + ascii.count <= bytes.count else { return false }
        return Array(bytes[at..<(at + ascii.count)]) == ascii
    }

    static func isUTF8(_ bytes: [UInt8]) -> Bool {
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            let need: Int
            switch b {
            case 0x00...0x7F: need = 0
            case 0xC2...0xDF: need = 1
            case 0xE0...0xEF: need = 2
            case 0xF0...0xF4: need = 3
            default: return false
            }
            if need > 0 && i + need >= bytes.count { return false }
            for k in stride(from: 1, through: need, by: 1) where bytes[i + k] & 0xC0 != 0x80 { return false }
            if need == 2 {
                let code = (UInt32(b & 0x0F) << 12) | (UInt32(bytes[i + 1] & 0x3F) << 6) | UInt32(bytes[i + 2] & 0x3F)
                if code < 0x800 || (0xD800...0xDFFF).contains(code) { return false }
            }
            if need == 3 {
                let code = (UInt32(b & 0x07) << 18) | (UInt32(bytes[i + 1] & 0x3F) << 12) |
                    (UInt32(bytes[i + 2] & 0x3F) << 6) | UInt32(bytes[i + 3] & 0x3F)
                if code < 0x10000 || code > 0x10FFFF { return false }
            }
            i += need + 1
        }
        return true
    }

    /// What a file is, from its bytes — never from its name.
    public static func detect(_ bytes: [UInt8]) -> DraftFormat {
        let pk: [UInt8] = [0x50, 0x4B, 0x03, 0x04]
        if startsWith(bytes, 0, pk) {
            var at = 0
            var n = 0
            while n < 512, at + 30 <= bytes.count, startsWith(bytes, at, pk) {
                let nameLength = Int(bytes[at + 26]) | Int(bytes[at + 27]) << 8
                let extraLength = Int(bytes[at + 28]) | Int(bytes[at + 29]) << 8
                let packed = Int(bytes[at + 18]) | Int(bytes[at + 19]) << 8 | Int(bytes[at + 20]) << 16 | Int(bytes[at + 21]) << 24
                let name = Array(bytes[(at + 30)..<min(bytes.count, at + 30 + nameLength)])
                if name == Array("mimetype".utf8) || name == Array("manifest.json".utf8) || name == Array("script.json".utf8) {
                    return .draft
                }
                at += 30 + nameLength + extraLength + packed
                n += 1
            }
            return .unknown
        }
        if startsWith(bytes, 0, Array("%PDF-".utf8)) { return .pdf }
        var at = startsWith(bytes, 0, [0xEF, 0xBB, 0xBF]) ? 3 : 0
        while at < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[at]) { at += 1 }
        if startsWith(bytes, at, Array("<?xml".utf8)) || startsWith(bytes, at, Array("<FinalDraft".utf8)) { return .fdx }
        return isUTF8(bytes) ? .text : .unknown
    }

    // MARK: - Writing (§4, §5)

    static let fixedPaths = ["mimetype", "manifest.json", "script.json", "notes.json", "script.fountain"]

    static func byUnits(_ a: String, _ b: String) -> Bool { a.utf16.lexicographicallyPrecedes(b.utf16) }

    /// Write a document as a .draft file — the same bytes on every platform.
    public static func write(_ document: DraftDocument, writerName: String, writerVersion: String) throws -> [UInt8] {
        if let problem = checkScript(.object(document.script)) {
            throw DraftFormatError(code: "invalid-document", message: "the script is invalid: \(problem)")
        }
        if let notes = document.notes, let problem = checkNotes(.object(notes)) {
            throw DraftFormatError(code: "invalid-document", message: "the notes are invalid: \(problem)")
        }
        if let revisions = document.revisions, let problem = checkRevisions(.object(revisions)) {
            throw DraftFormatError(code: "invalid-document", message: "the revisions are invalid: \(problem)")
        }
        if let production = document.production, let problem = checkProduction(.object(production)) {
            throw DraftFormatError(code: "invalid-document", message: "the production data is invalid: \(problem)")
        }
        let script = canonicalScript(document.script)
        let notes = document.notes.map(canonicalNotes)
        let revisions = document.revisions.map(canonicalRevisions)
        let production = document.production.map(canonicalProduction)

        var fresh: [String: [UInt8]] = [:]
        fresh["script.json"] = Array(CanonicalJSON.canonical(.object(script)).utf8)
        if let notes { fresh["notes.json"] = Array(CanonicalJSON.canonical(.object(notes)).utf8) }
        var forRendition = document
        forRendition.script = script
        fresh["script.fountain"] = Array(Fountain.serialise(toScreenplay(forRendition).screenplay).utf8)
        if let revisions { fresh["revisions.json"] = Array(CanonicalJSON.canonical(.object(revisions)).utf8) }
        if let production { fresh["production.json"] = Array(CanonicalJSON.canonical(.object(production)).utf8) }

        var carried: [(String, [UInt8])] = []
        func isCarried(_ path: String) -> Bool { carried.contains { $0.0 == path } }
        for part in document.parts {
            var path = part.path
            if !isValidPath(path) {
                throw DraftFormatError(code: "invalid-document", message: "part path \"\(path)\" is not allowed")
            }
            if fresh[path] != nil || path == "mimetype" || path == "manifest.json" {
                if !part.damaged {
                    throw DraftFormatError(code: "invalid-document", message: "part \"\(path)\" is written by the writer")
                }
                path = "damaged/" + path
            }
            while isCarried(path) { path = "damaged/" + path }
            carried.append((path, part.data))
        }
        let keys = carried.map(\.0)
        let origin = keys.filter { $0.hasPrefix("origin/") }.sorted(by: byUnits)
        let history = keys.filter { $0.hasPrefix("history/") }.sorted(by: byUnits)
        let extensions = keys.filter { $0.hasPrefix("ext/") }.sorted(by: byUnits)
        let others = keys.filter { !$0.hasPrefix("origin/") && !$0.hasPrefix("ext/") && !$0.hasPrefix("history/") }.sorted(by: byUnits)
        var remaining = Dictionary(carried, uniquingKeysWith: { first, _ in first })
        var body: [(String, [UInt8])] = []
        for path in ["script.json", "notes.json", "script.fountain"] {
            if let data = fresh[path] {
                body.append((path, data))
            } else if let data = remaining[path] {
                body.append((path, data))
                remaining[path] = nil
            }
        }
        for path in ["revisions.json", "production.json"] {
            if let data = fresh[path] { body.append((path, data)) }
        }
        for path in history + origin + others + extensions {
            if let data = remaining[path] { body.append((path, data)) }
        }

        var manifest = JSONObject([
            ("format", .string("draft")),
            ("version", .string(formatVersion)),
            ("minReader", .string(minReader)),
            ("writer", .object(JSONObject([("name", .string(writerName)), ("version", .string(writerVersion))])))
        ])
        if let title = document.title { manifest["title"] = .string(title) }
        manifest["parts"] = .array(body.map { path, data in
            .object(JSONObject([("path", .string(path)), ("sha256", .string(SHA256Digest.hex(data))), ("size", .int(Int64(data.count)))]))
        })
        var fingerprints = JSONObject([("script", .string(SHA256Digest.hex(Array(CanonicalJSON.jcs(.object(script)).utf8))))])
        if let notes { fingerprints["notes"] = .string(SHA256Digest.hex(Array(CanonicalJSON.jcs(.object(notes)).utf8))) }
        manifest["fingerprints"] = .object(fingerprints)
        for member in document.manifestExtra?.members ?? [] where !Order.manifest.contains(member.name) {
            manifest[member.name] = member.value
        }

        let entries = [
            Zip.Entry(name: "mimetype", data: Array(mediaType.utf8)),
            Zip.Entry(name: "manifest.json", data: Array(CanonicalJSON.canonical(.object(manifest)).utf8))
        ] + body.map { Zip.Entry(name: $0.0, data: $0.1) }
        return Zip.writeStored(entries, dosDate: dosDate1980, dosTime: 0, utf8Names: true)
    }

    // MARK: - Reading (§7, §8, §11)

    static func readJSON(_ data: [UInt8]) -> JSONValue? {
        guard isUTF8(data) else { return nil }
        return try? CanonicalJSON.parse(String(decoding: data, as: UTF8.self))
    }

    static func version(_ s: String) -> (Int, Int) {
        let parts = s.split(separator: ".").map { Int($0) ?? 0 }
        return (parts.first ?? 0, parts.count > 1 ? parts[1] : 0)
    }

    /// Read a .draft file, every rung of the recovery ladder (§7.2) included.
    /// A file with no script in any readable form is refused — never opened
    /// empty.
    public static func read(_ bytes: [UInt8]) throws -> DraftReadResult {
        if bytes.count > maxFileBytes {
            throw DraftFormatError(code: "over-limits", message: "the file is over the \(maxFileBytes)-byte limit")
        }
        let zip: Zip.TolerantResult
        do {
            zip = try Zip.readTolerant(bytes)
        } catch let error as Zip.FormatError {
            let code = error.message.contains("limit") ? "over-limits" : "not-a-draft"
            throw DraftFormatError(code: code, message: "not a readable .draft: \(error.message)")
        }
        var diagnostics: [DraftDiagnostic] = []
        if zip.directory == "local" {
            diagnostics.append(DraftDiagnostic(code: "directory-damaged", detail: "read from the local headers"))
        }

        var entryOrder: [String] = []
        var entries: [String: (data: [UInt8], error: String?)] = [:]
        var seen = Set<String>()
        var parts: [DraftPart] = []
        for (index, entry) in zip.entries.enumerated() {
            let validName = isUTF8(entry.nameBytes) && isValidPath(entry.name)
            let key = entry.name.precomposedStringWithCanonicalMapping.lowercased()
            if !validName || seen.contains(key) {
                diagnostics.append(DraftDiagnostic(
                    code: validName ? "duplicate-entry" : "invalid-entry-name",
                    path: "damaged/entry-\(index)",
                    detail: validName ? entry.name : "the name is not an allowed path"
                ))
                parts.append(DraftPart(path: "damaged/entry-\(index)", data: entry.data, damaged: true))
                continue
            }
            seen.insert(key)
            entryOrder.append(entry.name)
            entries[entry.name] = (entry.data, entry.error)
        }
        guard ["mimetype", "manifest.json", "script.json", "script.fountain"].contains(where: { entries[$0] != nil }) else {
            throw DraftFormatError(code: "not-a-draft", message: "the archive is not a .draft (no mimetype, manifest or script)")
        }
        func damaged(_ path: String, _ detail: String) {
            diagnostics.append(DraftDiagnostic(code: "part-damaged", path: path, detail: detail))
            parts.append(DraftPart(path: path, data: entries[path]!.data, damaged: true))
        }

        if let mimetype = entries["mimetype"] {
            if mimetype.error != nil || zip.entries.first?.name != "mimetype" || !isUTF8(mimetype.data)
                || String(decoding: mimetype.data, as: UTF8.self) != mediaType {
                diagnostics.append(DraftDiagnostic(code: "mimetype-wrong"))
                parts.append(DraftPart(path: "mimetype", data: mimetype.data, damaged: true))
            }
        } else {
            diagnostics.append(DraftDiagnostic(code: "mimetype-missing"))
        }

        var readOnly = false
        var listedOrder: [String] = []
        var listed: [String: String]?
        var title: String?
        var manifestExtra: JSONObject?
        let manifestEntry = entries["manifest.json"]
        let manifest = manifestEntry.flatMap { $0.error == nil ? readJSON($0.data) : nil }
        let manifestProblem = manifest.map(checkManifest) ?? "it is not valid I-JSON"
        if manifestEntry == nil || manifestProblem != nil {
            let detail = manifestEntry == nil ? "it is missing" : (manifestEntry!.error ?? manifestProblem!)
            diagnostics.append(DraftDiagnostic(code: "manifest-unreadable", detail: detail))
            if let manifestEntry { parts.append(DraftPart(path: "manifest.json", data: manifestEntry.data, damaged: true)) }
        } else if let m = manifest?.objectValue {
            let (major, _) = version(m["version"]!.stringValue!)
            let minReaderText = m["minReader"]!.stringValue!
            let (readerMajor, readerMinor) = version(minReaderText)
            let (ourMajor, ourMinor) = version(formatVersion)
            if major > ourMajor || readerMajor > ourMajor {
                throw DraftFormatError(code: "newer-major", message: "the file needs a reader of version \(minReaderText) or later")
            }
            if readerMajor == ourMajor && readerMinor > ourMinor {
                readOnly = true
                diagnostics.append(DraftDiagnostic(code: "read-only-newer-minor", detail: minReaderText))
            }
            var map: [String: String] = [:]
            for item in m["parts"]?.arrayValue ?? [] {
                guard let p = item.objectValue, let path = p["path"]?.stringValue, let sha = p["sha256"]?.stringValue else { continue }
                if map[path] == nil { listedOrder.append(path) }
                map[path] = sha
            }
            listed = map
            title = m["title"]?.stringValue
            for member in m.members where !Order.manifest.contains(member.name) {
                if manifestExtra == nil { manifestExtra = JSONObject() }
                manifestExtra![member.name] = member.value
            }
        }
        if let listed {
            for path in listedOrder where entries[path] == nil {
                diagnostics.append(DraftDiagnostic(code: "missing-part", path: path))
            }
            for path in entryOrder where path != "mimetype" && path != "manifest.json" && listed[path] == nil {
                diagnostics.append(DraftDiagnostic(code: "unlisted-part", path: path))
            }
        }
        func jsonPart(_ path: String, _ check: (JSONValue) -> String?) -> JSONObject? {
            guard let entry = entries[path] else { return nil }
            if let error = entry.error {
                damaged(path, error)
                return nil
            }
            let value = readJSON(entry.data)
            if let problem = value.map(check) ?? "it is not valid I-JSON" {
                damaged(path, problem)
                return nil
            }
            if let digest = listed?[path], digest != SHA256Digest.hex(entry.data) {
                diagnostics.append(DraftDiagnostic(code: "outside-edit", path: path))
            }
            return value?.objectValue
        }

        var script = jsonPart("script.json", checkScript)
        var notes = jsonPart("notes.json", checkNotes)
        func typedPart(_ path: String, _ check: (JSONValue) -> String?) -> JSONObject? {
            guard let entry = entries[path] else { return nil }
            if let error = entry.error {
                damaged(path, error)
                return nil
            }
            guard let value = readJSON(entry.data) else {
                damaged(path, "it is not valid I-JSON")
                return nil
            }
            if check(value) != nil { return nil }
            if let digest = listed?[path], digest != SHA256Digest.hex(entry.data) {
                diagnostics.append(DraftDiagnostic(code: "outside-edit", path: path))
            }
            return value.objectValue
        }
        let revisions = typedPart("revisions.json", checkRevisions)
        let production = typedPart("production.json", checkProduction)
        var typedPaths: Set<String> = []
        if revisions != nil { typedPaths.insert("revisions.json") }
        if production != nil { typedPaths.insert("production.json") }
        var fromRenditionIDs = false
        let rendition = entries["script.fountain"]
        if let error = rendition?.error { damaged("script.fountain", error) }
        if script == nil {
            guard let rendition, rendition.error == nil, isUTF8(rendition.data),
                  let parsed = try? Fountain.parse(String(decoding: rendition.data, as: UTF8.self), emphasis: .runs)
            else {
                throw DraftFormatError(code: "no-script", message: "neither script.json nor its Fountain rendition can be read")
            }
            let fromRendition = fromScreenplay(parsed)
            diagnostics.append(DraftDiagnostic(code: "script-from-rendition", detail: "element ids and word anchors are lost"))
            script = fromRendition.script
            if notes == nil, let renditionNotes = fromRendition.notes {
                notes = renditionNotes
            } else {
                fromRenditionIDs = true
            }
        } else if let rendition, rendition.error == nil, let digest = listed?["script.fountain"] {
            if digest != SHA256Digest.hex(rendition.data) {
                diagnostics.append(DraftDiagnostic(code: "outside-edit", path: "script.fountain"))
            }
        }

        for path in entryOrder where !fixedPaths.contains(path) && !typedPaths.contains(path) {
            let entry = entries[path]!
            if let error = entry.error {
                damaged(path, error)
                continue
            }
            if let digest = listed?[path], digest != SHA256Digest.hex(entry.data) {
                diagnostics.append(DraftDiagnostic(code: "outside-edit", path: path))
            }
            parts.append(DraftPart(path: path, data: entry.data))
        }

        if var n = notes {
            refindAnchors(script: script!, notes: &n, diagnostics: &diagnostics, idsTrusted: !fromRenditionIDs)
            notes = n
        }
        var diagnosticsOut = diagnostics
        if production?["state"] == .string("issued") {
            let sets = revisions?["sets"]?.arrayValue ?? []
            if sets.isEmpty {
                diagnosticsOut.append(DraftDiagnostic(
                    code: "state-contradiction",
                    path: "production.json",
                    detail: "state is \"issued\" but revisions.json has no sets"
                ))
            }
        }
        let document = DraftDocument(
            title: title, script: script!, notes: notes,
            revisions: revisions, production: production,
            parts: parts, manifestExtra: manifestExtra
        )
        return DraftReadResult(document: document, diagnostics: diagnosticsOut, readOnly: readOnly)
    }
}

/// SHA-256 (FIPS 180-4) for the manifest and the fingerprints. The engine's
/// own, like CRC32 — the package is Foundation-only — pinned against the
/// TypeScript port by `Fixtures/draft.json`.
public enum SHA256Digest {
    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
    ]

    public static func digest(_ bytes: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
        var message = bytes
        let bitLength = UInt64(bytes.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { message.append(UInt8((bitLength >> UInt64(shift)) & 0xFF)) }
        var w = [UInt32](repeating: 0, count: 64)
        for block in stride(from: 0, to: message.count, by: 64) {
            for t in 0..<16 {
                let i = block + t * 4
                w[t] = UInt32(message[i]) << 24 | UInt32(message[i + 1]) << 16 | UInt32(message[i + 2]) << 8 | UInt32(message[i + 3])
            }
            for t in 16..<64 {
                let s0 = rotr(w[t - 15], 7) ^ rotr(w[t - 15], 18) ^ (w[t - 15] >> 3)
                let s1 = rotr(w[t - 2], 17) ^ rotr(w[t - 2], 19) ^ (w[t - 2] >> 10)
                w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7]
            for t in 0..<64 {
                let t1 = hh &+ (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) &+ ((e & f) ^ (~e & g)) &+ k[t] &+ w[t]
                let t2 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) &+ ((a & b) ^ (a & c) ^ (b & c))
                hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d
            h[4] = h[4] &+ e; h[5] = h[5] &+ f; h[6] = h[6] &+ g; h[7] = h[7] &+ hh
        }
        return h.flatMap { [UInt8($0 >> 24), UInt8(($0 >> 16) & 0xFF), UInt8(($0 >> 8) & 0xFF), UInt8($0 & 0xFF)] }
    }

    public static func hex(_ bytes: [UInt8]) -> String {
        digest(bytes).map { String(format: "%02x", $0) }.joined()
    }

    private static func rotr(_ x: UInt32, _ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }
}
