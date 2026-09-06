import AppKit
import EDraftCore
import SwiftUI

/// The page, as SwiftUI sees it.
///
/// Deliberately thin. Everything that decides anything lives in
/// `ScriptSurface`, where a test can reach it; this adds lifetime and the
/// three things SwiftUI is actually needed for — noticing that the model
/// changed, noticing that the window changed width, and keeping the
/// surface alive between the two.
public struct ScriptPageView: NSViewRepresentable {
    private let editor: EditorState

    public init(editor: EditorState) {
        self.editor = editor
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let surface = context.coordinator.surface
        surface.bind(to: editor)
        surface.renderIfNeeded(editor)
        return surface.scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.surface.bind(to: editor)
        context.coordinator.surface.renderIfNeeded(editor)
        context.coordinator.remeasureIfNeeded(editor, in: scrollView)
        // makeNSView runs before the view has a window, so the first update
        // pass is the earliest moment the caret has somewhere to go.
        context.coordinator.surface.takeInitialFocus()
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    /// What the representable cannot hold itself: the surface, and the last
    /// measure it laid the page to.
    @MainActor
    public final class Coordinator {
        let surface = ScriptSurface()
        private var measure: CGFloat = 0

        /// A resized window recentres the page card. Ignored until the window
        /// has a width at all, so the first layout pass does not centre a
        /// card on a zero-width canvas.
        func remeasureIfNeeded(_ editor: EditorState, in scrollView: NSScrollView) {
            let width = scrollView.contentView.bounds.width
            guard width > 1, abs(width - measure) > 0.5 else { return }
            measure = width
            surface.remeasure(to: width, elements: editor.screenplay.elements)
        }
    }
}
