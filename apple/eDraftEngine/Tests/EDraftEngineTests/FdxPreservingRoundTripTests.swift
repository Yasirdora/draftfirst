import Testing
import Foundation
@testable import EDraftEngine

/// A Final Draft file is edited, not rebuilt.
///
/// Reading an .fdx into a screenplay and writing a new one from that
/// screenplay throws away everything the screenplay cannot hold — on a real
/// production draft, 19 revisions, 171 revised runs, 25 locked pages, 73
/// deleted-text marks, 248 production tags, 6 dual-dialogue blocks, 136
/// emphasis runs and 3 script notes, all from changing one word and saving.
@Suite("FDX preserving round trip")
struct FdxPreservingRoundTripTests {

    /// A production draft in miniature: the constructs a screenplay model
    /// cannot hold, and a scene heading with its arc beats nested inside.
    static let production = """
    <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
    <FinalDraft DocumentType="Script" Template="No" Version="6">
      <Content>
        <Paragraph Type="Scene Heading" Number="1" id="a1">
          <SceneProperties Length="4/8" Page="1" Title="Set up Gold Key">
            <SceneArcBeats>
              <CharacterArcBeat Name="TANGLE">
                <Paragraph><Text>Tangle is obsessed with the treasure.</Text></Paragraph>
              </CharacterArcBeat>
            </SceneArcBeats>
          </SceneProperties>
          <Text>INT. HOME LIBRARY - DAY</Text>
        </Paragraph>
        <Paragraph Type="Action" id="a2"><Text>Majestic.</Text></Paragraph>
        <Paragraph Type="Action" id="a3"><Text RevisionID="2">Light </Text><Text Style="Italic">glinting</Text><Text> off it.</Text></Paragraph>
        <Paragraph Alignment="Center" Type="General"><Text>The end</Text></Paragraph>
      </Content>
      <LockedPages><LockedPage Number="1"/></LockedPages>
      <Revisions><Revision Color="Blue" Mark="*" Name="First Revision" Number="1"/></Revisions>
      <TagData><TagDefinition Id="t1" Label="Spanish moss"/></TagData>
    </FinalDraft>
    """

    /// The invariant everything rests on.
    @Test("A save with no edit returns the identical file")
    func noOpIsIdentical() {
        let document = Fdx.open(Self.production)
        #expect(document.rewrite(document.script) == Self.production)
    }

    @Test("An edit rewrites that paragraph and touches nothing else")
    func editKeepsTheRest() {
        let document = Fdx.open(Self.production)
        var script = document.script
        script.elements = script.elements.map { element in
            guard element.text == "Majestic." else { return element }
            var edited = element
            edited.text = "Majestic, and lit."
            return edited
        }
        let xml = document.rewrite(script)

        #expect(xml.contains("Majestic, and lit."))
        #expect(!xml.contains(">Majestic.<"))
        // Everything the screenplay cannot hold survived the edit.
        #expect(xml.contains("<Revision"))
        #expect(xml.contains("<LockedPage"))
        #expect(xml.contains("<TagDefinition"))
        #expect(xml.contains("Style=\"Italic\""))
        #expect(xml.contains("<SceneProperties"))
    }

    /// A scene heading carries its arc beats. Editing its words must not cost
    /// the writer their beats.
    @Test("A scene heading keeps its nested blocks when its text changes")
    func headingKeepsItsBeats() {
        let document = Fdx.open(Self.production)
        var script = document.script
        script.elements = script.elements.map { element in
            guard element.type == .scene else { return element }
            var edited = element
            edited.text = "INT. SOMEWHERE ELSE - NIGHT"
            return edited
        }
        let xml = document.rewrite(script)

        #expect(xml.contains("INT. SOMEWHERE ELSE - NIGHT"))
        #expect(xml.contains("<CharacterArcBeat Name=\"TANGLE\">"))
        #expect(xml.contains("Tangle is obsessed"))
        #expect(xml.contains("Number=\"1\""))
    }

