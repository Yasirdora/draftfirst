import Foundation

/// Final Draft (.fdx) interoperability — the Swift port of the TypeScript
/// engine's `fdx.ts`, pinned byte-for-byte by `Fixtures/fdx.json`.
///
/// Import is bounded and best-effort: malformed input produces structured
/// diagnostics instead of escaping as an exception, and the reader is total —
/// it cannot throw. Export reports every lossy conversion, and the emitted
/// XML carries an in-file warning comment when non-printing structure must be
/// omitted (FDX cannot represent the engine's structural elements).
public enum Fdx {

    // MARK: - Diagnostics

    public enum Severity: String, Codable, Sendable {
        /// What a save did on the writer's behalf; never a warning. The
        /// TypeScript engine has always had it (`FdxDiagnosticSeverity`);
        /// no conformance case reached one until notes gained anchors, so
        /// the gap sat unnoticed. Decoding a TypeScript diagnostic needs it.
        case info
        case warning
        case error
    }

    public struct Diagnostic: Codable, Equatable, Sendable {
        public let code: String
        public let severity: Severity
        public let message: String
        public let offset: Int?
        public let paragraphIndex: Int?
        public let elementIndex: Int?
        public let count: Int?

        public init(
            code: String,
            severity: Severity,
            message: String,
            offset: Int? = nil,
            paragraphIndex: Int? = nil,
            elementIndex: Int? = nil,
            count: Int? = nil
        ) {
            self.code = code
            self.severity = severity
            self.message = message
            self.offset = offset
            self.paragraphIndex = paragraphIndex
            self.elementIndex = elementIndex
            self.count = count
        }
    }

    // MARK: - Options and results

    public struct ImportOptions: Sendable {
        /// Maximum UTF-16 code units accepted from one document. Default: 16 MiB.
        public var maxSourceCharacters: Int?
        /// Maximum paragraphs collected from one document. Default: 100,000.
        public var maxParagraphs: Int?
        /// Maximum Text runs processed from one document. Default: 500,000.
        public var maxTextRuns: Int?
        /// Maximum diagnostics returned. Default: 100.
        public var maxWarnings: Int?

        public init(
            maxSourceCharacters: Int? = nil,
            maxParagraphs: Int? = nil,
            maxTextRuns: Int? = nil,
            maxWarnings: Int? = nil
        ) {
            self.maxSourceCharacters = maxSourceCharacters
            self.maxParagraphs = maxParagraphs
            self.maxTextRuns = maxTextRuns
            self.maxWarnings = maxWarnings
        }
    }

    public struct ExportOptions: Sendable {
        /// Maximum diagnostics returned. Default: 100.
        public var maxWarnings: Int?
        /// How the writer's notes are written into <ScriptNotes>.
        public var notes: NoteWriting?

        public init(maxWarnings: Int? = nil, notes: NoteWriting? = nil) {
            self.maxWarnings = maxWarnings
            self.notes = notes
        }
    }

    public struct ImportResult: Sendable {
        public let script: Screenplay
        /// Backward-compatible messages. Prefer `diagnostics` for programmatic use.
        public let warnings: [String]
        public let diagnostics: [Diagnostic]
        /// The file's ScriptNotes, in file order. See `Fdx.ScriptNote`.
        public let scriptNotes: [ScriptNote]
    }

    public struct ExportResult: Sendable {
        public let xml: String
        public let warnings: [String]
        public let diagnostics: [Diagnostic]
    }

    // MARK: - Limits

    struct Limits {
        var maxSourceCharacters: Int
        var maxParagraphs: Int
        var maxTextRuns: Int
        var maxWarnings: Int
    }

    private static let defaultLimits = Limits(
        maxSourceCharacters: 16 * 1024 * 1024,
        maxParagraphs: 100_000,
        maxTextRuns: 500_000,
        maxWarnings: 100
    )

    /// TypeScript `positiveInteger`: a present, positive safe integer wins;
    /// anything else falls back to the default.
    /// Whether a Text run carries Final Draft's AllCaps style
    /// (TypeScript `runIsAllCaps`).
    ///
    /// This is how Final Draft shouts: it stores what the writer typed and
    /// marks the run, so `<Text Style="AllCaps">cHroNo-aGEnT vAL</Text>` has
    /// been displayed as CHRONO-AGENT VAL for the life of the document. Read
    /// the text without the style and a script that looked immaculate for years
    /// opens as though it were typed with a broken shift key.
    ///
    /// Styles are a '+'-separated list — `Bold+Underline+AllCaps` — so this
    /// matches a whole entry rather than a substring.
    static func runIsAllCaps(_ style: String?) -> Bool {
        guard let style else { return false }
        return style.split(separator: "+").contains {
            $0.trimmingCharacters(in: .whitespaces).lowercased() == "allcaps"
        }
    }

    private static func positiveInteger(_ value: Int?, fallback: Int) -> Int {
        guard let value, value > 0 else { return fallback }
        return value
    }

    private static func limits(of options: ImportOptions) -> Limits {
        Limits(
            maxSourceCharacters: positiveInteger(
                options.maxSourceCharacters, fallback: defaultLimits.maxSourceCharacters
            ),
            maxParagraphs: positiveInteger(options.maxParagraphs, fallback: defaultLimits.maxParagraphs),
            maxTextRuns: positiveInteger(options.maxTextRuns, fallback: defaultLimits.maxTextRuns),
            maxWarnings: positiveInteger(options.maxWarnings, fallback: defaultLimits.maxWarnings)
        )
    }

    /// A bounded diagnostic sink: at the limit the last slot becomes the
    /// truncation marker, exactly as the TypeScript `DiagnosticCollector`.
    final class DiagnosticCollector {
        private let limit: Int
        private var items: [Diagnostic] = []
        private var truncated = false

        init(limit: Int) {
            self.limit = limit
        }

        func add(_ diagnostic: Diagnostic) {
            if items.count < limit {
                items.append(diagnostic)
                return
            }
            if truncated || limit == 0 { return }
            truncated = true
            items[limit - 1] = Diagnostic(
                code: "FDX_DIAGNOSTICS_TRUNCATED",
                severity: .warning,
                message: "Additional diagnostics were omitted after the \(limit)-message limit."
            )
        }

        func result() -> [Diagnostic] { items }
    }

    // MARK: - Type mapping

    private static let fdxToModel: [String: ElementKind] = [
        "scene heading": .scene,
        "action": .action,
        "character": .character,
        "dialogue": .dialogue,
        "parenthetical": .parenthetical,
        "transition": .transition,
        "shot": .shot,
        "general": .general,
        // A Final Draft "Note" is a line in the script that does not print,
        // which is exactly what Fountain's [[ ]] is. Reading it as General put
        // a writer's notes on the page — ten of them across the two real
        // features this was measured on.
        "note": .note,
        // The card that opens an act prints and is structure: the model's
        // actbreak keeps both (RFC-ACT-BREAK §3). Its Alignment="Center" is a
        // property of the type, so nothing is refined from attributes.
        "new act": .actbreak
        /* "end of act" is deliberately absent: it carries no fact the model
           lacks — an act ends where the next one begins (D3). The import loop
           absorbs it; mapping it here would store a derivable fact. */
    ]

    /// The outline levels, which Final Draft lets a writer rename.
    ///
    /// Stock they are `Outline 1`, `Outline 2`, `Outline 3`; renamed they
    /// arrive as `Outline 1 (Acts)`, `Outline 2 (Sequences)`, `Outline 3
    /// (Scenes)` — both shapes are in the two production drafts this was
    /// measured on, from the same writer. Matching the number and ignoring
    /// whatever they called it is the only rule that reads both.
    private static let outlineType = try! NSRegularExpression(
        pattern: "^outline\\s+(\\d+)(?:\\s*\\(.*\\))?$"
    )

    /// What a Final Draft paragraph type means to the engine, and how deep it
    /// sits. `nil` for a type we have never heard of — the caller warns and
    /// falls back to General, which is what it always did.
    static func fdxElementKind(_ key: String) -> (type: ElementKind, depth: Int?)? {
        if let known = fdxToModel[key] { return (known, nil) }

        /* An outline heading is a section, at the level Final Draft gives it.
           Read as General these printed on the page as stage directions — 82
           of them across the two real features, and they took the page count
           with them, because a section does not paginate and General does. */
        let range = NSRange(key.startIndex..<key.endIndex, in: key)
        if let match = outlineType.firstMatch(in: key, range: range),
           let level = Range(match.range(at: 1), in: key),
           let depth = Int(key[level]) {
            return (.section, Swift.max(1, depth))
        }

        /* The prose under an outline heading. Fountain calls it a synopsis and
           writes it `= like this`; Final Draft calls it a Summary. Same thing:
           what the scene is for, not a line of it. */
        if key == "summary" { return (.synopsis, nil) }

        return nil
    }

    /// The Final Draft paragraph type an element goes out as.
    ///
    /// Keyed on the element rather than on its type alone, because a section's
    /// level is part of what it is: `# Act One` is `Outline 1` and `### A
    /// scene` is `Outline 3`, and a map from type to string cannot say that.
    static func fdxType(of element: ScreenplayElement) -> String? {
        if element.type == .section { return "Outline \(Swift.max(1, element.depth ?? 1))" }
        return modelToFdx[element.type]
    }

    private static let modelToFdx: [ElementKind: String] = [
        .scene: "Scene Heading",
        .action: "Action",
        .character: "Character",
        .dialogue: "Dialogue",
        .parenthetical: "Parenthetical",
        .transition: "Transition",
        .shot: "Shot",
        .general: "General",
        .centered: "General",
        .lyrics: "General",
        .actbreak: "New Act",
        .note: "Note",
        .synopsis: "Summary"
        /* `.section` is not here: its level is part of its type — see
           `fdxType(of:)`. */
    ]

    /* Our own FDX extension namespace: the attributes Final Draft has no
       field for (lyrics, title-page keys). The prefix and URI changed with
       the eDraft rename, so both are READ and only the current one is
       written — an .fdx exported under the old name must keep re-importing
       losslessly forever. Mirrors the TypeScript engine exactly. */
    private static let namespace = "https://edraft.xyz/ns/fdx/1"
    private static let extensionPrefix = "EDraft"
    private static let legacyAttributePrefixes = ["draftfirst"]
    private static let xmlHeader = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"no\" ?>"

    // MARK: - Paragraph collection

    /// One Text element's attributes, read as a model run — nothing when
    /// the run carries nothing (AllCaps aside, which lives in the text
    /// itself; see `runIsAllCaps`).
    private static func modelRun(
        from attributes: [(name: String, value: String)], start: Int, end: Int
    ) -> StyleRun? {
        guard end > start else { return nil }
        var styles: StyleSet = []
        if let style = attributes.last(where: { $0.name == "style" })?.value {
            for part in style.split(separator: "+") {
                switch part.trimmingCharacters(in: .whitespaces) {
                case "Bold": styles.insert(.bold)
                case "Italic": styles.insert(.italic)
                case "Underline": styles.insert(.underline)
                case "Strikeout": styles.insert(.strikeout)
                case "HiddenText": styles.insert(.hiddenText)
                default: break   // AllCaps lives in the text — the file's own rule
                }
            }
        }
        let revision = attributes.last(where: { $0.name == "revisionid" })
            .flatMap { Int($0.value) }
        let tags = (attributes.last(where: { $0.name == "tagnumber" })?.value ?? "")
            .split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        var highlight: HighlightColor?
        let highlightValue = attributes.last(where: {
            $0.name == "\(Fdx.extensionPrefix.lowercased()):highlight"
        })?.value ?? Fdx.legacyAttributePrefixes.lazy.compactMap({ legacy in
            attributes.last(where: { $0.name == "\(legacy):highlight" })?.value
        }).first
        if highlightValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "yellow" {
            highlight = .yellow
        }
        guard !styles.isEmpty || revision != nil || !tags.isEmpty || highlight != nil
        else { return nil }
        return StyleRun(
            start: start, end: end, styles: styles,
            revisionID: revision, tagNumbers: tags.isEmpty ? nil : tags,
            highlight: highlight
        )
    }

    private struct CollectedParagraph {
        var attributes: [(name: String, value: String)]
        var text: String
        var paragraphIndex: Int
        var inTitlePage: Bool
        /// Where the whole <Paragraph> sits in the source, in UTF-16 units,
        /// for a preserving write. See `Fdx.Document`.
        var start: Int = 0
        var end: Int = 0
        /// Where its direct-child <Text> runs sit, so only they are replaced.
        var textStart: Int = -1
        var textEnd: Int = -1
        /// The runs the paragraph's direct-child <Text> elements declared.
        var runs: [StyleRun] = []
        /// Where each block Final Draft embeds in the paragraph — a
        /// <DualDialogue>, an <OmittedScene> — sits among its text, as a
        /// UTF-16 offset into `text` (TypeScript `FdxParagraph.blocks`).
        var blocks: [Int] = []
        /// Each <DualDialogue> directly inside it, as UTF-16 source offsets
        /// (TypeScript `FdxParagraph.dialogues`).
        var dialogues: [(start: Int, end: Int)] = []
        /// Each <OmittedScene> directly inside it, as UTF-16 source offsets
        /// (TypeScript `FdxParagraph.omissions`).
        var omissions: [(start: Int, end: Int)] = []

        func attribute(_ name: String) -> String? {
            attributes.last { $0.name == name }?.value
        }

        /// One of our own extension attributes, read under the current
        /// prefix or any legacy one. Files exported before the eDraft
        /// rename carry `draftfirst:`; they must keep importing losslessly.
        func extensionAttribute(_ name: String) -> String? {
            if let current = attribute("\(Fdx.extensionPrefix.lowercased()):\(name)"), !current.isEmpty {
                return current
            }
            for legacy in Fdx.legacyAttributePrefixes {
                if let value = attribute("\(legacy):\(name)"), !value.isEmpty { return value }
            }
            return nil
        }
    }

    /// The scan state, held by reference so the tokeniser's handlers can
    /// mutate it — the direct port of the closure captures in `paragraphsOf`.
    private final class ParagraphCollector {
        let limits: Limits
        let diagnostics: DiagnosticCollector

        var body: [CollectedParagraph] = []
        var title: [CollectedParagraph] = []
        var hasFinalDraftRoot = false
        var titleDepth = 0
        var textDepth = 0
        /// The elements open above the cursor, so a <Content> can be told from
        /// its parent. A self-closing tag dispatches both start and end, so
        /// this balances.
        var open: [String] = []
        /// One entry per open <Content>: whether it is the script's.
        ///
        /// A Final Draft document has many. The screenplay is the one directly
        /// under <FinalDraft>, the title page has its own under <TitlePage>,
        /// and a feature written with the Beat Board carries one per <Outline>
        /// section — fifty-three of them in the files this was measured
        /// against. Taking paragraphs from all of them puts the writer's
        /// beats, page goals and cast list into the script.
        var contents: [Bool] = []
        /// How deep inside the current paragraph the cursor is, counting
        /// everything that is not the paragraph's own <Text>.
        ///
        /// A paragraph's text is the <Text> that is its *direct child*.
        /// Everything else inside it is Final Draft's metadata — and in a real
        /// file that includes whole paragraphs: a scene heading carries
        /// <SceneProperties> with a <CharacterArcBeat> for every character in
        /// the scene, each holding its own <Paragraph><Text>. Reading those as
        /// script is what emptied every scene heading in the file and put the
        /// arc beats in the body.
        ///
        /// Counting rather than naming the containers is deliberate. FDX is a
        /// large and unstable format; a list of tags to skip is a list to keep
        /// up with, and the rule "a paragraph owns only its direct-child Text"
        /// is the format itself. It is bounded by the paragraph's own closing
        /// tag, so a strange document cannot make it run away.
        var metadataDepth = 0
        /// Whether the Text run being read is styled AllCaps by Final Draft.
        var runUppercases = false
        /// The direct-child Text run being read, so its attributes become a
        /// model run: styles, revision, tags, and our own highlight.
        var openRun: (attributes: [(name: String, value: String)], start: Int)?
        var paragraphCount = 0
        var textRunCount = 0
        var limitReached = false
        var current: CollectedParagraph?

