import AppKit
import CoreText
import EDraftEngine
import EDraftCore
import Foundation

/// The screenplay, set for a Mac text view.
///
/// This is the Mac's half of what `ScriptTextView` does on the phone: turn a
/// list of elements into one attributed string, remember which character range
/// each element occupies, and answer where a given element sits on the page.
/// Measurements come from `ScreenplayPageLayout` — Courier 12, the paginator's
/// character indents, six lines per inch — so the page a writer types on is
/// the page the PDF prints. The phone still reads `ScriptTypography` (a
/// fraction of a hand-width); the desk has paper.
///
/// It exists as a package rather than inside an app target for one reason: the
/// question that decides the whole Mac port — whether the text system can tell
/// us where an element is — is answerable by a test, and only if the code
/// under test can be linked by a test.
public enum ScriptLayout {

    /// Which characters belong to which element, in the flattened text.
    public struct ElementRange: Equatable, Sendable {
        public let id: UUID
        public let range: NSRange
    }

    /// The two text systems AppKit offers, and the reason this package exists.
    ///
    /// The iPhone's surface runs TextKit 1 deliberately: its scroll and reveal
    /// arithmetic reads `NSLayoutManager` rectangles directly, and TextKit 2
    /// answers a different question in a different shape. Rather than assume
    /// either way for the Mac, both are built here and measured by the same
    /// tests — see `ScriptLayoutTests`.
    public enum TextStack: Sendable {
        case textKit1
        case textKit2
    }

    // MARK: - Setting the page

    /// The styled faces of Courier 12, converted once by the font manager.
    /// Bold and italic are traits of the same fixed-pitch advance, so a
    /// styled run wraps exactly where its plain text would — pagination
    /// cannot see emphasis.
    private static let styledFaces: [Int: NSFont] = {
        let manager = NSFontManager.shared
        var faces: [Int: NSFont] = [:]
        for styles: StyleSet in [.bold, .italic, [.bold, .italic]] {
            var face = font(for: .action)
            if styles.contains(.bold) { face = manager.convert(face, toHaveTrait: .boldFontMask) }
            if styles.contains(.italic) { face = manager.convert(face, toHaveTrait: .italicFontMask) }
            faces[styles.rawValue] = face
        }
        return faces
    }()