    /// Fountain has no `Shot` and no `General`, so both come back as action.
    /// Rewriting them as Action would be a loss the writer never asked for —
    /// and it is what dropped all twelve `<DualDialogue>` wrappers on a real
    /// production draft, since those live in the whitespace between the
    /// paragraphs being replaced.
    @Test("A kind Fountain cannot carry survives an edit")
    func keepsAFlattenedKind() {
        let xml = """
        <FinalDraft><Content>
        <Paragraph Type="Shot"><Text>CLOSE ON: A GOLD KEY</Text></Paragraph>
        </Content></FinalDraft>
        """
        let document = Fdx.open(xml)
        #expect(document.script.elements.first?.type == .shot)

        // What the editor gives back after a Fountain round trip: action.
        let out = document.rewrite(Screenplay(titlePage: [], elements: [
            ScreenplayElement(type: .action, text: "CLOSE ON: A SILVER KEY")
        ]))
        #expect(out.contains("Type=\"Shot\""))
        #expect(out.contains("CLOSE ON: A SILVER KEY"))
    }

    /// A kind Fountain *can* carry is the writer's to change.
    @Test("A kind the writer really did change is written")
    func writesARealKindChange() {
        let xml = """
        <FinalDraft><Content>
        <Paragraph Type="Action" id="k1"><Text>MARA</Text></Paragraph>
        </Content></FinalDraft>
        """
        let document = Fdx.open(xml)
        let out = document.rewrite(Screenplay(titlePage: [], elements: [
            ScreenplayElement(type: .character, text: "MARA")
        ]))
        #expect(out.contains("Type=\"Character\""))
        #expect(out.contains("id=\"k1\""))
    }

    @Test("A file with nothing to preserve is written whole")
    func nothingToPreserve() {
        let document = Fdx.open("not xml at all")
        let xml = document.rewrite(
            Screenplay(titlePage: [], elements: [
                ScreenplayElement(type: .action, text: "A fresh start.")
            ])
        )
        #expect(xml.contains("<FinalDraft"))
        #expect(xml.contains("A fresh start."))
    }
}

/// End of Act through a save.
///
/// The import absorbs End of Act (RFC-ACT-BREAK D3), so no element stands for
/// it. Left to the alignment, every save deleted the card — and a card with
/// no Alignment, typed General, was paired with the writer's next edit and
/// given their text. The save now keeps each card verbatim in front of the
/// next paragraph it keeps, or after the last element when none is left.
@Suite("FDX preserving round trip · End of Act")
struct FdxEndOfActRoundTripTests {

    private static let corpus: FdxCorpus.Root = {
        do { return try FixtureStore.load("fdx.json") }
        catch {
            Issue.record("Failed to load fdx.json: \(error)")
            return FdxCorpus.Root(importCases: [], exportCases: [])
        }
    }()

    /// A real feature, anonymised, with one End of Act card near its end.
    private static let sample: String = {
        do {
            return try String(
                contentsOf: FixtureStore.directory.appendingPathComponent("sample0-2.fdx"),
                encoding: .utf8
            )
        } catch {
            Issue.record("Failed to load sample0-2.fdx: \(error)")
            return ""
        }
    }()

    @Test("corpus loads non-empty")
    func corpusLoads() {
        #expect(Self.corpus.rewriteCases.count == 69)
    }