        /// The units of the source, so a span can be sliced back out of it.
        var units: [UInt16] = []

        init(limits: Limits, diagnostics: DiagnosticCollector) {
            self.limits = limits
            self.diagnostics = diagnostics
        }

        /// The end of the tag that opened at `offset`, past its '>'.
        func tagEnd(_ offset: Int) -> Int {
            var index = offset
            while index < units.count && units[index] != 62 { index += 1 }   // 62 is ">"
            return min(index + 1, units.count)
        }

        var inScriptContent: Bool { contents.contains(true) }

        func finishParagraph() {
            guard let paragraph = current else { return }
            metadataDepth = 0
            if paragraph.inTitlePage { title.append(paragraph) } else { body.append(paragraph) }
            current = nil
            textDepth = 0
            runUppercases = false
        }

        func start(_ tag: FdxXmlScanner.Tag, offset: Int) -> Bool {
            let parent = open.last
            open.append(tag.name)

            if tag.name == "finaldraft" { hasFinalDraftRoot = true }
            if tag.name == "titlepage" { titleDepth += 1 }
            if tag.name == "content" {
                // The screenplay's, the title page's, and nobody else's.
                contents.append(parent == "finaldraft" || parent == "titlepage")
            }

            /* A block Final Draft embeds in the paragraph is still skipped as
               metadata, but its place is kept: a ScriptNote Range counts it. */
            if metadataDepth == 0, Fdx.embeddedBlocks.contains(tag.name), let place = current?.text.utf16.count {
                current?.blocks.append(place)
                if tag.name == "dualdialogue" { current?.dialogues.append((start: offset, end: -1)) }
                if tag.name == "omittedscene" { current?.omissions.append((start: offset, end: -1)) }
            }
            // Inside a paragraph, anything that is not its own <Text> is
            // metadata — including nested paragraphs. Skipped whole.
            if current != nil,
               metadataDepth > 0 || (tag.name != "text" && tag.name != "content") {
                metadataDepth += 1
                return true
            }

            if tag.name == "paragraph" && inScriptContent {
                if paragraphCount >= limits.maxParagraphs {
                    limitReached = true
                    return false
                }
                if current != nil {
                    // Not the nested-metadata case, which is handled above:
                    // this is a paragraph that never closed.
                    diagnostics.add(.init(
                        code: "FDX_NESTED_PARAGRAPH",
                        severity: .warning,
                        message: "A nested Paragraph closed the preceding paragraph best-effort.",
                        offset: offset
                    ))
                    finishParagraph()
                }
                current = CollectedParagraph(
                    attributes: tag.attributes,
                    text: "",
                    paragraphIndex: paragraphCount,
                    inTitlePage: titleDepth > 0,
                    start: offset,
                    end: offset
                )
                paragraphCount += 1
            }

            if tag.name == "text" && current != nil {
                if textRunCount >= limits.maxTextRuns {
                    limitReached = true
                    return false
                }
                textRunCount += 1
                textDepth += 1
                if current?.textStart == -1 { current?.textStart = offset }
                runUppercases = Fdx.runIsAllCaps(
                    tag.attributes.first { $0.name == "style" }?.value
                )
                openRun = (attributes: tag.attributes, start: current?.text.utf16.count ?? 0)
            }
            return true
        }

        func end(_ name: String, offset: Int) -> Bool {
            if open.last == name { open.removeLast() }

            if current != nil && metadataDepth > 0 {
                if name == "omittedscene", metadataDepth == 1, let count = current?.omissions.count, count > 0 {
                    current?.omissions[count - 1].end = tagEnd(offset)
                }
                if name == "dualdialogue", metadataDepth == 1, let count = current?.dialogues.count, count > 0 {
                    current?.dialogues[count - 1].end = tagEnd(offset)
                }
                metadataDepth -= 1
                if name == "content", !contents.isEmpty { contents.removeLast() }
                return true
            }

            if name == "text" && textDepth > 0 {
                textDepth -= 1
                runUppercases = false
                current?.textEnd = tagEnd(offset)
                if let run = openRun, current != nil {
                    if let span = Fdx.modelRun(
                        from: run.attributes,
                        start: run.start, end: current!.text.utf16.count
                    ) {
                        current?.runs.append(span)
                    }
                }
                openRun = nil
            }
            if name == "paragraph" {
                current?.end = tagEnd(offset)
                finishParagraph()
            }
            if name == "content", !contents.isEmpty { contents.removeLast() }
            if name == "titlepage" && titleDepth > 0 { titleDepth -= 1 }
            return true
        }

        func text(_ value: String, cdata: Bool) -> Bool {
            if current != nil && textDepth > 0 && metadataDepth == 0 {
                let decoded = cdata ? value : Fdx.decodeXmlEntities(value)
                current?.text += runUppercases ? decoded.uppercased() : decoded
            }
            return true
        }
    }

    private static func collectParagraphs(
        from source: String,
        limits: Limits,
        diagnostics: DiagnosticCollector
    ) -> (body: [CollectedParagraph], title: [CollectedParagraph], hasFinalDraftRoot: Bool) {
        let collector = ParagraphCollector(limits: limits, diagnostics: diagnostics)
        collector.units = Array(source.utf16)
        FdxXmlScanner.scan(
            source,
            handlers: FdxXmlScanner.Handlers(
                start: { tag, offset in collector.start(tag, offset: offset) },
                end: { name, offset in collector.end(name, offset: offset) },
                text: { value, cdata in collector.text(value, cdata: cdata) }
            ),
            diagnostics: diagnostics
        )

        if let unterminated = collector.current {
            diagnostics.add(.init(
                code: "FDX_UNTERMINATED_PARAGRAPH",
                severity: .warning,
                message: "An unterminated Paragraph was imported best-effort.",
                paragraphIndex: unterminated.paragraphIndex
            ))
            collector.finishParagraph()
        }
        if collector.limitReached {
            diagnostics.add(.init(
                code: "FDX_PARSE_LIMIT_REACHED",
                severity: .error,
                message: "Import stopped at \(limits.maxParagraphs) paragraphs or \(limits.maxTextRuns) Text runs.",
                count: collector.paragraphCount
            ))
        }
        return (collector.body, collector.title, collector.hasFinalDraftRoot)
    }

    // MARK: - Import

    /// The title page, verbatim (RFC-TITLE-PAGE D5): every paragraph
    /// becomes a line — text, alignment, styled runs, blanks and all. Our
    /// TitleKey extension attribute survives as an annotation when the
    /// file carries it; nothing is guessed, because guessing was how
    /// foreign files lost their layout.
    private static func titlePageLines(of paragraphs: [CollectedParagraph]) -> [TitlePageLine] {
        paragraphs.map { paragraph in
            var line = TitlePageLine(text: paragraph.text)
            switch (paragraph.attribute("alignment") ?? "").lowercased() {
            case "left": line.alignment = .left
            case "right": line.alignment = .right
            case "center": line.alignment = .center
            default: break
            }
            let runs = Emphasis.normalise(paragraph.runs, textLength: paragraph.text.utf16.count)
            if !runs.isEmpty { line.runs = runs }
            if let key = paragraph.extensionAttribute("titlekey"), !key.isEmpty {
                line.key = key
            }
            return line
        }
    }

    private static func emptyImport(_ diagnostics: DiagnosticCollector) -> ImportResult {
        let items = diagnostics.result()
        return ImportResult(
            script: Screenplay(titlePage: [], elements: []),
            warnings: items.map(\.message),
            diagnostics: items,
            scriptNotes: []
        )
    }

    /// Parse FDX XML into the engine model. Total by construction: every
    /// failure mode lands in `diagnostics`, never in a thrown error. (The
    /// TypeScript try/catch around this path has no Swift counterpart —
    /// there is nothing here that can throw.)
    public static func parse(_ xml: String, options: ImportOptions = ImportOptions()) -> ImportResult {
        let limits = limits(of: options)
        let diagnostics = DiagnosticCollector(limit: limits.maxWarnings)
        let source = xml

        if source.utf16.count > limits.maxSourceCharacters {
            diagnostics.add(.init(
                code: "FDX_INPUT_TOO_LARGE",
                severity: .error,
                message: "The FDX input exceeds the \(limits.maxSourceCharacters)-character safety limit.",
                count: source.utf16.count
            ))
            return emptyImport(diagnostics)
        }

        let parsed = collectParagraphs(from: source, limits: limits, diagnostics: diagnostics)
        if !parsed.hasFinalDraftRoot {
            diagnostics.add(.init(
                code: "FDX_ROOT_MISSING",
                severity: .warning,
                message: "Missing <FinalDraft> root — attempting best-effort paragraph import."
            ))
        }

        var elements: [ScreenplayElement] = []
        /* Every body paragraph as a ScriptNote Range counts it — absorbed ones
           included, because Final Draft's text still holds them. */
        var layout: [ParagraphLayout] = []
        let sourceUnits: [UInt16] = parsed.body.contains { !$0.dialogues.isEmpty || !$0.omissions.isEmpty }
            ? Array(source.utf16)
            : []
        /* Scenes the production has omitted (§7.3), as spans over `elements`. */
        var omissions: [Omission] = []
        for paragraph in parsed.body {
            let fdxType = paragraph.attribute("type") ?? ""
            let key = fdxType.jsTrimmed.lowercased()
            /* RFC-ACT-BREAK D3: an End of Act carries no fact the model lacks —
               an act ends where the next one begins, and the export regenerates
               these. Absorbed without a warning: a diagnostic the reader cannot
               act on only teaches them to ignore the list. */
            layout.append(ParagraphLayout(
                length: paragraph.text.utf16.count + Fdx.blockUnits * paragraph.blocks.count,
                blocks: paragraph.blocks,
                element: key == "end of act" ? nil : elements.count
            ))
            if key == "end of act" { continue }
            let kind = fdxElementKind(key)
            if kind == nil && !fdxType.isEmpty {
                diagnostics.add(.init(
                    code: "FDX_UNKNOWN_PARAGRAPH_TYPE",
                    severity: .warning,
                    message: "Unknown paragraph type \"\(fdxType)\" — imported as General.",
                    paragraphIndex: paragraph.paragraphIndex
                ))
            }

            /* Final Draft keeps dual dialogue as a paragraph with no text of its
               own holding a <DualDialogue>, whose paragraphs are the two
               speeches. Read as metadata, all of it was invisible: each block
               arrived as one empty General element. Its lines are the script. */
            func dualElements(_ lines: [CollectedParagraph]) -> [ScreenplayElement] {
                var cues = 0
                return lines.map { line in
                    var element = importedElement(
                        line, kind: fdxElementKind((line.attribute("type") ?? "").jsTrimmed.lowercased())
                    )
                    // The second speaker's cue is the one Fountain marks `^`.
                    if element.type == .character {
                        cues += 1
                        if cues == 2 { element.dual = true }
                    }
                    return element
                }
            }
            if !paragraph.dialogues.isEmpty,
               let lines = dualDialogue(of: paragraph, in: sourceUnits, limits: limits) {
                elements += dualElements(lines)
                continue
            }
            if !paragraph.dialogues.isEmpty {
                diagnostics.add(.init(
                    code: "FDX_DUAL_DIALOGUE_NOT_READ",
                    severity: .warning,
                    message: "A paragraph holds dual dialogue in a form not read (text of its own, or more than one block); its speeches are not shown.",
                    paragraphIndex: paragraph.paragraphIndex
                ))
            }
            /* An omitted scene is nested inside the Scene Heading that shows
               its OMITTED card (§7.3). The card stays the element it always
               was — its index, its number, its Range unchanged — and the body
               follows it, with the omission naming the span. Skipped as
               metadata before this, the whole scene was lost on any export
               that did not keep the file's own bytes. */
            elements.append(importedElement(paragraph, kind: kind))
            if !paragraph.omissions.isEmpty,
               let omitted = omittedScene(of: paragraph, in: sourceUnits, limits: limits) {
                let start = elements.count
                for line in omitted {
                    /* An omitted scene's dual dialogue is its lines, as it is
                       anywhere else in the script. */
                    if !line.dialogues.isEmpty,
                       let lines = dualDialogue(of: line, in: sourceUnits, limits: limits) {
                        elements += dualElements(lines)
                        continue
                    }
                    elements.append(importedElement(
                        line, kind: fdxElementKind((line.attribute("type") ?? "").jsTrimmed.lowercased())
                    ))
                }
                omissions.append(Omission(start: start, end: elements.count))
            }
        }

        /* The title page reads verbatim — it reports no diagnostics, so the
           collector's snapshot needs no particular order against it. */
        let title = titlePageLines(of: parsed.title)
        let read = scriptNotes(in: source, layout: layout, limits: limits, diagnostics: diagnostics)
        let (withOwn, notes, movedTo) = withOwnedNotes(elements, read.notes, read.ownership)
        let items = diagnostics.result()
        return ImportResult(
            script: Screenplay(
                titlePage: title,
                elements: withOwn,
                /* Notes read in front of their line shift the elements after
                   them, so a span recorded during the read moves with them. */
                omissions: omissions.isEmpty ? nil : movedOmissions(omissions, movedTo, withOwn.count)
            ),
            warnings: items.map(\.message),
            diagnostics: items,
            scriptNotes: notes
        )
    }

    /// What a paragraph typed "General" actually is.
    ///
    /// Final Draft has one bucket for anything that is not a script element,
    /// and what it means is carried by other attributes: centred by its
    /// alignment, lyrics by ours. Shared by the import and the preserving
    /// rewrite, because a rewrite has to reach the same answer the import did
    /// — deriving it twice was how a centred paragraph came out as an
    /// unmatched insert and rewrote the tail of the file.
    private static func refineGeneral(
        _ type: ElementKind, _ paragraph: CollectedParagraph
    ) -> ElementKind {
        guard type == .general else { return type }
        if (paragraph.extensionAttribute("elementtype") ?? "").lowercased() == "lyrics" {
            return .lyrics
        }
        if (paragraph.attribute("alignment") ?? "").lowercased() == "center" {
            return .centered
        }
        return type
    }

    /// The element a paragraph becomes, warnings aside — the same answer the
    /// import reaches, so a rewrite cannot disagree with it.
    /// One paragraph as the import reads it into an element (TypeScript `elementOf`).
    private static func importedElement(
        _ paragraph: CollectedParagraph, kind: (type: ElementKind, depth: Int?)?
    ) -> ScreenplayElement {
        let type: ElementKind = refineGeneral(kind?.type ?? .general, paragraph)
        var element = ScreenplayElement(type: type, text: paragraph.text)
        if !paragraph.runs.isEmpty {
            element.runs = Emphasis.normalise(paragraph.runs, textLength: paragraph.text.utf16.count)
        }
        if type == .section, let depth = kind?.depth { element.depth = depth }
        let sceneNumber = paragraph.attribute("number") ?? ""
        if type == .scene && !sceneNumber.isEmpty { element.sceneNumber = sceneNumber }
        if type == .character, (paragraph.attribute("dual") ?? "").lowercased() == "yes" {
            element.dual = true
        }
        return element
    }

    private static let dualDialogueFrame = Array("<FinalDraft><Content>".utf16)
    private static let dualDialogueFrameEnd = Array("</Content></FinalDraft>".utf16)

    /// The lines of a dual dialogue: the paragraphs of the one <DualDialogue> a
    /// paragraph with no text of its own holds, in order, with where they sit
    /// in UTF-16 units — or nil for any other paragraph (TypeScript
    /// `dualDialogueOf`).
    ///
    /// Measured on files Final Draft wrote, every dual dialogue has this form:
    /// a General paragraph, no text, one block of Character, Dialogue,
    /// Character, Dialogue. The block is read as a script of its own, so each
    /// line is read exactly as a body paragraph is.
    private static func dualDialogue(
        of paragraph: CollectedParagraph, in units: [UInt16], limits: Limits
    ) -> [CollectedParagraph]? {
        guard paragraph.text.isEmpty, paragraph.dialogues.count == 1,
              let block = paragraph.dialogues.first, block.end != -1 else { return nil }
        let shift = block.start - dualDialogueFrame.count
        let wrapped = dualDialogueFrame + Array(units[block.start..<block.end]) + dualDialogueFrameEnd
        let lines = collectParagraphs(
            from: String(decoding: wrapped, as: UTF16.self),
            limits: limits,
            diagnostics: DiagnosticCollector(limit: 1)
        ).body
        guard !lines.isEmpty else { return nil }
        return lines.map { line in
            var line = line
            line.start += shift
            line.end += shift
            if line.textStart != -1 { line.textStart += shift }
            if line.textEnd != -1 { line.textEnd += shift }
            return line
        }
    }

