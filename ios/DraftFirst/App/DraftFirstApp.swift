import SwiftUI
import UIKit

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
        let style: UIUserInterfaceStyle = switch AppearancePreference(
            rawValue: UserDefaults.standard.string(forKey: "appearance") ?? ""
        ) ?? .dark {
        case .light: .light
        case .dark: .dark
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

@main
struct DraftFirstApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
#if EDITOR_PREVIEW
        WindowGroup {
            EditorPreviewHost()
        }
#else
        // Adopting DocumentGroupLaunchScene makes the system retire its
        // document chrome (back button + file-name menu) in the editor — the
        // app owns the whole top bar. EditorChrome holds the writing tools;
        // returning to this launch scene lives in the Story panel.
        DocumentGroupLaunchScene("Screenplays") {
            NewDocumentButton("New Screenplay")
        }
        DocumentGroup(newDocument: DraftFirstDocument()) { file in
            // A writer resumes where the writing ends: the caret opens at the
            // end of the document, never stranded on the first element. For a
            // blank screenplay that is its single empty Action.
            EditorView(document: file.$document, startsAtEnd: true)
        }
#endif
    }
}

#if EDITOR_PREVIEW
private struct EditorPreviewHost: View {
    @State private var document: DraftFirstDocument

    init() {
        _document = State(initialValue: DraftFirstDocument(source: EditorPreviewConfiguration.source))
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

    static var usesPredictionFixture: Bool {
        arguments.contains { argument in
            [
                "-prediction-fixture",
                "-character-prediction-fixture",
                "-parenthetical-prediction-fixture",
                "-scroll-prediction-fixture",
                "-qa-character-uppercase",
                "-qa-quicktype-scene"
            ].contains(argument)
        }
    }

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
        if arguments.contains("-qa-quicktype-scene") {
            // A mid-word scene heading: QuickType would offer "bedroom" here.
            return "INT. BED"
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
