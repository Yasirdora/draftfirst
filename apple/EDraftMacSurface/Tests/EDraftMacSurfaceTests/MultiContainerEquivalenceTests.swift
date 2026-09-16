import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// Stage 1 of the multi-container migration — the floor, written before the
/// thing it judges. See `docs/RFC-MULTI-CONTAINER-PAGES.md`.
///
/// Two-page mode draws the script through a fold applied at paint time while
/// the layout manager still believes the script is one column, so everything
/// that asks "what is at this point?" gets the column's answer. The fix is
/// the arrangement TextKit is built for: one storage, one layout manager, one
/// container per sheet. Before any production code moves, two things have to
/// be true of that arrangement, and this file is where they are proved.
///
///   1. PAGE STARTS. Each container must begin at exactly the character the
///      ENGINE says begins that page. TextKit fills containers by height and
///      knows nothing of screenplay rules — cues that must not orphan,
///      (MORE)/(CONT'D), heading widows — so left to itself it would break
///      pages the engine does not, and the screen would show a different page
///      number from the PDF. The containers are therefore driven by
///      `ScreenplayPageLayout.pageStartLocations`, and this asserts they obey.
///
///   2. GEOMETRY. Every character must sit at the same place on its page as
///      it does today. Compared as an offset from the first character of the
///      character's own page, because where a *sheet* lands on the canvas is
///      Stage 2's business; what must not move is the type on the paper. One
///      assertion covering the caret, the reveal mark, the format bar and the
///      find rectangles at once.
///
/// A failure here is information, not an obstacle: a divergence names the
/// screenplay rule TextKit cannot express, and the migration gains a
/// requirement instead of a surprise.
@MainActor
final class MultiContainerEquivalenceTests: XCTestCase {

    /// How far two architectures may disagree about a character's place
    /// before it counts as a move. Half a point: well under a hairline, far
    /// under the twelve-point line this type is set on.
    private static let tolerance: CGFloat = 0.5

    // MARK: - The candidate architecture

    /// A container that stops dead at a chosen character.
    ///
    /// The same override point `PageGapContainer` uses for its desk bands —
    /// this project has been steering TextKit this way all along, inside one
    /// container rather than across many. Measured working in the Stage 0
    /// spike; see the RFC §2.1.
    private final class ForcedBreakContainer: NSTextContainer {
        /// The first character this container refuses. `Int.max` on the last.
        nonisolated(unsafe) var breakAt: Int = Int.max

        nonisolated override init(size: CGSize) { super.init(size: size) }
        nonisolated required init(coder: NSCoder) { super.init(coder: coder) }

        nonisolated override func lineFragmentRect(
            forProposedRect proposedRect: CGRect,
            at characterIndex: Int,
            writingDirection baseWritingDirection: NSWritingDirection,
            remaining remainingRect: UnsafeMutablePointer<CGRect>?
        ) -> CGRect {
            if characterIndex >= breakAt {
                remainingRect?.pointee = .zero
                return .zero
            }
            return super.lineFragmentRect(
                forProposedRect: proposedRect,
                at: characterIndex,
                writingDirection: baseWritingDirection,
                remaining: remainingRect
            )
        }
    }

    /// One storage, one layout manager, one container per page, each stopped
    /// at the engine's own page start.
    ///
    /// Configured to match `ScriptSurface.init` exactly — the same measure,
    /// `lineFragmentPadding = 0`, and `FixedLeading` as the layout manager's
    /// delegate. Without that delegate the line box is AppKit's rather than
    /// six-to-the-inch, and this would compare a replica instead of the real
    /// thing.
    private struct Candidate {
        let layoutManager: NSLayoutManager
        let containers: [ForcedBreakContainer]
        /// Held because `NSLayoutManager.delegate` is weak — exactly the
        /// reason `ScriptSurface` holds its own.
        let leading: FixedLeading
        let storage: NSTextStorage
    }