    /// The paragraphs of the <OmittedScene> a paragraph holds, or nil when it
    /// holds none (RFC-DRAFT-PRODUCTION §7.3, TypeScript `omittedSceneOf`).
    ///
    /// Final Draft nests an omitted scene INSIDE the Scene Heading paragraph
    /// that shows the OMITTED card, so unlike a dual dialogue the holding
    /// paragraph has text of its own — the card's. Read like a dual dialogue:
    /// the block is a script of its own.
    private static func omittedScene(
        of paragraph: CollectedParagraph, in units: [UInt16], limits: Limits
    ) -> [CollectedParagraph]? {
        guard paragraph.omissions.count == 1,
              let block = paragraph.omissions.first, block.end != -1 else { return nil }
        let shift = block.start - dualDialogueFrame.count
        let wrapped = dualDialogueFrame + Array(units[block.start..<block.end]) + dualDialogueFrameEnd
        let lines = collectParagraphs(
            from: String(decoding: wrapped, as: UTF16.self),
            limits: limits,
            diagnostics: DiagnosticCollector(limit: 1)
        ).body
        guard !lines.isEmpty else { return nil }
        return lines.map { line in
            var line = line
            line.start += shift
            line.end += shift
            if line.textStart != -1 { line.textStart += shift }
            if line.textEnd != -1 { line.textEnd += shift }
            /* A dual dialogue inside the omitted scene is read from the file
               like any other, so it has to point at the file too. */
            line.dialogues = line.dialogues.map { ($0.start + shift, $0.end == -1 ? -1 : $0.end + shift) }
            return line
        }
    }

    private static func elementKind(of paragraph: CollectedParagraph) -> ElementKind {
        let key = (paragraph.attribute("type") ?? "").jsTrimmed.lowercased()
        /* End of Act falls to .general here and is kept as a span, marked
           absorbed by `open` with the rule the import absorbs it with
           (RFC-ACT-BREAK D3). No element ever stands for it, so the rewrite
           owns its bytes: dropping the span would lose them, and leaving it
           unmarked let the alignment delete it. */
        return refineGeneral(fdxElementKind(key)?.type ?? .general, paragraph)
    }

    // MARK: - Preserving round trip

    /// A Final Draft file, kept whole.
    ///
    /// Reading an .fdx into a screenplay and writing a new one from that
    /// screenplay throws away everything the screenplay cannot hold. Measured
    /// on a real production draft: 19 revisions, 171 revised runs, 25 locked
    /// pages, 73 deleted-text marks, 248 production tags, 6 dual-dialogue
    /// blocks, 136 emphasis runs and 3 script notes — all gone, from opening
    /// the file, changing one word and saving. On a script a crew is shooting
    /// from, the revision history and the locked pages *are* the document.
    ///
    /// So the file is not rebuilt, it is edited. A write replaces only the
    /// paragraphs whose text actually changed; the rest, and the whole of the
    /// document outside the script's own <Content>, is emitted byte for byte.
    /// This costs no understanding — eDraft need not know what a
    /// `<TagDefinition>` means in order to keep it.
    public struct Document: Sendable {
        public let script: Screenplay
        public let warnings: [String]
        public let diagnostics: [Diagnostic]

        fileprivate let units: [UInt16]
        fileprivate let spans: [Span]
        fileprivate let blocks: [DualDialogueBlock]
        /// The script's top-level paragraphs as a ScriptNote Range counts them,
        /// where each starts, and where each note's Range value sits.
        fileprivate let topLevelUnits: [[Int32]]
        fileprivate let topLevelAt: [Int: Int]
        fileprivate let rangeValues: [ScriptNoteRangeValue?]
        /// Where each note and their container sit, and which are eDraft's.
        fileprivate let places: ScriptNotesPlaces
        fileprivate let limits: Limits

        /// The screenplay written back into the file it came from.
        ///
        /// `unedited` is this file as the caller read it before any edit — for
        /// an editor that works in Fountain, the file carried through Fountain
        /// and read back (TypeScript `FdxRewriteOptions.unedited`). A
        /// representation that cannot carry everything the file does makes
        /// every paragraph it cannot carry look edited: Fountain has no
        /// production tags and reads an emphasised heading as Action. Given
        /// this reading, a paragraph whose element comes back exactly as it
        /// was read is written as its original bytes, whatever was lost.
        public func rewrite(_ script: Screenplay, unedited: Screenplay? = nil, notes: NoteWriting? = nil) -> String {
            guard let first = spans.first, let last = spans.last else {
                // Nothing recognisable to edit: write a whole new file rather
                // than pretend, so a malformed original cannot corrupt a save.
                return Fdx.write(script, options: ExportOptions(notes: notes)).xml
            }

            var elements = script.elements

            /* An omitted scene's body is the file's own bytes, inside its
               card's paragraph (§7.3). Those elements have no paragraph of
               their own here, so they are taken out of the alignment before
               anything is paired — otherwise each would be written a second
               time, as a live paragraph, which is the resurrection this work
               exists to prevent. Found by the file's structure, because
               Fountain has no spelling for an omission and the app's own save
               path goes through it. */
            let omittedRuns = Fdx.omittedRuns(in: elements, spans: spans)
            var unedited = unedited?.elements
            /* Located in each reading on its own terms: an edit that adds or
               removes a line moves everything after it. */
            let omittedBefore = unedited.map { Fdx.omittedRuns(in: $0, spans: spans) }
            /* What `script.omissions` says, when it says anything (TypeScript
               `omissionPlan`). Nil is a caller that cannot know — a script
               carried through Fountain — and the file's structure decides, as
               it always has. A list is the writer's word: a scene omitted
               since the file was read is written inside its card, and one of
               the file's own the writer restored comes out of its card as
               live paragraphs, each keeping its bytes. */
            let plan = Fdx.omissionPlan(script.omissions, runs: omittedRuns, count: elements.count)
            var nestingRole = plan.roles
            /* TypeScript reports here — how many bodies were kept as the
               file had them, and any the save could not find. This port's
               `rewrite` returns bytes with no diagnostic sink, so the
               behaviour is the same and the telling is the other port's. */
            if !plan.kept.isEmpty {
                func dropped(_ runs: [OmittedRun]) -> Set<Int> {
                    var drop = Set<Int>()
                    for run in runs { for k in 0..<run.body.count { drop.insert(run.start + k) } }
                    return drop
                }
                let drop = dropped(plan.kept)
                elements = elements.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
                nestingRole = nestingRole.enumerated().filter { !drop.contains($0.offset) }.map(\.element)
            }
            if !omittedRuns.isEmpty, let before = unedited, let omittedBefore {
                /* The unedited reading loses what the save's own script lost:
                   every body kept inside its card. A restored scene's body
                   stays — it is live again, and pairs with the paragraphs it
                   was — and only its card goes, which the writer removed. */
                var gone = Set<Int>()
                for run in omittedBefore {
                    if plan.restored.contains(run.span) {
                        let card = run.start - 1
                        if card >= 0, Fdx.omissionKey(before[card].text) == Fdx.omissionKey(run.card) {
                            gone.insert(card)
                        }
                    } else {
                        for k in 0..<run.body.count { gone.insert(run.start + k) }
                    }
                }
                unedited = before.enumerated().filter { !gone.contains($0.offset) }.map(\.element)
            }

            /* Only paragraphs the import turned into elements can be matched to
               one. An absorbed End of Act left in the alignment was deleted by
               every save, and — typed General when it has no Alignment — was
               paired with the writer's next edit and given their text. A card
               whose scene the writer restored is gone; the paragraphs it held
               stand in its place, so the restored lines pair with the bytes
               they were. */
            let aligned = spans.filter { !$0.absorbed }.flatMap { span -> [Span] in
                guard plan.restored.contains(span.start), let held = span.omittedSpans else { return [span] }
                return held
            }

            /* A paragraph the writer did not edit is written as its original
               bytes. With the caller's unedited reading, "did not edit" is asked
               in the caller's own terms: the paragraph's element — or the run of
               elements its lines became — comes back exactly as it was read.
               Measured without this on a file Final Draft wrote, a save through
               Fountain that changed nothing lost 400 of 407 production tags. */
            var verbatim: [Int: Span] = [:]
            var merged: [Int: (span: Span, bytes: [UInt16])] = [:]
            var consumed = Set<Int>()
            if let reading = unedited {
                let ranges = Fdx.correspondence(aligned, reading)
                let matches = Fdx.unchangedFrom(elements, reading)
                var savedAt: [Int: Int] = [:]
                for (j, k) in matches.enumerated() {
                    if let k { savedAt[k] = j }
                }
                paragraphs: for (i, range) in ranges.enumerated() {
                    guard let range, let at = savedAt[range.lowerBound] else { continue }
                    for k in (range.lowerBound + 1)..<max(range.lowerBound + 1, range.upperBound)
                    where savedAt[k] != at + (k - range.lowerBound) {
                        continue paragraphs
                    }
                    verbatim[at] = aligned[i]
                    for k in (range.lowerBound + 1)..<max(range.lowerBound + 1, range.upperBound) {
                        consumed.insert(at + (k - range.lowerBound))
                    }
                }

                /* A paragraph the writer did edit — its elements edited in place —
                   has only the writer's change written into it: its Type, its
                   attributes, its nested blocks, and every tag, revision mark and
                   run split on the words they did not touch stay the file's.
                   Rewritten from the edited element instead, a typo fix lost a
                   line's tags and an emphasised heading became Action with
                   Fountain's `#2#` in its text. An edit that cannot be placed
                   is written as before (TypeScript reports it). */
                let inPlace = Fdx.pairedInPlace(matches, readingCount: reading.count)
                editedParagraphs: for (i, range) in ranges.enumerated() {
                    guard let range, let at = inPlace[range.lowerBound],
                          verbatim[at] == nil, !consumed.contains(at) else { continue }
                    /* A line of another kind with other words, in its place, replaced
                       it: that is not this paragraph edited, and is paired as before. */
                    if range.count == 1, reading[range.lowerBound].type != elements[at].type,
                       Fdx.wordsKey(reading[range.lowerBound].text) != Fdx.wordsKey(elements[at].text) {
                        continue
                    }
                    for k in (range.lowerBound + 1)..<max(range.lowerBound + 1, range.upperBound) {
                        let line = at + (k - range.lowerBound)
                        guard inPlace[k] == line, verbatim[line] == nil, !consumed.contains(line) else {
                            continue editedParagraphs
                        }
                    }
                    guard let bytes = Fdx.mergedParagraph(
                        aligned[i],
                        unedited: Array(reading[range]),
                        edited: Array(elements[at..<min(elements.count, at + range.count)]),
                        in: units
                    ) else { continue }
                    merged[at] = (aligned[i], bytes)
                    for k in 1..<max(1, range.count) { consumed.insert(at + k) }
                }
            }

            // Everything else is paired as it always was.
            let writtenAsRead = Set(verbatim.values.map(\.start) + merged.values.map(\.span.start))
            let rest = elements.indices.filter { verbatim[$0] == nil && merged[$0] == nil && !consumed.contains($0) }
            let restPaired = Fdx.align(
                aligned.filter { !writtenAsRead.contains($0.start) },
                to: rest.map { elements[$0] }
            )
            var paired = [Span?](repeating: nil, count: elements.count)
            for (r, j) in rest.enumerated() { paired[j] = restPaired[r] }
            for (j, span) in verbatim { paired[j] = span }
            for (j, entry) in merged { paired[j] = entry.span }

            /* The writer's notes go into <ScriptNotes> (RFC-NOTES-SYSTEM §4.2):
               every note that is not one of the file's own body Note
               paragraphs. A body Note paragraph stays a paragraph — kept,
               edited or deleted as before. Taken out of the script before
               anything is laid out, so a note never becomes a paragraph and
               never parts a dual pair; each remembers the element it sits in
               front of. */
            var outOfBody: [(element: ScreenplayElement, before: Int)] = []
            if elements.indices.contains(where: { elements[$0].type == .note && paired[$0]?.type != .note }) {
                var keep: [Int] = []
                for (j, element) in elements.enumerated() {
                    if element.type == .note && paired[j]?.type != .note {
                        outOfBody.append((element, keep.count))
                    } else {
                        keep.append(j)
                    }
                }
                var moved: [Int: Int] = [:]
                for (k, j) in keep.enumerated() { moved[j] = k }
                var verbatimKept: [Int: Span] = [:]
                for (j, span) in verbatim { if let k = moved[j] { verbatimKept[k] = span } }
                verbatim = verbatimKept
                var mergedKept: [Int: (span: Span, bytes: [UInt16])] = [:]
                for (j, entry) in merged { if let k = moved[j] { mergedKept[k] = entry } }
                merged = mergedKept
                consumed = Set(consumed.compactMap { moved[$0] })
                paired = keep.map { paired[$0] }
                elements = keep.map { elements[$0] }
                nestingRole = keep.map { nestingRole[$0] }
            }

            /* Each absorbed paragraph goes back, verbatim, in front of the
               first paragraph after it that this save keeps — anchored to what
               follows, so lines added at the end of an act still land before
               its End of Act — and after the last element when nothing after
               it survives. Never dropped: eDraft does not show an End of Act,
               so no writer can have meant to delete one. Keyed by where each
               paragraph starts, which is unique. */
            let kept = Set(paired.compactMap { $0?.start })
            var absorbedBefore: [Int: [Span]] = [:]
            var waiting: [Span] = []
            for span in spans {
                if span.absorbed {
                    waiting.append(span)
                } else if !waiting.isEmpty, kept.contains(span.start) {
                    absorbedBefore[span.start] = waiting
                    waiting = []
                }
            }

            /* A dual dialogue is kept whole where the writer kept it a dual pair:
               its frame is written verbatim around its lines, and lines added
               inside the pair go inside the block. Where the lines kept from it
               are no longer a dual pair — the second cue no longer dual, or the
               lines apart — the block is dissolved: its lines are written in its
               place as ordinary paragraphs, and the frame goes (TypeScript
               reports it). */
            var keptLines: [Int: [Int]] = [:]
            for (index, origin) in paired.enumerated() {
                if let block = origin?.block { keptLines[block, default: []].append(index) }
            }
            var pairs: [Int: (block: Int, end: Int)] = [:]
            for (block, kept) in keptLines {
                if let end = Fdx.dualPairEnd(elements, paired, consumed, block: block, kept: kept) {
                    pairs[kept[0]] = (block, end)
                }
            }

            let firstStart = first.block.map { blocks[$0].start } ?? first.start
            let lastEnd = last.block.map { blocks[$0].end } ?? last.end
            var out: [UInt16] = []
            /* Which original paragraph each paragraph written came from, in
               order, so each ScriptNote's Range can follow its words. */
            var written: [WrittenParagraph] = []
            func writtenFrom(_ start: Int, _ kind: WrittenParagraph.Kind) {
                written.append(WrittenParagraph(origin: topLevelAt[start], kind: kind))
            }
            var dissolvedWritten = Set<Int>()
            var lead: [UInt16] = []
            var wrote = false
            func restore(_ span: Span) {
                if wrote { out += span.lead.isEmpty ? lead : span.lead }
                if !span.lead.isEmpty { lead = span.lead }
                out += units[span.start..<span.end]
                writtenFrom(span.start, .same)
                wrote = true
            }
            func keptBytes(_ index: Int, _ origin: Span) -> [UInt16] {
                if verbatim[index]?.start == origin.start { return Array(units[origin.start..<origin.end]) }
                if let entry = merged[index], entry.span.start == origin.start {
                    return Fdx.numbered(entry.bytes, as: elements[index])
                }
                return Fdx.numbered(Fdx.rewritten(origin, as: elements[index], in: units), as: elements[index])
            }
            func freshBytes(_ element: ScreenplayElement) -> [UInt16] {
                let fresh = Fdx.writeXml(Screenplay(titlePage: [], elements: [element]))
                return Fdx.paragraphBody(of: fresh).map { Array($0.utf16) } ?? []
            }
            /* The paragraph each element was written into, as `written`
               counts: a note in front of an element is placed on that
               paragraph. */
            var paragraphOf = [Int](repeating: -1, count: elements.count)
            /* A scene omitted since the file was read (§7.3) is written the
               way Final Draft keeps one: its paragraphs inside the card's,
               in an <OmittedScene>. The body is written by the same loop as
               everything else — so each line keeps the bytes it had as a
               live paragraph — into a buffer of its own, which is closed
               into the card when the body ends. The card is one paragraph
               to a ScriptNote Range, so the body's paragraphs are not
               counted as written; a note on one of them lands on the card. */
            var nesting: (outer: [UInt16], close: [UInt16], lead: [UInt16], written: Int, card: Int)?
            func openNesting(card: Int, bytes: [UInt16]) {
                let close = Array("</Paragraph>".utf16)
                /* Only into a paragraph that ends as a paragraph does and
                   holds no block already; otherwise the body is written live,
                   where nothing is lost. */
                guard nesting == nil, bytes.count >= close.count, Array(bytes.suffix(close.count)) == close,
                      String(decoding: bytes, as: UTF16.self).range(of: "<OmittedScene") == nil
                else { return }
                out.removeLast(close.count)
                nesting = (out, close, lead, written.count, card)
                out = []
                wrote = false
            }
            func closeNesting(through end: Int) {
                guard let open = nesting else { return }
                nesting = nil
                let body = out
                let lineLead = open.lead.isEmpty ? Array("\n".utf16) : open.lead
                out = open.outer
                if !body.isEmpty {
                    out += Array("<OmittedScene>".utf16) + lineLead + body + lineLead + Array("</OmittedScene>".utf16)
                }
                out += open.close
                written.removeSubrange(open.written...)
                for k in (open.card + 1)..<max(open.card + 1, end) { paragraphOf[k] = open.written - 1 }
                wrote = true
            }
            var index = 0
            while index < elements.count {
                if nesting != nil, nestingRole[index] != .body { closeNesting(through: index) }
                // A line of a paragraph already written whole.
                if consumed.contains(index) {
                    paragraphOf[index] = written.count - 1
                    index += 1
                    continue
                }
                if let pair = pairs[index] {
                    let block = blocks[pair.block]
                    for start in block.lineStarts { absorbedBefore[start]?.forEach(restore) }
                    if wrote { out += block.lead.isEmpty ? lead : block.lead }
                    if !block.lead.isEmpty { lead = block.lead }
                    out += block.head
                    writtenFrom(block.start, .same)
                    var lineLead = block.lineLead
                    for line in index...pair.end {
                        let origin = paired[line]
                        if line > index {
                            if let origin, !origin.lead.isEmpty { out += origin.lead } else { out += lineLead }
                        }
                        if let origin, !origin.lead.isEmpty { lineLead = origin.lead }
                        if let origin {
                            out += keptBytes(line, origin)
                        } else {
                            // Inside Final Draft's block, a speaker is dual by where it stands.
                            var speech = elements[line]
                            speech.dual = nil
                            out += freshBytes(speech)
                        }
                    }
                    out += block.tail
                    for line in index...pair.end { paragraphOf[line] = written.count - 1 }
                    wrote = true
                    index = pair.end + 1
                    continue
                }
                let bytes: [UInt16]
                if let origin = paired[index] {
                    absorbedBefore[origin.start]?.forEach(restore)
                    let ownLead = origin.block.map { blocks[$0].lead } ?? origin.lead
                    if wrote { out += ownLead.isEmpty ? lead : ownLead }
                    if !ownLead.isEmpty { lead = ownLead }
                    bytes = keptBytes(index, origin)
                    out += bytes
                    if let block = origin.block {
                        // A dissolved dual dialogue: its place is its first line.
                        if dissolvedWritten.contains(block) {
                            written.append(WrittenParagraph(origin: nil, kind: .same))
                        } else {
                            writtenFrom(blocks[block].start, .firstLine)
                        }
                        dissolvedWritten.insert(block)
                    } else {
                        writtenFrom(origin.start, verbatim[index]?.start == origin.start ? .same : .text)
                    }
                } else {
                    if wrote { out += lead.isEmpty ? Array("\n".utf16) : lead }
                    bytes = freshBytes(elements[index])
                    out += bytes
                    written.append(WrittenParagraph(origin: nil, kind: .same))
                }
                paragraphOf[index] = written.count - 1
                wrote = true
                if nestingRole[index] == .card { openNesting(card: index, bytes: bytes) }
                index += 1
            }
            closeNesting(through: elements.count)
            waiting.forEach(restore)

            /* Each ScriptNote stays on its words (TypeScript reports the moves).
               Final Draft counts a Range over the script as it now stands, so a
               Range written for the old text points at other words after any
               edit that moves them. Only the Range values that move are
               rewritten.

               Then the writer's notes (RFC-NOTES-SYSTEM §4.2, stage 1). A note
               of eDraft's the writer left as it was, on the same line, keeps
               every byte but its Range. One whose note is gone — deleted, or
               changed, which stage 1 writes as a new note — is taken out. Every
               note left over is written as a new ScriptNote on the paragraph it
               sits in front of. Final Draft's own notes are never touched. */
            var prefix = Array(units[0..<firstStart])
            var suffix = Array(units[lastEnd...])
            let ownedCount = places.notes.filter { $0.owned != nil }.count
            if rangeValues.contains(where: { $0 != nil }) || !outOfBody.isEmpty || ownedCount > 0 {
                let after = Fdx.collectParagraphs(
                    from: String(decoding: prefix + out + suffix, as: UTF16.self),
                    limits: limits,
                    diagnostics: DiagnosticCollector(limit: 1)
                ).body
                let afterUnits = after.map(Fdx.rangeUnits)
                let matched = after.count == written.count
                let moved = matched
                    ? Fdx.movedScriptNoteRanges(
                        before: topLevelUnits, written: written, after: afterUnits, values: rangeValues
                    )
                    : (replacements: [], ranges: rangeValues.map { $0?.range })
                let lengths = afterUnits.map(\.count)
                var starts: [Int] = []
                var cursor = 0
                for length in lengths {
                    starts.append(cursor)
                    cursor += length + 1
                }
                func paragraphAt(_ position: Int) -> Int {
                    var found = -1
                    var index = 0
                    while index < starts.count && starts[index] <= position {
                        found = index
                        index += 1
                    }
                    return found
                }
                let lastParagraph = written.count - 1
                let placed: [(element: ScreenplayElement, at: Int)] = outOfBody.map { note in
                    (note.element, matched ? (note.before < paragraphOf.count ? paragraphOf[note.before] : lastParagraph) : -1)
                }

                // Stage 1 pairs eDraft's notes by their line and their words.
                var removed = Set<Int>()
                var pairedNote = Set<Int>()
                for (index, note) in places.notes.enumerated() {
                    guard let owned = note.owned else { continue }
                    let range = index < moved.ranges.count ? moved.ranges[index] : nil
                    // Where the import put it: the paragraph its Range starts in, or the end.
                    let at: Int? = !matched ? nil : range.map { paragraphAt($0.start) } ?? lastParagraph
                    let text = Fdx.ownedNoteText(owned)
                    let match = placed.indices.first { k in
                        !pairedNote.contains(k) && (at == nil || placed[k].at == at) && placed[k].element.text == text
                    }
                    if let match { pairedNote.insert(match) } else { removed.insert(index) }
                }

                var edits: [(start: Int, end: Int, value: [UInt16])] = []
                for replacement in moved.replacements where !removed.contains(replacement.note) {
                    edits.append((replacement.start, replacement.end, Array(replacement.value.utf16)))
                }
                for index in removed { edits.append((places.notes[index].start, places.notes[index].end, [])) }
                let fresh = placed.indices.filter { !pairedNote.contains($0) }.map { placed[$0] }
                if !fresh.isEmpty {
                    let writing = Fdx.resolvedNoteWriting(notes)
                    let names = (writing.writer.map { [$0] } ?? []) + places.notes.compactMap { $0.owned.flatMap(Fdx.ownedNoteAuthor) }
                    var id = places.notes.reduce(0) { highest, note in note.id.map { max(highest, $0) } ?? highest }
                    let diagnostics = DiagnosticCollector(limit: 1)
                    var lines: [(depth: Int, text: String)] = []
                    for note in fresh {
                        id += 1
                        let authorship = Fdx.noteAuthorship(note.element.text, names: names, writer: writing.writer)
                        lines += Fdx.scriptNoteLines(
                            id: id,
                            author: authorship.author,
                            message: authorship.message,
                            range: Fdx.noteRange(
                                Fdx.paragraphRange(lengths, at: note.at),
                                paragraph: note.at >= 0 && note.at < after.count
                                    ? (text: after[note.at].text, blocks: after[note.at].blocks)
                                    : nil,
                                anchor: note.element.anchor,
                                diagnostics: diagnostics
                            ),
                            writing: writing,
                            diagnostics: diagnostics
                        )
                    }
                    let indented = lines.map { "\n" + String(repeating: " ", count: 4 + 2 * $0.depth) + $0.text }.joined()
                    if let container = places.container, let close = container.close {
                        var lineStart = close - 1
                        while lineStart >= 0 && units[lineStart] != 10 { lineStart -= 1 }
                        let indentOnly = lineStart >= 0 && units[(lineStart + 1)..<close].allSatisfy { $0 == 32 || $0 == 9 }
                        let at = indentOnly ? lineStart : close
                        edits.append((at, at, Array(indented.utf16)))
                    } else if let container = places.container {
                        var tagEnd = container.open
                        while tagEnd < units.count && units[tagEnd] != 62 { tagEnd += 1 }
                        edits.append((container.open, min(tagEnd + 1, units.count), Array("<ScriptNotes>\(indented)\n  </ScriptNotes>".utf16)))
                    } else {
                        let at = places.afterCharacters ?? places.rootClose ?? units.count
                        edits.append((at, at, Array("\n\n  <ScriptNotes>\(indented)\n  </ScriptNotes>".utf16)))
                    }
                }
                func apply(_ text: [UInt16], base: Int, limit: Int) -> [UInt16] {
                    var result = text
                    let inside = edits
                        .filter { $0.start >= base && $0.end <= limit }
                        .sorted { $0.start != $1.start ? $0.start > $1.start : $0.end > $1.end }
                    for edit in inside {
                        result.replaceSubrange((edit.start - base)..<(edit.end - base), with: edit.value)
                    }
                    return result
                }
                prefix = apply(prefix, base: 0, limit: firstStart)
                suffix = apply(suffix, base: lastEnd, limit: units.count)
            }
            let whole = prefix + out + suffix
            return Fdx.ensureNamespaceDeclared(
                String(utf16CodeUnits: whole, count: whole.count)
            )
        }
    }

