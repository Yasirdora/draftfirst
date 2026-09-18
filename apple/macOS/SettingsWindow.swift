import AppKit
import EDraftCore
import SwiftUI

/// The app's own Settings window — eDraft → Settings… (⌘,), where every Mac
/// app keeps it.
///
/// What lives here is what is true for every script a writer opens: how the
/// page looks, what size it prints, and whether pages are numbered. What is
/// true of one script — writing assistance, a note signature — stays in the
/// document's own panel, next to the work it changes. One window, held open
/// across closes, so returning to it is returning, not rebuilding.
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.contentViewController = NSHostingController(rootView: MacSettingsView())
        // As with the launch window, the size is stated after the view goes
        // in, so the window opens as designed rather than at the view's
        // minimum.
        window.setContentSize(NSSize(width: 440, height: 480))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SettingsWindowController is created in code")
    }

    /// Closing Settings and pressing ⌘, again brings the same window back,
    /// in front — as System Settings itself behaves.
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        NSApp.activate()
    }
}

/// The window's contents: two choices about the page, then the version card.
///
/// Each control writes the same `UserDefaults` keys the surfaces already
/// read, so a change here restyles every open window and every export with
/// nothing re-opened and nothing saved.
private struct MacSettingsView: View {
    @AppStorage("pageFormat") private var pageFormat: PageFormat = .letter
    @AppStorage("showPageNumbers") private var showPageNumbers = true
    @AppStorage(PagePaper.defaultsKey) private var pagePaper: PagePaper = .paper

    var body: some View {
        Form {
            Section("Page") {
                Picker("Paper Size", selection: $pageFormat) {
                    ForEach(PageFormat.allCases) { format in
                        Text(format.title).tag(format)
                    }
                }
                Toggle("Page Numbers", isOn: $showPageNumbers)
            }

            Section("Appearance") {
                Picker("Page", selection: $pagePaper) {
                    ForEach(PagePaper.allCases, id: \.self) { paper in
                        Text(paper.title).tag(paper)
                    }
                }
                .pickerStyle(.inline)
                Text(pagePaper.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("eDraft")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Version \(versionString)")
                            .foregroundStyle(.secondary)
                        if let copyright {
                            Text(copyright)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
                Link(destination: URL(string: "mailto:feedback@edraft.xyz")!) {
                    Label("Send Feedback", systemImage: "envelope")
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    private var copyright: String? {
        let text = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
        return text?.isEmpty == false ? text : nil
    }
}
