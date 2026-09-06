import EDraftCore
import SwiftUI

/// Whether the page is paper or dark, as a toolbar control.
///
/// The same choice as View → Page and the same storage; a writer who works in
/// the dark should not have to go into a menu to stop the page glaring at
/// them. It is a toggle rather than a menu because there are two answers and
/// the symbol says which one you are looking at — sun on paper, moon on a
/// dark page — the way the system's own light/dark controls do.
struct PagePaperToggle: View {
    @State private var paper = PagePaper.stored

    var body: some View {
        Button {
            paper = paper == .paper ? .inverted : .paper
            // The surfaces watch `UserDefaults`; writing it is the whole of
            // the action, and every open window restyles.
            PagePaper.store(paper)
        } label: {
            Label(
                paper == .paper ? "Dark Page" : "Paper Page",
                systemImage: paper == .paper ? "moon" : "sun.max"
            )
        }
        .help(paper == .paper ? "Darken the page" : "Return the page to paper")
        .accessibilityLabel("Page appearance")
        .accessibilityValue(paper.title)
    }
}
