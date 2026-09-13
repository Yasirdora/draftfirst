import Foundation

/// Assigning scene numbers the way a production does.
///
/// Before a script is distributed its numbers mean nothing and can be handed
/// out afresh. After it is distributed they are addresses: a call sheet, a
/// shooting schedule and a script supervisor's notes all cite them, so an
/// existing number must never change under anyone. A scene added later takes
/// a letter against its neighbour instead — 12A sits between 12 and 13 — which
/// is why numbering is two operations rather than one.
public enum SceneNumbering {

    /// The numbered scene heading grammar (routing pack — corpus-witnessed).
    /// Production drafts print the scene number at the heading's left edge,
    /// and some flank the heading with the same number at the right edge, a
    /// revision asterisk on its tail: "2 EXT. NORTH CARTHAGE- MORNING 2",
    /// "3 EXT. NICK DUNNE’S FRONT YARD- DAWN 3*" (gone-girl.txt, 244
    /// witnesses), "15 INT. HOLE." (corpus-6.txt, 40 witnesses). A scene
    /// added after distribution is lettered against its neighbour and the
    /// letter is part of the number: "128A EXT./INT. P~~BW MANSION - DUSK.
    /// 128A*" (corpus-6, 9 witnesses). An omitted scene keeps its number and
    /// prints the OMITTED card, numbered or bare: "113 OMITTED." (corpus-6),
    /// "OMITTED" (episode-101, whiplash) — or short, in La La Land's hand:
    /// "OMIT" (lalaland ×45).
    ///
    /// The number is furniture with a home — the element's sceneNumber —
    /// and the words are the writer's. Ported from the TypeScript engine's
    /// `sceneheading.ts`, pinned to it by `Fixtures/sceneheading.json`, and
    /// answered without a regex: digits are ASCII the way JavaScript's `\d`
    /// is, so the port cannot drift on a non-ASCII digit.
    public static func parseNumberedHeading(_ text: String) -> (number: String?, text: String)? {
        /* the OMITTED card, numbered or bare, digits only the way the
           TypeScript pattern reads it — and the card has one spelling in
           the model: La La Land's short "OMIT" and the production's
           "OMITTED." are the same card, held in full */
        var card = Substring(text)
        var cardNumber: String? = nil
        let cardDigits = card.prefix(while: { $0.isASCII && $0.isNumber })
        if !cardDigits.isEmpty {
            let whitespace = card.dropFirst(cardDigits.count).prefix(while: { $0.isWhitespace })
            if !whitespace.isEmpty {
                cardNumber = String(cardDigits)
                card = card.dropFirst(cardDigits.count + whitespace.count)
            }
        }
        if card.hasPrefix("OMIT") {
            var tail = card.dropFirst("OMIT".count)
            if tail.hasPrefix("TED") { tail = tail.dropFirst(3) }
            if tail.isEmpty || tail == "." {
                return (cardNumber, "OMITTED")
            }
        }

        /* the leading number — ^(\d+[A-Z]?)\s+ — the letter a scene added
           after distribution carries is part of the number */
        var body = Substring(text)
        var number: String? = nil
        let digits = body.prefix(while: { $0.isASCII && $0.isNumber })
        if !digits.isEmpty {
            var consumed = digits.count
            if let letter = body.dropFirst(consumed).first,
               letter.isASCII, letter.isLetter, letter.isUppercase {
                consumed += 1
            }
            let whitespace = body.dropFirst(consumed).prefix(while: { $0.isWhitespace })
            if !whitespace.isEmpty {
                number = String(body.prefix(consumed))
                body = body.dropFirst(consumed + whitespace.count)
            }
        }
        guard number != nil, !body.isEmpty, hasSceneIntro(body) else { return nil }

        /* the flanking number repeats the leading one, revisions marked —
           and only then is it furniture; "APARTMENT 4" is a place */
        var flanked = body
        var star = 0
        if flanked.hasSuffix("*") {
            star = 1
            flanked = flanked.dropLast()
        }
        var flankLetter: Character? = nil
        if let last = flanked.last, last.isASCII, last.isLetter, last.isUppercase {
            flankLetter = last
            flanked = flanked.dropLast()
        }
        let trailingDigits = suffix(flanked, where: { $0.isASCII && $0.isNumber })
        let flank = String(trailingDigits) + (flankLetter.map { String($0) } ?? "")
        if !trailingDigits.isEmpty, flank == number {
            let whitespace = suffix(flanked.dropLast(trailingDigits.count), where: { $0.isWhitespace })
            if !whitespace.isEmpty {
                body = body.dropLast(whitespace.count + trailingDigits.count + (flankLetter == nil ? 0 : 1) + star)
            }
        }
        return (number, String(body))
    }

