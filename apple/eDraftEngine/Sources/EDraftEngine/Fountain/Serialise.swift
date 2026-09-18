import Foundation

/// Fountain serializer, ported from the TypeScript engine's `serialise.ts`.
/// Behaviour is pinned by `Fixtures/serialise.json`.
///
/// Emits standards-compatible Fountain. Forcing syntax (`!`, `.`, `>`, `@`)
/// is used only when plain text would otherwise parse as a different element.
/// Dialogue-flow elements (character → parenthetical → dialogue) stay glued
/// without blank lines; every other block is blank-line separated.
extension Fountain {

    /// `mustForceCharacter`: force any cue that collides with another
    /// Fountain classifier.
    private static func mustForceCharacter(_ text: String) -> Bool {
        !FountainDetect.isUpper(text)
            || FountainDetect.isSceneHeading(text)
            || FountainDetect.isTransition(text)
            || FountainDetect.looksLikeShot(text)
            || FountainDetect.startsWithForcedMarker(text)
    }

    /// Without this escape, `> SOME TEXT <` reparses as centered text.
    private static func escapeForcedTransition(_ text: String) -> String {
        text.hasSuffix("<") ? String(text.dropLast()) + "\\<" : text
    }

    /// What the editor keeps beside the page rather than on it.
    private static func isAside(_ kind: ElementKind) -> Bool {
        kind == .note || kind == .section || kind == .synopsis
    }

    private struct AsidePlacement {
        /// Notes written at the end of the first line of the element at the key.
        var inline: [Int: [Int]] = [:]
        /// Asides written in front of the block whose first line is at the key.
        var hoisted: [Int: [Int]] = [:]
        /// Every aside written somewhere other than its own place.
        var moved: Set<Int> = []
    }

    /// Where each aside inside a dialogue block is written (IL-0040;
    /// TypeScript `placeAsides`).
    ///
    /// The editor puts a note in front of the line it is about. Written as its
    /// own paragraph between two lines of one block — a cue and its speech, or
    /// a parenthetical — it ended the block, and the next open read the cue and
    /// the speech as Action. So a run of asides between a line of a block and a
    /// parenthetical or speech line after it is written where Fountain can
    /// carry it (one in front of a dual second speaker's cue already survived,
    /// and is written as before):
    ///
    /// - one-line notes, inline at the end of the first line after them, where
    ///   the reader lifts them out and puts them back in front of that line;
    /// - anything else — a note of several lines, a section, a synopsis, or a
    ///   line after them that is empty — in front of the block, in order,
    ///   since Fountain has no way to write them inside it.
    private static func placeAsides(_ elements: [ScreenplayElement]) -> AsidePlacement {
        var placement = AsidePlacement()
        var blockStart: Int? = nil
        var last: ScreenplayElement? = nil
        var index = 0
        while index < elements.count {
            let element = elements[index]
            if !isAside(element.type) {
                let continues = last.map { $0.type.isDialogueFlow } == true
                    && element.type.isDialogueFlow
                    && (element.type != .character || element.dual == true)
                if !element.type.isDialogueFlow {
                    blockStart = nil
                } else if !continues {
                    blockStart = index
                }
                last = element
                index += 1
                continue
            }
            var end = index
            while end < elements.count && isAside(elements[end].type) { end += 1 }
            if let start = blockStart, end < elements.count,
               elements[end].type == .parenthetical || elements[end].type == .dialogue {
                let run = Array(index..<end)
                let oneLineNotes = run.allSatisfy {
                    elements[$0].type == .note && !elements[$0].text.contains("\n")
                }
                let firstLine = elementToFountain(elements[end])
                    .split(separator: "\n", omittingEmptySubsequences: false).first.map(String.init) ?? ""
                if oneLineNotes && !firstLine.trimmingCharacters(in: .whitespaces).isEmpty {
                    placement.inline[end, default: []] += run
                } else {
                    placement.hoisted[start, default: []] += run
                }
                placement.moved.formUnion(run)
            }
            index = end
        }
        return placement
    }

    /// A note's text, spelled so its only `]]` is the close: a space between
    /// every two adjacent `]`, and one before the close when the text ends in
    /// `]`. The reader trims that space and reads `] ]` back as `]]`. Text
    /// with neither is written as it is.
    private static func noteBody(_ body: String) -> String {
        let spaced = body.replacingOccurrences(of: "\\](?=\\])", with: "] ", options: .regularExpression)
        return spaced.hasSuffix("]") ? spaced + " " : spaced
    }