    /// How a paragraph is recognised across a round trip.
    ///
    /// Compared with the casing the app applies rather than the letters the
    /// file stores, because Final Draft stores what the writer typed and puts
    /// the capitals on in the *view* — `ElementSettings Type="Scene Heading"`
    /// carries `Style="Bold+AllCaps"`. Opening `Deeper in the woods -
    /// cONTINUOUS` therefore gives a screenplay that says DEEPER IN THE WOODS
    /// - CONTINUOUS, and comparing the letters would call every heading, cue
    /// and transition in the file an edit: measured on a real production
    /// draft, that rewrote them all, lost the writer's own casing, and dropped
    /// the twelve `<DualDialogue>` wrappers living between the paragraphs it
    /// replaced.
    ///
    /// So casing is not an edit. The file keeps what the writer typed; the app
    /// goes on showing capitals.
    fileprivate static func recognisedText(_ type: ElementKind, _ text: String) -> String {
        Normalize.canonicalCasing(kind: type, text: text)
    }

    /// Element kinds a Fountain round trip cannot carry.
    ///
    /// The document eDraft edits is Fountain, and Fountain has no `General`
    /// and no `Shot` — both arrive back as action. So a paragraph of either
    /// kind looks to a naive comparison as though the writer retyped it, and
    /// rewriting it as Action is a loss the writer never asked for. Measured
    /// on a real production draft: that alone dropped all twelve
    /// `<DualDialogue>` wrappers, which live in the whitespace between the
    /// paragraphs it replaced. The file's own type is authoritative for these;
    /// eDraft cannot prove it changed.
    fileprivate static let fountainFlattens: Set<ElementKind> = [.general, .shot]

    /// One paragraph as it sits in the original file.
    /// Where each omitted scene's body sits in the elements being saved
    /// (TypeScript `omittedRunsIn`).
    ///
    /// The file says which paragraphs are inside an <OmittedScene> and which
    /// Scene Heading holds them; this finds that run in the script being
    /// saved. Found by the body's own words, not by the card's: a round trip
    /// through Fountain gives a scene heading its canonical casing, so the
    /// card and the body's first line come back in different letters from
    /// the ones the file holds. Everything else comes back exactly, so the
    /// run is the window that matches most of them.
    fileprivate static func omittedRuns(
        in elements: [ScreenplayElement], spans: [Span]
    ) -> [OmittedRun] {
        var runs: [OmittedRun] = []
        /* Compared without casing: a round trip through Fountain gives a
           scene heading its canonical capitals, so the card and the body's
           first line come back in different letters from the file's. */
        let key = omissionKey
        var from = 0
        for span in spans {
            guard let body = span.omittedBody, !body.isEmpty else { continue }
            func score(at: Int) -> Int {
                var matched = 0
                for k in 0..<body.count where at + k < elements.count && elements[at + k].text == body[k] {
                    matched += 1
                }
                return matched
            }
            /* The card holds the body: its own paragraph is the one the
               block is nested in, so the run begins after it. */
            var best = -1
            var found = -1
            let cardKey = key(span.text)
            var at = from
            while at + body.count <= elements.count {
                if key(elements[at].text) == cardKey {
                    let matched = score(at: at + 1)
                    if matched > found {
                        found = matched
                        best = at + 1
                        if matched == body.count { break }
                    }
                }
                at += 1
            }
            /* A card with nothing of its body left under it is not evidence:
               the scene may have been edited, or deleted, and taking the
               elements that follow would swallow live paragraphs. At least
               one line must stand. */
            if found < 1 { best = -1 }
            /* No card to hang it on — its words were changed too. The body
               itself is then the only evidence, and must be unmistakable. */
            if best == -1 {
                let needed = max(1, Int((Double(body.count) * 0.6).rounded(.up)))
                found = -1
                var at = from
                while at + body.count <= elements.count {
                    let matched = score(at: at)
                    if matched >= needed && matched > found {
                        found = matched
                        best = at
                        if matched == body.count { break }
                    }
                    at += 1
                }
                if best == -1 { continue }
            }
            runs.append(OmittedRun(span: span.start, card: span.text, start: best, body: body))
            from = best + body.count
        }
        return runs
    }

    /// One of the file's omitted scenes, where it was found in a script:
    /// the card paragraph that holds it (by where that paragraph starts in
    /// the file, which is unique), the card's words, and the body's run.
    fileprivate struct OmittedRun {
        let span: Int
        let card: String
        let start: Int
        let body: [String]
    }

    /// A card's words as the search for one compares them.
    fileprivate static func omissionKey(_ text: String) -> String { text.jsTrimmed.uppercased() }

    /// How each element takes part in an omission this save writes for the
    /// first time: the card that will hold it, a line of its body, or
    /// neither.
    fileprivate enum NestingRole: Equatable { case none, card, body }

