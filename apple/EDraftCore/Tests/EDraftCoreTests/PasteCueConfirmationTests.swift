import XCTest
@testable import EDraftCore
@testable import EDraftEngine

/// Cue confirmation on the paste route (mirrored from the TypeScript
/// engine's confirmCues, classify.ts): a pasted cue keeps its character
/// kind only when speech follows it. The witnesses are the corpus's own —
/// lalaland's WINTER cards, breaking-bad's HANK, whiplash's fused studio
/// core member, corpus-6's ELI, episode-101's cast table. The writer
/// reported the class from a PDF paste: the season cards and the title
/// were posing as speakers in the cast panel.
///
/// Element counts below are the routes' own truth: the reassembled route
/// keeps one element per joined paragraph, the raw route one per source
/// line, and the planner never merges — demotion retypes, it never drops.
@MainActor
final class PasteCueConfirmationTests: XCTestCase {

    /// The route the surfaces take: a paste's signal-less line falls back
    /// to prose (a paste is not typing).
    private func paste(_ source: String) -> [ScriptElement] {
        ScreenplayEditPlanner.plan(
            elements: [ScriptElement(type: .action, text: "")],
            replacing: NSRange(location: 0, length: 0),
            with: source,
            intent: .multilinePaste,
            kindForNewElement: { previous, text, depth, attached in
                EditorState(source: "").kindForInsertedElement(
                    after: previous, text: text, pasteDepth: depth,
                    attached: attached, fallback: .action
                )
            }
        )?.elements ?? []
    }

    /// lalaland's WINTER: a season card and the prose under it all become
    /// action — every word survives, the false speaker leaves the cast.
    func testASeasonCardAndItsProseBlockBecomeAction() {
        let elements = paste([
            "Flash title card:",
            "WINTER",
            "We settle on a new car. A 1983 Dodge Riviera. In it is",
            "SEBASTIAN, 32, L.A. native. He’s listening to the radio. He’s",
            "playing a track on his music system -- a tape of Thelonious",
            "Monk’s “Japanese Folk Song”. But he keeps stopping it, over",
            "INT. AUDITION ROOMS - DAY",
            "Mia auditions. Pilot season cattle-call -- a series of soul-"
        ].joined(separator: "\n"))

        XCTAssertEqual(
            elements.map(\.type),
            [.action, .action, .action, .scene, .action],
            "the card, its prose block, the heading and the heading's action — each its own element"
        )
        XCTAssertEqual(elements[1].text, "WINTER", "the card's word survives as action")
        XCTAssertTrue(elements[2].text.contains("We settle on a new car."), "the prose survives with it")
    }

    /// A cue directly above a heading introduced no speech (lalaland's
    /// SPRING over OMIT/INT.): the card becomes what it is — action.
    func testACueAboveASceneIsNoSpeaker() {
        let elements = paste([
            "SPRING",
            "INT. AUDITION ROOMS - DAY",
            "Mia auditions. Pilot season cattle-call -- a series of soul-",
            "crushing disappointments, each one a little death of its own,",
            "and the room barely looks up at her at all today either."
        ].joined(separator: "\n"))

        XCTAssertEqual(
            elements.map(\.type),
            [.action, .scene, .action, .action, .action]
        )
    }

    /// The paste's own end is the cue's end: a closing card answers to
    /// nothing beneath it. (lalaland's own closing line is "IRIS FADE
    /// OUT." — the IRIS family is a transition shape the paste route does
    /// not read yet; named in the corpus plan, not this rule's ground.)
    func testACueThePasteEndsUnderIsNoSpeaker() {
        let elements = paste([
            "CUT TO:",
            "THE END"
        ].joined(separator: "\n"))

        XCTAssertEqual(elements.map(\.type), [.transition, .action])
    }

    /// A narrow speech confirms its cue — the everyday case must never move.
    func testARealSpeechKeepsItsCue() {
        let elements = paste([
            "MARA",
            "We need to talk.",
            "JONAH",
            "About what?"
        ].joined(separator: "\n"))

        XCTAssertEqual(
            elements.map(\.type),
            [.character, .dialogue, .character, .dialogue]
        )
    }

