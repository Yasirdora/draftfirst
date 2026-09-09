import Foundation

/// One recognised line of text, positioned on the page it came from.
///
/// Coordinates are fractions of the page with the origin at the top-left and
/// `top` increasing downward, so sorting by `top` is reading order. Vision and
/// PDFKit both report a lower-left origin; converting once at the boundary
/// keeps that convention out of the layout reasoning here.
public struct ScannedTextLine: Sendable, Equatable {
    public var text: String
    public var page: Int
    public var left: Double
    public var top: Double
    public var bottom: Double

    public init(text: String, page: Int, left: Double, top: Double, bottom: Double) {
        self.text = text
        self.page = page
        self.left = left
        self.top = top
        self.bottom = bottom
    }
}

/// Reconstructs a screenplay's Fountain source from the geometry of its
/// printed pages.
///
/// A screenplay is the rare document whose meaning is carried by its layout.
/// Scene headings sit at the left margin, dialogue is indented an inch further,
/// parentheticals half an inch beyond that, and character cues sit near the
/// centre — a convention printed scripts have followed for long enough that
/// where a line begins says what the line *is*. Recognising the words is the
/// easy half; this is the half that turns them back into a screenplay rather
/// than a wall of text.
///
/// Where a line's content settles the question, content wins — a slug line
/// beginning INT. is a scene heading however the page was cropped. Geometry
/// decides the rest, measured against the page's own action margin so that a
/// tilted or trimmed scan reads the same as a square one.
public enum ScreenplayTranscription {

    /// The standard US margins, as fractions of page width measured from the
    /// action margin: a printed page puts action at 1.5", dialogue at 2.5",
    /// parentheticals at 3.0" and character cues at 3.7" across 8.5" of paper.
    private enum Indent {
        static let dialogue = 1.0 / 8.5
        static let parenthetical = 1.5 / 8.5
        static let character = 2.2 / 8.5
        static let transition = 3.5 / 8.5

        /// Boundaries sit midway between neighbouring margins, so every line
        /// is read as whichever margin it lies closest to.
        static let overAction = dialogue / 2
        static let overDialogue = (dialogue + parenthetical) / 2
        static let overParenthetical = (parenthetical + character) / 2
    }

    /// Line pitch assumed when a page carries no measurable text: a screenplay
    /// page is 55 lines of 12pt type.
    private static let assumedPitch = 1.0 / 55.0

    public static func fountain(from lines: [ScannedTextLine]) -> String {
        let body = lines.filter { !isPageFurniture($0) }
        guard !body.isEmpty else { return "" }

        let margin = actionMargin(body)

        // Read the margins first. They are only abandoned for the words when
        // the page has no margins to read: silence is not evidence against
        // them, because a page of pure action — a montage, an opening, a
        // chase — has no speech to find and its indents were right all along.
        // Measuring the indents says what the absence of cues cannot.
        var blocks = build(body, margin: margin, layout: .margins)
        if !blocks.contains(where: { $0.role == .character }), isFlat(body, margin: margin) {
            let byContent = build(body, margin: margin, layout: .flat)
            if byContent.contains(where: { $0.role == .character }) {
                blocks = byContent
            }
        }
        return render(blocks)
    }

    // MARK: - Reading the page

    /// Running heads, page numbers and the marks a printed script carries
    /// across a page break. Only the top and bottom edges are considered: a
    /// scene heading is often the first line on a page and must survive.
    private static func isPageFurniture(_ line: ScannedTextLine) -> Bool {
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        guard line.top < 0.06 || line.bottom > 0.94 else { return false }

        let digitsAndDots = text.allSatisfy { $0.isNumber || $0 == "." }
        if digitsAndDots && text.contains(where: \.isNumber) { return true }

        return ["CONTINUED", "(CONTINUED)", "CONT'D", "(CONT'D)", "MORE", "(MORE)"]
            .contains(text.uppercased())
    }

    /// Where the page's action margin falls.
    ///
    /// Action is the leftmost thing on a screenplay page, but the single
    /// smallest reading is one stray box away from being wrong — a low
    /// percentile is the same answer with a bad reading's worth of slack.
    private static func actionMargin(_ lines: [ScannedTextLine]) -> Double {
        let lefts = lines.map(\.left).sorted()
        return lefts[min(lefts.count - 1, lefts.count / 10)]
    }

    /// Whether the page carries no indentation at all — every line beginning
    /// at the action margin, as a screenplay shown on a screen or exported
    /// without margins does. That, and not the absence of speech, is what
    /// makes the words the only structure left to read.
    private static func isFlat(_ lines: [ScannedTextLine], margin: Double) -> Bool {
        lines.allSatisfy { $0.left - margin < Indent.overAction }
    }

    private static func build(
        _ body: [ScannedTextLine], margin: Double, layout: Layout
    ) -> [Block] {
        var blocks: [Block] = []
        for page in pages(of: body) {
            append(page, margin: margin, layout: layout, to: &blocks)
        }
        resolveOrphans(&blocks)
        return blocks
    }

