import EDraftEngine
import Foundation

/// Converts a text-system replacement into screenplay elements without ever
/// matching paragraphs by array position. Unaffected elements retain their
/// identity and type; only paragraphs created by the replacement get new IDs.
public struct ScreenplayEditPlanner {
    public enum Intent {
        case backspaceAtElementStart
        case boundaryDeletion
        case returnKey
        case multilinePaste
        case replacement
    }

    public struct Plan {
        public let elements: [ScriptElement]
        public let selection: NSRange
        public let activeElementID: UUID
        public let activeOffset: Int
    }

    public struct ElementRange {
        public let id: UUID
        public let range: NSRange
    }

    public static func flattenedText(_ elements: [ScriptElement]) -> String {
        elements.map(\.text).joined(separator: "\n")
    }

    public static func ranges(for elements: [ScriptElement]) -> [ElementRange] {
        var location = 0
        return elements.enumerated().map { index, element in
            let length = (element.text as NSString).length
            defer { location += length + (index < elements.count - 1 ? 1 : 0) }
            return ElementRange(id: element.id, range: NSRange(location: location, length: length))
        }
    }

    /// The renumber rule (RFC-ACT-BREAK §4) over the surface's own element
    /// list, answered as the delta only: which element indices take which
    /// new card text. The rule itself lives in the engine — `Acts.renumber`
    /// — so the web app, the phone and the Mac count acts the same way;
    /// this is only the index-preserving bridge across the two element
    /// shapes, which is why a customised card and every non-act element
    /// come back absent from the delta rather than rewritten.
    public static func renumberedActCards(in elements: [ScriptElement]) -> [Int: String] {
        let projected = elements.map {
            ScreenplayElement(type: $0.type.engineKind, text: $0.text)
        }
        let renumbered = Acts.renumber(projected)
        var delta: [Int: String] = [:]
        for (index, pair) in zip(renumbered, elements).enumerated() {
            if pair.0.text != pair.1.text { delta[index] = pair.0.text }
        }
        return delta
    }

    /// The card a freshly inserted act break carries: the canonical
    /// spelling of the ordinal it lands at — one past the count of act
    /// breaks already in the script. The renumber rule keeps it true when
    /// a later insert or delete moves it.
    public static func defaultActCard(forInsertionInto elements: [ScriptElement]) -> String {
        let count = elements.count(where: { $0.type == .actbreak })
        return Acts.defaultCard(ordinal: count + 1)
    }

    public static func replacementBetween(_ oldText: String, _ newText: String) -> (NSRange, String)? {
        guard oldText != newText else { return nil }

        // Walk Swift Characters, not raw UTF-16 code units. UIKit ranges are
        // UTF-16, but a derived diff must never begin inside an emoji, combining
        // sequence, or other extended grapheme cluster.
        var oldStart = oldText.startIndex
        var newStart = newText.startIndex
        while oldStart < oldText.endIndex,
              newStart < newText.endIndex,
              oldText[oldStart] == newText[newStart] {
            oldText.formIndex(after: &oldStart)
            newText.formIndex(after: &newStart)
        }

        var oldEnd = oldText.endIndex
        var newEnd = newText.endIndex
        while oldEnd > oldStart, newEnd > newStart {
            let oldPrevious = oldText.index(before: oldEnd)
            let newPrevious = newText.index(before: newEnd)
            guard oldText[oldPrevious] == newText[newPrevious] else { break }
            oldEnd = oldPrevious
            newEnd = newPrevious
        }

        let prefixLength = oldText[..<oldStart].utf16.count
        let replacedLength = oldText[oldStart..<oldEnd].utf16.count
        return (
            NSRange(location: prefixLength, length: replacedLength),
            String(newText[newStart..<newEnd])
        )
    }

    public static func touchesParagraphBoundary(
        in source: NSString,
        range: NSRange,
        replacement: String
    ) -> Bool {
        let normalized = normalizeLineBreaks(replacement)
        guard range.location >= 0, NSMaxRange(range) <= source.length else { return true }
        return normalized.contains("\n") || source.substring(with: range).contains("\n")
    }