    /// Whether the text opens with a scene intro — INT./EXT. and family,
    /// including the reversed hand six corpus files write (EXT/INT.) —
    /// case-insensitively, the way the TypeScript `SCENE_INTRO` reads it:
    /// any intro word, then a dot or whitespace. A prefix that matches but
    /// is not followed by a boundary does not rule the text out — a shorter
    /// intro may still match ("INT./EXTX" is INT + "." to the TypeScript
    /// alternation, and must be here too).
    private static func hasSceneIntro(_ text: Substring) -> Bool {
        let upper = text.uppercased()
        for intro in ["INT./EXT", "INT/EXT", "EXT./INT", "EXT/INT", "I/E", "INT", "EXT", "EST"] {
            guard upper.hasPrefix(intro) else { continue }
            guard let next = upper.dropFirst(intro.count).first else { continue }
            if next == "." || next.isWhitespace { return true }
        }
        return false
    }

    /// `suffix(while:)` is the one Sequence convenience the standard library
    /// does not ship; the grammar needs it twice.
    private static func suffix(_ text: Substring, where predicate: (Character) -> Bool) -> Substring {
        var index = text.endIndex
        while index > text.startIndex {
            let previous = text.index(before: index)
            guard predicate(text[previous]) else { break }
            index = previous
        }
        return text[index...]
    }

    /// Numbers every scene from 1, discarding whatever was there.
    ///
    /// For a script that has not gone out yet. On one that has, this is the
    /// operation that renumbers somebody's schedule out from under them.
    public static func numberingAll(_ elements: [ScreenplayElement]) -> [ScreenplayElement] {
        var result = elements
        var next = 1
        for index in result.indices where result[index].type == .scene {
            result[index].sceneNumber = String(next)
            next += 1
        }
        return result
    }

    /// Keeps every existing number exactly and letters the scenes that have
    /// none — the locked behaviour a distributed script needs.
    ///
    /// A new scene after 12 becomes 12A, then 12B. New scenes ahead of the
    /// first number take the letter in front instead: A1 precedes 1. A script
    /// with no numbers at all has nothing to preserve, so it is numbered
    /// outright.
    public static func numberingNewScenes(_ elements: [ScreenplayElement]) -> [ScreenplayElement] {
        let scenes = elements.indices.filter { elements[$0].type == .scene }
        var used = Set(scenes.compactMap { elements[$0].sceneNumber }.filter { !$0.isEmpty })
        guard !used.isEmpty else { return numberingAll(elements) }

        var result = elements
        var run: [Int] = []
        var previous: String?

        /// Letters the pending run. `next` is the number the run runs up to,
        /// used only before the first numbered scene, where there is no
        /// predecessor to letter against.
        func flush(upTo next: String?) {
            guard !run.isEmpty else { return }
            var letter = 0
            for index in run {
                var candidate: String
                repeat {
                    let suffix = letters(letter)
                    letter += 1
                    // Never reuse a number already in the script: a letter can
                    // collide with one a previous pass or an import assigned.
                    candidate = previous.map { $0 + suffix } ?? suffix + (next ?? "1")
                } while used.contains(candidate)
                used.insert(candidate)
                result[index].sceneNumber = candidate
            }
            run.removeAll()
        }

        for index in scenes {
            if let number = elements[index].sceneNumber, !number.isEmpty {
                flush(upTo: number)
                previous = number
            } else {
                run.append(index)
            }
        }
        flush(upTo: nil)
        return result
    }

    /// Clears every scene number. Only safe before a script goes out.
    public static func cleared(_ elements: [ScreenplayElement]) -> [ScreenplayElement] {
        var result = elements
        for index in result.indices where result[index].type == .scene {
            result[index].sceneNumber = nil
        }
        return result
    }

    /// Whether any scene carries a number — what decides if a script is
    /// already addressed and must be added to rather than renumbered.
    public static func isNumbered(_ elements: [ScreenplayElement]) -> Bool {
        elements.contains { $0.type == .scene && !($0.sceneNumber ?? "").isEmpty }
    }

    /// A, B, … Z, AA, AB — spreadsheet order, so a scene split twenty times
    /// still lands on a number a production can read aloud.
    static func letters(_ index: Int) -> String {
        var remaining = index
        var out = ""
        repeat {
            out = String(UnicodeScalar(UInt8(65 + remaining % 26))) + out
            remaining = remaining / 26 - 1
        } while remaining >= 0
        return out
    }
}
