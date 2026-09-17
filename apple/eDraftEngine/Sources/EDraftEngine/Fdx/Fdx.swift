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

        public init(maxWarnings: Int? = nil) {
            self.maxWarnings = maxWarnings
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
        for paragraph in parsed.body {
            let fdxType = paragraph.attribute("type") ?? ""
            let key = fdxType.jsTrimmed.lowercased()
            /* RFC-ACT-BREAK D3: an End of Act carries no fact the model lacks —
               an act ends where the next one begins, and the export regenerates
               these. Absorbed without a warning: a diagnostic the reader cannot
               act on only teaches them to ignore the list. */
            layout.append(ParagraphLayout(
                length: paragraph.text.utf16.count,
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

            let type: ElementKind = refineGeneral(kind?.type ?? .general, paragraph)

            var element = ScreenplayElement(type: type, text: paragraph.text)
            if !paragraph.runs.isEmpty {
                element.runs = Emphasis.normalise(
                    paragraph.runs, textLength: paragraph.text.utf16.count
                )
            }
            if type == .section, let depth = kind?.depth { element.depth = depth }
            let sceneNumber = paragraph.attribute("number") ?? ""
            if type == .scene && !sceneNumber.isEmpty { element.sceneNumber = sceneNumber }
            if type == .character,
               (paragraph.attribute("dual") ?? "").lowercased() == "yes" {
                element.dual = true
            }
            elements.append(element)
        }

        /* The title page reads verbatim — it reports no diagnostics, so the
           collector's snapshot needs no particular order against it. */
        let title = titlePageLines(of: parsed.title)
        let notes = scriptNotes(in: source, layout: layout, limits: limits, diagnostics: diagnostics)
        let items = diagnostics.result()
        return ImportResult(
            script: Screenplay(titlePage: title, elements: elements),
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
        public func rewrite(_ script: Screenplay, unedited: Screenplay? = nil) -> String {
            guard let first = spans.first, let last = spans.last else {
                // Nothing recognisable to edit: write a whole new file rather
                // than pretend, so a malformed original cannot corrupt a save.
                return Fdx.writeXml(script)
            }

            /* Only paragraphs the import turned into elements can be matched to
               one. An absorbed End of Act left in the alignment was deleted by
               every save, and — typed General when it has no Alignment — was
               paired with the writer's next edit and given their text. */
            let aligned = spans.filter { !$0.absorbed }
            let elements = script.elements

            /* A paragraph the writer did not edit is written as its original
               bytes. With the caller's unedited reading, "did not edit" is asked
               in the caller's own terms: the paragraph's element — or the run of
               elements its lines became — comes back exactly as it was read.
               Measured without this on a file Final Draft wrote, a save through
               Fountain that changed nothing lost 400 of 407 production tags. */
            var verbatim: [Int: Span] = [:]
            var consumed = Set<Int>()
            if let reading = unedited?.elements {
                let ranges = Fdx.correspondence(aligned, reading)
                var savedAt: [Int: Int] = [:]
                for (j, k) in Fdx.unchangedFrom(elements, reading).enumerated() {
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
            }

            // Everything else is paired as it always was.
            let writtenAsRead = Set(verbatim.values.map(\.start))
            let rest = elements.indices.filter { verbatim[$0] == nil && !consumed.contains($0) }
            let restPaired = Fdx.align(
                aligned.filter { !writtenAsRead.contains($0.start) },
                to: rest.map { elements[$0] }
            )
            var paired = [Span?](repeating: nil, count: elements.count)
            for (r, j) in rest.enumerated() { paired[j] = restPaired[r] }
            for (j, span) in verbatim { paired[j] = span }

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

            var out: [UInt16] = Array(units[0..<first.start])
            var lead: [UInt16] = []
            var wrote = false
            func restore(_ span: Span) {
                if wrote { out += span.lead.isEmpty ? lead : span.lead }
                if !span.lead.isEmpty { lead = span.lead }
                out += units[span.start..<span.end]
                wrote = true
            }
            for (index, element) in elements.enumerated() {
                // A line of a paragraph already written whole.
                if consumed.contains(index) { continue }
                if let origin = paired[index] {
                    absorbedBefore[origin.start]?.forEach(restore)
                    if wrote { out += origin.lead.isEmpty ? lead : origin.lead }
                    if !origin.lead.isEmpty { lead = origin.lead }
                    if verbatim[index]?.start == origin.start {
                        out += units[origin.start..<origin.end]
                    } else {
                        out += Fdx.rewritten(origin, as: element, in: units)
                    }
                } else {
                    if wrote { out += lead.isEmpty ? Array("\n".utf16) : lead }
                    let fresh = Fdx.writeXml(Screenplay(titlePage: [], elements: [element]))
                    if let body = Fdx.paragraphBody(of: fresh) { out += Array(body.utf16) }
                }
                wrote = true
            }
            waiting.forEach(restore)
            out += Array(units[last.end...])
            return Fdx.ensureNamespaceDeclared(
                String(utf16CodeUnits: out, count: out.count)
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

        var spans: [Span] = []
        var previousEnd = -1
        for paragraph in collected.body {
            let lead: [UInt16] = previousEnd == -1
                ? []
                : Array(units[previousEnd..<max(previousEnd, paragraph.start)])
            previousEnd = paragraph.end
            spans.append(Span(
                type: elementKind(of: paragraph),
                text: paragraph.text,
                start: paragraph.start,
                end: paragraph.end,
                textStart: paragraph.textStart,
                textEnd: paragraph.textEnd,
                lead: lead,
                runs: Emphasis.normalise(paragraph.runs, textLength: paragraph.text.utf16.count),
                absorbed: (paragraph.attribute("type") ?? "").jsTrimmed.lowercased() == "end of act"
            ))
        }

        return Document(
            script: imported.script,
            warnings: imported.warnings,
            diagnostics: imported.diagnostics,
            units: units,
            spans: spans
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
        var omittedStructural = 0
        var omittedUnknown = 0
        var actCount = 0
        /* the card the previous act break carries, so the generated End of
           Act can name the act the way the act names itself */
        var previousActCard: String?

        for (index, element) in script.elements.enumerated() {
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
                }
                previousActCard = element.text
            }

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
            /* encodeXmlValue is the diagnostics path (illegal code points
               are reported and repaired); the markup below re-encodes for
               the actual bytes. */
            _ = encodeXmlValue(
                element.text, diagnostics: diagnostics, context: "paragraph text", elementIndex: index
            )
            body.append("<Paragraph \(attributes.joined(separator: " "))>\(textRunsMarkup(text: element.text, runs: element.runs))</Paragraph>")
        }

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
