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

        public init(text: String, origin: CGPoint) {
            self.text = text
            self.origin = origin
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

    /// UTF-16 locations in flattened editor text of the first real
    /// character of each page. The surface uses these to place exclusion
    /// paths; it must not paginate again.
    public static func pageStartLocations(
        elements: [ScriptElement],
        pages: [EDraftEngine.ScriptPage]
    ) -> [Int] {
        let ranges = ScreenplayEditPlanner.ranges(for: elements)
        return pages.enumerated().map { pageIndex, page in
            guard let line = page.lines.first(where: { $0.element >= 0 }),
                  elements.indices.contains(line.element),
                  ranges.indices.contains(line.element)
            else { return 0 }
            let element = elements[line.element]
            let width = Paginator.geometry[element.type.engineKind]?.width
                ?? Paginator.pageWidthChars
            let wrapped = Paginator.wrapLines(element.text, width: width)
            let consumed = pages[0..<pageIndex]
                .flatMap(\.lines)
                .filter { $0.element == line.element && $0.isPrintedElement }
                .count
            let startInElement = wrapped.indices.contains(consumed)
                ? wrapped[consumed].utf16Start
                : 0
            return ranges[line.element].range.location + startInElement
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
    public static func scriptPageRuns(
        _ page: EDraftEngine.ScriptPage,
        sceneNumbers: [Int: String],
        format: PageFormat,
        showPageNumbers: Bool,
        widthOf: (String) -> CGFloat
    ) -> [Run] {
        let characterWidth = widthOf("0")
        let textTop = format.textTop
        let marks = ScreenplayExporter.sceneNumberMarks(for: page, numbers: sceneNumbers)
        var runs: [Run] = []

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
            switch line.type {
            case .element(.transition):
                runs.append(rightAligned(
                    text, rightEdge: format.textRight, y: y, widthOf: widthOf
                ))
            case .element(.centered):
                runs.append(centered(text, y: y, format: format, widthOf: widthOf))
            default:
                let x = textLeft + CGFloat(ScreenplayExporter.leadingSpaces(for: line)) * characterWidth
                runs.append(Run(text: text, origin: CGPoint(x: x, y: y)))
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
