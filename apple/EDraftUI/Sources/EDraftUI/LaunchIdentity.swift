import SwiftUI

/// What eDraft looks like before a word is written.
///
/// Every document-based app is handed the same launch card, and most of them
/// accept it: a system-weight title over a grey ground, above a browser that is
/// identical in all of them. The result is a shelf of applications that look
/// like one application. Almost nobody spends the styling they are given.
///
/// So this spends it, and spends it on the subject rather than on decoration.
/// A screenplay's identity is not a colour, it is a typewriter and a measured
/// page: a margin rule at the inch and a half where every script's text begins,
/// and the run of colours a production reprints its revisions on. Nothing here
/// is invented for the app; it is all borrowed from the craft the app is for.
///
/// It lives here rather than in a surface because it is the first thing a
/// writer sees on either machine, and two launch screens that drift are two
/// products. The phone shows it behind `DocumentGroupLaunchScene`; the Mac has
/// no such API (`@available(macOS, unavailable)`) and draws its own window on
/// the same ground.
public enum LaunchIdentity {

    /// The app's name.
    ///
    /// Measured on iOS, and worth keeping written down because the API invites
    /// the opposite conclusion: the launch scene accepts a `Text` but styles it
    /// itself. A monospaced face and a blue were both set and both ignored. So
    /// the title is a *string*, and the identity has to come from the ground it
    /// sits on.
    public static var title: Text { Text("eDraft") }

    /// One colour, kept as components so a test can weigh it rather than
    /// only compare it. Asserting that two colours differ says nothing about
    /// whether one can be read on the other.
    public nonisolated struct Tone: Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double

        public init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        public var color: Color { Color(red: red, green: green, blue: blue) }

        /// Rec. 709 relative luminance — how light this reads, not how light
        /// its numbers look.
        public var luminance: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
    }

    /// A tone that answers to the appearance the writer chose.
    ///
    /// A pair, resolved at draw time, rather than a `UIColor`/`NSColor` dynamic
    /// provider: this package may import neither kit, and a pair is also
    /// something a test can read without rendering anything.
    public nonisolated struct Ink: Sendable, Equatable {
        public let light: Tone
        public let dark: Tone

        public init(light: Tone, dark: Tone) {
            self.light = light
            self.dark = dark
        }

        public func resolved(_ scheme: ColorScheme) -> Tone {
            scheme == .dark ? dark : light
        }

        public func color(_ scheme: ColorScheme) -> Color { resolved(scheme).color }
    }

    /// The desk, not the page.
    ///
    /// Dark in *both* appearances, and deliberately so: on the phone this is a
    /// frame around a launch card that covers most of the screen, and a ground
    /// the colour of paper would say nothing at all. The name matters — called
    /// `paper`, it invited text in `ink.light` to be drawn on it, which is
    /// black on black. It is a desk. Things on it are lit.
    public nonisolated static let desk = Ink(
        light: Tone(0.129, 0.122, 0.157),
        dark: Tone(0.055, 0.051, 0.071)
    )

    /// What reads on the desk. One tone, because the desk is dark in both
    /// appearances and so its lettering is light in both.
    public nonisolated static let deskInk = Tone(0.914, 0.902, 0.878)

    /// The ground itself. A colour, and nothing drawn on it.
    ///
    /// It used to carry a margin rule at the inch and a half where a
    /// screenplay's text begins, and the run of colours a production reprints
    /// its revisions on. The argument for them was that this ground is a
    /// *frame* around a system card, so they would read at its edges as
    /// texture. What they read as, on a phone, is a hairline that runs for two
    /// hundred points and then disappears behind the card, and a sliver of
    /// colour under the file browser. On a Mac window they were worse: the rule
    /// sliced the title at 17.6% of something that is not a page.
    ///
    /// A page metaphor on a rectangle that is not a page is decoration wearing
    /// the costume of meaning, and it lasted this long because it was inherited
    /// rather than looked at.
    ///
    /// The production revision colours are a real thing and will be needed —
    /// beside `RevisionDiff` when M4 draws coloured pages, not in a launch
    /// screen's palette.
    public struct Background: View {
        @Environment(\.colorScheme) private var scheme

        public init() {}

        public var body: some View {
            LaunchIdentity.desk.color(scheme).ignoresSafeArea()
        }
    }
}
