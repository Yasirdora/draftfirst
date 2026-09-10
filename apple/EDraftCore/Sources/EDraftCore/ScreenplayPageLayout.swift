import CoreGraphics
import EDraftEngine
import Foundation

/// Where each line of a screenplay sits on a page.
///
/// Pagination (`Paginator`) decides *which* lines belong on a page. This
/// decides *where* those lines are drawn — the 12pt Courier rhythm, the
/// 1.5″ left margin, the scene numbers in both margins. Drawing a string
/// at the resulting point is the surface's job; the arithmetic is not.
///
/// Extracted from the iPhone's `ScreenplayPageRenderer` so the Mac and
/// the phone cannot disagree about a line's origin. A second copy of this
/// file would be two answers to the same question, and no compiler would
/// notice the day they drifted.
public enum ScreenplayPageLayout {

    /// Courier 12pt: six lines per inch, matching `Paginator`.
    public static let fontSize: CGFloat = 12
    public static let lineHeight: CGFloat = 12
    /// 1.5″ left margin.
    public static let textLeft: CGFloat = 108
    /// Page numbers print 0.5″ down, "2." style, from the second page on.
    public static let pageNumberY: CGFloat = 36
    /// `CONTINUED:` sits a tenth of an inch above the body.
    public static let continuedFromTopGap: CGFloat = 24

    /// One string, already placed. Alignment is baked into `origin.x`.
    public struct Run: Equatable, Sendable {
        public var text: String
        public var origin: CGPoint
        /// Styled spans of `text`, in the text's own UTF-16 offsets. Empty
        /// for anything that is not screenplay content — page numbers,
        /// CONTINUEDs, scene numbers, title-page lines.
        public var segments: [StyleSegment]

        public init(text: String, origin: CGPoint, segments: [StyleSegment] = []) {
            self.text = text
            self.origin = origin
            self.segments = segments
        }
    }

    /// A styled span of a `Run`'s text. Emphasis reaches the PDF without
    /// re-measuring anything: Courier's advance is fixed, so a bolded word
    /// stands exactly where its plain self stood.
    public struct StyleSegment: Equatable, Sendable {
        public var start: Int
        public var length: Int
        public var styles: StyleSet

        public init(start: Int, length: Int, styles: StyleSet) {
            self.start = start
            self.length = length
            self.styles = styles
        }
    }

    /// Width of the 60-character text block, in points.
    public static func textBlockWidth(_ format: PageFormat) -> CGFloat {
        format.textRight - textLeft
    }

    /// The paginator's line budget as a height. Letter is 55 × 12 = 660,
    /// not `pageRect.height - 2 * textTop` (648) — the bottom margin is
    /// 60pt, not a second inch.
    public static func textBlockHeight(_ format: PageFormat) -> CGFloat {
        CGFloat(format.linesPerPage) * lineHeight
    }

    public static func textBottom(_ format: PageFormat) -> CGFloat {
        format.pageRect.height - format.textTop - textBlockHeight(format)
    }

    /// Room above and below the text block for a glyph that is taller than
    /// its line.
    ///
    /// Line height is an advance, not a clipping box, so an emoji rises about
    /// three points above its box — measured, not guessed. On any line but the
    /// first that room is the line above; on the first line there is nothing,
    /// and the text view's own frame cuts it. One full line of slack is more
    /// than any glyph needs and costs nothing: the type still starts at
    /// `textTop`, because the view is moved up and the text inset back down by
    /// the same amount.
    public static let glyphOverflow: CGFloat = lineHeight

    /// Draw a glyph this much smaller than its own metrics so it sits
    /// inside the 12pt line. 1 when it already fits.
    public static func scaleToFitLine(measuredHeight: CGFloat) -> CGFloat {
        guard measuredHeight > lineHeight, measuredHeight > 0 else { return 1 }
        return lineHeight / measuredHeight
    }

    /// UTF-16 locations in flattened editor text of the first real
    /// character of each page. The surface uses these to place exclusion
    /// paths; it must not paginate again.
    ///
    /// One pass through the pages. Where a page begins inside a split
    /// element is how many printed lines of that element the pages above
    /// have consumed — so the walk carries that count forward rather than
    /// recounting it from page one for every page, which was quadratic:
    /// measured on a synthetic 910-page draft, the recount took 3.2 seconds
    /// where this walk takes milliseconds.
    public static func pageStartLocations(
        elements: [ScriptElement],
        pages: [EDraftEngine.ScriptPage]
    ) -> [Int] {
        let ranges = ScreenplayEditPlanner.ranges(for: elements)
        /// Printed lines of each element the pages walked so far consumed.
        var consumed: [Int: Int] = [:]
        /// An element is wrapped at most once; page starts repeat elements.
        var wrapped: [Int: [Paginator.WrappedLine]] = [:]
        return pages.map { page in
            defer {
                for line in page.lines where line.element >= 0 && line.isPrintedElement {
                    consumed[line.element, default: 0] += 1
                }
            }
            guard let line = page.lines.first(where: { $0.element >= 0 }),
                  elements.indices.contains(line.element),
                  ranges.indices.contains(line.element)
            else { return 0 }
            if wrapped[line.element] == nil {
                let element = elements[line.element]
                let width = Paginator.geometry[element.type.engineKind]?.width
                    ?? Paginator.pageWidthChars
                wrapped[line.element] = Paginator.wrapLines(element.text, width: width)
            }
            let lines = wrapped[line.element] ?? []
            let start = consumed[line.element] ?? 0
            let startInElement = lines.indices.contains(start) ? lines[start].utf16Start : 0
            return ranges[line.element].range.location + startInElement
        }
    }

