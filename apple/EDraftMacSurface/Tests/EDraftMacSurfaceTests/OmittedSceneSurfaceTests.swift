import AppKit
import EDraftCore
import EDraftEngine
import XCTest
@testable import EDraftMacSurface

/// A scene the production cut, on the page — RFC-DRAFT-PRODUCTION §7.3.
///
/// Collapsed out of the flow, not struck through it: one line where the
/// scene was, the body not in the layout at all, and a disclosure that puts
/// it back. What the collapse has to protect is the surface's own
/// arithmetic — `ranges` is indexed by element index everywhere, so a
/// hidden element keeps its place in that array and holds an empty range.
@MainActor
final class OmittedSceneSurfaceTests: XCTestCase {

    /// A file with one cut scene: the card, and two paragraphs behind it.
    private func fdx(
        before: [(String, String)] = [("Scene Heading", "INT. LAB - DAY"), ("Action", "She waits.")],
        after: [(String, String)] = [("Action", "The kettle screams.")],
        number: String = "21",
        length: String? = "2/8"
    ) -> Data {
        let head = before.map { "<Paragraph Type=\"\($0.0)\"><Text>\($0.1)</Text></Paragraph>" }.joined(separator: "\n")
        let tail = after.map { "<Paragraph Type=\"\($0.0)\"><Text>\($0.1)</Text></Paragraph>" }.joined(separator: "\n")
        let properties = length.map { "<SceneProperties Length=\"\($0)\" Page=\"1\"></SceneProperties>" } ?? ""
        return Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        \(head)
        <Paragraph Number="\(number)" Type="Scene Heading">
        <Text>OMITTED</Text>
        <OmittedScene>
        <Paragraph Type="Scene Heading">\(properties)<Text>EXT. THE YARD - DUSK</Text></Paragraph>
        <Paragraph Type="Action"><Text>Mara waits.</Text></Paragraph>
        </OmittedScene>
        </Paragraph>
        \(tail)
        </Content>
        </FinalDraft>
        """.utf8)
    }

    private func opened(_ data: Data) throws -> (EditorState, ScriptSurface) {
        let file = try ScreenplayFile.open(data, as: .finalDraftScreenplay)
        let editor = EditorState(source: file.source)
        editor.attachImportedNotes(from: file.origin)
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        return (editor, surface)
    }

    private func laid(_ surface: ScriptSurface) -> String {
        surface.textView.textStorage?.string ?? ""
    }

    private func key(_ editor: EditorState) throws -> DraftElementID {
        try XCTUnwrap(editor.omittedScenes.scenes.first?.key)
    }

    // MARK: - Collapsed by default

    func testTheCutBodyIsNotInTheLayoutAtAll() throws {
        let (_, surface) = try opened(fdx())
        let text = laid(surface)
        XCTAssertTrue(text.contains("OMITTED"), "the card is the line that stands in its place")
        XCTAssertFalse(text.contains("EXT. THE YARD - DUSK"), "the cut heading is out of the flow")
        XCTAssertFalse(text.contains("Mara waits."), "and so is its body")
        XCTAssertTrue(text.contains("The kettle screams."), "the live script is untouched")
    }

    /// The invariant the whole design rests on.
    func testRangesStayParallelToElementsWithHiddenOnesEmpty() throws {
        let (editor, surface) = try opened(fdx())
        XCTAssertEqual(surface.ranges.count, editor.screenplay.elements.count)
        for (index, element) in editor.screenplay.elements.enumerated() {
            XCTAssertEqual(surface.ranges[index].id, element.id, "range \(index) is its element's")
            if editor.isOmitted(element) {
                XCTAssertEqual(surface.ranges[index].range.length, 0, "a hidden element holds no text")
            }
        }
        // And every hidden element sits at its card's foot, not at zero.
        let card = try XCTUnwrap(editor.screenplay.elements.firstIndex { editor.omittedScenes.isCard($0) })
        let foot = surface.ranges[card].range.location + surface.ranges[card].range.length
        for (index, element) in editor.screenplay.elements.enumerated() where editor.isOmitted(element) {
            XCTAssertEqual(surface.ranges[index].range.location, foot)
        }
    }

    /// The layout decides what to lay out; the pagination decides what to
    /// count. They are two code paths over one predicate, and if they ever
    /// disagree the canvas and the page count drift apart again — which is
    /// the bug this design exists to end. So: the text on the page is
    /// exactly the elements `laidElements` names, in order, in both states.
    func testTheLaidTextIsExactlyWhatThePaginatorCounts() throws {
        let (editor, surface) = try opened(fdx())
        for _ in 0...1 {
            let expected = surface.laidElements(editor.screenplay.elements)
                .map(\.text)
                .joined(separator: "\n")
            XCTAssertEqual(laid(surface), expected, "the page and the page count are one script")
            surface.toggleOmission(try key(editor))
        }
    }

    func testNothingIsStruckThroughAnyMore() throws {
        let (_, surface) = try opened(fdx())
        let storage = try XCTUnwrap(surface.textView.textStorage)
        var struck = 0
        storage.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            if value != nil { struck += 1 }
        }
        XCTAssertEqual(struck, 0, "the struck presentation is gone, not disabled")
    }

    // MARK: - Opening it

    func testTheDisclosurePutsTheBodyBackInTheSameSepia() throws {
        let (editor, surface) = try opened(fdx())
        surface.toggleOmission(try key(editor))
        let text = laid(surface)
        XCTAssertTrue(text.contains("EXT. THE YARD - DUSK"))
        XCTAssertTrue(text.contains("Mara waits."))

        let storage = try XCTUnwrap(surface.textView.textStorage)
        let at = (text as NSString).range(of: "Mara waits.")
        var effective = NSRange()
        let ink = storage.attribute(.foregroundColor, at: at.location, effectiveRange: &effective) as? NSColor
        XCTAssertEqual(ink, NSColor.screenplayOmittedInk, "shown, and plainly not live")
        XCTAssertNil(storage.attribute(.strikethroughStyle, at: at.location, effectiveRange: &effective))
    }

    func testCollapsingPutsItAwayAgain() throws {
        let (editor, surface) = try opened(fdx())
        let scene = try key(editor)
        surface.toggleOmission(scene)
        XCTAssertTrue(surface.isOmissionExpanded(scene))
        surface.toggleOmission(scene)
        XCTAssertFalse(surface.isOmissionExpanded(scene))
        XCTAssertFalse(laid(surface).contains("Mara waits."))
    }

    /// The human's expectation, measured rather than asserted in prose: a
    /// document opened again comes back collapsed, because nothing about
    /// the expansion was written anywhere.
    func testAReopenedDocumentComesBackCollapsed() throws {
        let data = fdx()
        let (editor, surface) = try opened(data)
        surface.toggleOmission(try key(editor))
        XCTAssertTrue(laid(surface).contains("Mara waits."))

        let (reopenedEditor, reopened) = try opened(data)
        XCTAssertTrue(reopened.expandedOmissions.isEmpty, "nothing persisted")
        XCTAssertFalse(laid(reopened).contains("Mara waits."))
        XCTAssertFalse(reopened.isOmissionExpanded(try key(reopenedEditor)))
    }

    // MARK: - Closed to the caret, open or shut

    func testTypingIsRefusedInsideAnOpenedSpan() throws {
        let (editor, surface) = try opened(fdx())
        surface.toggleOmission(try key(editor))
        let at = (laid(surface) as NSString).range(of: "Mara waits.")
        XCTAssertFalse(
            surface.textView(
                surface.textView,
                shouldChangeTextIn: NSRange(location: at.location + 2, length: 0),
                replacementString: "x"
            )
        )
    }

    func testTypingOutsideTheSpanIsUntouchedInBothStates() throws {
        let (editor, surface) = try opened(fdx())
        for _ in 0...1 {
            let at = (laid(surface) as NSString).range(of: "The kettle screams.")
            XCTAssertTrue(
                surface.textView(
                    surface.textView,
                    shouldChangeTextIn: NSRange(location: at.location + 2, length: 0),
                    replacementString: "x"
                ),
                "a live line is a live line either way"
            )
            surface.toggleOmission(try key(editor))
        }
    }

    func testCollapsedThereIsNowhereInsideToPutACaret() throws {
        let (editor, surface) = try opened(fdx())
        let hidden = try XCTUnwrap(editor.screenplay.elements.firstIndex { editor.isOmitted($0) })
        let empty = surface.ranges[hidden].range
        XCTAssertEqual(empty.length, 0)
        XCTAssertFalse(surface.touchesOmitted(empty), "an empty range is not inside anything")
    }

    // MARK: - The chrome

    func testTheRegionIsMarkedCollapsedAndThenOpen() throws {
        let (editor, surface) = try opened(fdx())
        XCTAssertEqual(surface.omittedRegions.count, 1)
        XCTAssertTrue(try XCTUnwrap(surface.omittedRegions.first).collapsed)
        surface.toggleOmission(try key(editor))
        XCTAssertEqual(surface.omittedRegions.count, 1)
        XCTAssertFalse(try XCTUnwrap(surface.omittedRegions.first).collapsed)
    }

    func testTheRegionSaysItselfOutLoud() throws {
        let (editor, _) = try opened(fdx())
        let scene = try XCTUnwrap(editor.omittedScenes.scenes.first)
        XCTAssertEqual(scene.spoken(collapsed: true), "Scene 21, omitted, 0.3 pages cut, collapsed")
        XCTAssertEqual(scene.spoken(collapsed: false), "Scene 21, omitted, 0.3 pages cut, expanded")
        XCTAssertEqual(scene.pillText, "0.3 pgs CUT")
    }

    // MARK: - The sepia, on both papers

    func testTheSepiaIsLegibleOnBothPapers() {
        for dark in [false, true] {
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            var ink: NSColor?
            var paper: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                ink = NSColor.screenplayOmittedInk.usingColorSpace(.sRGB)
                paper = NSColor.screenplayPaper.usingColorSpace(.sRGB)
            }
            let contrast = Self.contrast(try! XCTUnwrap(ink), try! XCTUnwrap(paper))
            XCTAssertGreaterThanOrEqual(
                contrast, 4.5,
                "a whole cut scene is read in this ink; \(dark ? "dark" : "light") paper was \(contrast)"
            )
        }
    }

    /// WCAG relative luminance, so "legible" is a number and not a taste.
    private static func contrast(_ a: NSColor, _ b: NSColor) -> Double {
        func luminance(_ color: NSColor) -> Double {
            func channel(_ value: CGFloat) -> Double {
                let v = Double(value)
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channel(color.redComponent)
                + 0.7152 * channel(color.greenComponent)
                + 0.0722 * channel(color.blueComponent)
        }
        let first = luminance(a), second = luminance(b)
        return (max(first, second) + 0.05) / (min(first, second) + 0.05)
    }

    // MARK: - Edge cases

    func testAnOmissionAsTheDocumentsFirstElement() throws {
        let (editor, surface) = try opened(fdx(before: []))
        XCTAssertEqual(editor.omittedScenes.scenes.count, 1)
        XCTAssertFalse(laid(surface).contains("Mara waits."))
        XCTAssertTrue(laid(surface).hasPrefix("OMITTED"), "the card opens the document")
        XCTAssertEqual(surface.ranges.count, editor.screenplay.elements.count)
    }

    func testAnOmissionAsTheDocumentsLastElement() throws {
        let (editor, surface) = try opened(fdx(after: []))
        XCTAssertEqual(editor.omittedScenes.scenes.count, 1)
        XCTAssertFalse(laid(surface).contains("Mara waits."))
        XCTAssertTrue(laid(surface).hasSuffix("OMITTED"), "the card closes the document")
        XCTAssertEqual(surface.ranges.count, editor.screenplay.elements.count)
    }

    func testTwoOmissionsSeparatedByOneLiveParagraph() throws {
        let two = Data("""
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <FinalDraft DocumentType="Script" Version="6">
        <Content>
        <Paragraph Number="21" Type="Scene Heading">
        <Text>OMITTED</Text>
        <OmittedScene>
        <Paragraph Type="Scene Heading"><SceneProperties Length="2/8"></SceneProperties><Text>EXT. THE YARD - DUSK</Text></Paragraph>
        </OmittedScene>
        </Paragraph>
        <Paragraph Type="Action"><Text>One live line between them.</Text></Paragraph>
        <Paragraph Number="22" Type="Scene Heading">
        <Text>OMITTED</Text>
        <OmittedScene>
        <Paragraph Type="Scene Heading"><SceneProperties Length="1 4/8"></SceneProperties><Text>INT. THE HALL - DAY</Text></Paragraph>
        </OmittedScene>
        </Paragraph>
        </Content>
        </FinalDraft>
        """.utf8)
        let (editor, surface) = try opened(two)
        XCTAssertEqual(editor.omittedScenes.scenes.count, 2)
        XCTAssertEqual(surface.omittedRegions.count, 2)
        XCTAssertEqual(editor.omittedScenes.scenes.map(\.sceneNumber), ["21", "22"])
        XCTAssertEqual(editor.omittedScenes.scenes.map(\.pillText), ["0.3 pgs CUT", "1.5 pgs CUT"])

        let text = laid(surface)
        XCTAssertTrue(text.contains("One live line between them."), "the live line survives between them")
        XCTAssertFalse(text.contains("EXT. THE YARD - DUSK"))
        XCTAssertFalse(text.contains("INT. THE HALL - DAY"))
        XCTAssertEqual(surface.ranges.count, editor.screenplay.elements.count)

        // Opening one leaves the other shut.
        surface.toggleOmission(editor.omittedScenes.scenes[0].key)
        XCTAssertTrue(laid(surface).contains("EXT. THE YARD - DUSK"))
        XCTAssertFalse(laid(surface).contains("INT. THE HALL - DAY"))
    }
}