    /// breaking-bad's HANK: a wide line that closes its sentence is a
    /// complete utterance, however wide it runs.
    func testAWideLineClosingItsSentenceKeepsItsCue() {
        let elements = paste([
            "HANK",
            "You’re not listening to me, and I am done here."
        ].joined(separator: "\n"))

        XCTAssertEqual(elements.map(\.type), [.character, .dialogue])
    }

    /// corpus-6's ELI: a wide scan line opening with an ellipsis continues
    /// a sentence from above — it is not prose rejoining the margin.
    func testAWideLineOpeningWithAnEllipsisKeepsItsCue() {
        let elements = paste([
            "ELI",
            "... that’s enough now ... that’s enough ... he mu",
            "take the Holy Spirit in on his own now-.",
            "INT. CHURCH - DAY",
            "The congregation settles into the hard wooden pews and the"
        ].joined(separator: "\n"))

        XCTAssertEqual(
            elements.map(\.type),
            [.character, .dialogue, .dialogue, .scene, .action]
        )
    }

    /// whiplash's STUDIO CORE MEMBER #3: one fused scan line with a narrow
    /// second wrap is one long breath, not prose — and the next speaker
    /// under it keeps his own cue.
    func testAFusedLineWithANarrowSecondWrapKeepsItsCue() {
        let elements = paste([
            "STUDIO CORE MEMBER #3",
            "I don’t care what you think of me, or how many cheeseburgers",
            "you had for lunch.",
            "ANDREW",
            "Yes."
        ].joined(separator: "\n"))

        XCTAssertEqual(
            elements.map(\.type),
            [.character, .dialogue, .dialogue, .character, .dialogue]
        )
    }

    /// episode-101's cast table on the reassembled route, where a cue-shaped
    /// row types as a new cue — shape answers first there. MAID, CODY and
    /// THE SHAMAN each sit over a wide dotted-leader description cut off by
    /// the next row (or the paste's end) — demoted. TRAVIS MARTINEZ and
    /// ACOLYTES sit over another bare name row: nothing to measure — kept,
    /// the table's own residue, named rather than hidden.
    func testACastTableKeepsItsBareNameRowsAndDropsItsWideDescriptions() {
        let elements = paste([
            "MAID",
            "VAN’S MOM.....................................DEBORAH VANCELETTE",
            "TRAVIS MARTINEZ",
            "CODY MARTINEZ",
            "FACILITY MANAGER....................................VAN EPPERSON",
            "ACOLYTES",
            "THE SHAMAN",
            "MISTY QUIGLEY....................................CHRISTINA RICCI"
        ].joined(separator: "\n"))

        XCTAssertEqual(
            elements.map(\.type),
            [.action, .action, .character, .action, .action, .character, .action, .action],
            "wide description rows dissolve with the names above them; bare rows over bare rows stand"
        )
        XCTAssertEqual(elements[2].text, "TRAVIS MARTINEZ")
        XCTAssertEqual(elements[5].text, "ACOLYTES")
    }

    /// The raw route (blank-separated, unwrapped paragraphs): a cue whose
    /// single paragraph runs prose-wide with no sentence close, cut by a
    /// heading, is no speaker. The route's honest limit, named: a full
    /// paragraph ending in a period under an all-caps line is genuinely
    /// ambiguous without layout, and stays.
    func testTheRawRouteConfirmsByTheSameRule() {
        let demoted = paste([
            "WINTER",
            "",
            "We settle on a new car. A 1983 Dodge Riviera gleaming in the sun",
            "",
            "INT. AUDITION ROOMS - DAY"
        ].joined(separator: "\n"))
        XCTAssertEqual(demoted.map(\.type), [.action, .action, .scene])

        let kept = paste([
            "WINTER",
            "",
            "We settle on a new car. A 1983 Dodge Riviera gleaming in the sun.",
            "",
            "INT. AUDITION ROOMS - DAY"
        ].joined(separator: "\n"))
        XCTAssertEqual(kept.map(\.type), [.character, .dialogue, .scene])
    }
}