    /// Advances a running per-element line count past one page — the
    /// caller's half of the `consumed` walk that tells `scriptPageRuns`
    /// where a split element resumes.
    public static func consumePrintedLines(
        of page: EDraftEngine.ScriptPage,
        into consumed: inout [Int: Int]
    ) {
        for line in page.lines where line.isPrintedElement {
            consumed[line.element, default: 0] += 1
        }
    }

    /// Blank lines the paginator puts before this kind, as points of
    /// paragraph spacing — so the Mac page and the PDF keep the same
    /// vertical rhythm.
    public static func spacing(before kind: ScreenplayKind) -> Double {
        let blanks = Paginator.geometry[kind.engineKind]?.before ?? 1
        return Double(blanks) * Double(lineHeight)
    }

    /// Indent inside the text block, in points, from the paginator's
    /// character geometry. `nil` means the line runs the full measure.
    public static func indents(
        for kind: ScreenplayKind,
        measure: CGFloat,
        characterWidth: CGFloat
    ) -> (head: CGFloat, tail: CGFloat)? {
        guard let geometry = Paginator.geometry[kind.engineKind] else { return nil }
        if geometry.indent == 0, geometry.width == Paginator.pageWidthChars {
            return nil
        }
        let head = CGFloat(geometry.indent) * characterWidth
        let used = CGFloat(geometry.indent + geometry.width) * characterWidth
        return (head, max(0, measure - used))
    }

    // MARK: - Script page

    /// Glyph positions for one paginated page. `widthOf` is the surface
    /// measuring the font it will draw with — Courier's pitch, or a
    /// fallback monospaced face's, so a missing Courier still lays out.
    ///
    /// `elements` and `consumed` are the style-run plumbing: the engine's
    /// model, and how many printed lines of each element the pages before
    /// this one consumed — the same walk `pageStartLocations` makes, carried
    /// by the caller page over page. Defaults mean "unstyled": the phone's
    /// renderer passes nothing until its PDF learns runs.
    public static func scriptPageRuns(
        _ page: EDraftEngine.ScriptPage,
        elements: [EDraftEngine.ScreenplayElement] = [],
        consumed: [Int: Int] = [:],
        sceneNumbers: [Int: String],
        format: PageFormat,
        showPageNumbers: Bool,
        widthOf: (String) -> CGFloat
    ) -> [Run] {
        let characterWidth = widthOf("0")
        let textTop = format.textTop
        let marks = ScreenplayExporter.sceneNumberMarks(for: page, numbers: sceneNumbers)
        var runs: [Run] = []
        /// This page's own walk: where each element's next printed line
        /// resumes, starting from the pages before this one.
        var lineCursors = consumed
        /// An element is wrapped at most once per page; pages repeat elements.
        var wrapped: [Int: [Paginator.WrappedLine]] = [:]

        if page.number > 1, showPageNumbers {
            runs.append(rightAligned(
                "\(page.number).",
                rightEdge: format.textRight,
                y: pageNumberY,
                widthOf: widthOf
            ))
        }
        if page.continuedTop {
            runs.append(Run(
                text: "CONTINUED:",
                origin: CGPoint(x: textLeft, y: textTop - continuedFromTopGap)
            ))
        }

        for (index, line) in page.lines.enumerated() where line.type != .blank {
            let y = textTop + CGFloat(index) * lineHeight
            let text = ScreenplayExporter.renderedText(for: line)

            // The runs this printed line carries, sliced out of the element
            // at the offset the wrap walk says this line begins at. The
            // rendered text can be shorter than the paginator's (a dual
            // cue's ` ^` never prints); slicing clamps to what prints.
            var segments: [StyleSegment] = []
            if !elements.isEmpty, line.isPrintedElement, elements.indices.contains(line.element) {
                let element = elements[line.element]
                if let elementRuns = element.runs, !elementRuns.isEmpty {
                    if wrapped[line.element] == nil {
                        let width = Paginator.geometry[element.type]?.width
                            ?? Paginator.pageWidthChars
                        wrapped[line.element] = Paginator.wrapLines(element.text, width: width)
                    }
                    let wrappedLines = wrapped[line.element] ?? []
                    let cursor = lineCursors[line.element] ?? 0
                    if wrappedLines.indices.contains(cursor) {
                        let start = wrappedLines[cursor].utf16Start
                        segments = Emphasis.slice(
                            elementRuns, start..<(start + (text as NSString).length)
                        ).map {
                            StyleSegment(start: $0.start, length: $0.end - $0.start, styles: $0.styles)
                        }
                    }
                }
            }
            if !elements.isEmpty, line.isPrintedElement {
                lineCursors[line.element, default: 0] += 1
            }

            switch line.type {
            case .element(.transition):
                var run = rightAligned(
                    text, rightEdge: format.textRight, y: y, widthOf: widthOf
                )
                run.segments = segments
                runs.append(run)
            case .element(.centered):
                var run = centered(text, y: y, format: format, widthOf: widthOf)
                run.segments = segments
                runs.append(run)
            default:
                let x = textLeft + CGFloat(ScreenplayExporter.leadingSpaces(for: line)) * characterWidth
                runs.append(Run(text: text, origin: CGPoint(x: x, y: y), segments: segments))
            }
            if let number = marks[index] {
                runs.append(contentsOf: sceneNumberRuns(
                    number, y: y, format: format,
                    characterWidth: characterWidth, widthOf: widthOf
                ))
            }
        }

        if page.continuedBottom {
            runs.append(rightAligned(
                "(CONTINUED)",
                rightEdge: format.textRight,
                y: textTop + CGFloat(format.linesPerPage + 1) * lineHeight,
                widthOf: widthOf
            ))
        }
        return runs
    }