    @Test("rewrite", arguments: Self.corpus.rewriteCases)
    func rewrite(_ case_: FdxCorpus.RewriteCase) throws {
        let source = try case_.xml()
        let document = Fdx.open(source)
        let notes = case_.notes?.writing()
        let saved: String
        if case_.through == "fountain" {
            let reading = try FountainReading.of(source)
            if let edit = case_.edit {
                let text = FountainReading.source(of: source)
                #expect(text.components(separatedBy: edit.find).count == 2, "\(case_.name): the edit must occur once")
                let edited = try Fountain.parse(text.replacingOccurrences(of: edit.find, with: edit.replace), emphasis: .runs)
                saved = document.rewrite(edited, unedited: reading, notes: notes)
            } else {
                saved = document.rewrite(reading, unedited: reading, notes: notes)
            }
        } else {
            saved = document.rewrite(case_.screenplay ?? document.script, unedited: case_.unedited, notes: notes)
        }
        if let xml = case_.expected.xml {
            #expect(saved == xml, "\(case_.name): the save differs from the TypeScript engine")
        }
        #expect(case_.expected.xml != nil || case_.expected.identical != nil || case_.expected.changed != nil,
                "\(case_.name): nothing expected")
        if let changed = case_.expected.changed {
            let ranges = case_.expected.scriptNoteRanges
            if let ranges {
                #expect(ScriptNoteRanges.of(saved) == ranges, "\(case_.name): ScriptNote Ranges differ from the TypeScript engine")
            }
            let file = Array((ranges == nil ? source : ScriptNoteRanges.emptied(source)).utf16)
            let written = Array((ranges == nil ? saved : ScriptNoteRanges.emptied(saved)).utf16)
            let end = changed.at + changed.removed.utf16.count
            #expect(Array(file[changed.at..<end]) == Array(changed.removed.utf16), "\(case_.name): removed")
            #expect(written == Array(file[..<changed.at]) + Array(changed.inserted.utf16) + Array(file[end...]),
                    "\(case_.name): the save differs from the TypeScript engine")
        }
        if let identical = case_.expected.identical {
            #expect((saved == source) == identical,
                    "\(case_.name): the TypeScript engine says identical is \(identical)")
        }
    }

    @Test("A save with no edit returns the feature byte for byte, its End of Act included")
    func featureNoOpIsIdentical() {
        let document = Fdx.open(Self.sample)
        #expect(Self.sample.contains("Type=\"End of Act\" id="))
        #expect(document.rewrite(document.script) == Self.sample)
    }

    @Test("A card with no Alignment never takes the writer's edit")
    func bareCardKeepsItsBytes() throws {
        let card = "<Paragraph Type=\"End of Act\"><Text>END OF ACT ONE</Text></Paragraph>"
        let xml = """
        <FinalDraft><Content>
        <Paragraph Type="New Act"><Text>ACT ONE</Text></Paragraph>
        \(card)
        <Paragraph Type="New Act"><Text>ACT TWO</Text></Paragraph>
        <Paragraph Type="Action" id="a2"><Text>Buzz.</Text></Paragraph>
        </Content></FinalDraft>
        """
        let document = Fdx.open(xml)
        var script = document.script
        let index = try #require(script.elements.firstIndex { $0.text == "Buzz." })
        script.elements[index].text = "Buzz, buzz."
        let saved = document.rewrite(script)

        #expect(saved.contains(card))
        #expect(saved.contains("<Paragraph Type=\"Action\" id=\"a2\"><Text>Buzz, buzz.</Text></Paragraph>"))
        #expect(!saved.contains("Type=\"End of Act\"><Text>Buzz"))
    }

    /// Every byte outside the edited paragraph matches the original — for
    /// lines across the feature, and for both paragraphs beside its card.
    @Test("An edit changes bytes only inside the paragraph that was edited",
          arguments: [0, 6, 9, 17, 298, 536, 764, 765, 766, 767])
    func editIsConfined(_ index: Int) {
        let document = Fdx.open(Self.sample)
        var script = document.script
        let marker = "EDITED \(index)"
        script.elements[index].text = marker
        // Range values set aside: a save moves the Ranges whose words moved (IL-0033).
        let original = Array(ScriptNoteRanges.emptied(Self.sample).utf8)
        let saved = Array(ScriptNoteRanges.emptied(document.rewrite(script)).utf8)

        let shorter = min(original.count, saved.count)
        var prefix = 0
        while prefix < shorter, original[prefix] == saved[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < shorter - prefix,
              original[original.count - 1 - suffix] == saved[saved.count - 1 - suffix] {
            suffix += 1
        }
        let removed = String(decoding: original[prefix..<(original.count - suffix)], as: UTF8.self)
        let added = String(decoding: saved[prefix..<(saved.count - suffix)], as: UTF8.self)
        #expect(!removed.contains("Paragraph") && !added.contains("Paragraph"),
                "element \(index): the save changed bytes outside the edited paragraph")
        let window = saved[max(0, prefix - marker.utf8.count)..<min(saved.count, saved.count - suffix + marker.utf8.count)]
        #expect(String(decoding: window, as: UTF8.self).contains(marker),
                "element \(index): the change is not where the edit is")
    }
}

