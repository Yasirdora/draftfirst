import AppKit
import SwiftUI

/// A notice the document window gives the writer: the Final Draft page-lock
/// warning (IL-0090; `EditorState.pageLockNotice`) and the editor's banners
/// (IL-0099; `EditorState.banner`).
///
/// Quiet, the way the launch window's trash bar is: one line of secondary
/// type after an info mark, and a way to put it away. It says a thing the
/// writer needs to know; it does not ask them to do anything.
struct WindowNoticeBar: View {
    let text: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .onAppear {
            /* Said once, when it arrives: a reader of the page is not also
               reading the chrome. */
            AccessibilityNotification.Announcement(text).post()
        }
    }
}

/// The notice, docked under the toolbar.
///
/// A titlebar accessory, the way Safari and Mail dock theirs, and not a view
/// floated over the desk: AppKit takes its height out of the window's content
/// layout rectangle, so the page is laid out below it and no line is ever
/// under it at rest (MACOS-DESIGN §1.6 — controls may float over a canvas,
/// never over the thing being read).
final class WindowNoticeAccessory: NSTitlebarAccessoryViewController {

    let text: String
    private let hosting: NSHostingController<WindowNoticeBar>
    private var resizeObserver: NSObjectProtocol?

    init(text: String, onDismiss: @escaping () -> Void) {
        self.text = text
        hosting = NSHostingController(rootView: WindowNoticeBar(text: text, onDismiss: onDismiss))
        hosting.sizingOptions = []
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .bottom
        view = hosting.view
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not in a nib") }

    /// Sizes the strip for a window this wide: one line where the words fit,
    /// two where they do not — never cut off.
    func fit(width: CGFloat) {
        let height = ceil(hosting.sizeThatFits(in: CGSize(width: max(width, 1), height: .greatestFiniteMagnitude)).height)
        guard height > 0, abs(view.frame.height - height) > 0.5 else { return }
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    /// Called once the window holds it, and again whenever the window's
    /// width changes what the words need.
    func track(_ window: NSWindow) {
        fit(width: window.frame.width)
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main
        ) { [weak self] note in
            guard let window = note.object as? NSWindow else { return }
            MainActor.assumeIsolated { self?.fit(width: window.frame.width) }
        }
    }

    /// Stops following the window — the notice is leaving it.
    func stopTracking() {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
    }
}
