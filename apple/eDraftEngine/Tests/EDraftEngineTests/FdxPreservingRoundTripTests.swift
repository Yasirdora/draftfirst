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
        #expect(Self.corpus.rewriteCases.count == 39)
    }

    @Test("rewrite", arguments: Self.corpus.rewriteCases)
    func rewrite(_ case_: FdxCorpus.RewriteCase) throws {
        let source = try case_.xml()
        let document = Fdx.open(source)
        let saved: String
        if case_.through == "fountain" {
            let reading = try FountainReading.of(source)
            if let edit = case_.edit {
                let text = FountainReading.source(of: source)
                #expect(text.components(separatedBy: edit.find).count == 2, "\(case_.name): the edit must occur once")
                let edited = try Fountain.parse(text.replacingOccurrences(of: edit.find, with: edit.replace), emphasis: .runs)
                saved = document.rewrite(edited, unedited: reading)
            } else {
                saved = document.rewrite(reading, unedited: reading)
            }
        } else {
            saved = document.rewrite(case_.screenplay ?? document.script, unedited: case_.unedited)
        }
        if let xml = case_.expected.xml {
            #expect(saved == xml, "\(case_.name): the save differs from the TypeScript engine")
        }
        #expect(case_.expected.xml != nil || case_.expected.identical != nil || case_.expected.changed != nil,
                "\(case_.name): nothing expected")
        if let changed = case_.expected.changed {
            let file = Array(source.utf16)
            let end = changed.at + changed.removed.utf16.count
            #expect(Array(file[changed.at..<end]) == Array(changed.removed.utf16), "\(case_.name): removed")
            #expect(Array(saved.utf16) == Array(file[..<changed.at]) + Array(changed.inserted.utf16) + Array(file[end...]),
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
        let original = Array(Self.sample.utf8)
        let saved = Array(document.rewrite(script).utf8)

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
        sample02.taggedRuns = 392; sample02.revisionRuns = 98; sample02.adornmentSplits = 10
        sample02.dualDialogue = 6; sample02.omittedScenes = 1; sample02.endOfAct = 1
        sample02.emphasisedHeadings = 1; sample02.italicParentheticals = 2; sample02.trailingSpaces = 1
        var sample01 = Hazards()
        sample01.revisionRuns = 2; sample01.adornmentSplits = 3; sample01.dualDialogue = 6
        sample01.endOfAct = 1; sample01.emphasisedHeadings = 1; sample01.italicParentheticals = 2
        sample01.multiLineParagraphs = 1; sample01.trailingSpaces = 1; sample01.astral = 4
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
        let original = Array(before.utf16)
        let saved = Array(after.utf16)
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

            let saved = Array(Fdx.open(xml).rewrite(edited, unedited: reading).utf16)
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
}
