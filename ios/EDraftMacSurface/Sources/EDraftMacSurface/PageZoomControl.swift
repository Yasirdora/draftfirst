import EDraftCore
import SwiftUI

/// How large the page is drawn, in the corner of the canvas.
///
/// `MACOS-DESIGN` §1.6: controls may float over a *canvas*, never over the
/// thing being read. The canvas is the desk the page sits on, and its bottom
/// trailing corner is where Preview, Sketch and Figma all put this — far from
/// the text, reachable without a menu, and out of the way of the page itself.
///
/// The percentage is a button, and the useful thing it does is answer "how big
/// is this really?" without costing the writer the size they were working at.
/// One press shows actual size; the next gives back whatever they had — the
/// window's fit, or the size they chose with plus and minus.
struct PageZoomControl: View {
    let editor: EditorState

    var body: some View {
        HStack(spacing: 0) {
            step(.zoomOut, symbol: "minus", label: "Zoom Out")

            Button {
                editor.onZoom?(.toggleActualSize)
            } label: {
                // Monospaced digits so the capsule does not breathe as the
                // number changes under the pointer.
                Text(PageZoom.percentage(editor.zoom))
                    .font(.caption.monospacedDigit())
                    .frame(minWidth: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show actual size, and back again")
            .accessibilityLabel("Page zoom \(PageZoom.percentage(editor.zoom))")

            step(.zoomIn, symbol: "plus", label: "Zoom In")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator, lineWidth: 0.5))
        .padding(12)
    }

    private func step(_ command: PageZoom.Command, symbol: String, label: String) -> some View {
        Button {
            editor.onZoom?(command)
        } label: {
            Image(systemName: symbol)
                .font(.caption.weight(.medium))
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!PageZoom.isAvailable(command, at: editor.zoom))
        .help(label)
        .accessibilityLabel(label)
    }
}
