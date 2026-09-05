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
        "general": .general
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
        .lyrics: "General"
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
        var contentDepth = 0
        var textDepth = 0
        /// Whether the Text run being read is styled AllCaps by Final Draft.
        var runUppercases = false
        var paragraphCount = 0
        var textRunCount = 0
        var limitReached = false
        var current: CollectedParagraph?

        init(limits: Limits, diagnostics: DiagnosticCollector) {
            self.limits = limits
            self.diagnostics = diagnostics
        }

        func finishParagraph() {
            guard let paragraph = current else { return }
            if paragraph.inTitlePage { title.append(paragraph) } else { body.append(paragraph) }
            current = nil
            textDepth = 0
            runUppercases = false
        }

        func start(_ tag: FdxXmlScanner.Tag, offset: Int) -> Bool {
            if tag.name == "finaldraft" { hasFinalDraftRoot = true }
            if tag.name == "titlepage" { titleDepth += 1 }
            if tag.name == "content" { contentDepth += 1 }

            if tag.name == "paragraph" && contentDepth > 0 {
                if paragraphCount >= limits.maxParagraphs {
                    limitReached = true
                    return false
                }
                if current != nil {
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
                    inTitlePage: titleDepth > 0
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
                runUppercases = Fdx.runIsAllCaps(
                    tag.attributes.first { $0.name == "style" }?.value
                )
            }
            return true
        }

        func end(_ name: String) -> Bool {
            if name == "text" && textDepth > 0 {
                textDepth -= 1
                runUppercases = false
            }
            if name == "paragraph" { finishParagraph() }
            if name == "content" && contentDepth > 0 { contentDepth -= 1 }
            if name == "titlepage" && titleDepth > 0 { titleDepth -= 1 }
            return true
        }

        func text(_ value: String, cdata: Bool) -> Bool {
            if current != nil && textDepth > 0 {
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
        FdxXmlScanner.scan(
            source,
            handlers: FdxXmlScanner.Handlers(
                start: { tag, offset in collector.start(tag, offset: offset) },
                end: { name, _ in collector.end(name) },
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

            if type == .general,
               (paragraph.extensionAttribute("elementtype") ?? "").lowercased() == "lyrics" {
                type = .lyrics
            }
            if type == .general,
               (paragraph.attribute("alignment") ?? "").lowercased() == "center" {
                type = .centered
            }

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
