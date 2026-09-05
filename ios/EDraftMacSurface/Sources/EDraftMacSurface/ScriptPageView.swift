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
        context.coordinator.bind(to: editor)
        surface.render(editor.screenplay.elements)
        return surface.scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.bind(to: editor)
        context.coordinator.renderIfChanged(editor)
        context.coordinator.remeasureIfNeeded(editor, in: scrollView)
    }

    public func makeCoordinator() -> Coordinator { Coordinator() }

    /// What the representable cannot hold itself: the surface, and the last
    /// thing it drew.
    @MainActor
    public final class Coordinator {
        let surface = ScriptSurface()
        private weak var editor: EditorState?
        private var renderedRevision = -1
        private var measure: CGFloat = 0

        /// Points the model's callbacks at this surface.
        ///
        /// Re-run on every update rather than once, because SwiftUI may hand
        /// the view a different `EditorState` after an external change to the
        /// document — the same rebinding the phone's surface does, for the same
        /// reason: a surface still bound to a state nobody owns is an editor
        /// that has quietly stopped working.
        func bind(to editor: EditorState) {
            guard self.editor !== editor else { return }
            self.editor = editor
            renderedRevision = -1
            editor.onJumpToElement = { [weak self] id in
                self?.surface.reveal(id, reduceMotion: NSWorkspace.shared
                    .accessibilityDisplayShouldReduceMotion)
            }
        }

        func renderIfChanged(_ editor: EditorState) {
            guard editor.revision != renderedRevision else { return }
            surface.render(editor.screenplay.elements)
            renderedRevision = editor.revision
        }

        /// A resized window is a re-measured script. Ignored until the window
        /// has a width at all, so the first layout pass does not set the page
        /// to zero and lay every line out one character wide.
        func remeasureIfNeeded(_ editor: EditorState, in scrollView: NSScrollView) {
            let width = scrollView.contentView.bounds.width
            guard width > 1, abs(width - measure) > 0.5 else { return }
            measure = width
            surface.remeasure(to: width, elements: editor.screenplay.elements)
        }
    }
}