    /// How a page carries its structure.
    ///
    /// A printed screenplay says what each line is by where the line starts.
    /// Paper that has lost those margins says it only in the words — a script
    /// read off a screen, a PDF exported without indents, a photograph of an
    /// app. Reading that by indent alone runs a cue, its parenthetical and its
    /// speech together into a single paragraph, so it has to be read the other
    /// way: by what the lines say.
    private enum Layout { case margins, flat }

    private static func pages(of lines: [ScannedTextLine]) -> [[ScannedTextLine]] {
        Dictionary(grouping: lines, by: \.page)
            .sorted { $0.key < $1.key }
            .map { $0.value.sorted { $0.top < $1.top } }
    }

    // MARK: - Blocks

    private enum Role {
        case scene, action, character, parenthetical, dialogue, transition

        /// Whether a wrapped run of these lines is one paragraph. A cue and a
        /// transition are single lines by definition; everything else wraps.
        var wraps: Bool {
            switch self {
            case .action, .dialogue, .scene, .parenthetical: return true
            case .character, .transition: return false
            }
        }
    }

    private struct Block {
        var role: Role
        var text: String
    }

    private static func append(
        _ page: [ScannedTextLine], margin: Double, layout: Layout, to blocks: inout [Block]
    ) {
        let breakGap = paragraphBreak(of: page)
        var previous: (line: ScannedTextLine, role: Role)?
        var speaking = false

        for line in page {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let broke = previous.map { line.top - $0.line.top >= breakGap } ?? true

            let role = switch layout {
            case .margins:
                marginRole(of: text, indent: line.left - margin, previous: previous?.role)
            case .flat:
                flatRole(of: text, speaking: speaking, brokeParagraph: broke)
            }
            speaking = role == .character || role == .parenthetical
                || (role == .dialogue && speaking)

            // A line continues the paragraph above it when it plays the same
            // part and follows at the page's own spacing. A wider gap starts a
            // new paragraph even when the two lines look alike.
            if let previous, previous.role == role, role.wraps, !blocks.isEmpty, !broke {
                blocks[blocks.count - 1].text = joining(blocks[blocks.count - 1].text, text)
            } else {
                blocks.append(Block(role: role, text: text))
            }
            previous = (line, role)
        }
    }

    /// The vertical step past which two lines belong to different paragraphs.
    ///
    /// Measured from the height of the text rather than from the gaps between
    /// lines. A page may hold no two lines of a single paragraph anywhere on
    /// it — a title page, a page of slug lines, a short scene — and then no
    /// gap on that page shows what single spacing looks like, so any estimate
    /// drawn from gaps takes the space *between* paragraphs for the space
    /// inside one and runs them together. Ink height always shows it: a line
    /// of type stands between roughly 0.6 and 0.85 of its own line step, so
    /// twice that height falls between single and double spacing at either
    /// extreme, which is where the boundary belongs.
    ///
    /// The lower quartile of those heights, not the median, because a reader
    /// hands back what it considers one line and recognisers consider a whole
    /// wrapped paragraph to be one: those boxes are several rows tall, and a
    /// median drawn from them measures a paragraph rather than a line, putting
    /// the threshold above every real gap so that a page becomes one block.
    /// A quarter of the lines on any page are single rows — a cue, a slug, a
    /// short sentence — and the quartile finds them.
    private static func paragraphBreak(of page: [ScannedTextLine]) -> Double {
        let heights = page.map { $0.bottom - $0.top }.filter { $0 > 0 }.sorted()
        guard !heights.isEmpty else { return assumedPitch * 1.5 }
        return heights[heights.count / 4] * 2
    }

    /// Rejoins a wrapped line. A word broken across lines loses its hyphen;
    /// requiring the continuation to be lowercase keeps real hyphenated names
    /// (MARY-/ANNE) whole.
    private static func joining(_ head: String, _ tail: String) -> String {
        if head.hasSuffix("-"), let first = tail.first, first.isLowercase {
            return String(head.dropLast()) + tail
        }
        return head + " " + tail
    }

    // MARK: - Classification

    /// Reads a page with no usable margins by what its lines say: a short line
    /// of capitals names a speaker, a bracketed line under one is how they say
    /// it, and the line after that is what they said.
    private static func flatRole(of text: String, speaking: Bool, brokeParagraph: Bool) -> Role {
        if FountainDetect.isSceneHeading(text) { return .scene }
        if FountainDetect.isTransition(text) || FountainDetect.isFadeOpener(text) { return .transition }
        if speaking && text.hasPrefix("(") { return .parenthetical }
        // A cue only stands if something is spoken under it; `resolveOrphans`
        // turns the rest back into action.
        if FountainDetect.isUpper(text) && isName(text) { return .character }
        if speaking && !brokeParagraph { return .dialogue }
        return .action
    }

