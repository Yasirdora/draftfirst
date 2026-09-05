import SwiftUI

/// What eDraft looks like before a word is written.
///
/// Every document-based app on the App Store is handed the same launch card,
/// and most of them accept it: a system-weight title over a grey ground, above
/// a browser that is identical in all of them. The result is a shelf of
/// applications that look like one application. The API is not what makes them
/// alike — it hands you a `Text` you may style however you like and a
/// background you may draw yourself — it is that almost nobody spends them.
///
/// So this spends them, and spends them on the subject rather than on
/// decoration. A screenplay's identity is not a colour, it is a typewriter and
/// a measured page: Courier, a margin rule at the inch and a half where every
/// script's text begins, and the run of colours a production reprints its
/// revisions on. Nothing here is invented for the app; it is all borrowed from
/// the craft the app is for.
enum LaunchIdentity {

    /// The app's name.
    ///
    /// Measured, and worth writing down because the API invites the opposite
    /// conclusion: the launch scene accepts a `Text`, but styles it itself.
    /// A monospaced face and a blue were both set here and both were ignored —
    /// the word rendered in the system face, in black, exactly as the plain
    /// string does. So the title is a *string*, and the identity has to come
    /// from the ground it sits on.
    ///
    /// It stays a `Text` rather than a literal only so that this note has
    /// somewhere to live, next to the thing it is about.
    static var title: Text {
        Text("eDraft")
    }

    /// The ground the card sits on.
    ///
    /// Measured, not assumed: the launch card covers most of the screen, so the
    /// background is a *frame* rather than a canvas — it reads only where it
    /// meets the card's edge. A ground the colour of paper therefore says
    /// nothing at all. A desk does: the page floats on it, the margin rule runs
    /// down where a script's text begins, and the revision colours lie along
    /// the foot the way a stack of reprints does.
    struct Background: View {
        var body: some View {
            ZStack(alignment: .topLeading) {
                Color.launchPaper

                // The left margin of a screenplay page — 1.5 inches, where the
                // text block begins on every page ever printed. Drawn once, at
                // a weight you notice only if you look for it.
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.launchRule)
                        .frame(width: 1)
                        .offset(x: geometry.size.width * 0.17)
                }

                // The revision run, along the foot: white, blue, pink, yellow,
                // green, goldenrod, salmon, cherry, buff — the order a
                // production reprints in, and a sequence that means something
                // rather than a gradient that means nothing.
                VStack {
                    Spacer()
                    HStack(spacing: 0) {
                        ForEach(Color.revisionRun.indices, id: \.self) { index in
                            Color.revisionRun[index]
                        }
                    }
                    .frame(height: 3)
                }
            }
            .ignoresSafeArea()
        }
    }
}

private extension Color {
    /// Slightly warm, like paper; not the system's neutral grey.
    static let launchPaper = Color(
        light: Color(red: 0.129, green: 0.122, blue: 0.157),
        dark: Color(red: 0.055, green: 0.051, blue: 0.071)
    )
    static let launchInk = Color(
        light: Color(red: 0.086, green: 0.082, blue: 0.102),
        dark: Color(red: 0.914, green: 0.902, blue: 0.878)
    )
    static let launchRule = Color(
        light: Color(red: 0.239, green: 0.227, blue: 0.290),
        dark: Color(red: 0.180, green: 0.173, blue: 0.208)
    )

    /// The production revision colours, in the order a script reprints in.
    static let revisionRun: [Color] = [
        Color(red: 1.00, green: 1.00, blue: 1.00),   // White
        Color(red: 0.75, green: 0.83, blue: 0.91),   // Blue
        Color(red: 0.95, green: 0.77, blue: 0.82),   // Pink
        Color(red: 0.96, green: 0.90, blue: 0.66),   // Yellow
        Color(red: 0.78, green: 0.89, blue: 0.76),   // Green
        Color(red: 0.91, green: 0.78, blue: 0.56),   // Goldenrod
        Color(red: 0.98, green: 0.80, blue: 0.71),   // Salmon
        Color(red: 0.90, green: 0.62, blue: 0.65),   // Cherry
        Color(red: 0.94, green: 0.90, blue: 0.79)    // Buff
    ]

    /// A colour that answers to the appearance the writer chose.
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            UIColor(traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}