    /// Render one element as its Fountain source line
    /// (TypeScript `elementToFountain`).
    public static func elementToFountain(_ element: ScreenplayElement) -> String {
        /* Classification reads element.text — marker-free content — so
           markers can never hijack an element type; emission uses body,
           content with its style runs synthesised back into boundary
           markers. Known limit: a scene that needs the forcing `.` AND
           starts with a styled character cannot round-trip (Fountain
           requires an alphanumeric after the dot) — recorded as an
           accepted Fountain-boundary loss. */
        let body: String
        if let runs = element.runs, !runs.isEmpty {
            body = Emphasis.synthesise(element.text, runs)
        } else {
            body = element.text
        }
        switch element.type {
        case .scene:
            let number = element.sceneNumber.map { " #\($0)#" } ?? ""
            /* Force scene headings the standard detector cannot recognize. */
            let head = FountainDetect.isSceneHeading(element.text)
                ? body
                : "." + body
            return head + number

        case .character:
            let cue = body + (element.dual == true ? " ^" : "")
            return mustForceCharacter(element.text) ? "@" + cue : cue

        case .dialogue:
            /* Fountain's connected blank dialogue line is exactly two spaces. */
            return element.text.isEmpty ? "  " : body

        case .parenthetical:
            return body

        case .transition:
            let recognized = FountainDetect.isTransition(element.text)
                || FountainDetect.isFadeOpener(element.text)
            return recognized && FountainDetect.isUpper(element.text)
                ? body
                : "> " + escapeForcedTransition(body)

        case .centered:
            return "> \(body) <"

        case .actbreak:
            /* Fountain has no act spelling; the centred card prints correctly
               everywhere and re-imports as centered — the named degradation,
               RFC-ACT-BREAK §3. The paste route is smarter than the format. */
            return "> \(body) <"

        case .lyrics:
            return "~ \(body)"

        case .shot:
            /* Fountain has no shot type. eDraft recognises isolated
               uppercase shot phrases; `!` stays exclusively for Action. */
            return FountainDetect.expandTabs(body)

        case .general, .action:
            let text = FountainDetect.expandTabs(body)
            let classified = FountainDetect.expandTabs(element.text)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            /* Force action when the plain line would parse as another element. */
            let risky = FountainDetect.isSceneHeading(classified)
                || FountainDetect.isUpper(classified)
                || FountainDetect.startsWithForcedMarker(classified)
                || classified.isEmpty
                || (classified.allSatisfy { $0 == "=" } && classified.count >= 3)
            return risky ? "!" + text : text

        case .note:
            return "[[\(noteBody(body))]]"

        case .section:
            let depth = max(1, element.depth ?? 1)
            return String(repeating: "#", count: depth) + " " + body

        case .synopsis:
            return "= " + body

        case .pagebreak:
            return "==="
        }
    }

    /// Serialize a screenplay to Fountain source (TypeScript
    /// `serialiseFountain`).
    public static func serialise(_ script: Screenplay) -> String {
        var out: [String] = []

        /* The title page serialises as its keys (RFC-TITLE-PAGE D7);
           derivation's fold rule means no line is ever dropped here.
           Emission follows the page's own order — the stack, extras in
           appearance order, contact last — so serialise → parse is a fixed
           point in key order as well as in content. */
        let derived = TitlePage.derive(script.titlePage)
        func pick(_ key: String) -> [TitlePage.DerivedEntry] {
            derived.entries.filter { $0.key.lowercased() == key }
        }
        let special: Set<String> = ["title", "credit", "author", "contact"]
        let titleEntries = pick("title") + pick("credit") + pick("author")
            + derived.entries.filter { !special.contains($0.key.lowercased()) }
            + pick("contact")
        if !titleEntries.isEmpty {
            for entry in titleEntries {
                out.push("\(entry.key): \(entry.values.first ?? "")")
                for value in entry.values.dropFirst() {
                    out.push("   " + value)
                }
            }
            out.push("")
        }

        let elements = script.elements
        let asides = placeAsides(elements)
        var prev: ElementKind? = nil
        func emit(_ element: ScreenplayElement, _ line: String) {
            /*
             * Glue only WITHIN one speech block (cue → parenthetical →
             * dialogue). A new character cue must always be blank-line
             * separated: glued to the previous dialogue it would reparse as
             * dialogue text (Fountain spec).
             */
            let glued = element.type.isDialogueFlow
                && element.type != .character
                && prev != nil
                && prev!.isDialogueFlow
            if !glued && !out.isEmpty && out.last != "" {
                out.push("")
            }
            out.push(line)
            prev = element.type
        }
        for (index, element) in elements.enumerated() where !asides.moved.contains(index) {
            for k in asides.hoisted[index] ?? [] { emit(elements[k], elementToFountain(elements[k])) }
            var line = elementToFountain(element)
            if let notes = asides.inline[index] {
                let inline = notes.map { " " + elementToFountain(elements[$0]) }.joined()
                if let lineEnd = line.firstIndex(of: "\n") {
                    line.insert(contentsOf: inline, at: lineEnd)
                } else {
                    line += inline
                }
            }
            emit(element, line)
        }

        var result = out.joined(separator: "\n")
        /* JS `.replace(/\n+$/, '\n')` — collapse trailing newlines to one. */
        while result.hasSuffix("\n\n") { result.removeLast() }
        return result
    }
}

private extension Array {
    /// Local alias to keep the port visually close to the TS `out.push`.
    mutating func push(_ element: Element) { append(element) }
}