    /// The attributes a style run adds over its span. `allCaps` and
    /// `hiddenText` have no Fountain spelling and no UI in this phase, so
    /// they cannot enter the model here — should one arrive anyway (a file
    /// from a future Final Draft), it stays in the model and is simply not
    /// drawn: a style is a view concern; the text stays.
    public static func styleAttributes(for styles: StyleSet) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [:]
        let face = styles.intersection([.bold, .italic])
        if !face.isEmpty, let styled = styledFaces[face.rawValue] {
            attributes[.font] = styled
        }
        if styles.contains(.underline) {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if styles.contains(.strikeout) {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    /// The flattened script, styled, with the map of element ranges.
    ///
    /// Elements are joined by newlines exactly as `ScreenplayEditPlanner`
    /// flattens them, so a range computed here means the same characters the
    /// planner means.
    /// A region of the layout a cut scene occupies (§7.3). Collapsed, it is
    /// the card's own line and the body is not in the text at all;
    /// expanded, it is the body, and the region's foot takes a dotted rule.
    public struct OmittedRegion: Equatable {
        public let key: DraftElementID
        public let range: NSRange
        public let collapsed: Bool
    }

    /// The script as one attributed string, and where each element sits in
    /// it — for a caller with no cut scenes to place.
    ///
    /// The shape this had before §7.3: two members, no regions. Kept so the
    /// layout's own tests and any caller that never draws a region read the
    /// same as they did.
    public static func attributedScript(
        _ elements: [ScriptElement], measure: CGFloat
    ) -> (text: NSAttributedString, ranges: [ElementRange]) {
        let script = attributedScript(elements, measure: measure, omitted: OmittedScenes(), expanded: [])
        return (script.text, script.ranges)
    }

    /// The script as one attributed string, and where each element sits in
    /// it.
    ///
    /// **A cut scene is collapsed out of the flow (§7.3).** Its card is the
    /// line that stands in its place; the body is not appended at all, and
    /// every element of it takes an *empty* range at the card's end. That
    /// keeps `ranges` parallel to `elements` — which the surface relies on,
    /// indexing one by the other — while the text the layout, the canvas
    /// and the paginator all see is the same text, with the cut scene out
    /// of it. Expanded, the body is appended in the same sepia and the
    /// ranges are real again.
    public static func attributedScript(
        _ elements: [ScriptElement], measure: CGFloat,
        omitted: OmittedScenes = OmittedScenes(),
        expanded: Set<DraftElementID> = []
    ) -> (text: NSAttributedString, ranges: [ElementRange], regions: [OmittedRegion]) {
        let result = NSMutableAttributedString()
        var ranges: [ElementRange] = Array(
            repeating: ElementRange(id: UUID(), range: NSRange(location: 0, length: 0)),
            count: elements.count
        )
        var regions: [OmittedRegion] = []

        /* What takes a line. A collapsed span contributes none: its card,
           which is a live element in front of it, already has one. */
        var rows: [Int] = []
        var hidden: [Int: OmittedScene] = [:]
        var at = 0
        while at < elements.count {
            guard let scene = omitted.scene(for: elements[at]), omitted.contains(elements[at]),
                  !expanded.contains(scene.key)
            else {
                rows.append(at)
                at += 1
                continue
            }
            var end = at
            while end < elements.count, omitted.contains(elements[end]),
                  omitted.scene(for: elements[end])?.key == scene.key {
                hidden[end] = scene
                end += 1
            }
            at = end
        }

        for (place, index) in rows.enumerated() {
            let element = elements[index]
            let location = result.length
            let next = place + 1 < rows.count ? elements[rows[place + 1]].type : nil
            let spacingAfter = next.map { ScreenplayPageLayout.spacing(before: $0) } ?? 0
            let style = attributes(
                for: element.type, measure: measure, spacingAfter: spacingAfter
            )
            result.append(NSAttributedString(string: element.text, attributes: style))
            let length = (element.text as NSString).length
            /* A cut scene's body, when the writer has opened it: the same
               sepia the card takes, at reading weight. Never struck — the
               collapse is what says "cut"; the ink says "not live". */
            if omitted.contains(element), length > 0 {
                result.addAttributes(
                    [.foregroundColor: NSColor.screenplayOmittedInk],
                    range: NSRange(location: location, length: length)
                )
            }
            // Runs are canonical over the text (sorted, clamped,
            // non-overlapping), so each one lands as an attribute range.
            for run in element.runs ?? [] {
                let start = min(max(0, run.start), length)
                let end = min(max(start, run.end), length)
                guard end > start else { continue }
                var runAttributes = styleAttributes(for: run.styles)
                // The attention mark is a wash on the paper, never a color
                // on the ink — a storage attribute because it is content,
                // not a decoration (docs/RFC-HIGHLIGHTER.md).
                if run.highlight != nil {
                    runAttributes[.backgroundColor] = NSColor.highlightWash
                }
                guard !runAttributes.isEmpty else { continue }
                result.addAttributes(
                    runAttributes,
                    range: NSRange(location: location + start, length: end - start)
                )
            }
            ranges[index] = ElementRange(
                id: element.id,
                range: NSRange(location: location, length: length)
            )
            /* Every element of a span hidden behind this card takes an
               empty range at the card's end: parallel, and impossible to
               put a caret inside or to sweep a selection into. */
            if let scene = omitted.scene(for: element), omitted.isCard(element),
               !expanded.contains(scene.key) {
                let foot = NSRange(location: location + length, length: 0)
                for (hiddenIndex, behind) in hidden where behind.key == scene.key {
                    ranges[hiddenIndex] = ElementRange(id: elements[hiddenIndex].id, range: foot)
                }
                regions.append(OmittedRegion(
                    key: scene.key,
                    range: NSRange(location: location, length: length),
                    collapsed: true
                ))
            }
            if place < rows.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: style))
            }
        }