    private func candidate(for elements: [ScriptElement], starts: [Int]) -> Candidate {
        let script = ScriptLayout.attributedScript(elements, measure: ScriptLayout.pageMeasure)
        let storage = NSTextStorage(attributedString: script.text)
        let layoutManager = NSLayoutManager()
        let leading = FixedLeading()
        layoutManager.delegate = leading
        storage.addLayoutManager(layoutManager)

        var containers: [ForcedBreakContainer] = []
        for page in starts.indices {
            let container = ForcedBreakContainer(
                size: CGSize(width: ScriptLayout.pageMeasure, height: .greatestFiniteMagnitude)
            )
            container.widthTracksTextView = false
            container.lineFragmentPadding = 0
            // Set before layout. Assigning it afterwards without
            // `textContainerChangedGeometry` leaves the old layout standing,
            // silently — the Stage 0 spike lost a run to exactly that.
            container.breakAt = page + 1 < starts.count ? starts[page + 1] : Int.max
            layoutManager.addTextContainer(container)
            containers.append(container)
        }
        for container in containers { layoutManager.ensureLayout(for: container) }
        return Candidate(
            layoutManager: layoutManager, containers: containers,
            leading: leading, storage: storage
        )
    }

    /// The characters a container actually holds.
    private func characterRange(
        of container: NSTextContainer, in layoutManager: NSLayoutManager
    ) -> NSRange {
        layoutManager.characterRange(
            forGlyphRange: layoutManager.glyphRange(for: container), actualGlyphRange: nil
        )
    }

    /// One character's rectangle inside its own container.
    private func candidateRect(
        _ location: Int, _ candidate: Candidate, page: Int
    ) -> CGRect? {
        guard page < candidate.containers.count else { return nil }
        let glyphs = candidate.layoutManager.glyphRange(
            forCharacterRange: NSRange(location: location, length: 1), actualCharacterRange: nil
        )
        guard glyphs.length > 0 else { return nil }
        let rect = candidate.layoutManager.boundingRect(
            forGlyphRange: glyphs, in: candidate.containers[page]
        )
        return rect.height > 0 ? rect : nil
    }

    // MARK: - The corpus

    private func scenes(_ count: Int, seed: String) -> [ScriptElement] {
        var elements: [ScriptElement] = []
        for beat in 1...count {
            elements.append(ScriptElement(type: .scene, text: "INT. \(seed) \(beat) - DAY"))
            elements.append(ScriptElement(
                type: .action,
                text: "Action for beat \(beat). The road holds its breath for a full line of the page."
            ))
            elements.append(ScriptElement(type: .character, text: "MARA"))
            elements.append(ScriptElement(
                type: .dialogue,
                text: "Line \(beat), spoken plainly and without hurry at all."
            ))
        }
        return elements
    }

    /// Short elements in bulk, so page boundaries land on many different kinds
    /// of line — a heading last on a page, a cue parted from its dialogue,
    /// a long unbroken speech. The awkward cases are the point.
    private func awkward() -> [ScriptElement] {
        var elements: [ScriptElement] = []
        for beat in 1...40 {
            elements.append(ScriptElement(type: .scene, text: "EXT. LEDGE \(beat) - NIGHT"))
            elements.append(ScriptElement(type: .character, text: "TOM"))
            elements.append(ScriptElement(type: .dialogue, text: "Short."))
            elements.append(ScriptElement(type: .action, text: "Beat."))
            if beat % 5 == 0 {
                elements.append(ScriptElement(type: .character, text: "MARA"))
                elements.append(ScriptElement(
                    type: .dialogue,
                    text: String(repeating: "A long unbroken speech that runs past one line. ", count: 6)
                ))
            }
        }
        return elements
    }

    private func corpus() -> [(name: String, elements: [ScriptElement])] {
        [
            ("one page", scenes(3, seed: "ROOM")),
            ("four pages", scenes(25, seed: "ROOM")),
            ("ten pages", scenes(60, seed: "HALL")),
            ("awkward boundaries", awkward()),
        ]
    }

    /// The engine's own page starts — the authority the containers must obey.
    private func engineStarts(_ elements: [ScriptElement]) throws -> [Int] {
        let pages = try XCTUnwrap(
            ScreenplayExporter.paginate(Screenplay(elements: elements)),
            "the engine must paginate the corpus"
        )
        return ScreenplayPageLayout.pageStartLocations(elements: elements, pages: pages)
    }

    /// Which page holds a character, from the engine's starts.
    private func page(of location: Int, in starts: [Int]) -> Int {
        var page = 0
        while page + 1 < starts.count, starts[page + 1] <= location { page += 1 }
        return page
    }

    // MARK: - 1. Page starts

