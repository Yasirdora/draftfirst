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

        var prev: ElementKind? = nil
        for element in script.elements {
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
            out.push(elementToFountain(element))
            prev = element.type
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