    private static func marginRole(of text: String, indent: Double, previous: Role?) -> Role {
        // What a line says outranks where it sits: a slug line is a scene
        // heading however the page was cropped.
        if FountainDetect.isSceneHeading(text) { return .scene }
        if FountainDetect.isTransition(text) || FountainDetect.isFadeOpener(text) { return .transition }

        let speaking = previous == .character || previous == .parenthetical || previous == .dialogue
        if speaking && text.hasPrefix("(") { return .parenthetical }

        // Capitals set far right and ending in a colon are a transition the
        // detector does not know by name — SMASH CUT:, MATCH CUT:.
        if indent >= Indent.transition, FountainDetect.isUpper(text), text.hasSuffix(":") {
            return .transition
        }
        if indent >= Indent.overParenthetical {
            if text.hasPrefix("(") { return .parenthetical }
            // At the cue margin a short line names who speaks. Demanding
            // capitals here would lose McCREADY and DeSANTIS — names that
            // carry lowercase and so are not capitals to the parser.
            return isName(text) ? .character : .dialogue
        }
        if indent >= Indent.overDialogue {
            if text.hasPrefix("(") { return .parenthetical }
            return FountainDetect.isUpper(text) && isName(text) ? .character : .dialogue
        }
        if indent >= Indent.overAction {
            return speaking ? .dialogue : .action
        }
        return .action
    }

    /// A cue names who speaks: a few words, with no sentence among them.
    ///
    /// Length alone used to be the whole test, and forty characters of
    /// capitals is a sentence as readily as a name. A script that sets its
    /// action in capitals — plenty do — came back with BOTH OF THEM FREEZE.
    /// in the cast list and the paragraph beneath it as her first speech.
    ///
    /// Punctuation is what separates the two: a name neither ends a sentence
    /// nor contains one. Abbreviated honorifics are the exception that rule
    /// has to keep, since MRS. HUDSON and DR. K are cues, so a full stop only
    /// counts as a sentence when the word it closes is long enough to be a
    /// word rather than an abbreviation.
    private static func isName(_ text: String) -> Bool {
        // A guard against pathological input, not the name limit: the limit
        // is measured below, on the name alone.
        guard !text.isEmpty, text.count <= 120 else { return false }

        // An extension says how the line is heard, not who says it:
        // TOM (V.O.) is TOM, and its brackets are not prose punctuation.
        // It is removed before the name is measured, so a long one —
        // (CONTINUING, OVER THE RADIO) — cannot push a short name out.
        let bare = text
            .replacingOccurrences(
                of: #"(?:\s*\([^)]*\))+\s*$"#, with: "", options: .regularExpression
            )
            .trimmingCharacters(in: .whitespaces)
        guard !bare.isEmpty, bare.count <= 40 else { return false }
        // Something has to be said. A stray mark or a lone number is not a
        // name, whatever margin it was found at.
        guard bare.contains(where: \.isLetter) else { return false }

        // Marks that only appear in prose. A colon would be a transition,
        // which is settled before this is ever asked.
        if bare.contains(where: { ",;:!?".contains($0) }) { return false }

        let words = bare.split(separator: " ")
        guard !words.isEmpty, words.count <= 5 else { return false }
        for word in words where word.hasSuffix(".") {
            if word.dropLast().count > 3 { return false }
        }
        return true
    }

    /// Dialogue only means anything under a cue, and a cue only means anything
    /// with speech beneath it. Geometry alone will occasionally produce one
    /// without the other — on a title page, or a page of notes — and what it
    /// produced there was always action.
    private static func resolveOrphans(_ blocks: inout [Block]) {
        for index in blocks.indices where blocks[index].role == .character {
            let next = blocks.indices.contains(index + 1) ? blocks[index + 1].role : nil
            if next != .dialogue && next != .parenthetical {
                blocks[index].role = .action
            }
        }

        var speaking = false
        for index in blocks.indices {
            switch blocks[index].role {
            case .character:
                speaking = true
            case .dialogue, .parenthetical:
                if !speaking { blocks[index].role = .action }
            default:
                speaking = false
            }
        }
    }

    // MARK: - Writing Fountain

    private static func render(_ blocks: [Block]) -> String {
        var lines: [String] = []

        for block in blocks {
            switch block.role {
            case .scene:
                separate(&lines)
                // No forcing marker: a block is only ever a scene because the
                // detector recognised its slug, so it will recognise it again.
                lines.append(block.text)

            case .transition:
                separate(&lines)
                let natural = (FountainDetect.isTransition(block.text)
                    || FountainDetect.isFadeOpener(block.text)) && FountainDetect.isUpper(block.text)
                lines.append(natural ? block.text : "> " + block.text)

            case .character:
                separate(&lines)
                // A name carrying lowercase — McCREADY — is not capitals to
                // the parser and would read as action; forcing keeps the cue.
                lines.append(FountainDetect.isUpper(block.text) ? block.text : "@" + block.text)

            case .action:
                separate(&lines)
                // Only a line opening with a Fountain marker needs forcing.
                // Capitals do not: every action block is followed by a blank
                // line, and that is what stops them reading as a cue.
                lines.append(
                    FountainDetect.startsWithForcedMarker(block.text) ? "!" + block.text : block.text
                )

            case .parenthetical, .dialogue:
                // Speech follows its cue with no blank line between them —
                // that adjacency is what makes it speech.
                lines.append(block.text)
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func separate(_ lines: inout [String]) {
        if !lines.isEmpty { lines.append("") }
    }
}
