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
/// window's fit, or the size they chose with plus and minus. Near actual size
/// — 110% or below — a toggle would only nod, so the percentage becomes a
/// menu: Fit to Screen first, then the named sizes. A press that has already
/// gone to 100% is still a toggle: that is the way back, and a menu would
/// swallow it.
struct PageZoomControl: View {
    let editor: EditorState

    var body: some View {
        HStack(spacing: 0) {
            step(.zoomOut, symbol: "minus", label: "Zoom Out")

            if PageZoom.percentageShowsMenu(
                at: editor.zoom, holdingActualSize: editor.holdingActualSize
            ) {
                Menu {
                    Button("Fit to Screen") {
                        editor.onZoom?(.fit)
                    }
                    Divider()
                    ForEach(PageZoom.namedStops, id: \.self) { stop in
                        Button {
                            editor.onZoomTo?(stop)
                        } label: {
                            if PageZoom.displayedPercentage(stop) == PageZoom.displayedPercentage(editor.zoom) {
                                Label(PageZoom.percentage(stop), systemImage: "checkmark")
                            } else {
                                Text(PageZoom.percentage(stop))
                            }
                        }
                    }
                } label: {
                    percentageLabel
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose a size")
                .accessibilityLabel("Page zoom \(PageZoom.percentage(editor.zoom))")
            } else {
                Button {
                    editor.onZoom?(.toggleActualSize)
                } label: {
                    percentageLabel
                }
                .buttonStyle(.plain)
                .help("Show actual size, and back again")
                .accessibilityLabel("Page zoom \(PageZoom.percentage(editor.zoom))")
            }

            step(.zoomIn, symbol: "plus", label: "Zoom In")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        // Glass, like the toolbar above it: a control floating over the desk
        // is made of the same material as the controls floating over it.
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(12)
    }

    // Monospaced digits so the capsule does not breathe as the number
    // changes under the pointer. One label for both affordances, so the
    // control reads the same whether it toggles or offers the menu.
    private var percentageLabel: some View {
        Text(PageZoom.percentage(editor.zoom))
            .font(.caption.monospacedDigit())
            .frame(minWidth: 44)
            .contentShape(Rectangle())
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