    /// What a save does with each omitted scene (TypeScript `omissionPlan`).
    ///
    /// `kept` are the file's own omitted scenes the script still omits —
    /// written back inside their cards as the file has them. `restored` are
    /// the file's own the script no longer omits, by card paragraph: their
    /// lines are written live, and the card goes. `roles` marks each
    /// omission the file did not have — its card and its body — so the
    /// write can nest the body inside the card.
    fileprivate static func omissionPlan(
        _ omissions: [Omission]?, runs: [OmittedRun], count: Int
    ) -> (kept: [OmittedRun], restored: Set<Int>, roles: [NestingRole]) {
        var roles = [NestingRole](repeating: .none, count: count)
        /* Nil is a caller that cannot say — the file's structure decides. */
        guard let omissions else { return (runs, [], roles) }
        /* Spans in order, each inside the script and after a card, none
           overlapping the one before it: anything else is not a span. */
        var spans: [Omission] = []
        for omission in omissions.sorted(by: { $0.start < $1.start })
        where omission.start > 0 && omission.start < omission.end && omission.end <= count {
            if let previous = spans.last, omission.start - 1 < previous.end { continue }
            spans.append(omission)
        }
        var kept: [OmittedRun] = []
        var restored = Set<Int>()
        var matched = Set<Int>()
        for run in runs {
            if let at = spans.firstIndex(where: { $0.start == run.start && $0.end == run.start + run.body.count }) {
                kept.append(run)
                matched.insert(at)
            } else {
                restored.insert(run.span)
            }
        }
        let keptBody = Set(kept.flatMap { run in run.start..<(run.start + run.body.count) })
        for (at, span) in spans.enumerated() where !matched.contains(at) {
            guard !keptBody.contains(span.start - 1),
                  !(span.start..<span.end).contains(where: keptBody.contains) else { continue }
            roles[span.start - 1] = .card
            for k in span.start..<span.end { roles[k] = .body }
        }
        return (kept, restored, roles)
    }

    fileprivate struct Span: Sendable {
        let type: ElementKind
        let text: String
        let start: Int
        let end: Int
        let textStart: Int
        let textEnd: Int
        /// The whitespace before it, kept so a save reproduces the file byte
        /// for byte rather than re-indenting every line of a 750KB document.
        let lead: [UInt16]
        /// The runs the file itself declared, in canonical form, for the
        /// content gate on a preserving save — a run changed without a
        /// character moving still rewrites the paragraph. Canonical because
        /// Final Draft splits runs the model merges ("HOME LIBRARY, " and
        /// "CASALINDA", one tag): compared raw, every such paragraph read as
        /// edited and lost its tags on a save that changed nothing.
        let runs: [StyleRun]
        /// Whether the import absorbed this paragraph — an End of Act — so
        /// that no element will ever stand for it. The rewrite writes these
        /// back itself and never lets the alignment see them.
        let absorbed: Bool
        /// For the Scene Heading that holds an <OmittedScene> (§7.3): the
        /// words of the paragraphs nested inside it, in order. The block's
        /// bytes belong to this paragraph, so a preserving save writes them
        /// back untouched and the body's elements take no part in the
        /// alignment (TypeScript `OriginParagraph.omittedBody`).
        var omittedBody: [String]?
        /// The same paragraphs as spans of their own, for a save in which the
        /// writer restored the scene: each is written back as a live
        /// paragraph from its own bytes.
        var omittedSpans: [Span]?
        /// The dual dialogue this paragraph is a line of: an index into the
        /// document's blocks.
        var block: Int? = nil
    }

    /// A Final Draft dual dialogue as the save sees it: the paragraph that
    /// holds the <DualDialogue>, as a frame around its lines (TypeScript
    /// `DualDialogueBlock`). Each line is a paragraph to the save like any
    /// other; the frame is written around the lines kept together, verbatim.
    fileprivate struct DualDialogueBlock: Sendable {
        /// The whitespace before the holding paragraph.
        let lead: [UInt16]
        let start: Int
        let end: Int
        /// The frame: its bytes up to the first line, and after the last line.
        let head: [UInt16]
        let tail: [UInt16]
        /// Where each line starts, and the whitespace before its second line.
        let lineStarts: [Int]
        let lineLead: [UInt16]
    }

    /// The kinds that belong to a speech after its cue.
    fileprivate static let speechTypes: Set<ElementKind> = [.dialogue, .parenthetical, .lyrics]

    /// Where a dual dialogue kept by a save ends — the element index of the
    /// second speaker's last line — or nil when the lines kept from it no
    /// longer form a dual pair there (TypeScript `dualPairEnd`).
    ///
    /// A dual pair is what Fountain reads as one: a cue, its speech, the cue
    /// marked dual, its speech. It must open on the first line kept from the
    /// block, hold every line kept from it, and hold nothing another paragraph
    /// of the file became — only the block's own lines and lines the writer
    /// added.
    fileprivate static func dualPairEnd(
        _ elements: [ScreenplayElement], _ paired: [Span?], _ consumed: Set<Int>, block: Int, kept: [Int]
    ) -> Int? {
        guard let start = kept.first, let lastKept = kept.last else { return nil }
        var at = start
        guard at < elements.count, elements[at].type == .character, elements[at].dual != true else { return nil }
        at += 1
        while at < elements.count, speechTypes.contains(elements[at].type) { at += 1 }
        guard at < elements.count, elements[at].type == .character, elements[at].dual == true else { return nil }
        at += 1
        while at < elements.count, speechTypes.contains(elements[at].type) { at += 1 }
        let end = at - 1
        guard lastKept <= end else { return nil }
        for index in start...end {
            if consumed.contains(index) { return nil }
            if let origin = paired[index], origin.block != block { return nil }
        }
        return end
    }

    // MARK: - ScriptNote Ranges through a save

    /// A paragraph of a written script, as a Range counts it, and what it came
    /// from: the original top-level paragraph, and how its units relate — its
    /// own bytes, text that changed, or the first line of a dissolved dual
    /// dialogue. `nil` for a paragraph the writer added (TypeScript
    /// `WrittenParagraph`).
    fileprivate struct WrittenParagraph {
        enum Kind { case same, text, firstLine }
        let origin: Int?
        let kind: Kind
    }

    /// A paragraph's units as a Range counts them: its text, with two for each
    /// embedded block where it sits (-1, which no text unit equals)
    /// (TypeScript `rangeUnitsOf`).
    private static func rangeUnits(_ paragraph: CollectedParagraph) -> [Int32] {
        let text = Array(paragraph.text.utf16)
        var units: [Int32] = []
        units.reserveCapacity(text.count + blockUnits * paragraph.blocks.count)
        var block = 0
        for unit in 0...text.count {
            while block < paragraph.blocks.count, paragraph.blocks[block] == unit {
                units += [Int32](repeating: -1, count: blockUnits)
                block += 1
            }
            if unit < text.count { units.append(Int32(text[unit])) }
        }
        return units
    }

    /// For each old unit, the new unit it is — or -1: the common prefix and
    /// suffix, and a longest common subsequence between them when small enough
    /// (TypeScript `unitCorrespondence`).
    fileprivate static func unitCorrespondence(_ before: [Int32], _ after: [Int32]) -> [Int] {
        var pairs = [Int](repeating: -1, count: before.count)
        var head = 0
        while head < before.count, head < after.count, before[head] == after[head] {
            pairs[head] = head
            head += 1
        }
        var tail = 0
        while tail < before.count - head, tail < after.count - head,
              before[before.count - 1 - tail] == after[after.count - 1 - tail] {
            pairs[before.count - 1 - tail] = after.count - 1 - tail
            tail += 1
        }
        if let middle = alignedUnits(
            Array(before[head..<(before.count - tail)]), Array(after[head..<(after.count - tail)])
        ) {
            for (r, n) in middle.enumerated() where n >= 0 { pairs[head + r] = head + n }
        }
        return pairs
    }

    /// The Range values a save must rewrite so each note stays on its words
    /// (TypeScript `movedScriptNoteRanges`).
    ///
    /// Each end of a Range stays with its character: a start before the first
    /// character of the note that survives, an end after the last. Text typed
    /// inside a note joins it; text typed at its edges does not. A note whose
    /// words are all gone closes to zero length where they stood. A Range
    /// already past the script's end when the file was read keeps its bytes,
    /// as does every Range that does not move.
    fileprivate static func movedScriptNoteRanges(
        before: [[Int32]], written: [WrittenParagraph], after: [[Int32]], values: [ScriptNoteRangeValue?]
    ) -> (replacements: [(start: Int, end: Int, value: String, note: Int)], ranges: [ScriptNote.Range?]) {
        func layout(_ paragraphs: [[Int32]]) -> (starts: [Int], lengths: [Int], end: Int) {
            var starts: [Int] = []
            var lengths: [Int] = []
            var cursor = 0
            for paragraph in paragraphs {
                starts.append(cursor)
                lengths.append(paragraph.count)
                cursor += paragraph.count + 1
            }
            return (starts, lengths, cursor - 1)
        }
        let old = layout(before)
        let now = layout(after)
        var writtenAt: [Int: Int] = [:]
        for (at, paragraph) in written.enumerated() {
            if let origin = paragraph.origin, writtenAt[origin] == nil { writtenAt[origin] = at }
        }
        var correspondences: [Int: [Int]] = [:]

        func boundary(_ position: Int, start side: Bool) -> Int {
            var low = 0
            var high = before.count - 1
            while low < high {
                let middle = (low + high + 1) >> 1
                if old.starts[middle] <= position { low = middle } else { high = middle - 1 }
            }
            guard let at = writtenAt[low] else {
                // Gone: where it stood — the start of what follows the last paragraph kept before it.
                var previous = -1
                for (index, paragraph) in written.enumerated() {
                    if let origin = paragraph.origin, origin < low { previous = index }
                }
                return previous == -1 ? 0 : min(now.starts[previous] + now.lengths[previous] + 1, now.end)
            }
            let offset = position - old.starts[low]
            switch written[at].kind {
            case .firstLine:
                return now.starts[at]
            case .same:
                return now.starts[at] + min(offset, now.lengths[at])
            case .text:
                let pairs = correspondences[low] ?? unitCorrespondence(before[low], after[at])
                correspondences[low] = pairs
                if side {
                    var unit = offset
                    while unit < pairs.count {
                        if pairs[unit] >= 0 { return now.starts[at] + pairs[unit] }
                        unit += 1
                    }
                    return now.starts[at] + now.lengths[at]
                }
                var unit = min(offset, pairs.count) - 1
                while unit >= 0 {
                    if pairs[unit] >= 0 { return now.starts[at] + pairs[unit] + 1 }
                    unit -= 1
                }
                return now.starts[at]
            }
        }

        var replacements: [(start: Int, end: Int, value: String, note: Int)] = []
        var ranges: [ScriptNote.Range?] = values.map { $0?.range }
        guard !before.isEmpty, !after.isEmpty else { return (replacements, ranges) }
        for (note, value) in values.enumerated() {
            guard let value, value.range.end <= old.end else { continue }
            let start = value.range.start
            let end = value.range.end
            var movedStart = boundary(start, start: true)
            var movedEnd = start == end ? movedStart : boundary(end, start: false)
            if start < end && movedEnd <= movedStart {
                movedStart = min(movedStart, movedEnd)
                movedEnd = movedStart
            }
            if movedStart == start && movedEnd == end { continue }
            ranges[note] = ScriptNote.Range(start: movedStart, end: movedEnd)
            replacements.append((
                value.valueStart, value.valueEnd,
                value.reversed ? "\(movedEnd),\(movedStart)" : "\(movedStart),\(movedEnd)",
                note
            ))
        }
        return (replacements, ranges)
    }

    /// Opens a Final Draft file and keeps it, so it can be written back whole.
    ///
    /// The screenplay is exactly `parse`'s. Use this whenever the file may be
    /// saved again; `parse` remains right for reading a script that will never
    /// be written back.
    public static func open(_ xml: String, options: ImportOptions = ImportOptions()) -> Document {
        let imported = parse(xml, options: options)
        let limits = limits(of: options)
        let collected = collectParagraphs(
            from: xml, limits: limits, diagnostics: DiagnosticCollector(limit: 1)
        )
        let units = Array(xml.utf16)

        func span(of paragraph: CollectedParagraph, lead: [UInt16]) -> Span {
            Span(
                type: elementKind(of: paragraph),
                text: paragraph.text,
                start: paragraph.start,
                end: paragraph.end,
                textStart: paragraph.textStart,
                textEnd: paragraph.textEnd,
                lead: lead,
                runs: Emphasis.normalise(paragraph.runs, textLength: paragraph.text.utf16.count),
                absorbed: (paragraph.attribute("type") ?? "").jsTrimmed.lowercased() == "end of act"
            )
        }
        var spans: [Span] = []
        var blocks: [DualDialogueBlock] = []
        var previousEnd = -1
        for paragraph in collected.body {
            let lead: [UInt16] = previousEnd == -1
                ? []
                : Array(units[previousEnd..<max(previousEnd, paragraph.start)])
            previousEnd = paragraph.end
            let endOfAct = (paragraph.attribute("type") ?? "").jsTrimmed.lowercased() == "end of act"
            guard !endOfAct, !paragraph.dialogues.isEmpty,
                  let lines = dualDialogue(of: paragraph, in: units, limits: limits) else {
                var only = span(of: paragraph, lead: lead)
                /* An omitted scene's paragraphs live inside this one, so this
                   paragraph's bytes already carry them: the save writes it
                   whole and the body is preserved exactly (§7.3, "Preserved
                   on splice"). Recorded so the alignment can leave those
                   elements out — they have no paragraph of their own. */
                if !endOfAct, !paragraph.omissions.isEmpty,
                   let omitted = omittedScene(of: paragraph, in: units, limits: limits) {
                    /* Element by element, as the import reads them — a dual
                       dialogue is its lines, framed by its block — so a
                       restored scene's lines pair with the bytes they were.
                       Led like the card they come out of: a restored line
                       stands at the Content's own indent, not the block's. */
                    var held: [Span] = []
                    for line in omitted {
                        guard !line.dialogues.isEmpty,
                              let lines = dualDialogue(of: line, in: units, limits: limits) else {
                            held.append(span(of: line, lead: lead))
                            continue
                        }
                        let index = blocks.count
                        blocks.append(DualDialogueBlock(
                            lead: lead,
                            start: line.start,
                            end: line.end,
                            head: Array(units[line.start..<lines[0].start]),
                            tail: Array(units[lines[lines.count - 1].end..<line.end]),
                            lineStarts: lines.map(\.start),
                            lineLead: lines.count > 1 ? Array(units[lines[0].end..<lines[1].start]) : lead
                        ))
                        for (at, inner) in lines.enumerated() {
                            var lineSpan = span(of: inner, lead: at == 0 ? [] : Array(units[lines[at - 1].end..<inner.start]))
                            lineSpan.block = index
                            held.append(lineSpan)
                        }
                    }
                    only.omittedBody = held.map(\.text)
                    only.omittedSpans = held
                }
                spans.append(only)
                continue
            }
            let index = blocks.count
            blocks.append(DualDialogueBlock(
                lead: lead,
                start: paragraph.start,
                end: paragraph.end,
                head: Array(units[paragraph.start..<lines[0].start]),
                tail: Array(units[lines[lines.count - 1].end..<paragraph.end]),
                lineStarts: lines.map(\.start),
                lineLead: lines.count > 1 ? Array(units[lines[0].end..<lines[1].start]) : lead
            ))
            for (at, line) in lines.enumerated() {
                var lineSpan = span(of: line, lead: at == 0 ? [] : Array(units[lines[at - 1].end..<line.start]))
                lineSpan.block = index
                spans.append(lineSpan)
            }
        }

        var topLevelAt: [Int: Int] = [:]
        for (index, paragraph) in collected.body.enumerated() { topLevelAt[paragraph.start] = index }
        let noteScan = scriptNoteRangeValues(in: xml, limits: limits)
        return Document(
            script: imported.script,
            warnings: imported.warnings,
            diagnostics: imported.diagnostics,
            units: units,
            spans: spans,
            blocks: blocks,
            topLevelUnits: collected.body.map(rangeUnits),
            topLevelAt: topLevelAt,
            rangeValues: noteScan.values,
            places: noteScan.places,
            limits: limits
        )
    }

    // MARK: - Unedited paragraphs

    /// How far ahead the correspondence looks to find its footing again.
    private static let correspondenceReach = 16