        /* An expanded span's region is its body, from the first element to
           the last — what the dotted rule closes. */
        for scene in omitted.scenes where expanded.contains(scene.key) {
            /* By identity only. `draftID ?? scene.key` would have counted
               every element that has no identity yet as part of the span. */
            let placed = elements.indices.filter { index in
                guard let id = elements[index].draftID else { return false }
                return scene.elements.contains(id)
            }
            guard let first = placed.first, let last = placed.last,
                  ranges[first].range.length > 0 || ranges[last].range.length > 0 else { continue }
            let start = ranges[first].range.location
            let end = ranges[last].range.location + ranges[last].range.length
            regions.append(OmittedRegion(
                key: scene.key,
                range: NSRange(location: start, length: max(0, end - start)),
                collapsed: false
            ))
        }

        fitTallGlyphs(result)
        return (result, ranges, regions)
    }

    /// An emoji's own metrics exceed the 12pt line. Shrink the font on
    /// those characters so TextKit draws them inside the box rather than
    /// clipping the top. Courier is left alone.
    static func fitTallGlyphs(_ text: NSMutableAttributedString, range: NSRange? = nil) {
        let full = range ?? NSRange(location: 0, length: text.length)
        guard full.length > 0, NSMaxRange(full) <= text.length else { return }
        let ns = text.string as NSString

        // Nothing to do for a script written in the Latin alphabet, which is
        // almost all of them, and finding that out must not cost a scan of
        // every character. Only a character outside ASCII can be taller than
        // Courier's line: the ones this exists for are emoji and marks that
        // stack. Measured on a 910-page draft, the enumeration below with a
        // `CTLine` built per grapheme took 2.7 seconds; this returns from it
        // in a few milliseconds.
        guard ns.rangeOfCharacter(from: Self.beyondASCII, options: [], range: full).location
                != NSNotFound
        else { return }

        ns.enumerateSubstrings(in: full, options: .byComposedCharacterSequences) { substring, subrange, _, _ in
            guard let substring else { return }
            // The same test again per grapheme, so a single emoji in a
            // feature does not put every other character through Core Text.
            guard substring.unicodeScalars.contains(where: { $0.value > 127 }) else { return }
            let font = (text.attribute(.font, at: subrange.location, effectiveRange: nil) as? NSFont)
                ?? ScriptLayout.font(for: .action)
            let height = glyphPathHeight(substring, font: font)
            let scale = ScreenplayPageLayout.scaleToFitLine(measuredHeight: height)
            guard scale < 0.999 else { return }
            let fitted = NSFont(name: font.fontName, size: font.pointSize * scale)
                ?? font.withSize(font.pointSize * scale)
            text.addAttribute(.font, value: fitted, range: subrange)
        }
    }

    /// Everything Courier sets on its own line: anything outside it may not.
    private static let beyondASCII: CharacterSet = {
        var set = CharacterSet(charactersIn: UnicodeScalar(0)...UnicodeScalar(127))
        set.invert()
        return set
    }()

    /// Ink height, not the font's line box. Courier 12 reports ~14pt via
    /// `NSString.size` and would scale every letter; glyph path bounds
    /// of an "A" sit inside 12pt and an emoji does not.
    static func glyphPathHeight(_ string: String, font: NSFont) -> CGFloat {
        let attributed = NSAttributedString(string: string, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        return CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds]).height
    }

    /// One element's attributes, built from the print measurements.
    public static func attributes(
        for kind: ScreenplayKind, measure: CGFloat, spacingAfter: Double
    ) -> [NSAttributedString.Key: Any] {
        let font = font(for: kind)
        let paragraph = NSMutableParagraphStyle()
        // Leading is `FixedLeading`'s, not the paragraph style's. Clamping it
        // here compresses the line fragment and crops anything taller than a
        // line; the delegate sets the same 12pt advance and lets a tall glyph
        // overflow, which is what every other editor does.
        _ = ScreenplayPageLayout.lineHeight
        // Space belongs to the paragraph before, so the caret is drawn at the
        // next baseline rather than stretched through screenplay whitespace.
        paragraph.paragraphSpacing = spacingAfter

        let characterWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        if let indents = ScreenplayPageLayout.indents(
            for: kind, measure: measure, characterWidth: characterWidth
        ) {
            paragraph.firstLineHeadIndent = indents.head
            paragraph.headIndent = indents.head
            paragraph.tailIndent = -indents.tail
        }
        switch ScriptTypography.alignment(for: kind) {
        case .natural: break
        case .right: paragraph.alignment = .right
        case .centred: paragraph.alignment = .center
        }

        return [
            .font: font,
            .foregroundColor: NSColor.screenplayInk,
            .paragraphStyle: paragraph
        ]
    }

    /// Courier 12, the face the PDF prints. A missing Courier falls back to
    /// the system mono at the same size so layout still measures a pitch.
    public static func font(for kind: ScreenplayKind) -> NSFont {
        NSFont(name: "Courier", size: ScreenplayPageLayout.fontSize)
            ?? .monospacedSystemFont(ofSize: ScreenplayPageLayout.fontSize, weight: .regular)
    }

    /// The text-block width the page is set to — not the window.
    ///
    /// Sixty Courier characters as the font actually measures them, not the
    /// 432 points the page geometry says that is. Courier 12's advance is
    /// 7.201171875, so sixty of them are 432.0703125 — seven hundredths of a
    /// point wider than the block. A container of exactly 432 therefore wraps
    /// a full line at fifty-nine characters and pushes a word down, and every
    /// full-measure paragraph gains a line.
    ///
    /// Measured on a production draft: the text view laid out one to two more
    /// lines than the paginator counted on twenty-five of twenty-six pages,
    /// so the type overran the foot of nearly every sheet and a character cue
    /// was left stranded from its dialogue across the page break.
    ///
    /// Only full-measure elements were affected. Dialogue, parentheticals and
    /// cues are given head and tail indents in character units, so their wrap
    /// was always in characters; action, scene headings and transitions have
    /// no indents and fall back to the container, which is this.
    ///
    /// This is the *screen's* measure. The printed page is unchanged — the
    /// PDF places glyphs by character position rather than by wrapping — so
    /// nothing here moves a word on paper.
    public static var pageMeasure: CGFloat {
        measuredTextWidth(for: PageFormat.current)
    }

    /// The width sixty of this font's characters really occupy, rounded up so
    /// the sixtieth always fits.
    public static func measuredTextWidth(for format: PageFormat) -> CGFloat {
        let advance = ("0" as NSString).size(withAttributes: [.font: font(for: .action)]).width
        guard advance > 0 else { return ScreenplayPageLayout.textBlockWidth(format) }
        return (CGFloat(Paginator.pageWidthChars) * advance).rounded(.up)
    }

    // MARK: - Asking where an element is

    /// A text view with the script in it, on the chosen text system.
    ///
    /// TextKit 2 is what `NSTextView` gives you by default; TextKit 1 has to
    /// be assembled, which is itself part of the answer this package exists to
    /// find out.
    public static func textView(
        _ elements: [ScriptElement], measure: CGFloat, using stack: TextStack
    ) -> (view: NSTextView, ranges: [ElementRange]) {
        let script = attributedScript(elements, measure: measure)
        let frame = NSRect(x: 0, y: 0, width: measure, height: 600)
        let view: NSTextView

        switch stack {
        case .textKit2:
            view = NSTextView(frame: frame)
        case .textKit1:
            let storage = NSTextStorage()
            let layout = NSLayoutManager()
            let container = NSTextContainer(size: CGSize(width: measure, height: .greatestFiniteMagnitude))
            container.widthTracksTextView = true
            storage.addLayoutManager(layout)
            layout.addTextContainer(container)
            view = NSTextView(frame: frame, textContainer: container)
        }

        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textStorage?.setAttributedString(script.text)
        return (view, script.ranges)
    }

    /// A blank line encloses no glyphs and so measures no width. Left as it
    /// comes, a mark drawn on it would be an invisible sliver, so an empty line
    /// is given the measure it occupies — which is what a reader means by "that
    /// line" anyway.
    private static func widened(_ rect: CGRect, toAtLeast container: NSTextContainer) -> CGRect {
        guard rect.width < 1 else { return rect }
        return CGRect(x: rect.minX, y: rect.minY, width: container.size.width, height: rect.height)
    }

    /// Where an element sits, in the text view's own coordinates.
    ///
    /// This is the whole question. A Navigator row scrolls to a rectangle and
    /// marks it; if the text system will not say where a range is, neither is
    /// possible, and the iPhone's answer — read `NSLayoutManager` directly —
    /// does not exist on TextKit 2.
    /// Container coordinates into the view's own, which differ by the text
    /// container's origin. They were the same while the inset was zero, and
    /// every caller reads this as a view rectangle — so the conversion belongs
    /// here rather than in each of them, and it costs nothing when there is no
    /// inset to speak of.
    private static func inView(_ rect: CGRect, _ view: NSTextView) -> CGRect {
        let origin = view.textContainerOrigin
        return rect.offsetBy(dx: origin.x, dy: origin.y)
    }

    /// A range may cross containers. Measure only the part drawn by this
    /// view; querying another container's glyphs produces unrelated rects.
    static func sheetBoundingRect(of range: NSRange, in view: NSTextView) -> CGRect? {
        guard let layout = view.layoutManager, let container = view.textContainer else { return nil }
        layout.ensureLayout(for: container)
        let owned = layout.characterRange(forGlyphRange: layout.glyphRange(for: container), actualGlyphRange: nil)
        if range.length == 0 {
            guard range.location >= owned.location, range.location <= NSMaxRange(owned) else { return nil }
            return boundingRect(of: range, in: view)
        }
        let intersection = NSIntersectionRange(range, owned)
        guard intersection.length > 0 else { return nil }
        return boundingRect(of: intersection, in: view)
    }

    /// The text column the range's lines occupy — the fragment's full
    /// measure, not the glyphs that happen to sit on it.
    ///
    /// The omitted-scene overlay is framed by this: its controls
    /// trailing-align, and against a glyph rect "trailing" is the end of the
    /// word OMITTED, so a pill and a disclosure wider than one word run
    /// leftward over the card's own text and off the page into the gutter.
    /// `boundingRect` stays the glyph answer — reveals, find and the note
    /// wash rely on it — and this is the column answer beside it.
    static func sheetColumnRect(of range: NSRange, in view: NSTextView) -> CGRect? {
        guard let layout = view.layoutManager, let container = view.textContainer else {
            // TextKit 2: a layout fragment already spans the column, so the
            // glyph answer and the column answer are the same rect.
            return boundingRect(of: range, in: view)
        }
        layout.ensureLayout(for: container)
        // A range may cross containers. Measure only the part this view
        // draws; querying another container's fragments produces unrelated
        // rects — the same clip `sheetBoundingRect` applies.
        let owned = layout.characterRange(forGlyphRange: layout.glyphRange(for: container), actualGlyphRange: nil)
        let clipped: NSRange
        if range.length == 0 {
            guard range.location >= owned.location, range.location <= NSMaxRange(owned) else { return nil }
            clipped = range
        } else {
            let intersection = NSIntersectionRange(range, owned)
            guard intersection.length > 0 else { return nil }
            clipped = intersection
        }

        // Union the fragment of every line the range touches. A fragment
        // spans the container — the column — whatever its glyphs measure.
        let glyphs = layout.glyphRange(forCharacterRange: clipped, actualCharacterRange: nil)
        let count = layout.numberOfGlyphs
        var union: CGRect?
        var glyph = glyphs.location
        let end = NSMaxRange(glyphs)
        while glyph < end, glyph < count {
            var effective = NSRange()
            let fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: &effective)
            if fragment.height > 0 {
                union = union.map { $0.union(fragment) } ?? fragment
            }
            let next = NSMaxRange(effective)
            glyph = next > glyph ? next : glyph + 1
        }
        if let union { return inView(union, view) }

        // A zero-length range asks for the line it sits on. Past the end of
        // the text there is no glyph at all, and the spot lives in the extra
        // fragment the text system keeps for exactly that case.
        guard count > 0 else { return nil }
        let fragment = glyphs.location >= count
            ? layout.extraLineFragmentRect
            : layout.lineFragmentRect(forGlyphAt: min(glyphs.location, count - 1), effectiveRange: nil)
        return fragment.height > 0 ? inView(fragment, view) : nil
    }

    public static func boundingRect(of range: NSRange, in view: NSTextView) -> CGRect? {
        if let layoutManager = view.layoutManager, let container = view.textContainer {
            // TextKit 1: the same arithmetic the iPhone's surface uses.
            // Lay out the glyphs asked for — never the whole container, which
            // this used to do: a whole-container ensure costs about a
            // millisecond even when the layout is already valid, and a page
            // boundary walk on a feature asks it nine hundred times.
            let glyphs = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            layoutManager.ensureLayout(forGlyphRange: glyphs)
            let measured = layoutManager.boundingRect(forGlyphRange: glyphs, in: container)
            if measured.height > 0 {
                return inView(widened(measured, toAtLeast: container), view)
            }

            // A line with nothing on it still has a height and a place — it is
            // the blank line a writer is about to type into, and a reader can
            // be sent to it. An empty line in the body borrows the fragment it
            // sits in; an empty line at the very end has none, and lives in the
            // extra fragment the text system keeps for exactly that case. The
            // extra fragment exists only once the container is finished — the
            // one place a whole-container ensure is still bought.
            if NSMaxRange(range) >= (view.string as NSString).length {
                layoutManager.ensureLayout(for: container)
            }
            let length = layoutManager.numberOfGlyphs
            let fallback = glyphs.location >= length
                ? layoutManager.extraLineFragmentUsedRect
                : layoutManager.lineFragmentUsedRect(
                    forGlyphAt: min(glyphs.location, max(0, length - 1)), effectiveRange: nil
                )
            return fallback.height > 0 ? inView(widened(fallback, toAtLeast: container), view) : nil
        }

        guard let layoutManager = view.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              let start = contentManager.location(
                  contentManager.documentRange.location, offsetBy: range.location
              ),
              let end = contentManager.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end)
        else { return nil }

        // TextKit 2: the same answer, assembled from the fragments the range
        // touches. `ensureLayout` first, or a fragment that has never been
        // displayed reports nothing at all.
        layoutManager.ensureLayout(for: textRange)
        var union: CGRect?
        layoutManager.enumerateTextLayoutFragments(
            from: textRange.location, options: [.ensuresLayout]
        ) { fragment in
            guard fragment.rangeInElement.location.compare(textRange.endLocation) == .orderedAscending
            else { return false }
            union = union.map { $0.union(fragment.layoutFragmentFrame) } ?? fragment.layoutFragmentFrame
            return true
        }
        return union
    }
}
