import EDraftCore
import SwiftUI

/// The element selector as a Mac toolbar item.
///
/// Follows the iOS design by offering the current kind as its title,
/// and breaking options into "Suggested" (contextualKinds) and "All Elements".
/// Using a standard Menu ensures native accessibility and hover states,
/// as required by the Mac's toolbar guidelines.
///
/// It does not follow `isEditing`, and that is the difference between the two
/// platforms rather than an oversight. On a phone, editing is a visible state
/// — the keyboard is up or it is not — and chrome that follows it is telling
/// the writer something true. On a Mac, focus moves to the sidebar, the scene
/// filter and the toolbar constantly and means nothing about the document; a
/// control that changed identity each time would be flickering between two
/// jobs while the writer did ordinary things. There is no reading mode on a
/// Mac. A document window opens with the page focused and this control names
/// the element under the caret, always.
struct ElementModeControl: View {
    let editor: EditorState

    var body: some View {
        Menu {
            Section("Suggested") {
                ForEach(editor.contextualKinds, id: \.self) { kind in
                    Button {
                        editor.onChangeElementKind?(kind)
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            }

            Section("All Elements") {
                ForEach(ScreenplayKind.editorKinds.filter { !editor.contextualKinds.contains($0) }, id: \.self) { kind in
                    Button {
                        editor.onChangeElementKind?(kind)
                    } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            }
        } label: {
            // Icon *and* name, as on the phone. A toolbar menu renders a Label
            // icon-only unless told otherwise, and an unlabelled glyph makes
            // the writer decode a picture to learn which element they are
            // typing — the one question this control exists to answer.
            Label(editor.activeKind.shortTitle, systemImage: editor.activeKind.symbol)
                .labelStyle(.titleAndIcon)
        }
        // Glass, because everything else in this bar is. A menu in a toolbar
        // draws a plain capsule by default, which reads as a flat chip laid
        // on the chrome rather than a control made of it.
        .buttonStyle(.glass)
        .help("Screenplay element: \(editor.activeKind.title)")
    }
}
