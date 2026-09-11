import Testing
@testable import EDraftEngine

/// Incremental pagination: the same pages as the full pass, always.
///
/// Mirrors `paginate.test.ts` — the property is proven in both languages,
/// because the corpus pins the full pass and only the fuzz pins the splice.
@Suite("Incremental pagination")
struct IncrementalPaginationTests {

    private func el(_ type: ElementKind, _ text: String) -> ScreenplayElement {
        ScreenplayElement(type: type, text: text)
    }

    /// A feature-shaped document: scenes, action, exchanges, transitions.
    private func feature(_ scenes: Int) -> Screenplay {
        var elements: [ScreenplayElement] = []
        for beat in 1...scenes {
            elements.append(el(.scene, "INT. ROOM \(beat) - DAY"))
            elements.append(el(.action, "Action for beat \(beat). The road holds its breath for a full line of the page."))
            elements.append(el(.character, "MARA"))
            elements.append(el(.parenthetical, "(quietly)"))
            elements.append(el(.dialogue, "Line \(beat), spoken plainly and without hurry at all."))
            elements.append(el(.character, "DAVID"))
            elements.append(el(.dialogue, "Reply in scene \(beat). I hear you, and I agree completely."))
            elements.append(el(.transition, "CUT TO:"))
        }
        return Screenplay(titlePage: [], elements: elements)
    }

    @Test("answers the full pass when there is no cache")
    func noCache() throws {
        let script = feature(20)
        let incremental = try Paginator.paginateIncrementally(
            script, previous: Screenplay(titlePage: [], elements: []), previousPages: []
        )
        let full = try Paginator.paginate(script)
        #expect(incremental == full)
    }

    @Test("returns the previous pages when nothing the fold reads changed")
    func noLayoutChange() throws {
        let before = feature(20)
        let pages = try Paginator.paginate(before)
        var after = feature(20)
        after.elements[5].sceneNumber = "A12"  // margin data, not layout
        let result = try Paginator.paginateIncrementally(after, previous: before, previousPages: pages)
        #expect(result.map(\.number) == pages.map(\.number))
        #expect(result == pages)
    }

    @Test("a text edit mid-document paginates identically to the full pass")
    func midDocumentTextEdit() throws {
        let before = feature(40)
        let pages = try Paginator.paginate(before)
        var after = feature(40)
        after.elements[100].text = "A wholly different reply, longer and more considered than before."
        let incremental = try Paginator.paginateIncrementally(after, previous: before, previousPages: pages)
            let full = try Paginator.paginate(after)
            #expect(incremental == full)
    }

    @Test("a keystroke at the end paginates identically")
    func endKeystroke() throws {
        let before = feature(40)
        let pages = try Paginator.paginate(before)
        var after = feature(40)
        after.elements[after.elements.count - 1].text += " Again."
        let incremental = try Paginator.paginateIncrementally(after, previous: before, previousPages: pages)
            let full = try Paginator.paginate(after)
            #expect(incremental == full)
    }

    @Test("a Return (insertion) paginates identically")
    func insertion() throws {
        let before = feature(40)
        let pages = try Paginator.paginate(before)
        var elements = before.elements
        elements.insert(el(.action, "A new paragraph lands in the middle of the script."), at: 57)
        let after = Screenplay(titlePage: [], elements: elements)
        let incremental = try Paginator.paginateIncrementally(after, previous: before, previousPages: pages)
            let full = try Paginator.paginate(after)
            #expect(incremental == full)
    }

    @Test("a deletion paginates identically")
    func deletion() throws {
        let before = feature(40)
        let pages = try Paginator.paginate(before)
        var elements = before.elements
        elements.removeSubrange(100..<104)
        let after = Screenplay(titlePage: [], elements: elements)
        let incremental = try Paginator.paginateIncrementally(after, previous: before, previousPages: pages)
            let full = try Paginator.paginate(after)
            #expect(incremental == full)
    }

    @Test("a cue becoming action splits the flow block — still identical")
    func typeChangeSplitsFlow() throws {
        let before = feature(40)
        let pages = try Paginator.paginate(before)
        var after = feature(40)
        after.elements[102] = el(.action, "Not a cue any more, just narration of it.")
        let incremental = try Paginator.paginateIncrementally(after, previous: before, previousPages: pages)
            let full = try Paginator.paginate(after)
            #expect(incremental == full)
    }

    @Test("fuzz: random single-region edits are identical to the full pass")
    func fuzz() throws {
        var seed: UInt64 = 20260911
        func random() -> Double {
            seed = (seed &* 1103515245 &+ 12345) & 0x7fffffff
            return Double(seed) / Double(0x7fffffff)
        }
        let words = ["night", "door", "light", "road", "silence", "again", "KANE", "window"]
        func phrase() -> String {
            (0..<(3 + Int(random() * 18))).map { _ in words[Int(random() * Double(words.count))] }
                .joined(separator: " ")
        }

        for _ in 0..<300 {
            let before = feature(30 + Int(random() * 30))
            let pages = try Paginator.paginate(before)
            var elements = before.elements
            let pick = random()
            let at = Int(random() * Double(elements.count))
            if pick < 0.45 {
                elements[at] = el(elements[at].type, phrase())
            } else if pick < 0.6 {
                let types: [ElementKind] = [.action, .character, .dialogue, .scene]
                elements[at] = el(types[Int(random() * 4)], elements[at].text)
            } else if pick < 0.8 {
                elements.insert(el(.action, phrase()), at: at)
            } else {
                let end = Swift.min(elements.count, at + 1 + Int(random() * 3))
                elements.removeSubrange(at..<end)
            }
            let after = Screenplay(titlePage: [], elements: elements)
            let incremental = try Paginator.paginateIncrementally(after, previous: before, previousPages: pages)
                let full = try Paginator.paginate(after)
                #expect(incremental == full)
        }
    }
}
