import EDraftCore
import SwiftUI

/// The element selector as a Mac toolbar item.
///
/// Follows the iOS design by offering the current kind as its title,
/// and breaking options into "Suggested" (contextualKinds) and "All Elements".
/// Using a standard Menu ensures native accessibility and hover states,
/// as required by the Mac's toolbar guidelines.
struct ElementModeControl: View {
    let editor: EditorState

    var body: some View {
        if editor.isEditing {
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
                Label(editor.activeKind.shortTitle, systemImage: editor.activeKind.symbol)
            }
            .help("Screenplay element: \(editor.activeKind.title)")
        } else {
            Button {
                editor.beginEditing()
            } label: {
                Text("Edit")
            }
            .buttonStyle(.borderedProminent)
            .help("Edit Screenplay")
        }
    }
}
