import EDraftCore
import SwiftUI

/// The things a writer reaches for occasionally, behind one mark.
///
/// Everything here has a keyboard shortcut and a place in the menu bar
/// already — this is a second way to them for a writer whose hands are on the
/// trackpad, not a second definition of them. Each item calls the same model
/// hook the menu bar item calls, so a shortcut and a click cannot come to mean
/// different things.
struct ScriptOverflowMenu: View {
    let editor: EditorState

    var body: some View {
        Menu {
            Button("Find…") { editor.onShowFind?() }
                .keyboardShortcut("f", modifiers: .command)
            Button("Add Note") { editor.onAddNote?() }
                .keyboardShortcut("k", modifiers: [.command, .shift])

            Divider()

            Picker("Layout", selection: Binding(
                get: { editor.layoutMode },
                set: { editor.onSetLayoutMode?($0) }
            )) {
                ForEach(PageLayoutMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.inline)

            Divider()

            Button("Zoom In") { editor.onZoom?(.zoomIn) }
                .disabled(!PageZoom.isAvailable(.zoomIn, at: editor.zoom))
            Button("Zoom Out") { editor.onZoom?(.zoomOut) }
                .disabled(!PageZoom.isAvailable(.zoomOut, at: editor.zoom))
            Button("Actual Size") { editor.onZoom?(.actualSize) }
                .disabled(!PageZoom.isAvailable(.actualSize, at: editor.zoom))
            Button("Zoom to Fit") { editor.onZoom?(.fit) }
        } label: {
            // Turned, not a different symbol: `ellipsis.vertical` is not in
            // this SF Symbols set. Checked rather than assumed.
            Image(systemName: "ellipsis")
                .rotationEffect(.degrees(90))
                .accessibilityLabel("More")
        }
        .help("More actions")
        .menuIndicator(.hidden)
    }
}