    func testEveryContainerBeginsWhereTheEngineSaysThePageBegins() throws {
        for (name, elements) in corpus() {
            let starts = try engineStarts(elements)
            XCTAssertFalse(starts.isEmpty, "\(name): the engine produced no pages")
            let built = candidate(for: elements, starts: starts)

            XCTAssertEqual(
                built.containers.count, starts.count,
                "\(name): one container per page"
            )

            for (page, container) in built.containers.enumerated() {
                let held = characterRange(of: container, in: built.layoutManager)
                XCTAssertEqual(
                    held.location, starts[page],
                    "\(name), page \(page + 1): container begins at character \(held.location), "
                        + "the engine says \(starts[page])"
                )
                if page + 1 < starts.count {
                    XCTAssertEqual(
                        NSMaxRange(held), starts[page + 1],
                        "\(name), page \(page + 1): container ends at \(NSMaxRange(held)), "
                            + "the next page begins at \(starts[page + 1])"
                    )
                }
            }
        }
    }

    /// The containers must between them hold the whole script exactly once —
    /// a break that silently drops or repeats text would satisfy the starts
    /// and still lose a scene.
    func testTheContainersHoldTheWholeScriptExactlyOnce() throws {
        for (name, elements) in corpus() {
            let starts = try engineStarts(elements)
            let built = candidate(for: elements, starts: starts)
            let length = built.storage.length

            var covered = 0
            for container in built.containers {
                covered += characterRange(of: container, in: built.layoutManager).length
            }
            XCTAssertEqual(
                covered, length,
                "\(name): containers hold \(covered) characters of \(length)"
            )
        }
    }

    // MARK: - 2. Geometry

    func testEveryCharacterSitsWhereItSitsToday() throws {
        for (name, elements) in corpus() {
            let starts = try engineStarts(elements)
            let built = candidate(for: elements, starts: starts)

            let surface = ScriptSurface()
            surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 400)
            surface.render(elements)
            surface.setLayoutMode(.pages)

            let length = (surface.textView.string as NSString).length
            XCTAssertEqual(length, built.storage.length, "\(name): same text in both")

            // Offsets are measured from the first character of the page the
            // character is on. Where a sheet lands on the canvas belongs to
            // Stage 2; what must not move is the type on the paper — and the
            // text container inset, constant in both, cancels.
            var pageOriginToday: [Int: CGPoint] = [:]
            var pageOriginCandidate: [Int: CGPoint] = [:]
            for (page, start) in starts.enumerated() {
                if let today = ScriptLayout.boundingRect(
                    of: NSRange(location: start, length: 1), in: surface.textView
                ) {
                    pageOriginToday[page] = today.origin
                }
                if let built = candidateRect(start, built, page: page) {
                    pageOriginCandidate[page] = built.origin
                }
            }

            var compared = 0
            var firstFailure: String?
            for location in 0..<length {
                let page = page(of: location, in: starts)
                guard let todayOrigin = pageOriginToday[page],
                      let candidateOrigin = pageOriginCandidate[page],
                      let today = ScriptLayout.boundingRect(
                          of: NSRange(location: location, length: 1), in: surface.textView
                      ),
                      let mine = candidateRect(location, built, page: page)
                else { continue }

                let todayOffset = CGPoint(
                    x: today.minX - todayOrigin.x, y: today.minY - todayOrigin.y
                )
                let mineOffset = CGPoint(
                    x: mine.minX - candidateOrigin.x, y: mine.minY - candidateOrigin.y
                )
                compared += 1
                if abs(todayOffset.x - mineOffset.x) > Self.tolerance
                    || abs(todayOffset.y - mineOffset.y) > Self.tolerance {
                    if firstFailure == nil {
                        firstFailure =
                            "\(name), page \(page + 1), character \(location): "
                            + "today \(todayOffset), multi-container \(mineOffset)"
                    }
                }
            }

            // `compared > 0` is not a floor: it passes while the harness
            // checks a dozen characters of twenty thousand and calls the
            // architectures equivalent. Demand most of the script.
            XCTAssertGreaterThanOrEqual(
                compared, (length * 9) / 10,
                "\(name): compared only \(compared) of \(length) characters — "
                    + "the harness is mostly blind and proves nothing"
            )
            XCTAssertNil(firstFailure, firstFailure ?? "")
        }
    }
}
