import Foundation
import Testing
@testable import EDraftEngine

/// The casing a kind is written in, for text arriving from elsewhere.
///
/// Every case here came out of a real Final Draft file: it stores what the
/// writer typed and shouts it in the view, so an .fdx that looked immaculate
/// for years opens elsewhere reading like a broken shift key.
@Suite("Canonical casing")
struct CanonicalCasingTests {

    @Test("The kinds a screenplay shouts are shouted")
    func shouted() {
        #expect(Normalize.canonicalCasing(kind: .character, text: "UnCLE") == "UNCLE")
        #expect(Normalize.canonicalCasing(kind: .character, text: "yOUNG GIRL (tRANSLATED)")
                == "YOUNG GIRL (TRANSLATED)")
        #expect(Normalize.canonicalCasing(kind: .transition, text: "cUT TO:") == "CUT TO:")
        #expect(Normalize.canonicalCasing(kind: .scene, text: "iNT. WASHROOM - DAY")
                == "INT. WASHROOM - DAY")
        #expect(Normalize.canonicalCasing(kind: .shot, text: "aNGLE ON") == "ANGLE ON")
    }

    @Test("Everywhere else the writer keeps their own casing")
    func untouched() {
        #expect(Normalize.canonicalCasing(kind: .action, text: "She waits.") == "She waits.")
        #expect(Normalize.canonicalCasing(kind: .dialogue, text: "Take the key.") == "Take the key.")
        #expect(Normalize.canonicalCasing(kind: .parenthetical, text: "(beat)") == "(beat)")
    }

    @Test("It is idempotent, so an import can be repeated safely")
    func idempotent() {
        let once = Normalize.canonicalCasing(kind: .character, text: "UnCLE")
        #expect(Normalize.canonicalCasing(kind: .character, text: once) == once)
    }

    @Test("The two engines agree on which kinds are shouted")
    func sameListAsTypeScript() {
        #expect(Normalize.uppercaseKinds == [.scene, .character, .transition, .shot])
    }
}