/// The file as the app's editor first holds it: carried through Fountain,
/// casing applied the way `ScreenplayFile.open` applies it, and read back.
/// A file's ScriptNote Range values, in note order, and the file with each one
/// emptied — so a change to the script is read apart from the Ranges a save
/// moves to keep every note on its words (IL-0033).
enum ScriptNoteRanges {
    private static let pattern = try! NSRegularExpression(pattern: #"(<ScriptNote\b[^>]*?\sRange=")([^"]*)(")"#)

    static func of(_ xml: String) -> [String] {
        let text = xml as NSString
        return pattern.matches(in: xml, range: NSRange(location: 0, length: text.length))
            .map { text.substring(with: $0.range(at: 2)) }
    }

    static func emptied(_ xml: String) -> String {
        pattern.stringByReplacingMatches(
            in: xml, range: NSRange(location: 0, length: (xml as NSString).length), withTemplate: "$1$3"
        )
    }
}

enum FountainReading {
    /// The file as the app's editor first holds it: its Fountain source…
    static func source(of xml: String) -> String {
        var imported = Fdx.parse(xml).script
        imported.elements = imported.elements.map { element in
            var element = element
            element.text = Normalize.canonicalCasing(kind: element.type, text: element.text)
            return element
        }
        return Fountain.serialise(imported)
    }

    /// …and that source read back.
    static func of(_ xml: String) throws -> Screenplay {
        try Fountain.parse(source(of: xml), emphasis: .runs)
    }
}

/// Files Final Draft itself wrote.
///
/// The no-edit proof above runs on a file an old eDraft save had already
/// stripped of its production tags, so it could not fail — and a save that
/// lost 400 of 407 tags passed it. These fixtures are anonymised copies of
/// files Final Draft wrote, still carrying everything a careless save loses,
/// and the guard refuses any fixture that does not.
@Suite("FDX preserving round trip · files Final Draft wrote")
struct FdxFinalDraftWrittenTests {

    static let files = ["finaldraft-sample02.fdx", "finaldraft-sample01.fdx"]

    private static func fixture(_ name: String) -> String {
        do {
            return try String(contentsOf: FixtureStore.directory.appendingPathComponent(name), encoding: .utf8)
        } catch {
            Issue.record("Failed to load \(name): \(error)")
            return ""
        }
    }

    /// What a no-edit proof on a file depends on, counted (TypeScript `hazards`).
    struct Hazards: Equatable, CustomStringConvertible {
        var eDraftNamespace = false
        var bareParagraphLines = 0
        var taggedRuns = 0
        var revisionRuns = 0
        var adornmentSplits = 0
        var dualDialogue = 0
        var omittedScenes = 0
        var endOfAct = 0
        var emphasisedHeadings = 0
        var italicParentheticals = 0
        var multiLineParagraphs = 0
        var trailingSpaces = 0
        var astral = 0

        var description: String {
            "tags \(taggedRuns) · revisions \(revisionRuns) · adornment splits \(adornmentSplits) · dual \(dualDialogue) · omitted \(omittedScenes) · end of act \(endOfAct) · emphasised headings \(emphasisedHeadings) · italic parentheticals \(italicParentheticals) · multi-line \(multiLineParagraphs) · trailing spaces \(trailingSpaces) · astral \(astral) · eDraft namespace \(eDraftNamespace) · bare lines \(bareParagraphLines)"
        }

        init() {}