    public static func plan(
        elements sourceElements: [ScriptElement],
        replacing requestedRange: NSRange,
        with requestedReplacement: String,
        intent: Intent,
        kindForNewElement: (_ previous: ScriptElement?, _ text: String, _ pasteDepth: Int?, _ attached: Bool) -> ScreenplayKind
    ) -> Plan? {
        let elements = sourceElements.isEmpty
            ? [ScriptElement(type: .action, text: "")]
            : sourceElements
        let source = flattenedText(elements) as NSString
        guard requestedRange.location >= 0, NSMaxRange(requestedRange) <= source.length else {
            return nil
        }

        let replacement = normalizeLineBreaks(requestedReplacement)
        let mappedRanges = ranges(for: elements)
        guard let start = position(at: requestedRange.location, in: mappedRanges),
              let end = position(at: NSMaxRange(requestedRange), in: mappedRanges) else {
            return nil
        }

        if intent == .backspaceAtElementStart,
           requestedReplacement.isEmpty,
           source.substring(with: requestedRange) == "\n",
           end.offset == 0,
           elements[end.index].type != .action,
           elements[end.index].text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty {
            var result = elements
            result[end.index].type = .action
            result[end.index].text = ""
            result[end.index].runs = nil   // the style dies with the text
            let resultRanges = ranges(for: result)
            let caret = resultRanges[end.index].range.location
            return Plan(
                elements: result,
                selection: NSRange(location: caret, length: 0),
                activeElementID: result[end.index].id,
                activeOffset: 0
            )
        }

        // Return inside a parenthetical ends it; it never splits its brackets.
        //
        // Splitting the raw text the way every other element splits leaves the
        // opener on one line and the closer alone on the next — "(whispering"
        // above a dialogue line reading ")". A parenthetical is a bracketed
        // unit, so the head closes as its own direction and whatever followed
        // the caret becomes the speech it was introducing, which is the
        // element that follows a parenthetical anyway.
        if intent == .returnKey,
           requestedRange.length == 0,
           start.index == end.index,
           elements[start.index].type == .parenthetical,
           // Only between the brackets. A caret before the opener or after the
           // closer splits cleanly on its own, and those splits already behave.
           start.offset > 0,
           start.offset < (elements[start.index].text as NSString).length {
            let text = elements[start.index].text as NSString
            let cut = start.offset
            let head = Normalize.normalizeParenthetical(text.substring(to: cut))

            // Return before the direction has begun — the caret just inside
            // the opener — would leave an empty bracket behind. Keep the
            // direction whole instead and open the speech beneath it: nothing
            // is lost, and nothing is left half-written.
            let keepsWhole = head.isEmpty
            var result = elements
            let styleRuns = elements[start.index].runs
            result[start.index].text = keepsWhole ? elements[start.index].text : head
            /* Runs ride surviving text. The normalisation helpers can trim
               and re-bracket from either end, so propagate only when they
               were the identity — offsets stay honest, or the style is let
               go rather than pinned to the wrong words. */
            if !keepsWhole, head != text.substring(to: cut) {
                result[start.index].runs = nil
            } else if !keepsWhole {
                result[start.index].runs = Emphasis.slice(styleRuns ?? [], 0..<cut)
            }
            let spoken = keepsWhole
                ? ""
                : Normalize.unwrapParenthetical(text.substring(from: cut))
            var dialogue = ScriptElement(type: .dialogue, text: spoken)
            if !keepsWhole, spoken == text.substring(from: cut) {
                let sliced = Emphasis.slice(styleRuns ?? [], cut..<text.length)
                dialogue.runs = sliced.isEmpty ? nil : sliced
            }
            result.insert(dialogue, at: start.index + 1)

            let caret = ranges(for: result)[start.index + 1].range.location
            return Plan(
                elements: result,
                selection: NSRange(location: caret, length: 0),
                activeElementID: dialogue.id,
                activeOffset: 0
            )
        }

        // Replacing a selected separator with the same separator is a caret
        // move, not a screenplay rewrite. Preserve every identity and type.
        if source.substring(with: requestedRange) == replacement {
            let caret = requestedRange.location + (replacement as NSString).length
            guard let active = position(at: caret, in: mappedRanges) else { return nil }
            return Plan(
                elements: elements,
                selection: NSRange(location: caret, length: 0),
                activeElementID: elements[active.index].id,
                activeOffset: active.offset
            )
        }

        if intent == .multilinePaste,
           requestedRange.length == 0,
           replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let caret = requestedRange.location
            guard let active = position(at: caret, in: mappedRanges) else { return nil }
            return Plan(
                elements: elements,
                selection: NSRange(location: caret, length: 0),
                activeElementID: elements[active.index].id,
                activeOffset: active.offset
            )
        }

