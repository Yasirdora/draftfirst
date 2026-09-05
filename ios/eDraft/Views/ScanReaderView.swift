import PDFKit
import SwiftUI

/// Reads a scanned document.
///
/// PDFKit rather than an image view, because the scanner writes a real text
/// layer beneath the page image. That layer is what makes the words selectable,
/// searchable, and copyable straight into a screenplay — the reason for keeping
/// scans in this app rather than in Files. Rasterising the page and recognising
/// it again would throw away work already done and get a worse answer.
struct ScanReaderView: View {
    let document: ScanDocument

    @State private var isShowingText = false

    var body: some View {
        PDFDocumentView(data: document.data)
            .ignoresSafeArea(edges: .bottom)
            .background(Color.screenplayPaper)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Text", systemImage: "text.quote") {
                        isShowingText = true
                    }
                    .disabled(document.text.isEmpty)
                }
            }
            .sheet(isPresented: $isShowingText) {
                ScanTextSheet(text: document.text)
            }
    }
}

/// The scan's words, in one place, ready to be taken.
///
/// The text layer under the page is invisible by design — that is what makes
/// the scan look like the paper it came from. But invisible also means
/// undiscoverable: a writer looking at a scanned page has no way to tell the
/// words are there, and dragging a selection across a photograph is not an
/// obvious thing to try. This is the same text, shown plainly, so taking it
/// into a screenplay is one tap rather than a guess.
private struct ScanTextSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
            }
            .navigationTitle("Scanned Text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Copy", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = text
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct PDFDocumentView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        // Continuous vertical scrolling is how a multi-page document is read;
        // page-at-a-time is a slideshow.
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.autoScales = true
        view.usePageViewController(false)
        view.backgroundColor = .clear
        // The scale floor tracks the view's own size, so turning the phone
        // refits the page instead of leaving it at a scale chosen for the
        // previous bounds.
        view.minScaleFactor = view.scaleFactorForSizeToFit
        view.maxScaleFactor = 8
        load(into: view)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        guard view.document == nil else { return }
        load(into: view)
    }

    private func load(into view: PDFView) {
        view.document = PDFDocument(data: data)
        view.autoScales = true
    }
}
