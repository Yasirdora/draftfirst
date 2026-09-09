import EDraftCore
import EDraftUI
import SwiftUI
import UIKit

// Only the QA-fixture build reaches into the surface package from here, for
// the launch-argument predicate the fixtures share. Guarded rather than
// unconditional so the dependency says exactly when it is real.
#if EDITOR_PREVIEW
import EDraftUIKitSurface
#endif

/// Applies the writer's chosen appearance to every window the app owns —
/// document browser, editor, sheets — so the in-app choice is absolute and
/// the system theme never silently overrides part of the app. SwiftUI's
/// preferredColorScheme cannot reach a DocumentGroupLaunchScene, which is
/// why a view-scoped override left the browser on the system theme.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private var defaultsObserver: NSObjectProtocol?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Self.applyAppearance()
        // Any preference write (the document menu's Appearance picker)
        // re-styles every window immediately — no relaunch, no stale window.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Self.applyAppearance()
        }
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        Self.applyAppearance()
    }

    static func applyAppearance() {
        // `.unspecified` for System hands the window back to the device, so
        // sunset-scheduled dark mode reaches every window we own.
        let style = AppearancePreference.stored.userInterfaceStyle
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

@main
struct EDraftApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
#if EDITOR_PREVIEW
        WindowGroup {
            EditorPreviewHost()
        }
#else
        // Adopting DocumentGroupLaunchScene retires the browser-style
        // chrome; the editor's navigation bar keeps only the system's close
        // button, and everything else in that bar is ours, configured on
        // the navigation item directly (see EditorChrome).
        // Scanning and importing are actions in the system's own stack,
        // which renders a third as "More…". Drawing them into the card
        // instead was tried and abandoned: the launch scene's overlay
        // accessory is the only layer that reaches the card, and the browser
        // sits above it for touches — a hit test at a button drawn there
        // returns the browser's scroll view, so the buttons look right and do
        // nothing. `DocumentLaunchGeometryProxy`, which would have placed
        // them honestly, reports both of its rectangles as zero.
        // The title and the ground are ours to draw — see LaunchIdentity for
        // why that matters and what it is drawn from.
        DocumentGroupLaunchScene(LaunchIdentity.title) {
            NewDocumentButton("New Screenplay")
            ScreenplayLaunchActions.scan()
            ScreenplayLaunchActions.importExisting()
        } background: {
            LaunchIdentity.Background()
        }
        DocumentGroup(newDocument: EDraftDocument()) { file in
            // A script opens at its first page, because opening one now means
            // reading it. Resuming at the end was right while opening always
            // meant writing, but a screenplay's last lines are usually the
            // blank ones left behind by the last Return — so a document opened
            // to be read showed a blank screen with the writing above it.
            EditorView(document: file.$document, fileURL: file.fileURL)
        }
        // Scans share the browser with screenplays rather than living in a
        // library of their own. A writer's paper — a marked-up draft, a
        // contract, a page of research — belongs beside the script it relates
        // to, and declaring the type is the whole of what that takes.
        DocumentGroup(viewing: ScanDocument.self) { file in
            ScanReaderView(document: file.document)
        }
#endif
    }
}

#if EDITOR_PREVIEW
private struct EditorPreviewHost: View {
    @State private var document: EDraftDocument

    init() {
        _document = State(initialValue: EDraftDocument(source: EditorPreviewConfiguration.source))
    }

    var body: some View {
        // The editor's chrome lives in the navigation bar; the preview
        // supplies the stack a DocumentGroup would provide in production.
        NavigationStack {
            EditorView(
                document: $document,
                startsAtEnd: EditorPreviewConfiguration.usesPredictionFixture
            )
        }
    }
}

enum EditorPreviewConfiguration {
    static let arguments = ProcessInfo.processInfo.arguments

    /// Read from the surface, which is what actually behaves differently under
    /// a prediction fixture. Two copies of this list would drift, and the
    /// symptom would be a QA fixture that quietly stops asserting.
    static var usesPredictionFixture: Bool { EditorPreviewFixture.usesPrediction }

    static var source: String {
        if arguments.contains("-prediction-fixture") {
            return "IN"
        }
        if arguments.contains("-character-prediction-fixture") {
            return "INT. LAB - NIGHT\n\nELENA\nHello.\n\n@EL"
        }
        if arguments.contains("-parenthetical-prediction-fixture") {
            return "INT. LAB - NIGHT\n\nELENA\n(whispering)\nHello.\n\nELENA\n(wh"
        }
        if arguments.contains("-scroll-prediction-fixture") {
            let scenes = (1...32).map { number in
                """
                INT. ROOM \(number) - DAY

                A long action paragraph for scene \(number) fills the editor so the final prediction is measured while the text view is deeply scrolled.
                """
            }
            return scenes.joined(separator: "\n\n") + "\n\nIN"
        }
        if arguments.contains("-qa-scroll-stability") {
            // Ends with a blank line: typing there creates a new paragraph,
            // which routes through the structural render path under test.
            let scenes = (1...32).map { number in
                """
                INT. ROOM \(number) - DAY

                A long action paragraph for scene \(number) fills the editor so the document is deeply scrolled when typing at its end.
                """
            }
            return scenes.joined(separator: "\n\n") + "\n\n"
        }
        if arguments.contains("-ordinary-space-fixture") {
            return "Hello"
        }
        if arguments.contains("-backspace-fixture") {
            return "INT. LAB - NIGHT\n\nELENA\nWait."
        }
        if arguments.contains("-qa-action-lowercase") {
            return "FADE IN:\n\nThe door opens.\n\n"
        }
        if arguments.contains("-qa-character-uppercase") {
            // "@" forces a character cue in Fountain, deterministically.
            return "INT. LAB - NIGHT\n\nELENA\nWait.\n\n@EL"
        }
        if arguments.contains("-qa-sharp-s") {
            // "@" forces a character cue in Fountain, deterministically. The
            // cue is empty so the typed ß is the whole of it.
            return "INT. LAB - NIGHT\n\nELENA\nWait.\n\n@"
        }
        if arguments.contains("-qa-quicktype-scene") {
            // A mid-word scene heading: QuickType would offer "bedroom" here.
            return "INT. BED"
        }
        if arguments.contains("-show-story-cast") {
            // Two voices and two locations for the Navigator's cast footer.
            return """
            INT. LAB - DAY

            MARA
            The array is awake.

            DAVID
            Then we move.

            EXT. RIDGE - NIGHT

            MARA
            Already moving.

            """
        }
        return sampleSource
    }

    private static let sampleSource = """
    Title: The Last Light
    Credit: written by
    Author: Sample Writer

    FADE IN:

    EXT. KAROO DESERT - RADIO TELESCOPE ARRAY - NIGHT

    A sea of white satellite dishes stretches across the flat desert basin, silent and moonlit.

    INT. CONTROL ROOM - NIGHT

    Dark except for the blue wash of monitors. DR. ELENA VOSS (38) sits before a wall of spectrograms scrolling in real time.

    ELENA
    The signal is repeating.
    """
}
#endif

extension Color {
    static let screenplayPaper = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.055, green: 0.055, blue: 0.06, alpha: 1)
                : UIColor(red: 0.995, green: 0.99, blue: 0.975, alpha: 1)
        }
    )
}