        let startElement = elements[start.index]
        let endElement = elements[end.index]
        let startText = startElement.text as NSString
        let endText = endElement.text as NSString
        let head = startText.substring(to: min(start.offset, startText.length))
        let tail = endText.substring(from: min(end.offset, endText.length))
        let discardsEmptyPlaceholder = intent == .multilinePaste
            && start.index == end.index
            && startElement.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let effectiveHead = discardsEmptyPlaceholder ? "" : head
        let effectiveTail = discardsEmptyPlaceholder ? "" : tail
        let headLength = (effectiveHead as NSString).length
        let replacementLength = (replacement as NSString).length
        let tailStart = headLength + replacementLength
        let rawParts = (effectiveHead + replacement + effectiveTail).components(separatedBy: "\n")
        // Each part's span in the composed source, so runs can be carried by
        // span arithmetic rather than by matching text.
        var partOffsets = Array(repeating: 0, count: rawParts.count)
        for index in rawParts.indices.dropFirst() {
            partOffsets[index] = partOffsets[index - 1] + (rawParts[index - 1] as NSString).length + 1
        }
        // Inserted text inherits its donor per the platform's own rule (§4):
        // the style of the character before the caret, or — when nothing
        // precedes it — of the character that followed the replaced range.
        let donor: StyleRun? = headLength > 0
            ? startElement.runs?.first(where: { $0.start <= headLength - 1 && headLength - 1 < $0.end })
            : endElement.runs?.first(where: { $0.start <= end.offset && end.offset < $0.end })
        let rawCaret = positionInParts(
            at: (effectiveHead as NSString).length + (replacement as NSString).length,
            parts: rawParts
        )
        var parts: [(rawIndex: Int, text: String)] = rawParts.enumerated().map {
            (rawIndex: $0.offset, text: $0.element)
        }
        /// Each part's depth past the paste's base column, when the paste
        /// carried one — the signal that says dialogue from action once the
        /// margins are gone.
        var pasteDepths: [Int?] = Array(repeating: nil, count: parts.count)
        /// The kind the reassembly read from the paste's structure, when it
        /// read one — an unindented hard-wrapped paste carries its kinds
        /// because there are no margins to measure them from.
        var pasteKinds: [ScreenplayKind?] = Array(repeating: nil, count: parts.count)
        /// Whether the part sits directly under the content line above it —
        /// no blank line between. The raw paste route types every line on
        /// its own, so attachment is the only witness a wrapped speech has
        /// left; the reassembly joins its own wraps and never needs it.
        var pasteAttached: [Bool] = Array(repeating: false, count: parts.count)
        /// The source lines behind each part — the reassembled route's
        /// paragraphs keep the wrapped lines they joined, the raw route's
        /// parts each are one. Cue confirmation measures a speech's width
        /// and sentence shape on these, never on the joined text.
        var pasteSourceLines: [[String]] = parts.map { [$0.text] }
        var pasteWasReassembled = false
        if intent == .multilinePaste {
            // A hard-wrapped paste into an empty place is reassembled into
            // its paragraphs first — margins off, continuation lines joined
            // (PasteReassembly) — because splitting it on newlines alone
            // stores the courier's margins inside the writer's text.
            if discardsEmptyPlaceholder,
               let reassembled = PasteReassembly.paragraphs(from: replacement) {
                parts = reassembled.enumerated().map { (rawIndex: $0.offset, text: $0.element.text) }
                pasteDepths = reassembled.map { $0.depth }
                pasteKinds = reassembled.map { $0.kind }
                pasteAttached = Array(repeating: false, count: parts.count)
                pasteSourceLines = reassembled.map { $0.sourceLines }
                pasteWasReassembled = true
            } else {
                /// The card grammar's state (plaintext.ts): a marker opens
                /// the card, its date/time/message lines keep it, the first
                /// prose line closes it. Marker lines drop; content lines
                /// keep as centered — and both are hard boundaries the
                /// attachment scan must not cross.
                var cardOpen = false
                var cardHasDate = false
                var cardSawTime = false
                var cardBoundaryRawIndexes = Set<Int>()
                let printable = parts.compactMap { part -> (rawIndex: Int, text: String, attached: Bool, card: Bool)? in
                    let trimmed = part.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    // The revision asterisk comes off before any other test:
                    // it is furniture riding on content, not content, and a
                    // bare mark drops outright. End-of-act cards are
                    // furniture (RFC-ACT-BREAK §5): an act ends where the
                    // next one begins, so the closing card is dropped here,
                    // never stored. Page numbers, loose scene numbers, draft
                    // stamps, (MORE) and CONTINUED are furniture of the
                    // printed page, dropped the same way.
                    let text = PasteHeuristics.strippingRevisionStar(trimmed)
                    // A blank line or an end-of-act card closes any open
                    // card, the way the TypeScript import reads it.
                    if text.isEmpty || Acts.isEndActCard(text) {
                        cardOpen = false
                        return nil
                    }
                    guard !PasteHeuristics.isPaginationArtifact(text) else { return nil }
                    if let cardInline = PasteHeuristics.titleCardMarker(text) {
                        cardBoundaryRawIndexes.insert(part.rawIndex)
                        guard cardInline.isEmpty else {
                            // The marker carries the whole card on its own
                            // line — "INSERT CHYRON: 1994".
                            return (part.rawIndex, cardInline, false, true)
                        }
                        cardOpen = true
                        cardHasDate = false
                        cardSawTime = false
                        return nil
                    }
                    if cardOpen {
                        if PasteHeuristics.isTitleCardDate(text) {
                            cardHasDate = true
                            cardBoundaryRawIndexes.insert(part.rawIndex)
                            return (part.rawIndex, text, false, true)
                        }
                        if PasteHeuristics.isTitleCardTime(text) {
                            cardSawTime = true
                            cardBoundaryRawIndexes.insert(part.rawIndex)
                            return (part.rawIndex, text, false, true)
                        }
                        // The message slot: open at the marker and under a
                        // date — shut after a bare time stamp, where the caps
                        // line is the next speaker, not the card's text.
                        if PasteHeuristics.isCardMessage(text), cardHasDate || !cardSawTime {
                            cardOpen = false
                            cardBoundaryRawIndexes.insert(part.rawIndex)
                            return (part.rawIndex, text, false, true)
                        }
                        cardOpen = false  // the first prose line closes the card
                    }
                    // Attachment is read the way the TypeScript import reads
                    // it (plaintext.ts): the dropped furniture keeps the
                    // attachment it rode in on — (MORE) splits a speech, not
                    // a thought — while a blank line or an end-of-act card is
                    // a hard boundary nothing continues across.
                    var attached = false
                    for above in parts[..<part.rawIndex].reversed() {
                        let aboveTrimmed = above.text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if aboveTrimmed.isEmpty { break }
                        let aboveText = PasteHeuristics.strippingRevisionStar(aboveTrimmed)
                        if aboveText.isEmpty { continue }
                        if PasteHeuristics.isPaginationArtifact(aboveText) { continue }
                        if Acts.isEndActCard(aboveText) { break }
                        // A card line grants no attachment: the marker opens
                        // a centered world, and the next prose stands alone.
                        if cardBoundaryRawIndexes.contains(above.rawIndex) { break }
                        attached = true
                        break
                    }
                    // Kept lines keep their source text exactly unless the
                    // strip changed it; offsets past a dropped or shortened
                    // line name the pre-strip source, as they already did
                    // for the furniture this filter has always dropped.
                    return (part.rawIndex, text == trimmed ? part.text : text, attached, false)
                }
                if !printable.isEmpty {
                    parts = printable.map { (rawIndex: $0.rawIndex, text: $0.text) }
                    pasteAttached = printable.map { $0.attached }
                    pasteKinds = printable.map { $0.card ? ScreenplayKind.centered : nil }
                    pasteSourceLines = parts.map { [$0.text] }
                }
            }
        }

