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
        "note": .note
    ]

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
        .note: "Note"
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

    /// Guess a title-page key from paragraph position when an external FDX
    /// has no key metadata. JavaScript's out-of-bounds `undefined ?? 'Contact'`
    /// is a trap in Swift — real Final Draft title pages run well past five
    /// paragraphs, so the fallback must be written, not subscripted.
    private static func titleKey(for index: Int) -> String {
        let keys = ["Title", "Credit", "Author", "Source", "Contact"]
        return index < keys.count ? keys[index] : "Contact"
    }

    /// TypeScript `Number(...)`: full-string numeric parse (whitespace-
    /// trimmed; empty is 0; hex/octal/binary prefixes honoured), accepted
    /// only when the result is a non-negative safe integer.
    private static func jsSafeInteger(_ raw: String) -> Int? {
        let text = raw.jsTrimmed
        if text.isEmpty { return 0 }
        if text.count > 2 {
            let radix: Int?
            if text.hasPrefix("0x") || text.hasPrefix("0X") { radix = 16 }
            else if text.hasPrefix("0o") || text.hasPrefix("0O") { radix = 8 }
            else if text.hasPrefix("0b") || text.hasPrefix("0B") { radix = 2 }
            else { radix = nil }
            if let radix {
                let digits = text.dropFirst(2)
                guard let value = UInt64(digits, radix: radix),
                      value <= 9_007_199_254_740_991 else { return nil }
                return Int(value)
            }
        }
        guard let value = Double(text),
              value.isFinite,
              value.rounded() == value,
              abs(value) <= 9_007_199_254_740_991 else { return nil }
        return Int(value)
    }

    private static func titlePage(
        of paragraphs: [CollectedParagraph],
        diagnostics: DiagnosticCollector
    ) -> [TitlePageEntry] {
        var tagged: [Int: TitlePageEntry] = [:]
        var untagged: [String] = []

        for paragraph in paragraphs {
            let key = paragraph.extensionAttribute("titlekey") ?? ""
            let rawEntryIndex = paragraph.extensionAttribute("titleentry") ?? ""
            if key != "", !rawEntryIndex.isEmpty,
               let entryIndex = jsSafeInteger(rawEntryIndex), entryIndex >= 0 {
                if var existing = tagged[entryIndex] {
                    if existing.key == key {
                        existing.values.append(paragraph.text)
                        tagged[entryIndex] = existing
                    } else {
                        diagnostics.add(.init(
                            code: "FDX_CONFLICTING_TITLE_METADATA",
                            severity: .warning,
                            message: "Title entry \(entryIndex) declared conflicting keys; the later paragraph was imported positionally.",
                            paragraphIndex: paragraph.paragraphIndex
                        ))
                        if !paragraph.text.jsTrimmed.isEmpty { untagged.append(paragraph.text) }
                    }
                } else {
                    tagged[entryIndex] = TitlePageEntry(key: key, values: [paragraph.text])
                }
            } else if !paragraph.text.jsTrimmed.isEmpty {
                untagged.append(paragraph.text)
            }
        }

        var titlePage = tagged.sorted { $0.key < $1.key }.map(\.value)
        for (index, text) in untagged.enumerated() {
            let key = titleKey(for: index)
            if let existing = titlePage.firstIndex(where: { $0.key == key }) {
                titlePage[existing].values.append(text)
            } else {
                titlePage.append(TitlePageEntry(key: key, values: [text]))
            }
        }
        return titlePage
    }

    private static func emptyImport(_ diagnostics: DiagnosticCollector) -> ImportResult {
        let items = diagnostics.result()
        return ImportResult(
            script: Screenplay(titlePage: [], elements: []),
            warnings: items.map(\.message),
            diagnostics: items
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
        for paragraph in parsed.body {
            let fdxType = paragraph.attribute("type") ?? ""
            let key = fdxType.jsTrimmed.lowercased()
            var type = fdxToModel[key]
            if type == nil {
                if !fdxType.isEmpty {
                    diagnostics.add(.init(
                        code: "FDX_UNKNOWN_PARAGRAPH_TYPE",
                        severity: .warning,
                        message: "Unknown paragraph type \"\(fdxType)\" — imported as General.",
                        paragraphIndex: paragraph.paragraphIndex
                    ))
                }
                type = .general
            }

            type = refineGeneral(type ?? .general, paragraph)

            var element = ScreenplayElement(type: type ?? .general, text: paragraph.text)
            let sceneNumber = paragraph.attribute("number") ?? ""
            if type == .scene && !sceneNumber.isEmpty { element.sceneNumber = sceneNumber }
            if type == .character,
               (paragraph.attribute("dual") ?? "").lowercased() == "yes" {
                element.dual = true
            }
            elements.append(element)
        }

        // The title page is folded BEFORE the diagnostics are read out:
        // conflict detection there reports into the same collector, and the
        // TypeScript return order (script first, then `diagnostics.result()`)
        // captures it — snapshotting `items` first would silently drop it.
        let title = titlePage(of: parsed.title, diagnostics: diagnostics)
        let items = diagnostics.result()
        return ImportResult(
            script: Screenplay(titlePage: title, elements: elements),
            warnings: items.map(\.message),
            diagnostics: items
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
        return refineGeneral(fdxToModel[key] ?? .general, paragraph)
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
        public func rewrite(_ script: Screenplay) -> String {
            guard let first = spans.first, let last = spans.last else {
                // Nothing recognisable to edit: write a whole new file rather
                // than pretend, so a malformed original cannot corrupt a save.
                return Fdx.writeXml(script)
            }

            let paired = Fdx.align(spans, to: script.elements)
            var out: [UInt16] = Array(units[0..<first.start])
            var lead: [UInt16] = []
            var wrote = false
            for (index, element) in script.elements.enumerated() {
                if let origin = paired[index] {
                    if wrote { out += origin.lead.isEmpty ? lead : origin.lead }
                    if !origin.lead.isEmpty { lead = origin.lead }
                    out += Fdx.rewritten(origin, as: element, in: units)
                } else {
                    if wrote { out += lead.isEmpty ? Array("\n".utf16) : lead }
                    let fresh = Fdx.writeXml(Screenplay(titlePage: [], elements: [element]))
                    if let body = Fdx.paragraphBody(of: fresh) { out += Array(body.utf16) }
                }
                wrote = true
            }
            out += Array(units[last.end...])
            return String(utf16CodeUnits: out, count: out.count)
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
                lead: lead
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
        let changedKind = origin.type != element.type
            && !fountainFlattens.contains(origin.type)
            && modelToFdx[element.type] != nil
        if sameText && !changedKind { return whole }
        guard origin.textStart >= 0, origin.textEnd > origin.textStart else { return whole }

        // The attributes and every nested block stay; only the paragraph's own
        // text runs are replaced. A scene heading keeps its <SceneProperties>.
        var out = changedKind
            ? retypedOpenTag(origin, as: modelToFdx[element.type] ?? "Action", in: units)
            : Array(units[origin.start..<origin.textStart])
        if sameText {
            out += Array(units[origin.textStart..<origin.end])
            return out
        }
        out += Array("<Text>\(encodeXmlEntities(element.text))</Text>".utf16)
        out += Array(units[origin.textEnd..<origin.end])
        return out
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

        for (index, element) in script.elements.enumerated() {
            guard let fdxType = modelToFdx[element.type] else {
                if element.type.isPrinting { omittedUnknown += 1 } else { omittedStructural += 1 }
                continue
            }

            var attributes = ["Type=\"\(fdxType)\""]
            if element.type == .centered { attributes.append("Alignment=\"Center\"") }
            if element.type == .lyrics { attributes.append("\(extensionPrefix):ElementType=\"lyrics\"") }
            if element.type == .character && element.dual == true { attributes.append("Dual=\"Yes\"") }
            if element.type == .scene, let sceneNumber = element.sceneNumber, !sceneNumber.isEmpty {
                attributes.append(
                    "Number=\"\(encodeXmlValue(sceneNumber, diagnostics: diagnostics, context: "scene number", elementIndex: index))\""
                )
            }
            let encoded = encodeXmlValue(
                element.text, diagnostics: diagnostics, context: "paragraph text", elementIndex: index
            )
            body.append("<Paragraph \(attributes.joined(separator: " "))><Text>\(encoded)</Text></Paragraph>")
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

        if !script.titlePage.isEmpty {
            out.append("<TitlePage>")
            out.append("<Content>")
            for (entryIndex, entry) in script.titlePage.enumerated() {
                let values = entry.values.isEmpty ? [""] : entry.values
                let key = encodeXmlValue(
                    entry.key, diagnostics: diagnostics, context: "title-page key \(entryIndex)"
                )
                for value in values {
                    let encoded = encodeXmlValue(
                        value, diagnostics: diagnostics, context: "title-page entry \(entryIndex)"
                    )
                    out.append(
                        "<Paragraph Alignment=\"Center\" Type=\"General\" \(extensionPrefix):TitleKey=\"\(key)\" \(extensionPrefix):TitleEntry=\"\(entryIndex)\"><Text>\(encoded)</Text></Paragraph>"
                    )
                }
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
