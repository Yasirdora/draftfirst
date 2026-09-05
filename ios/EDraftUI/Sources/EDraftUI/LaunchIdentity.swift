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

    /// Where a screenplay's text block begins: 1.5 inches of an 8.5 inch page.
    ///
    /// The phone drew this at a literal `0.17`, which is that fraction rounded.
    /// Naming it exactly is worth the two and a half points it moves on a
    /// handset, because the whole point of the rule is that it is *the* margin
    /// rather than a line near it.
    public nonisolated static let marginRuleFraction: CGFloat = 1.5 / 8.5

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

    public nonisolated static let rule = Ink(
        light: Tone(0.239, 0.227, 0.290),
        dark: Tone(0.180, 0.173, 0.208)
    )

    /// The production revision colours, in the order a script reprints in —
    /// white, blue, pink, yellow, green, goldenrod, salmon, cherry, buff.
    /// A sequence that means something, rather than a gradient that means
    /// nothing.
    public nonisolated static let revisionRun: [Color] = [
        Color(red: 1.00, green: 1.00, blue: 1.00),
        Color(red: 0.75, green: 0.83, blue: 0.91),
        Color(red: 0.95, green: 0.77, blue: 0.82),
        Color(red: 0.96, green: 0.90, blue: 0.66),
        Color(red: 0.78, green: 0.89, blue: 0.76),
        Color(red: 0.91, green: 0.78, blue: 0.56),
        Color(red: 0.98, green: 0.80, blue: 0.71),
        Color(red: 0.90, green: 0.62, blue: 0.65),
        Color(red: 0.94, green: 0.90, blue: 0.79)
    ]

    /// The ground the launch experience sits on.
    ///
    /// Measured, not assumed: on the phone the launch card covers most of the
    /// screen, so this reads only where it meets the card's edge. A ground the
    /// colour of paper would therefore say nothing at all. A desk does — the
    /// page floats on it, the margin rule runs down where a script's text
    /// begins, and the revision colours lie along the foot the way a stack of
    /// reprints does.
    public struct Background: View {
        @Environment(\.colorScheme) private var scheme

        public init() {}

        public var body: some View {
            ZStack(alignment: .topLeading) {
                LaunchIdentity.desk.color(scheme)

                // Drawn once, at a weight you notice only if you look for it.
                GeometryReader { geometry in
                    Rectangle()
                        .fill(LaunchIdentity.rule.color(scheme))
                        .frame(width: 1)
                        .offset(x: geometry.size.width * LaunchIdentity.marginRuleFraction)
                }

                VStack {
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(LaunchIdentity.revisionRun.indices, id: \.self) { index in
                            LaunchIdentity.revisionRun[index]
                        }
                    }
                    .frame(height: 3)
                }
            }
            .ignoresSafeArea()
        }
    }
}