        var owners = Array<Int?>(repeating: nil, count: parts.count)
        let replacesEmptyTarget = discardsEmptyPlaceholder

        if replacesEmptyTarget {
            // The empty placeholder has no semantic ownership. Classify the
            // first pasted paragraph as carefully as every following one.
        } else if start.index == end.index {
            if parts.count == 1 {
                owners[0] = start.index
            } else if start.offset == 0, end.offset < startText.length {
                // Return at the start keeps the existing semantic paragraph
                // attached to its content, rather than turning a character cue
                // into dialogue merely because text moved to the second line.
                owners[parts.count - 1] = start.index
            } else {
                owners[0] = start.index
            }
        } else {
            let leftSurvives = start.offset > 0
                || ((intent == .boundaryDeletion || intent == .backspaceAtElementStart)
                    && start.offset == startText.length)
            let rightSurvives = end.offset < endText.length
                || NSMaxRange(requestedRange) == mappedRanges[end.index].range.location

            if parts.count == 1 {
                if leftSurvives {
                    owners[0] = start.index
                } else if rightSurvives {
                    owners[0] = end.index
                }
            } else {
                if leftSurvives { owners[0] = start.index }
                if rightSurvives { owners[parts.count - 1] = end.index }
            }
        }

        if intent == .replacement, start.index != end.index {
            let affectedCount = end.index - start.index + 1
            if parts.count == affectedCount {
                // Native Writing Tools and proofreading commonly replace one
                // contiguous range while retaining the same paragraph shape.
                // Preserve all semantic owners, even when every line changed.
                for partIndex in parts.indices {
                    owners[partIndex] = start.index + partIndex
                }
            } else {
                let usedOwners = Set(owners.compactMap { $0 })
                for match in stableOwnerMatches(
                    elements: elements,
                    elementRange: start.index...end.index,
                    parts: parts.map(\.text)
                ) where owners[match.partIndex] == nil
                    && !usedOwners.contains(match.elementIndex) {
                    owners[match.partIndex] = match.elementIndex
                }
            }
        }

