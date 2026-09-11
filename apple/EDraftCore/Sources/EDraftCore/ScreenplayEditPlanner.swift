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
        kindForNewElement: (_ previous: ScriptElement?, _ text: String, _ pasteDepth: Int?) -> ScreenplayKind
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
                pasteWasReassembled = true
            } else {
                let printable = parts.filter {
                    !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
                if !printable.isEmpty { parts = printable }
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
                let kind = pasteKinds[partIndex]
                    ?? kindForNewElement(previous, part.text, pasteDepths[partIndex])
                let finalText = kind.uppercasesInput ? part.text.uppercased() : part.text
                var created = ScriptElement(type: kind, text: finalText)
                created.runs = runsForPart(
                    sourceRange: sourceRange, partText: part.text, finalText: finalText,
                    headRuns: startElement.runs ?? [], headLength: headLength,
                    tailRuns: endElement.runs ?? [], tailStart: tailStart,
                    tailOffset: end.offset, donor: donor
                )
                element = created
            }
            result.append(element)
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

        // Replacement: inherits the donor's properties wholesale.
        let donorStart = max(partStart, headLength)
        let donorEnd = min(partEnd, tailStart)
        if donorStart < donorEnd, let donor {
            out.append(StyleRun(
                start: donorStart - partStart,
                end: donorEnd - partStart,
                styles: donor.styles,
                revisionID: donor.revisionID,
                tagNumbers: donor.tagNumbers
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
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }
}
