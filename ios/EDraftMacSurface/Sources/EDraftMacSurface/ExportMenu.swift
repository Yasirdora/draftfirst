import EDraftCore
import SwiftUI

/// Export, as a toolbar menu.
///
/// The four formats come from `ScreenplayExportFormat`, so this and the File
/// menu cannot come to offer different ones; choosing one calls the model's
/// `onExport`, and what happens to the bytes is the app's business.
struct ExportMenu: View {
    let editor: EditorState

    var body: some View {
        Menu {
            ForEach(ScreenplayExportFormat.allCases, id: \.self) { format in
                Button("\(format.title)…") { editor.onExport?(format) }
            }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .help("Export the screenplay")
        .menuIndicator(.hidden)
    }
}