        var result = Array(elements[..<start.index])
        /// The running right edge of the pasted speech in progress — the
        /// witness the edge tell measures a rejoining action line against.
        var speechEdge = 0
        for (partIndex, part) in parts.enumerated() {
            let element: ScriptElement
            // A reassembled paste carries no runs across: the target was
            // empty and the paste is plain text, so the span arithmetic has
            // nothing to map — say so with an explicitly empty range rather
            // than trusting offsets that no longer name the source.
            let sourceRange = pasteWasReassembled
                ? 0..<0
                : partOffsets[part.rawIndex]..<(partOffsets[part.rawIndex] + (part.text as NSString).length)
            if let owner = owners[partIndex] {
                var preserved = elements[owner]
                let finalText = preserved.type.uppercasesInput ? part.text.uppercased() : part.text
                preserved.text = finalText
                if finalText != elements[owner].text {
                    // The text changed under this identity; re-derive the runs
                    // from the spans they covered before the edit.
                    preserved.runs = runsForPart(
                        sourceRange: sourceRange, partText: part.text, finalText: finalText,
                        headRuns: startElement.runs ?? [], headLength: headLength,
                        tailRuns: endElement.runs ?? [], tailStart: tailStart,
                        tailOffset: end.offset, donor: donor
                    )
                }
                element = preserved
            } else {
                let previous = result.last
                var partText = part.text
                var suggestedKind = pasteKinds[partIndex]
                var parsedRuns: [StyleRun]? = nil
                if intent == .multilinePaste {
                    // The writer's formatting survives the paste as data:
                    // Fountain's centred line becomes the element's type and
                    // its emphasis markers become runs — the same parse the
                    // file boundary applies, so a paste and an import agree.
                    let trimmed = partText.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix(">"), trimmed.hasSuffix("<"),
                       trimmed.utf16.count > 2 {
                        partText = String(trimmed.dropFirst().dropLast())
                            .trimmingCharacters(in: .whitespaces)
                        suggestedKind = .centered
                    }
                    let parsed = Emphasis.parse(partText)
                    partText = parsed.text
                    parsedRuns = parsed.runs.isEmpty ? nil : parsed.runs
                    // Structural grammar outranks alignment, the way the
                    // TypeScript classifier orders it (scene arms before the
                    // alignment arm): the omitted-scene card a printed title
                    // sequence carries — corpus-6's centered "128 OMITTED" —
                    // is the scene, not the card's styling.
                    if suggestedKind == .centered, PasteHeuristics.looksLikeSceneHeading(partText) {
                        suggestedKind = .scene
                    }
                }
                let suggested = suggestedKind
                    ?? kindForNewElement(previous, partText, pasteDepths[partIndex], pasteAttached[partIndex])
                // The edge tell (PasteHeuristics.speechEndsHere, mirrored
                // from classify.ts rule 7): an attached line that outruns
                // both the dialogue column and the speech's own running
                // edge is action rejoining the left margin, not more speech.
                let kind: ScreenplayKind
                if intent == .multilinePaste, suggested == .dialogue, pasteAttached[partIndex],
                   previous?.type == .dialogue, let lastLine = previous?.text,
                   PasteHeuristics.speechEndsHere(edge: speechEdge, lastLine: lastLine, line: partText) {
                    kind = .action
                } else {
                    kind = suggested
                }
                var sceneNumber: String?
                if kind == .scene, intent == .multilinePaste,
                   let numbered = SceneNumbering.parseNumberedHeading(partText) {
                    // The number a production draft prints at the heading's
                    // edge is furniture with a home — sceneNumber — not
                    // part of the writer's heading.
                    partText = numbered.text
                    sceneNumber = numbered.number
                }
                let finalText = kind.uppercasesInput ? partText.uppercased() : partText
                var created = ScriptElement(type: kind, text: finalText)
                created.sceneNumber = sceneNumber
                if let parsedRuns {
                    // A case expansion (ß→SS) shifts the spans the parser
                    // measured; where the length moved, no run can be trusted.
                    created.runs = finalText.utf16.count == partText.utf16.count
                        ? parsedRuns : nil
                } else {
                    created.runs = runsForPart(
                        sourceRange: sourceRange, partText: partText, finalText: finalText,
                        headRuns: startElement.runs ?? [], headLength: headLength,
                        tailRuns: endElement.runs ?? [], tailStart: tailStart,
                        tailOffset: end.offset, donor: donor
                    )
                }
                element = created
            }
            result.append(element)
            if intent == .multilinePaste {
                // A fresh speech resets the edge to its first line's width;
                // inside one, the edge is the widest the speech has run.
                if element.type == .dialogue {
                    let before = result.dropLast().last
                    speechEdge = (before?.type == .character || before?.type == .parenthetical)
                        ? element.text.utf16.count
                        : max(speechEdge, element.text.utf16.count)
                } else {
                    speechEdge = 0
                }
            }
        }
        if intent == .multilinePaste {
            // Cue confirmation, mirrored from the TypeScript engine's
            // confirmCues (classify.ts): a pasted cue keeps its character
            // kind only when speech follows it.
            confirmPastedCues(&result, pasteStart: start.index, owners: owners, pasteSourceLines: pasteSourceLines)
        }
        if end.index + 1 < elements.count {
            result.append(contentsOf: elements[(end.index + 1)...])
        }