        init(_ xml: String) {
            let elements = Fdx.parse(xml).script.elements
            let runs = elements.flatMap { $0.runs ?? [] }
            func count(_ pattern: String, lines: Bool = false) -> Int {
                let regex = try! NSRegularExpression(pattern: pattern, options: lines ? [.anchorsMatchLines] : [])
                return regex.numberOfMatches(in: xml, range: NSRange(xml.startIndex..., in: xml))
            }
            func styled(_ kind: ElementKind, _ styles: StyleSet) -> Int {
                elements.filter { element in
                    element.type == kind && (element.runs ?? []).contains { !$0.styles.intersection(styles).isEmpty }
                }.count
            }
            eDraftNamespace = xml.contains("xmlns:EDraft")
            bareParagraphLines = count(#"^\s*<Paragraph Type="[^"]+"><Text>"#, lines: true)
            taggedRuns = runs.filter { !($0.tagNumbers ?? []).isEmpty }.count
            revisionRuns = runs.filter { $0.revisionID != nil }.count
            adornmentSplits = count(#"<Text [^>]*AdornmentStyle="-1""#)
            dualDialogue = count("<DualDialogue>")
            omittedScenes = count("<OmittedScene>")
            endOfAct = count(#"<Paragraph [^>]*Type="End of Act""#)
            emphasisedHeadings = styled(.scene, [.bold, .italic])
            italicParentheticals = styled(.parenthetical, .italic)
            multiLineParagraphs = elements.filter { $0.text.contains("\n") }.count
            trailingSpaces = elements.filter { $0.text.hasSuffix(" ") }.count
            astral = elements.filter { $0.text.utf16.contains { (0xD800...0xDBFF).contains($0) } }.count
        }
    }

    static let required: [String: Hazards] = {
        var sample02 = Hazards()
        sample02.taggedRuns = 394; sample02.revisionRuns = 98; sample02.adornmentSplits = 10
        sample02.dualDialogue = 6; sample02.omittedScenes = 1; sample02.endOfAct = 1
        sample02.emphasisedHeadings = 1; sample02.italicParentheticals = 2; sample02.trailingSpaces = 9
        var sample01 = Hazards()
        sample01.revisionRuns = 2; sample01.adornmentSplits = 3; sample01.dualDialogue = 6
        sample01.endOfAct = 1; sample01.emphasisedHeadings = 1; sample01.italicParentheticals = 2
        sample01.multiLineParagraphs = 1; sample01.trailingSpaces = 3; sample01.astral = 4
        return ["finaldraft-sample02.fdx": sample02, "finaldraft-sample01.fdx": sample01]
    }()

    /// Why a file cannot stand as a fidelity fixture — nothing, when it can.
    static func provenanceProblems(_ xml: String, required: Hazards) -> [String] {
        let found = Hazards(xml)
        var problems: [String] = []
        if found.eDraftNamespace || found.bareParagraphLines > 0 { problems.append("carries eDraft save marks") }
        if found != required { problems.append("hazards: \(found), needs \(required)") }
        return problems
    }

    private static func tags(_ xml: String) -> Int {
        xml.components(separatedBy: "TagNumber=\"").count - 1
    }

    /// Every byte outside one paragraph matches: the changed stretch holds no
    /// boundary between two of the script's paragraphs, which Final Draft
    /// indents four spaces (TypeScript `confinedToOneParagraph`).
    private static func confinedToOneParagraph(_ before: String, _ after: String, marker: String) -> Bool {
        // Range values set aside: a save moves the Ranges whose words moved (IL-0033).
        let original = Array(ScriptNoteRanges.emptied(before).utf16)
        let saved = Array(ScriptNoteRanges.emptied(after).utf16)
        let shorter = min(original.count, saved.count)
        var prefix = 0
        while prefix < shorter, original[prefix] == saved[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < shorter - prefix, original[original.count - 1 - suffix] == saved[saved.count - 1 - suffix] {
            suffix += 1
        }
        let boundary = try! NSRegularExpression(pattern: #"</Paragraph>\s*\n {4}<Paragraph[ >]|\n {4}<Paragraph[ >][\s\S]*\n {4}<Paragraph[ >]"#)
        func crosses(_ units: ArraySlice<UInt16>) -> Bool {
            let text = String(decoding: units, as: UTF16.self)
            return boundary.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        let window = saved[max(0, prefix - marker.utf16.count)..<min(saved.count, saved.count - suffix + marker.utf16.count)]
        return !crosses(original[prefix..<(original.count - suffix)])
            && !crosses(saved[prefix..<(saved.count - suffix)])
            && String(decoding: window, as: UTF16.self).contains(marker)
    }

    @Test("Each fixture is a file Final Draft wrote, with everything the proofs depend on", arguments: files)
    func provenance(_ name: String) throws {
        let required = try #require(Self.required[name])
        #expect(Self.provenanceProblems(Self.fixture(name), required: required).isEmpty,
                "\(name): \(Self.provenanceProblems(Self.fixture(name), required: required))")
    }

    @Test("The guard turns away a file eDraft has saved")
    func guardRejectsASavedFile() throws {
        let required = try #require(Self.required["finaldraft-sample02.fdx"])
        let problems = Self.provenanceProblems(Self.fixture("sample0-2.fdx"), required: required)
        #expect(problems.contains("carries eDraft save marks"))
        #expect(problems.count == 2)
    }

    @Test("A save with no edit returns the file byte for byte", arguments: files)
    func engineNoOp(_ name: String) {
        let xml = Self.fixture(name)
        let document = Fdx.open(xml)
        #expect(document.rewrite(document.script) == xml)
    }

    @Test("So does a save through Fountain with no edit, given the unedited reading", arguments: files)
    func fountainNoOp(_ name: String) throws {
        let xml = Self.fixture(name)
        let reading = try FountainReading.of(xml)
        #expect(Fdx.open(xml).rewrite(reading, unedited: reading) == xml)
    }

    @Test("Without the unedited reading, that same save loses the tags — the leak this closes")
    func withoutTheReadingTagsAreLost() throws {
        let xml = Self.fixture("finaldraft-sample02.fdx")
        let saved = Fdx.open(xml).rewrite(try FountainReading.of(xml))
        #expect(Self.tags(saved) < Self.tags(xml) / 2)
    }

    @Test("An edit through Fountain changes bytes only inside the edited paragraph",
          arguments: [0, 6, 19, 42, 150, 336, 520, 700, 760, 761])
    func fountainEditIsConfined(_ index: Int) throws {
        let xml = Self.fixture("finaldraft-sample02.fdx")
        let reading = try FountainReading.of(xml)
        var edited = reading
        let marker = "EDITED \(index)"
        edited.elements[index].text = marker
        #expect(Self.confinedToOneParagraph(xml, Fdx.open(xml).rewrite(edited, unedited: reading), marker: marker),
                "element \(index): the save changed bytes outside the edited paragraph")
    }

    @Test("An edit through the engine changes bytes only inside the edited paragraph",
          arguments: [0, 21, 300, 823])
    func engineEditIsConfined(_ index: Int) {
        let xml = Self.fixture("finaldraft-sample01.fdx")
        let document = Fdx.open(xml)
        var edited = document.script
        let marker = "EDITED \(index)"
        edited.elements[index].text = marker
        #expect(Self.confinedToOneParagraph(xml, document.rewrite(edited), marker: marker),
                "element \(index): the save changed bytes outside the edited paragraph")
    }

    /* An edited paragraph is merged, not rewritten (IL-0028). The measured
       cases are corpus cases (`merged-*`), saved here through this engine's
       own Fountain and held to the TypeScript engine's bytes; this sweeps the
       rule across both files (TypeScript: the same sweep). */
    @Test("An edit anywhere changes bytes only inside the runs it falls in", arguments: files)
    func editIsConfinedToItsRuns(_ name: String) throws {
        let xml = Self.fixture(name)
        let file = Array(xml.utf16)
        let source = Array(FountainReading.source(of: xml).utf16)
        let reading = try Fountain.parse(String(decoding: source, as: UTF16.self), emphasis: .runs)
        let runs = try NSRegularExpression(pattern: #"\s*<Text\b[^>]*?(?:/>|>[^<]*</Text>)"#)
            .matches(in: xml, range: NSRange(location: 0, length: file.count)).map(\.range)
        let letters: Set<UInt16> = [UInt16(UInt8(ascii: "x")), UInt16(UInt8(ascii: "X"))]
        let between = (1..<source.count).filter { letters.contains(source[$0 - 1]) && letters.contains(source[$0]) }
        var proven = 0
        for at in stride(from: 0, to: between.count, by: between.count / 16) {
            let position = between[at]
            let typed = source[position] == UInt16(UInt8(ascii: "X")) ? "QZ" : "qz"
            let edited = try Fountain.parse(
                String(decoding: source[..<position], as: UTF16.self) + typed + String(decoding: source[position...], as: UTF16.self),
                emphasis: .runs
            )
            guard edited.elements.count == reading.elements.count,
                  zip(edited.elements, reading.elements).filter({ !$0.text.utf16.elementsEqual($1.text.utf16) }).count == 1,
                  zip(edited.elements, reading.elements).allSatisfy({ $0.type == $1.type }) else { continue }

            // Range values set aside, which their notes' words are proven by; a Range value holds no run.
            let saved = Array(ScriptNoteRanges.emptied(Fdx.open(xml).rewrite(edited, unedited: reading)).utf16)
            let file = Array(ScriptNoteRanges.emptied(xml).utf16)
            var prefix = 0
            while prefix < min(file.count, saved.count), file[prefix] == saved[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < file.count - prefix, suffix < saved.count - prefix,
                  file[file.count - 1 - suffix] == saved[saved.count - 1 - suffix] { suffix += 1 }
            let from = prefix
            let to = max(file.count - suffix, prefix + 1)
            let touched = runs.filter { $0.location < to && $0.location + $0.length > from }
            #expect((1...2).contains(touched.count), "\(name) at \(position): \(touched.count) runs changed")
            if touched.count == 2 {
                #expect(touched[1].location == touched[0].location + touched[0].length, "\(name) at \(position): runs apart")
            }
            #expect(String(decoding: saved[prefix..<(saved.count - suffix)], as: UTF16.self).contains(typed))
            #expect(Self.tags(String(decoding: saved, as: UTF16.self)) >= Self.tags(xml))
            proven += 1
        }
        #expect(proven >= 10, "\(name): only \(proven) positions proven")
    }

    /* IL-0032: Final Draft keeps dual dialogue as a paragraph with no text of
       its own holding a <DualDialogue>, its paragraphs the two speeches. Read
       as metadata, all 48 lines in these two files were invisible
       (TypeScript: the same proofs; the save cases are corpus cases). */

    /// Each dual dialogue in the file: its lines as (type, text).
    private static func dualDialogueLines(_ xml: String) -> [[(type: String, text: String)]] {
        let block = try! NSRegularExpression(pattern: #"<DualDialogue>([\s\S]*?)</DualDialogue>"#)
        let line = try! NSRegularExpression(pattern: #"\n {8}<Paragraph Type="([^"]+)"[^>]*>([\s\S]*?)\n {8}</Paragraph>"#)
        let run = try! NSRegularExpression(pattern: #"<Text[^>]*>([^<]*)</Text>"#)
        let whole = xml as NSString
        return block.matches(in: xml, range: NSRange(location: 0, length: whole.length)).map { match in
            let inner = whole.substring(with: match.range(at: 1)) as NSString
            return line.matches(in: inner as String, range: NSRange(location: 0, length: inner.length)).map { paragraph in
                let body = inner.substring(with: paragraph.range(at: 2)) as NSString
                let text = run.matches(in: body as String, range: NSRange(location: 0, length: body.length))
                    .map { Fdx.decodeXmlEntities(body.substring(with: $0.range(at: 1))) }
                    .joined()
                return (inner.substring(with: paragraph.range(at: 1)).lowercased(), text)
            }
        }
    }

    @Test("Every line of every dual dialogue is in the script, the second cue dual", arguments: files)
    func dualDialogueIsRead(_ name: String) {
        let xml = Self.fixture(name)
        let result = Fdx.parse(xml)
        let blocks = Self.dualDialogueLines(xml)
        #expect(blocks.count == 6)
        #expect(result.diagnostics.isEmpty)
        #expect(!result.script.elements.contains { $0.type == .general && $0.text.isEmpty })
        let dualCues = result.script.elements.indices.filter { result.script.elements[$0].dual == true }
        #expect(dualCues.count == 6)
        for (block, cue) in zip(blocks, dualCues) {
            let lines = Array(result.script.elements[(cue - 2)..<(cue - 2 + block.count)])
            #expect(lines.map { "\($0.type.rawValue)|\($0.text)" } == block.map { "\($0.type)|\($0.text)" })
            #expect(lines.map { $0.dual ?? false } == [false, false, true, false])
        }
    }

    @Test("A typo in any dual dialogue line changes that one character, inside its block", arguments: files)
    func dualDialogueTypos(_ name: String) throws {
        let xml = Self.fixture(name)
        let file = Array(xml.utf16)
        let reading = try FountainReading.of(xml)
        let dualCues = reading.elements.indices.filter { reading.elements[$0].dual == true }
        #expect(dualCues.count == 6)
        let blockPattern = try NSRegularExpression(pattern: #"<DualDialogue>[\s\S]*?</DualDialogue>"#)
        let blocks = blockPattern.matches(in: xml, range: NSRange(location: 0, length: file.count)).map(\.range)
        for cue in dualCues {
            for line in [cue - 2, cue - 1, cue, cue + 1] {
                var edited = reading
                edited.elements[line].text = "Q" + String(edited.elements[line].text.dropFirst())
                let saved = Array(Fdx.open(xml).rewrite(edited, unedited: reading).utf16)
                var at = 0
                while at < file.count, file[at] == saved[at] { at += 1 }
                #expect(saved == Array(file[..<at]) + Array("Q".utf16) + Array(file[(at + 1)...]),
                        "\(name) line \(line): more than one character changed")
                #expect(blocks.contains { $0.location < at && at < $0.location + $0.length })
            }
        }
    }

    @Test("Reads each line of a dual dialogue exactly as a body paragraph, the second cue dual")
    func dualDialogueLinesRead() {
        let result = Fdx.parse(#"<FinalDraft><Content><Paragraph Type="Action"><Text>Hum.</Text></Paragraph><Paragraph Type="General"><DualDialogue><Paragraph Type="Character"><Text>MARA</Text></Paragraph><Paragraph Type="Dialogue"><Text>Yes.</Text></Paragraph><Paragraph Type="Character"><Text TagNumber="4">JON</Text></Paragraph><Paragraph Type="Parenthetical"><Text>(beat)</Text></Paragraph><Paragraph Type="Dialogue"><Text>No.</Text></Paragraph></DualDialogue></Paragraph><Paragraph Type="Action"><Text>Go.</Text></Paragraph></Content></FinalDraft>"#)
        #expect(result.diagnostics.isEmpty)
        #expect(result.script.elements == [
            ScreenplayElement(type: .action, text: "Hum."),
            ScreenplayElement(type: .character, text: "MARA"),
            ScreenplayElement(type: .dialogue, text: "Yes."),
            ScreenplayElement(type: .character, text: "JON",
                              runs: [StyleRun(start: 0, end: 3, styles: [], tagNumbers: [4])], dual: true),
            ScreenplayElement(type: .parenthetical, text: "(beat)"),
            ScreenplayElement(type: .dialogue, text: "No."),
            ScreenplayElement(type: .action, text: "Go."),
        ])
    }

    @Test("Dual dialogue in any other form is read as before, and reported")
    func dualDialogueNotRead() {
        let block = #"<DualDialogue><Paragraph Type="Character"><Text>MARA</Text></Paragraph><Paragraph Type="Dialogue"><Text>Yes.</Text></Paragraph><Paragraph Type="Character"><Text>JON</Text></Paragraph><Paragraph Type="Dialogue"><Text>No.</Text></Paragraph></DualDialogue>"#
        let result = Fdx.parse(#"<FinalDraft><Content><Paragraph Type="General"><Text>Look:</Text>"# + block + #"</Paragraph><Paragraph Type="General">"# + block + block + "</Paragraph></Content></FinalDraft>")
        #expect(result.script.elements == [
            ScreenplayElement(type: .general, text: "Look:"),
            ScreenplayElement(type: .general, text: ""),
        ])
        #expect(result.diagnostics.map(\.code) == ["FDX_DUAL_DIALOGUE_NOT_READ", "FDX_DUAL_DIALOGUE_NOT_READ"])
        #expect(result.diagnostics.map(\.paragraphIndex) == [0, 1])
    }
}