    /// A paragraph's words as the correspondence compares them, in UTF-16
    /// units (TypeScript `wordsKey`): casing and the whitespace at either end
    /// are not what makes two paragraphs different.
    private static func wordsKey(_ text: String) -> [UInt16] {
        Array(text.uppercased().jsTrimmed.utf16)
    }

    /// Which elements of the unedited reading each file paragraph became
    /// (TypeScript `correspondence`).
    ///
    /// The reading may carry a paragraph differently from the file — Fountain
    /// reads an emphasised heading as Action, trims a trailing space, and
    /// splits a paragraph at its line breaks — so this pairs by words, never by
    /// element: one paragraph to one element when their words agree; to the
    /// run of consecutive elements its lines became when those agree; and,
    /// where the words disagree for as many paragraphs as elements before both
    /// sides agree again, by position. A region that cannot be paired stays
    /// unpaired and is judged against the file as before.
    fileprivate static func correspondence(
        _ spans: [Span], _ reading: [ScreenplayElement]
    ) -> [Range<Int>?] {
        var ranges = [Range<Int>?](repeating: nil, count: spans.count)
        let file = spans.map { wordsKey($0.text) }
        let read = reading.map { wordsKey($0.text) }
        var i = 0
        var k = 0
        while i < spans.count && k < reading.count {
            if file[i] == read[k] {
                ranges[i] = k..<(k + 1)
                i += 1
                k += 1
                continue
            }
            let lines = spans[i].text.components(separatedBy: "\n").count
            if lines > 1, k + lines <= reading.count,
               wordsKey(reading[k..<(k + lines)].map(\.text).joined(separator: "\n")) == file[i] {
                ranges[i] = k..<(k + lines)
                i += 1
                k += lines
                continue
            }
            // Find footing again: the nearest place both sides agree, nearest first.
            var found: (Int, Int)?
            reaching: for reach in 1...correspondenceReach {
                for skipped in 0...reach {
                    let di = skipped
                    let dk = reach - skipped
                    if i + di < spans.count, k + dk < reading.count, file[i + di] == read[k + dk] {
                        found = (di, dk)
                        break reaching
                    }
                }
            }
            guard let (di, dk) = found else { break }
            if di == dk {
                for step in 0..<di { ranges[i + step] = (k + step)..<(k + step + 1) }
            }
            i += di
            k += dk
        }
        return ranges
    }

    /// Whether two elements are the same element, property for property,
    /// text compared in UTF-16 units (TypeScript `sameElement`).
    private static func sameElement(_ a: ScreenplayElement, _ b: ScreenplayElement) -> Bool {
        a.type == b.type
            && a.text.utf16.elementsEqual(b.text.utf16)
            && (a.dual ?? false) == (b.dual ?? false)
            && Array((a.sceneNumber ?? "").utf16) == Array((b.sceneNumber ?? "").utf16)
            && (a.depth ?? 0) == (b.depth ?? 0)
            && runsEqual(
                Emphasis.normalise(a.runs ?? [], textLength: a.text.utf16.count),
                Emphasis.normalise(b.runs ?? [], textLength: b.text.utf16.count)
            )
    }