        if result.count == 1,
           result[0].text.isEmpty,
           owners.allSatisfy({ $0 == nil }) {
            result[0] = ScriptElement(type: .action, text: "")
        }

        let resultRanges = ranges(for: result)
        let caretPartIndex: Int
        let rawOffset: Int
        if pasteWasReassembled {
            // The paste's own end is the caret, said plainly: the raw-caret
            // arithmetic speaks in raw source lines, which the reassembly
            // deliberately collapsed.
            caretPartIndex = parts.count - 1
            rawOffset = (parts[caretPartIndex].text as NSString).length
        } else if let exact = parts.firstIndex(where: { $0.rawIndex == rawCaret.index }) {
            caretPartIndex = exact
            rawOffset = min(rawCaret.offset, (parts[exact].text as NSString).length)
        } else if let previous = parts.lastIndex(where: { $0.rawIndex < rawCaret.index }) {
            caretPartIndex = previous
            rawOffset = (parts[previous].text as NSString).length
        } else {
            caretPartIndex = 0
            rawOffset = 0
        }
        let activeIndex = start.index + caretPartIndex
        guard result.indices.contains(activeIndex), resultRanges.indices.contains(activeIndex) else {
            return nil
        }
        let activeElement = result[activeIndex]
        let activeOffset = normalizedOffset(
            rawOffset,
            in: parts[caretPartIndex].text,
            uppercased: activeElement.type.uppercasesInput
        )
        let caret = resultRanges[activeIndex].range.location
            + min(activeOffset, resultRanges[activeIndex].range.length)
        return Plan(
            elements: result,
            selection: NSRange(location: caret, length: 0),
            activeElementID: activeElement.id,
            activeOffset: min(activeOffset, resultRanges[activeIndex].range.length)
        )
    }

    /// Carries style runs across a rebuild by span arithmetic over the
    /// composed source `head + replacement + tail` — never by matching text.
    ///
    /// Head offsets are start-element coordinates; tail offsets are rebased
    /// out of the end element; inserted text takes the donor's whole property
    /// set (§4). Returns nil when no run survives, or when casing changed the
    /// text length (ß→SS) and no offset can be trusted.
    /// Cue confirmation, mirrored from the TypeScript engine's confirmCues
    /// (classify.ts — the comment there carries the witnesses). A pasted cue
    /// keeps its character kind only when speech follows it: the cue shape is
    /// cheap to fake — every season card (lalaland's WINTER ×2), time card
    /// (manchester ×29), subject slug (whiplash's ON STAGE ×4) and title-page
    /// line is uppercase and short — so shape alone is an application and the
    /// speech beneath it is the interview. Two failures rescind it:
    ///
    ///   structural — the next element is a heading, transition, act card,
    ///     centered card or shot, or the paste ends under it (a whole-script
    ///     load's "THE END"). A cue introduces speech; these are not speech.
    ///
    ///   wide block — a "speech" follows but runs prose-wide: its first line
    ///     outruns the dialogue column without ending a sentence or opening
    ///     as a continuation, and either its second line runs just as wide or
    ///     a structural line (or the paste's end) cuts the block off. A
    ///     single wide line is also cut off by the next cue — a cast table's
    ///     description row (episode-101's MAID).
    ///
    /// Demotion converts the cue and its whole block — parentheticals and
    /// dialogue — to action: the words all survive, only the false speaker
    /// leaves the cast. Only elements this paste typed are retyped; an
    /// owner-preserved element keeps the kind its document gave it. The
    /// evidence is the paste's own slice: a cue closing the paste is
    /// unconfirmed — its speech must ride in with it (unwitnessed beyond
    /// whole-document loads, and a single-line paste never reaches here).
    private static func confirmPastedCues(
        _ result: inout [ScriptElement],
        pasteStart: Int,
        owners: [Int?],
        pasteSourceLines: [[String]]
    ) {
        let pasteEnd = pasteStart + owners.count
        guard pasteStart >= 0, pasteEnd <= result.count, pasteSourceLines.count == owners.count else { return }
        /// The kinds that end a cue's candidacy when one sits directly under
        /// it (the TypeScript CUE_ENDING_FOLLOWER set).
        let cueEnding: Set<ScreenplayKind> = [.scene, .transition, .actbreak, .centered, .shot]
        var index = pasteStart
        while index < pasteEnd {
            defer { index += 1 }
            guard owners[index - pasteStart] == nil, result[index].type == .character else { continue }
            let next = index + 1 < pasteEnd ? result[index + 1] : nil
            var block: [Int] = []
            let demote: Bool
            if next == nil || cueEnding.contains(next!.type) {
                demote = true
            } else {
                // A cue-shaped line directly under a cue is typed its speech
                // (position answers first), so the block scan also covers the
                // cast table's name rows.
                var speechLines: [String] = []
                var cursor = index + 1
                while cursor < pasteEnd,
                      result[cursor].type == .parenthetical || result[cursor].type == .dialogue {
                    if result[cursor].type == .dialogue {
                        let lines = pasteSourceLines[cursor - pasteStart]
                        speechLines.append(contentsOf: lines.isEmpty ? [result[cursor].text] : lines)
                    }
                    block.append(cursor)
                    cursor += 1
                }
                guard let first = speechLines.first else { continue }  // brackets and no words — unwitnessed; left flagged
                let wide = first.utf16.count > PasteHeuristics.speechColumnCeiling
                    && !PasteHeuristics.endsWithTerminalSentence(first)
                    && !PasteHeuristics.opensAsSentenceContinuation(first)
                guard wide else { continue }
                let after = cursor < pasteEnd ? result[cursor].type : nil
                let cutOff = after == nil || cueEnding.contains(after!)
                let secondWide = speechLines.count >= 2
                    && speechLines[1].utf16.count > PasteHeuristics.speechColumnCeiling
                demote = secondWide || cutOff || (speechLines.count == 1 && after == .character)
            }
            guard demote else { continue }
            result[index].type = .action
            for member in block where owners[member - pasteStart] == nil {
                result[member].type = .action
            }
        }
    }

    private static func runsForPart(
        sourceRange: Range<Int>,
        partText: String,
        finalText: String,
        headRuns: [StyleRun],
        headLength: Int,
        tailRuns: [StyleRun],
        tailStart: Int,
        tailOffset: Int,
        donor: StyleRun?
    ) -> [StyleRun]? {
        if finalText != partText, finalText.utf16.count != partText.utf16.count {
            return nil
        }
        let partStart = sourceRange.lowerBound
        let partEnd = sourceRange.upperBound
        var out: [StyleRun] = []

        // Head: S coordinates are the start element's own coordinates.
        if partStart < headLength {
            out += Emphasis.slice(headRuns, partStart..<min(partEnd, headLength))
        }

        // Replacement: inherits the donor's properties wholesale — the
        // *whole* set, mark included (§4). Leaving `highlight` off this
        // construction silently dropped the mark from text inserted into a
        // highlighted span.
        let donorStart = max(partStart, headLength)
        let donorEnd = min(partEnd, tailStart)
        if donorStart < donorEnd, let donor {
            out.append(StyleRun(
                start: donorStart - partStart,
                end: donorEnd - partStart,
                styles: donor.styles,
                revisionID: donor.revisionID,
                tagNumbers: donor.tagNumbers,
                highlight: donor.highlight
            ))
        }

        // Tail: slice in end-element coordinates, then shift into place.
        let tailFrom = max(partStart, tailStart)
        if tailFrom < partEnd {
            let sliced = Emphasis.slice(
                tailRuns,
                (tailOffset + tailFrom - tailStart)..<(tailOffset + partEnd - tailStart)
            )
            out += sliced.map { run in
                var shifted = run
                shifted.start += tailFrom - partStart
                shifted.end += tailFrom - partStart
                return shifted
            }
        }

        let normalised = Emphasis.normalise(out, textLength: finalText.utf16.count)
        return normalised.isEmpty ? nil : normalised
    }

    private static func positionInParts(at requestedOffset: Int, parts: [String]) -> (index: Int, offset: Int) {
        guard !parts.isEmpty else { return (0, 0) }
        var remaining = max(0, requestedOffset)
        for index in parts.indices {
            let length = (parts[index] as NSString).length
            if remaining <= length { return (index, remaining) }
            remaining -= length
            if index < parts.count - 1, remaining > 0 { remaining -= 1 }
        }
        let last = parts.count - 1
        return (last, (parts[last] as NSString).length)
    }

    private static func normalizedOffset(
        _ rawOffset: Int,
        in text: String,
        uppercased: Bool
    ) -> Int {
        let source = text as NSString
        let prefix = source.substring(to: min(max(0, rawOffset), source.length))
        let normalized = uppercased ? prefix.uppercased() : prefix
        return normalized.utf16.count
    }

    private static func stableOwnerMatches(
        elements: [ScriptElement],
        elementRange: ClosedRange<Int>,
        parts: [String]
    ) -> [(partIndex: Int, elementIndex: Int)] {
        let elementIndices = Array(elementRange)
        guard !elementIndices.isEmpty, !parts.isEmpty,
              elementIndices.count * parts.count <= 40_000 else { return [] }

        var lengths = Array(
            repeating: Array(repeating: 0, count: parts.count + 1),
            count: elementIndices.count + 1
        )
        for oldIndex in elementIndices.indices.reversed() {
            for partIndex in parts.indices.reversed() {
                let element = elements[elementIndices[oldIndex]]
                let candidate = element.type.uppercasesInput
                    ? parts[partIndex].uppercased()
                    : parts[partIndex]
                if element.text == candidate {
                    lengths[oldIndex][partIndex] = lengths[oldIndex + 1][partIndex + 1] + 1
                } else {
                    lengths[oldIndex][partIndex] = max(
                        lengths[oldIndex + 1][partIndex],
                        lengths[oldIndex][partIndex + 1]
                    )
                }
            }
        }

        var matches: [(partIndex: Int, elementIndex: Int)] = []
        var oldIndex = 0
        var partIndex = 0
        while oldIndex < elementIndices.count, partIndex < parts.count {
            let element = elements[elementIndices[oldIndex]]
            let candidate = element.type.uppercasesInput
                ? parts[partIndex].uppercased()
                : parts[partIndex]
            if element.text == candidate {
                matches.append((partIndex, elementIndices[oldIndex]))
                oldIndex += 1
                partIndex += 1
            } else if lengths[oldIndex + 1][partIndex] >= lengths[oldIndex][partIndex + 1] {
                oldIndex += 1
            } else {
                partIndex += 1
            }
        }
        return matches
    }

    private static func position(
        at location: Int,
        in ranges: [ElementRange]
    ) -> (index: Int, offset: Int)? {
        guard !ranges.isEmpty else { return nil }
        if let index = ranges.firstIndex(where: { $0.range.location == location }) {
            return (index, 0)
        }
        if let index = ranges.firstIndex(where: {
            location > $0.range.location && location <= NSMaxRange($0.range)
        }) {
            return (index, location - ranges[index].range.location)
        }
        if location == NSMaxRange(ranges[ranges.count - 1].range) {
            return (ranges.count - 1, ranges[ranges.count - 1].range.length)
        }
        return nil
    }

    private static func normalizeLineBreaks(_ text: String) -> String {
        /* a stray NUL is a UTF-16 paste leak, never text (pasted-26 ×199) */
        text.replacingOccurrences(of: "\0", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
