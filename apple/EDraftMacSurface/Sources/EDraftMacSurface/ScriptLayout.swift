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

    /// The flattened script, styled, with the map of element ranges.
    ///
    /// Elements are joined by newlines exactly as `ScreenplayEditPlanner`
    /// flattens them, so a range computed here means the same characters the
    /// planner means.
    public static func attributedScript(
        _ elements: [ScriptElement], measure: CGFloat
    ) -> (text: NSAttributedString, ranges: [ElementRange]) {
        let result = NSMutableAttributedString()
        var ranges: [ElementRange] = []

        for (index, element) in elements.enumerated() {
            let location = result.length
            let spacingAfter = index + 1 < elements.count
                ? ScreenplayPageLayout.spacing(before: elements[index + 1].type)
                : 0
            let style = attributes(
                for: element.type, measure: measure, spacingAfter: spacingAfter
            )
            result.append(NSAttributedString(string: element.text, attributes: style))
            ranges.append(
                ElementRange(
                    id: element.id,
                    range: NSRange(location: location, length: (element.text as NSString).length)
                )
            )
            if index < elements.count - 1 {
                result.append(NSAttributedString(string: "\n", attributes: style))
            }
        }
        fitTallGlyphs(result)
        return (result, ranges)
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