    /// For each element being saved, the element of the unedited reading it
    /// still is, unchanged — or nil (TypeScript `unchangedFrom`).
    ///
    /// A longest common subsequence over whole elements, run only between the
    /// common prefix and suffix, which is where an edit actually is. Past four
    /// million cells the middle pairs by position: still exact for an unedited
    /// script and for an edit in place.
    fileprivate static func unchangedFrom(
        _ saved: [ScreenplayElement], _ reading: [ScreenplayElement]
    ) -> [Int?] {
        var matched = [Int?](repeating: nil, count: saved.count)
        var head = 0
        while head < saved.count, head < reading.count, sameElement(saved[head], reading[head]) {
            matched[head] = head
            head += 1
        }
        var tail = 0
        while tail < saved.count - head, tail < reading.count - head,
              sameElement(saved[saved.count - 1 - tail], reading[reading.count - 1 - tail]) {
            matched[saved.count - 1 - tail] = reading.count - 1 - tail
            tail += 1
        }
        let n = saved.count - head - tail
        let m = reading.count - head - tail
        guard n > 0, m > 0 else { return matched }

        guard n * m <= 4_000_000 else {
            for d in 0..<min(n, m) where sameElement(saved[head + d], reading[head + d]) {
                matched[head + d] = head + d
            }
            return matched
        }

        var table = [Int32](repeating: 0, count: (n + 1) * (m + 1))
        func at(_ i: Int, _ j: Int) -> Int { i * (m + 1) + j }
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[at(i, j)] = sameElement(saved[head + i], reading[head + j])
                    ? table[at(i + 1, j + 1)] + 1
                    : max(table[at(i + 1, j)], table[at(i, j + 1)])
            }
        }
        var i = 0
        var j = 0
        while i < n && j < m {
            if sameElement(saved[head + i], reading[head + j]) {
                matched[head + i] = head + j
                i += 1
                j += 1
            } else if table[at(i + 1, j)] >= table[at(i, j + 1)] {
                i += 1
            } else {
                j += 1
            }
        }
        return matched
    }

    // MARK: - Edited paragraphs

    /// The emphasis a Fountain reading carries — bold, italic, underline and
    /// strikeout, the low four bits of `StyleSet`. Everything else on a run is
    /// the file's, and only the file's.
    private static let carriedTokens = ["Bold", "Italic", "Underline", "Strikeout"]
    private static let carriedMask = 0b1111
    private static let styleTokenOrder = ["Bold", "Italic", "Underline", "Strikeout", "AllCaps", "HiddenText"]

    /// Past this many cells an alignment of two texts is not attempted.
    private static let alignmentCells = 4_000_000

    /// One direct-child <Text> run of a file paragraph: its bytes and its words
    /// (TypeScript `FileRun`).
    private struct FileRun {
        /// Where the whitespace before it starts.
        let lead: Int
        let start: Int
        let end: Int
        /// The opening tag's attributes, in the file's order, values verbatim.
        let attributes: [(name: String, value: String)]
        let text: [UInt16]
    }

    /// A tag's attributes, strictly `name="value"` separated by whitespace — or
    /// nil (TypeScript `strictAttributes`).
    private static func strictAttributes(_ raw: ArraySlice<UInt16>) -> [(name: String, value: String)]? {
        let equals = UInt16(UInt8(ascii: "="))
        let quote = UInt16(UInt8(ascii: "\""))
        var attributes: [(name: String, value: String)] = []
        var cursor = raw.startIndex
        while cursor < raw.endIndex {
            let at = cursor
            while cursor < raw.endIndex, JSWhitespace.matches(unit: raw[cursor]) { cursor += 1 }
            if cursor >= raw.endIndex { break }
            if cursor == at { return nil }
            let nameStart = cursor
            while cursor < raw.endIndex, raw[cursor] != equals, !JSWhitespace.matches(unit: raw[cursor]) { cursor += 1 }
            guard cursor != nameStart, cursor + 1 < raw.endIndex,
                  raw[cursor] == equals, raw[cursor + 1] == quote else { return nil }
            let valueStart = cursor + 2
            guard let valueEnd = raw[valueStart...].firstIndex(of: quote) else { return nil }
            attributes.append((
                String(decoding: raw[nameStart..<cursor], as: UTF16.self),
                String(decoding: raw[valueStart..<valueEnd], as: UTF16.self)
            ))
            cursor = valueEnd + 1
        }
        return attributes
    }

    /// A paragraph's own runs, or nil when its text region holds anything but
    /// plain `<Text>` runs and the whitespace between them — then nothing is
    /// safe to merge into (TypeScript `fileRunsOf`).
    private static func fileRuns(of origin: Span, in source: [UInt16]) -> [FileRun]? {
        guard origin.textStart >= 0, origin.textEnd > origin.textStart else { return nil }
        let open = Array("<Text".utf16)
        let close = Array("</Text>".utf16)
        let greater = UInt16(UInt8(ascii: ">"))
        let slash = UInt16(UInt8(ascii: "/"))
        let less = UInt16(UInt8(ascii: "<"))
        var runs: [FileRun] = []
        var cursor = origin.textStart
        while cursor < origin.textEnd {
            let lead = cursor
            while cursor < origin.textEnd, JSWhitespace.matches(unit: source[cursor]) { cursor += 1 }
            if cursor >= origin.textEnd { break }
            guard source[cursor...].starts(with: open),
                  let tagEnd = source[cursor..<origin.textEnd].firstIndex(of: greater) else { return nil }
            var raw = source[(cursor + open.count)..<tagEnd]
            let selfClosing = raw.last == slash
            if selfClosing { raw = raw.dropLast() }
            if let first = raw.first, !JSWhitespace.matches(unit: first) { return nil }
            guard let attributes = strictAttributes(raw) else { return nil }
            if selfClosing {
                runs.append(FileRun(lead: lead, start: cursor, end: tagEnd + 1, attributes: attributes, text: []))
                cursor = tagEnd + 1
                continue
            }
            var endTag = tagEnd + 1
            while endTag + close.count <= origin.textEnd, !source[endTag..<(endTag + close.count)].elementsEqual(close) {
                endTag += 1
            }
            guard endTag + close.count <= origin.textEnd else { return nil }
            let content = source[(tagEnd + 1)..<endTag]
            if content.contains(less) { return nil }
            runs.append(FileRun(
                lead: lead, start: cursor, end: endTag + close.count, attributes: attributes,
                text: Array(decodeXmlEntities(String(decoding: content, as: UTF16.self)).utf16)
            ))
            cursor = endTag + close.count
        }
        return runs
    }

    /// A text's UTF-16 units as numbers that are equal exactly when the units
    /// are the same letter, casing aside — a surrogate only ever equal to
    /// itself. `spelled` numbers the uppercase forms longer than one unit,
    /// across texts (TypeScript `letterKeys`).
    private static func letterKeys(_ text: [UInt16], _ spelled: inout [[UInt16]: Int32]) -> [Int32] {
        var keys: [Int32] = []
        keys.reserveCapacity(text.count)
        for unit in text {
            if (0xD800...0xDFFF).contains(unit) {
                keys.append(0x20000 + Int32(unit))
                continue
            }
            let upper = Array(String(utf16CodeUnits: [unit], count: 1).uppercased().utf16)
            if upper.count == 1 {
                keys.append(Int32(upper[0]))
                continue
            }
            if let key = spelled[upper] {
                keys.append(key)
            } else {
                let key = 0x30000 + Int32(spelled.count)
                spelled[upper] = key
                keys.append(key)
            }
        }
        return keys
    }

    /// For each unit of `a`, the unit of `b` a longest common subsequence pairs
    /// it with, or -1 — nil when the alignment would be too large to attempt
    /// (TypeScript `alignedUnits`).
    private static func alignedUnits(_ a: [Int32], _ b: [Int32]) -> [Int]? {
        let n = a.count
        let m = b.count
        var pairs = [Int](repeating: -1, count: n)
        if n == 0 || m == 0 { return pairs }
        if n * m > alignmentCells { return nil }
        var table = [Int32](repeating: 0, count: (n + 1) * (m + 1))
        func at(_ i: Int, _ j: Int) -> Int { i * (m + 1) + j }
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[at(i, j)] = a[i] == b[j]
                    ? table[at(i + 1, j + 1)] + 1
                    : max(table[at(i + 1, j)], table[at(i, j + 1)])
            }
        }
        var i = 0
        var j = 0
        while i < n && j < m {
            if a[i] == b[j] {
                pairs[i] = j
                i += 1
                j += 1
            } else if table[at(i + 1, j)] >= table[at(i, j + 1)] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }

    /// A stretch of the unedited reading and the edited text that do not
    /// correspond (TypeScript `Hunk`).
    private struct Hunk {
        var readStart: Int
        var readEnd: Int
        var nowStart: Int
        var nowEnd: Int
        var size: Int { (readEnd - readStart) + (nowEnd - nowStart) }
    }

    /// The hunks an alignment of reading to edited text leaves (TypeScript
    /// `changeHunks`). A line retyped shares a space or a letter here and there
    /// with what it replaced; those are coincidences, not text the writer kept,
    /// so an unchanged stretch no longer than the changes on both sides of it
    /// is folded into them.
    private static func changeHunks(_ readToNow: [Int], readLength: Int, nowLength: Int) -> [Hunk] {
        var hunks: [Hunk] = []
        func push(_ hunk: Hunk) {
            var current = hunk
            while let last = hunks.last {
                let kept = current.readStart - last.readEnd
                if kept > last.size || kept > current.size { break }
                hunks.removeLast()
                current = Hunk(readStart: last.readStart, readEnd: current.readEnd,
                               nowStart: last.nowStart, nowEnd: current.nowEnd)
            }
            hunks.append(current)
        }
        var lastRead = -1
        var lastNow = -1
        func close(_ readNext: Int, _ nowNext: Int) {
            if readNext - lastRead > 1 || nowNext - lastNow > 1 {
                push(Hunk(readStart: lastRead + 1, readEnd: readNext, nowStart: lastNow + 1, nowEnd: nowNext))
            }
        }
        for (r, n) in readToNow.enumerated() where n >= 0 {
            close(r, n)
            lastRead = r
            lastNow = n
        }
        close(readLength, nowLength)
        return hunks
    }

    /// The carried emphasis a run's Style attribute holds (TypeScript `carriedOf`).
    private static func carriedBits(of style: String?) -> Int {
        let tokens = (style ?? "").components(separatedBy: "+").map(\.jsTrimmed)
        var bits = 0
        for (bit, token) in carriedTokens.enumerated() where tokens.contains(token) { bits |= 1 << bit }
        return bits
    }

    /// A run's attributes with its Style made of the file's own tokens and the
    /// given carried emphasis (TypeScript `attributesWith`).
    private static func attributes(
        _ attributes: [(name: String, value: String)], carrying carried: Int, droppingRevision: Bool
    ) -> [(name: String, value: String)] {
        var tokens: [String] = []
        let own = attributes.first { $0.name == "Style" }?.value ?? ""
        for token in own.components(separatedBy: "+").map(\.jsTrimmed)
        where !token.isEmpty && !tokens.contains(token) {
            tokens.append(token)
        }
        for (bit, token) in carriedTokens.enumerated() {
            if carried & (1 << bit) != 0 {
                if !tokens.contains(token) { tokens.append(token) }
            } else {
                tokens.removeAll { $0 == token }
            }
        }
        let style = (styleTokenOrder.filter { tokens.contains($0) } + tokens.filter { !styleTokenOrder.contains($0) })
            .joined(separator: "+")
        var out = attributes.filter { !(droppingRevision && $0.name == "RevisionID") }
        if let index = out.firstIndex(where: { $0.name == "Style" }) {
            if style.isEmpty { out.remove(at: index) } else { out[index].value = style }
        } else if !style.isEmpty {
            let before = out.firstIndex { "Style".utf16.lexicographicallyPrecedes($0.name.utf16) } ?? out.count
            out.insert((name: "Style", value: style), at: before)
        }
        return out
    }

    /// The writer's change to one paragraph, written in the file's own terms —
    /// or nil when it cannot be placed without guessing (TypeScript
    /// `mergedParagraph`).
    ///
    /// The change is what separates the unedited reading from the edited
    /// elements; the reading is aligned with the file's own text, casing aside,
    /// so what the reading added (Fountain's `#2#`, a leading `.`) and dropped
    /// (a trailing space, the file's casing, a run split) is known and never
    /// written. Replaced characters are the file characters matched to the
    /// replaced reading characters; a pure insertion deletes nothing only the
    /// file has, and sits beside characters the file has. Every run the change
    /// does not touch is written as its bytes; a run it touches keeps its
    /// opening tag's attributes, with the writer's emphasis applied. Inserted
    /// text takes the attributes of the run it is typed into — or the run
    /// before, at a boundary — except its RevisionID: a revision mark is the
    /// file's record of when text changed. The file's Type stands unless the
    /// writer changed the element's kind.
    fileprivate static func mergedParagraph(
        _ origin: Span, unedited: [ScreenplayElement], edited: [ScreenplayElement], in source: [UInt16]
    ) -> [UInt16]? {
        guard unedited.count == edited.count, !unedited.isEmpty else { return nil }
        for (read, now) in zip(unedited, edited) {
            // A dual dialogue line's `dual` is its block's, not its paragraph's.
            if origin.block == nil, (read.dual ?? false) != (now.dual ?? false) { return nil }
            /* A scene number is an attribute, not the paragraph's words: a
               change to it is written onto the opening tag afterwards
               (`numbered`), and the runs — tags, revisions — stay. */
            if unedited.count > 1, !(read.sceneNumber ?? "").utf16.elementsEqual((now.sceneNumber ?? "").utf16) { return nil }
            if (read.depth ?? 0) != (now.depth ?? 0) { return nil }
            if unedited.count > 1 && read.type != now.type { return nil }
        }
        guard let runs = fileRuns(of: origin, in: source), !runs.isEmpty else { return nil }

        // The elements' lines joined as the paragraph holds them, with each unit's carried emphasis.
        func joined(_ elements: [ScreenplayElement]) -> (text: [UInt16], carried: [Int]) {
            var text: [UInt16] = []
            var carried: [Int] = []
            for (at, element) in elements.enumerated() {
                if at > 0 {
                    text.append(0x0A)
                    carried.append(0)
                }
                let units = Array(element.text.utf16)
                var bits = [Int](repeating: 0, count: units.count)
                for run in Emphasis.normalise(element.runs ?? [], textLength: units.count) where run.start < run.end {
                    for unit in run.start..<run.end { bits[unit] = run.styles.rawValue & carriedMask }
                }
                text += units
                carried += bits
            }
            return (text, carried)
        }
        let read = joined(unedited)
        let now = joined(edited)
        let fileText = runs.flatMap(\.text)

        var spelled: [[UInt16]: Int32] = [:]
        let readKeys = letterKeys(read.text, &spelled)
        let fileKeys = letterKeys(fileText, &spelled)
        guard let readToFile = alignedUnits(readKeys, fileKeys) else { return nil }

        // The writer's change: of the two smallest alignments, the one that changes less.
        let readUnits = read.text.map { Int32($0) }
        let nowUnits = now.text.map { Int32($0) }
        guard let forward = alignedUnits(readUnits, nowUnits),
              let mirrored = alignedUnits(readUnits.reversed(), nowUnits.reversed()) else { return nil }
        var backward = [Int](repeating: -1, count: read.text.count)
        for (r, n) in mirrored.enumerated() where n >= 0 {
            backward[read.text.count - 1 - r] = now.text.count - 1 - n
        }
        let forwardHunks = changeHunks(forward, readLength: read.text.count, nowLength: now.text.count)
        let backwardHunks = changeHunks(backward, readLength: read.text.count, nowLength: now.text.count)
        let useBackward = backwardHunks.reduce(0) { $0 + $1.size } < forwardHunks.reduce(0) { $0 + $1.size }
        let readToNow = useBackward ? backward : forward
        let hunks = useBackward ? backwardHunks : forwardHunks

        // Where each hunk lands in the file's text.
        var placed: [(fileStart: Int, fileEnd: Int, nowStart: Int, nowEnd: Int)] = []
        for (h, hunk) in hunks.enumerated() {
            if hunk.readEnd > hunk.readStart {
                for r in hunk.readStart..<hunk.readEnd where readToFile[r] < 0 { return nil }
                placed.append((readToFile[hunk.readStart], readToFile[hunk.readEnd - 1] + 1, hunk.nowStart, hunk.nowEnd))
                continue
            }
            // A pure insertion may slide over equal characters; it goes where the file has neighbours.
            let floor = h > 0 ? hunks[h - 1].readEnd : 0
            let ceiling = h + 1 < hunks.count ? hunks[h + 1].readStart : read.text.count
            let inserted = Array(now.text[hunk.nowStart..<hunk.nowEnd])
            var candidates = [hunk.readStart]
            var text = inserted
            var position = hunk.readStart
            while position > floor, read.text[position - 1] == text[text.count - 1] {
                text = [read.text[position - 1]] + text.dropLast()
                position -= 1
                candidates.append(position)
            }
            text = inserted
            position = hunk.readStart
            while position < ceiling, read.text[position] == text[0] {
                text = Array(text.dropFirst()) + [read.text[position]]
                position += 1
                candidates.append(position)
            }
            let readLength = read.text.count
            let leftHas = { (p: Int) in p > 0 && readToFile[p - 1] >= 0 }
            let rightHas = { (p: Int) in p < readLength && readToFile[p] >= 0 }
            guard let chosen = candidates.first(where: { ($0 == 0 || leftHas($0)) && ($0 == readLength || rightHas($0)) })
                ?? candidates.first(where: leftHas)
                ?? candidates.first(where: { $0 == 0 && rightHas(0) })
            else { return nil }
            let fileAt = chosen > 0 ? readToFile[chosen - 1] + 1 : 0
            // The inserted text is the edited text at the chosen position.
            let shift = chosen - hunk.readStart
            placed.append((fileAt, fileAt, hunk.nowStart + shift, hunk.nowEnd + shift))
        }
        for p in placed.indices.dropFirst() {
            if placed[p].fileStart < placed[p - 1].fileEnd { return nil }
            if placed[p].fileStart == placed[p - 1].fileEnd, placed[p].fileStart == placed[p].fileEnd,
               placed[p - 1].fileStart == placed[p - 1].fileEnd { return nil }
        }

        // The emphasis the writer changed on characters they did not retype.
        var fileToRead = [Int](repeating: -1, count: fileText.count)
        for (r, f) in readToFile.enumerated() where f >= 0 { fileToRead[f] = r }

        // The merged paragraph, unit by unit: which run each unit comes from and its carried emphasis.
        struct Unit {
            var unit: UInt16
            var run: Int
            var original: Bool
            var carried: Int
        }
        var runOfFileUnit = [Int](repeating: 0, count: fileText.count)
        var offset = 0
        for (r, run) in runs.enumerated() {
            for u in 0..<run.text.count { runOfFileUnit[offset + u] = r }
            offset += run.text.count
        }
        let ownCarried = runs.map { run in carriedBits(of: run.attributes.first { $0.name == "Style" }?.value) }
        var units: [Unit] = []
        var next = 0
        func keepFileUnits(until: Int) {
            while next < until {
                let r = fileToRead[next]
                var carried = ownCarried[runOfFileUnit[next]]
                if r >= 0, readToNow[r] >= 0, read.carried[r] != now.carried[readToNow[r]] {
                    carried = now.carried[readToNow[r]]
                }
                units.append(Unit(unit: fileText[next], run: runOfFileUnit[next], original: true, carried: carried))
                next += 1
            }
        }
        for edit in placed {
            keepFileUnits(until: edit.fileStart)
            /* Replaced characters take the run they replace; typed characters
               continue the run before them — the first run, at the very start. */
            let donor = edit.fileEnd > edit.fileStart
                ? runOfFileUnit[edit.fileStart]
                : edit.fileStart > 0 ? runOfFileUnit[edit.fileStart - 1] : fileText.isEmpty ? 0 : runOfFileUnit[0]
            for u in edit.nowStart..<edit.nowEnd {
                units.append(Unit(unit: now.text[u], run: donor, original: false, carried: now.carried[u]))
            }
            next = edit.fileEnd
        }
        keepFileUnits(until: fileText.count)
        guard !units.isEmpty else { return nil }
        // A character outside the BMP is one character: half of it retyped retypes both halves.
        for at in 0..<(units.count - 1) {
            let high = units[at]
            let low = units[at + 1]
            guard (0xD800...0xDBFF).contains(high.unit), (0xDC00...0xDFFF).contains(low.unit),
                  high.original != low.original else { continue }
            let typed = high.original ? low : high
            for k in at...(at + 1) {
                units[k].run = typed.run
                units[k].original = false
                units[k].carried = typed.carried
            }
        }

        // Runs, emitted. Units group by the attributes they will carry; a run whose
        // every unit is present, in place and unchanged is written as its bytes.
        var markupCache: [Int: [UInt16]] = [:]
        func markup(_ unit: Unit) -> [UInt16] {
            let id = unit.run << 5 | unit.carried << 1 | (unit.original ? 1 : 0)
            if let cached = markupCache[id] { return cached }
            let written = attributes(runs[unit.run].attributes, carrying: unit.carried, droppingRevision: !unit.original)
                .map { " \($0.name)=\"\($0.value)\"" }.joined()
            markupCache[id] = Array(written.utf16)
            return markupCache[id] ?? []
        }
        var firstUnitOfRun = [Int](repeating: -1, count: runs.count)
        var unitsInRun = [Int](repeating: 0, count: runs.count)
        for (at, unit) in units.enumerated() where unit.original {
            if firstUnitOfRun[unit.run] == -1 { firstUnitOfRun[unit.run] = at }
            unitsInRun[unit.run] += 1
        }
        var whole: [Bool] = runs.indices.map { r in
            guard !runs[r].text.isEmpty, unitsInRun[r] == runs[r].text.count else { return false }
            for k in 0..<runs[r].text.count {
                let at = firstUnitOfRun[r] + k
                guard at < units.count, units[at].original, units[at].run == r,
                      units[at].carried == ownCarried[r] else { return false }
            }
            return true
        }
        // Text typed onto an untouched run with exactly its attributes joins that run.
        for unit in units where !unit.original && whole[unit.run] {
            var asOwn = unit
            asOwn.original = true
            asOwn.carried = ownCarried[unit.run]
            if markup(unit) == markup(asOwn) { whole[unit.run] = false }
        }

        var out: [UInt16] = []
        var emptyNext = 0
        var written = [Bool](repeating: false, count: runs.count)
        func emitEmpty(before limit: Int) {
            while emptyNext < limit {
                if runs[emptyNext].text.isEmpty && !written[emptyNext] {
                    out += source[runs[emptyNext].lead..<runs[emptyNext].end]
                }
                emptyNext += 1
            }
        }
        var u = 0
        while u < units.count {
            let r = units[u].run
            emitEmpty(before: r)
            if units[u].original && whole[r] && firstUnitOfRun[r] == u {
                out += source[runs[r].lead..<runs[r].end]
                u += runs[r].text.count
                continue
            }
            // Each run written is laid out as the file lays out the run it comes from.
            let key = markup(units[u])
            out += source[runs[r].lead..<runs[r].start]
            written[r] = true
            var text: [UInt16] = []
            while u < units.count, markup(units[u]) == key, !(units[u].original && whole[units[u].run]) {
                text.append(units[u].unit)
                u += 1
            }
            out += Array("<Text".utf16) + key + Array(">".utf16)
            out += Array(encodeXmlEntities(String(decoding: text, as: UTF16.self)).utf16)
            out += Array("</Text>".utf16)
        }
        emitEmpty(before: runs.count)

        var bytes: [UInt16]
        if unedited.count == 1, unedited[0].type != edited[0].type, let fdxType = modelToFdx[edited[0].type] {
            bytes = retypedOpenTag(origin, as: fdxType, in: source)
        } else {
            bytes = Array(source[origin.start..<origin.textStart])
        }
        bytes += out
        bytes += source[origin.textEnd..<origin.end]
        return bytes
    }

    /// Each reading element paired with the saved element it became: unchanged,
    /// or edited in place — where a stretch between two unchanged pairs holds as
    /// many saved elements as reading ones (TypeScript `pairedInPlace`).
    fileprivate static func pairedInPlace(_ matches: [Int?], readingCount: Int) -> [Int: Int] {
        var pairs: [Int: Int] = [:]
        var lastSaved = -1
        var lastRead = -1
        func fill(_ savedNext: Int, _ readNext: Int) {
            let gap = savedNext - lastSaved - 1
            guard gap > 0, gap == readNext - lastRead - 1 else { return }
            for d in 1...gap { pairs[lastRead + d] = lastSaved + d }
        }
        for (j, k) in matches.enumerated() {
            guard let k else { continue }
            fill(j, k)
            pairs[k] = j
            lastSaved = j
            lastRead = k
        }
        fill(matches.count, readingCount)
        return pairs
    }

    /// Which original paragraphs the new screenplay still contains.
    ///
    /// A longest-common-subsequence over (type, text): what matches is kept
    /// verbatim, what does not is an edit. The pass afterwards is what makes
    /// this worth doing — a delete and an insert of the same element type is
    /// one paragraph whose text was edited, and pairing them keeps its
    /// attributes and its nested blocks instead of writing a bare one.
    fileprivate static func align(
        _ origin: [Span], to elements: [ScreenplayElement]
    ) -> [Span?] {
        var paired = [Span?](repeating: nil, count: elements.count)
        let n = origin.count
        let m = elements.count
        guard n > 0, m > 0 else { return paired }

        // Falls back to matching by position when the table would be
        // extravagant. Still lossless for an unedited file and still right for
        // an edit in place; it only pairs less cleverly after a large move.
        guard n * m <= 4_000_000 else {
            for index in 0..<min(n, m) { paired[index] = origin[index] }
            return paired
        }

        // Text, not kind. A Fountain round trip has no `General` and no
        // `Shot` — both come back as action — so comparing kinds would call
        // every one of them an insert. See `fountainFlattens`.
        func same(_ i: Int, _ j: Int) -> Bool {
            Fdx.recognisedText(origin[i].type, origin[i].text)
                == Fdx.recognisedText(elements[j].type, elements[j].text)
        }

        var table = [Int32](repeating: 0, count: (n + 1) * (m + 1))
        func at(_ i: Int, _ j: Int) -> Int { i * (m + 1) + j }
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                table[at(i, j)] = same(i, j)
                    ? table[at(i + 1, j + 1)] + 1
                    : max(table[at(i + 1, j)], table[at(i, j + 1)])
            }
        }

        var dropped: [Int] = []
        var inserted: [Int] = []
        var i = 0
        var j = 0
        while i < n && j < m {
            if same(i, j) {
                paired[j] = origin[i]
                i += 1
                j += 1
            } else if table[at(i + 1, j)] >= table[at(i, j + 1)] {
                dropped.append(i)
                i += 1
            } else {
                inserted.append(j)
                j += 1
            }
        }
        while i < n { dropped.append(i); i += 1 }
        while j < m { inserted.append(j); j += 1 }

        // An edit in place: one paragraph gone and one arrived, same kind.
        for j2 in inserted {
            if let near = dropped.firstIndex(where: {
                origin[$0].type == elements[j2].type || Fdx.fountainFlattens.contains(origin[$0].type)
            }) {
                paired[j2] = origin[dropped[near]]
                dropped.remove(at: near)
            }
        }
        return paired
    }

    fileprivate static func rewritten(
        _ origin: Span, as element: ScreenplayElement, in units: [UInt16]
    ) -> [UInt16] {
        let whole = Array(units[origin.start..<origin.end])
        let sameText = recognisedText(origin.type, origin.text)
            == recognisedText(element.type, element.text)
        /* The text is only half of a paragraph's content: a highlight or a
           style changed without a character moving must rewrite the run too. */
        let sameRuns = runsEqual(
            origin.runs,
            Emphasis.normalise(element.runs ?? [], textLength: element.text.utf16.count)
        )
        let changedKind = origin.type != element.type
            && !fountainFlattens.contains(origin.type)
            && modelToFdx[element.type] != nil
        if sameText && sameRuns && !changedKind { return whole }
        guard origin.textStart >= 0, origin.textEnd > origin.textStart else { return whole }

        // The attributes and every nested block stay; only the paragraph's own
        // text runs are replaced. A scene heading keeps its <SceneProperties>.
        var out = changedKind
            ? retypedOpenTag(origin, as: modelToFdx[element.type] ?? "Action", in: units)
            : Array(units[origin.start..<origin.textStart])
        if sameText && sameRuns {
            out += Array(units[origin.textStart..<origin.end])
            return out
        }
        out += Array(textRunsMarkup(text: element.text, runs: element.runs).utf16)
        out += Array(units[origin.textEnd..<origin.end])
        return out
    }

    /// A scene heading's paragraph with its `Number` attribute saying the
    /// element's scene number, every other byte as it was (TypeScript
    /// `numberedParagraph`).
    ///
    /// The number is an attribute of the paragraph, not its words, so no
    /// text merge carries it. Without this a renumbered heading kept the
    /// file's old number — and a scene restored out of an OMITTED card,
    /// whose number Final Draft keeps on the card, came back with none.
    /// A paragraph whose number already agrees is returned untouched.
    fileprivate static func numbered(_ bytes: [UInt16], as element: ScreenplayElement) -> [UInt16] {
        guard element.type == .scene else { return bytes }
        let paragraph = String(decoding: bytes, as: UTF16.self)
        guard paragraph.hasPrefix("<Paragraph"), let close = paragraph.firstIndex(of: ">") else { return bytes }
        let head = paragraph[..<close]
        let wanted = element.sceneNumber ?? ""
        let attribute = head.range(of: #"\sNumber="[^"]*""#, options: .regularExpression)
        let current = attribute.map { range -> String in
            let quoted = head[range]
            guard let open = quoted.firstIndex(of: "\"") else { return "" }
            return decodeXmlEntities(String(quoted[quoted.index(after: open)..<quoted.index(before: quoted.endIndex)]))
        } ?? ""
        guard current != wanted else { return bytes }
        var rewritten = String(head)
        let value = " Number=\"\(encodeXmlEntities(wanted))\""
        if let attribute {
            let offset = head.distance(from: head.startIndex, to: attribute.lowerBound)
            let length = head.distance(from: attribute.lowerBound, to: attribute.upperBound)
            let start = rewritten.index(rewritten.startIndex, offsetBy: offset)
            let end = rewritten.index(start, offsetBy: length)
            rewritten.replaceSubrange(start..<end, with: wanted.isEmpty ? "" : value)
        } else {
            rewritten.insert(contentsOf: value, at: rewritten.index(rewritten.startIndex, offsetBy: "<Paragraph".count))
        }
        return Array((rewritten + paragraph[close...]).utf16)
    }

    /// Whether two run lists say the same thing, property for property.
    fileprivate static func runsEqual(_ a: [StyleRun], _ b: [StyleRun]) -> Bool {
        guard a.count == b.count else { return false }
        return zip(a, b).allSatisfy { run, other in
            run.start == other.start && run.end == other.end
                && run.styles == other.styles
                && run.revisionID == other.revisionID
                && (run.tagNumbers ?? []) == (other.tagNumbers ?? [])
                && run.highlight == other.highlight
        }
    }

    /// The paragraph's opening tag with a new Type, every other attribute left
    /// alone — an id, an alignment, a scene number all survive a writer
    /// changing what kind of line this is.
    fileprivate static func retypedOpenTag(
        _ origin: Span, as fdxType: String, in units: [UInt16]
    ) -> [UInt16] {
        let head = String(
            utf16CodeUnits: Array(units[origin.start..<origin.textStart]),
            count: origin.textStart - origin.start
        )
        guard let range = head.range(of: #"\sType="[^"]*""#, options: .regularExpression) else {
            return Array(head.replacingOccurrences(
                of: "<Paragraph", with: "<Paragraph Type=\"\(fdxType)\""
            ).utf16)
        }
        return Array(head.replacingCharacters(in: range, with: " Type=\"\(fdxType)\"").utf16)
    }

    /// A paragraph's text as one or more <Text> runs.
    ///
    /// The model's runs become the file's runs: styles in FDX's own '+'
    /// list, the highlight in our extension namespace, revision and tags
    /// carried. A paragraph with no runs writes exactly what it always did —
    /// the plain single <Text> — so a runless document's bytes never move.
    /// Shared by body paragraphs and title-page lines (TypeScript
    /// `textRunsMarkup`, widened the same way).
    fileprivate static func textRunsMarkup(text: String, runs: [StyleRun]?) -> String {
        let runs = runs ?? []
        guard !runs.isEmpty else {
            return "<Text>\(encodeXmlEntities(text))</Text>"
        }
        let text = text as NSString
        var out = ""
        var cursor = 0
        let styleOrder: [(StyleSet, String)] = [
            (.bold, "Bold"), (.italic, "Italic"), (.underline, "Underline"),
            (.strikeout, "Strikeout"), (.allCaps, "AllCaps"), (.hiddenText, "HiddenText")
        ]
        for run in runs.sorted(by: { $0.start < $1.start }) {
            let start = max(cursor, min(run.start, text.length))
            let end = max(start, min(run.end, text.length))
            if start > cursor {
                out += "<Text>\(encodeXmlEntities(text.substring(with: NSRange(location: cursor, length: start - cursor))))</Text>"
            }
            if end > start {
                var attrs: [String] = []
                let styles = styleOrder.filter { run.styles.contains($0.0) }.map { $0.1 }
                if !styles.isEmpty { attrs.append("Style=\"\(styles.joined(separator: "+"))\"") }
                if let revisionID = run.revisionID { attrs.append("RevisionID=\"\(revisionID)\"") }
                if let tagNumbers = run.tagNumbers, !tagNumbers.isEmpty {
                    attrs.append("TagNumber=\"\(tagNumbers.map(String.init).joined(separator: ","))\"")
                }
                if run.highlight != nil {
                    attrs.append("\(Fdx.extensionPrefix):Highlight=\"Yellow\"")
                }
                let attributeText = attrs.isEmpty ? "" : " " + attrs.joined(separator: " ")
                out += "<Text\(attributeText)>\(encodeXmlEntities(text.substring(with: NSRange(location: start, length: end - start))))</Text>"
            }
            cursor = end
        }
        if cursor < text.length {
            out += "<Text>\(encodeXmlEntities(text.substring(from: cursor)))</Text>"
        }
        return out
    }

    /// A namespaced attribute means nothing without its declaration. Files
    /// written by Final Draft have never heard of our prefix, so the first
    /// time eDraft's own metadata is spliced into one — a highlight, a lyrics
    /// mark — the root gains the declaration. Files that already declare it
    /// (anything eDraft wrote) pass through byte-identical.
    fileprivate static func ensureNamespaceDeclared(_ xml: String) -> String {
        guard xml.contains("\(Fdx.extensionPrefix):") else { return xml }
        guard !xml.contains("xmlns:\(Fdx.extensionPrefix)=") else { return xml }
        guard let root = xml.range(of: "<FinalDraft") else { return xml }
        var copy = xml
        copy.insert(
            contentsOf: " xmlns:\(Fdx.extensionPrefix)=\"\(Fdx.namespace)\"",
            at: root.upperBound
        )
        return copy
    }

    /// The single <Paragraph>…</Paragraph> out of a one-element export.
    fileprivate static func paragraphBody(of xml: String) -> String? {
        guard let open = xml.range(of: "<Paragraph"),
              let close = xml.range(of: "</Paragraph>", options: .backwards)
        else { return nil }
        return String(xml[open.lowerBound..<close.upperBound])
    }

    // MARK: - Export

    /// Serialise the engine model as FDX XML. Structural elements the FDX
    /// paragraph subset cannot represent are omitted, reported in
    /// `diagnostics`, and noted in an in-file warning comment.
    public static func write(_ script: Screenplay, options: ExportOptions = ExportOptions()) -> ExportResult {
        let diagnostics = DiagnosticCollector(
            limit: positiveInteger(options.maxWarnings, fallback: defaultLimits.maxWarnings)
        )
        var body: [String] = []
        /* Each paragraph's length as a ScriptNote Range counts it. */
        var lengths: [Int] = []
        /* And each paragraph's words, so a note anchored to some of them
           finds them (§5.1). A fresh write has no embedded blocks: dual
           dialogue is written as Dual="Yes" on the cue, never as a
           <DualDialogue> block (TypeScript `paragraphTexts`). */
        var paragraphTexts: [String] = []
        /* The writer's notes, and the paragraph each sits in front of. */
        var notes: [(element: ScreenplayElement, at: Int)] = []
        var waiting: [ScreenplayElement] = []
        var omittedStructural = 0
        var omittedUnknown = 0
        var actCount = 0
        /* the card the previous act break carries, so the generated End of
           Act can name the act the way the act names itself */
        var previousActCard: String?

        /* Omitted scenes (§7.3): the card each one hangs under, and every
           element inside a span — written inside its card, never on its own. */
        var omissionAfter: [Int: Omission] = [:]
        var omittedBody = Set<Int>()
        for omission in script.omissions ?? [] where omission.start > 0 && omission.end > omission.start {
            omissionAfter[omission.start - 1] = omission
            for at in omission.start..<omission.end { omittedBody.insert(at) }
        }
        func paragraphAttributes(_ element: ScreenplayElement, _ fdxType: String, _ index: Int) -> [String] {
            var attributes = ["Type=\"\(fdxType)\""]
            if element.type == .centered || element.type == .actbreak {
                attributes.append("Alignment=\"Center\"")
            }
            if element.type == .lyrics { attributes.append("\(extensionPrefix):ElementType=\"lyrics\"") }
            if element.type == .character && element.dual == true { attributes.append("Dual=\"Yes\"") }
            if element.type == .scene, let sceneNumber = element.sceneNumber, !sceneNumber.isEmpty {
                attributes.append(
                    "Number=\"\(encodeXmlValue(sceneNumber, diagnostics: diagnostics, context: "scene number", elementIndex: index))\""
                )
            }
            return attributes
        }
        /// One element of an omitted body, as the paragraph it was.
        func paragraphMarkup(_ element: ScreenplayElement, _ index: Int) -> String {
            let fdxType = Fdx.fdxType(of: element) ?? "Action"
            let attributes = paragraphAttributes(element, fdxType, index).joined(separator: " ")
            return "<Paragraph \(attributes)>\(textRunsMarkup(text: element.text, runs: element.runs))</Paragraph>"
        }

        for (index, element) in script.elements.enumerated() {
            /* Inside an omitted scene: written with its card, not here. */
            if omittedBody.contains(index) { continue }
            /* A note is a ScriptNote (RFC-NOTES-SYSTEM §4.2), never a
               paragraph: Final Draft shows a body Note paragraph as a line of
               the script. */
            if element.type == .note {
                waiting.append(element)
                continue
            }
            guard let fdxType = fdxType(of: element) else {
                if element.type.isPrinting { omittedUnknown += 1 } else { omittedStructural += 1 }
                continue
            }

            if element.type == .actbreak {
                /* D3, written out loud: the act that just ended is a derivable
                   fact, so its card is generated here rather than stored in the
                   model. Final Draft readers see the file their software would
                   have written; eDraft never stores it. The card names the act
                   the way the act names itself: a canonical card ends "END OF
                   ACT ONE", a writer's own card is mirrored — TEASER closes as
                   END TEASER, which is Breaking Bad's own spelling. */
                actCount += 1
                if actCount > 1, let previousActCard {
                    let endText = Acts.isCanonicalActCard(previousActCard)
                        ? "END OF ACT \(Acts.ordinal(actCount - 1))"
                        : "END \(previousActCard)"
                    body.append(
                        "<Paragraph Type=\"End of Act\" Alignment=\"Center\"><Text>\(encodeXmlValue(endText, diagnostics: diagnostics, context: "end-of-act card", elementIndex: index))</Text></Paragraph>"
                    )
                    lengths.append(endText.utf16.count)
                    paragraphTexts.append(endText)
                }
                previousActCard = element.text
            }

            let attributes = paragraphAttributes(element, fdxType, index)
            /* encodeXmlValue is the diagnostics path (illegal code points
               are reported and repaired); the markup below re-encodes for
               the actual bytes. */
            _ = encodeXmlValue(
                element.text, diagnostics: diagnostics, context: "paragraph text", elementIndex: index
            )
            /* An omitted scene is written back where Final Draft keeps it:
               inside the Scene Heading that shows its OMITTED card (§7.3).
               Its body is not also written as live paragraphs — that is the
               resurrection this work exists to prevent. */
            let omission = omissionAfter[index]
            let block = omission.map { omission in
                "<OmittedScene>" + script.elements[omission.start..<omission.end]
                    .enumerated()
                    .map { paragraphMarkup($0.element, omission.start + $0.offset) }
                    .joined() + "</OmittedScene>"
            } ?? ""
            body.append("<Paragraph \(attributes.joined(separator: " "))>\(textRunsMarkup(text: element.text, runs: element.runs))\(block)</Paragraph>")
            /* A ScriptNote Range counts an embedded block as two units,
               wherever it sits — so a file this writer produces reads back
               with the same Range space it was written from. */
            lengths.append(element.text.utf16.count + (omission != nil ? Fdx.blockUnits : 0))
            paragraphTexts.append(element.text)
            for note in waiting { notes.append((note, body.count - 1)) }
            waiting = []
        }
        for note in waiting { notes.append((note, body.count - 1)) }

        if omittedStructural > 0 {
            diagnostics.add(.init(
                code: "FDX_STRUCTURAL_ELEMENTS_OMITTED",
                severity: .warning,
                message: "\(omittedStructural) non-printing structural element(s) were omitted because the supported FDX paragraph subset cannot represent them safely.",
                count: omittedStructural
            ))
        }
        if omittedUnknown > 0 {
            diagnostics.add(.init(
                code: "FDX_UNKNOWN_ELEMENTS_OMITTED",
                severity: .error,
                message: "\(omittedUnknown) element(s) with unsupported runtime types were omitted.",
                count: omittedUnknown
            ))
        }

        var out: [String] = [
            xmlHeader,
            "<FinalDraft xmlns:\(extensionPrefix)=\"\(namespace)\" DocumentType=\"Script\" Version=\"3\">"
        ]
        if omittedStructural + omittedUnknown > 0 {
            out.append(
                "<!-- eDraft warning: \(omittedStructural + omittedUnknown) unsupported element(s) omitted; inspect writeFdxWithDiagnostics(). -->"
            )
        }
        out.append("<Content>")
        out.append(contentsOf: body)
        out.append("</Content>")

        /* The title page writes verbatim (RFC-TITLE-PAGE D5): each line a
           paragraph — its own alignment, styled runs, blanks and all. The
           key rides along as our annotation when the line carries one;
           nothing is recomputed, so a foreign page comes back as itself. */
        if !script.titlePage.isEmpty {
            out.append("<TitlePage>")
            out.append("<Content>")
            for (lineIndex, line) in script.titlePage.enumerated() {
                let alignment: String
                switch line.alignment ?? .center {
                case .left: alignment = "Left"
                case .right: alignment = "Right"
                case .center: alignment = "Center"
                }
                var attributes = "Alignment=\"\(alignment)\" Type=\"General\""
                if let key = line.key, !key.isEmpty {
                    attributes += " \(extensionPrefix):TitleKey=\"\(encodeXmlValue(key, diagnostics: diagnostics, context: "title-page key \(lineIndex)"))\""
                }
                _ = encodeXmlValue(
                    line.text, diagnostics: diagnostics, context: "paragraph text", elementIndex: lineIndex
                )
                out.append("<Paragraph \(attributes)>\(textRunsMarkup(text: line.text, runs: line.runs))</Paragraph>")
            }
            out.append("</Content>")
            out.append("</TitlePage>")
        }

        if !notes.isEmpty {
            let writing = resolvedNoteWriting(options.notes)
            let names = writing.writer.map { [$0] } ?? []
            out.append("<ScriptNotes>")
            for (index, note) in notes.enumerated() {
                let authorship = noteAuthorship(note.element.text, names: names, writer: writing.writer)
                out += scriptNoteLines(
                    id: index + 1,
                    author: authorship.author,
                    message: authorship.message,
                    range: noteRange(
                        paragraphRange(lengths, at: note.at),
                        paragraph: note.at >= 0 && note.at < paragraphTexts.count
                            ? (text: paragraphTexts[note.at], blocks: [])
                            : nil,
                        anchor: note.element.anchor,
                        diagnostics: diagnostics
                    ),
                    writing: writing,
                    diagnostics: diagnostics
                ).map(\.text)
            }
            out.append("</ScriptNotes>")
        }

        out.append("</FinalDraft>")
        out.append("")
        let items = diagnostics.result()
        return ExportResult(
            xml: out.joined(separator: "\n"),
            warnings: items.map(\.message),
            diagnostics: items
        )
    }

    /// Compatibility helper returning XML only (TypeScript `writeFdx`). Call
    /// `write(_:options:)` in new integrations so any lossy conversion can be
    /// reviewed before the file leaves the app.
    public static func writeXml(_ script: Screenplay) -> String {
        write(script).xml
    }
}