    // MARK: - Title page

    /// The classic centered title-page stack: title in uppercase ~1/3 down,
    /// then credit, then authors, then remaining keys in document order.
    /// Contact sits bottom-left.
    public static func titlePageRuns(
        _ screenplay: EDraftCore.Screenplay,
        format: PageFormat,
        widthOf: (String) -> CGFloat
    ) -> [Run] {
        func values(_ key: String) -> [String] {
            screenplay.titlePage
                .first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?
                .values.filter { !$0.isEmpty } ?? []
        }

        var runs: [Run] = []
        var y = format.pageRect.height * 0.32
        for line in values("Title") {
            runs.append(centered(line.uppercased(), y: y, format: format, widthOf: widthOf))
            y += lineHeight
        }
        y += lineHeight
        for line in values("Credit") {
            runs.append(centered(line, y: y, format: format, widthOf: widthOf))
            y += lineHeight
        }
        y += lineHeight
        for line in values("Author") {
            runs.append(centered(line, y: y, format: format, widthOf: widthOf))
            y += lineHeight
        }

        for entry in screenplay.titlePage {
            let key = entry.key.lowercased()
            guard !["title", "credit", "author", "contact"].contains(key) else { continue }
            let lines = entry.values.filter { !$0.isEmpty }
            guard !lines.isEmpty else { continue }
            y += lineHeight
            if key != "source" {
                runs.append(centered(entry.key, y: y, format: format, widthOf: widthOf))
                y += lineHeight
            }
            for line in lines {
                runs.append(centered(line, y: y, format: format, widthOf: widthOf))
                y += lineHeight
            }
        }

        let contact = values("Contact")
        if !contact.isEmpty {
            var contactY = format.pageRect.height - 72 - CGFloat(contact.count - 1) * lineHeight
            for line in contact {
                runs.append(Run(text: line, origin: CGPoint(x: textLeft, y: contactY)))
                contactY += lineHeight
            }
        }
        return runs
    }

    // MARK: - Placement

    private static func centered(
        _ text: String, y: CGFloat, format: PageFormat,
        widthOf: (String) -> CGFloat
    ) -> Run {
        Run(
            text: text,
            origin: CGPoint(x: (format.pageRect.width - widthOf(text)) / 2, y: y)
        )
    }

    private static func rightAligned(
        _ text: String, rightEdge: CGFloat, y: CGFloat,
        widthOf: (String) -> CGFloat
    ) -> Run {
        Run(text: text, origin: CGPoint(x: rightEdge - widthOf(text), y: y))
    }

    /// A scene number in both margins, level with its slug. The left number
    /// is right-aligned and the right one left-aligned, so "7" and "112A"
    /// sit a constant gap from the text.
    private static func sceneNumberRuns(
        _ number: String, y: CGFloat, format: PageFormat,
        characterWidth: CGFloat, widthOf: (String) -> CGFloat
    ) -> [Run] {
        let gap = characterWidth * 2
        return [
            rightAligned(number, rightEdge: textLeft - gap, y: y, widthOf: widthOf),
            Run(text: number, origin: CGPoint(x: format.textRight + gap, y: y))
        ]
    }
}

private extension EDraftEngine.PageLine {
    /// A line the editor actually has. `(MORE)` and `CONT'D` are print-only
    /// (`element == -1`); blanks are spacing, not a character in the storage.
    var isPrintedElement: Bool {
        guard element >= 0 else { return false }
        if case .element = type { return true }
        return false
    }
}
