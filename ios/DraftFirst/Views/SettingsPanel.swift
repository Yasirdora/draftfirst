import SwiftUI

/// The long-tail preferences behind the document menu's Settings… —
/// rename, suggestions, page size, feedback, about. The five destinations a
/// writer touches daily stay in the menu itself.
struct SettingsPanel: View {
    let editor: EditorState

    @Environment(\.dismiss) private var dismiss
    @AppStorage("pageFormat") private var pageFormat: PageFormat = .letter
    @State private var renamesScreenplay = false
    @State private var renameDraft = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        renameDraft = editor.screenplay.title
                        renamesScreenplay = true
                    } label: {
                        LabeledContent("Rename") {
                            Text(editor.screenplay.title)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                } footer: {
                    Text("Names the screenplay's title page and exports. The file name itself belongs to Documents — long-press it there.")
                }

                Section {
                    Picker("Suggestions", selection: predictionMode) {
                        ForEach(PredictionMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.symbol)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Writing")
                } footer: {
                    Text("\(editor.predictionMode.detail). Suggestions run on this iPhone. Press Space to accept the visible completion.")
                }

                Section {
                    Picker("Page Size", selection: $pageFormat) {
                        ForEach(PageFormat.allCases) { format in
                            Text(format.title).tag(format)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Script Options")
                } footer: {
                    Text("US Letter is the Hollywood standard. A4 reflows pagination, page counts, and the PDF.")
                }

                Section {
                    Link(destination: URL(string: "mailto:feedback@draftfirst.app")!) {
                        Label("Send Feedback", systemImage: "envelope")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: versionString)
                    if let engineVersion = editor.engineVersion {
                        LabeledContent("Engine", value: engineVersion)
                    }
                }
            }
            .tint(.primary)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename Screenplay", isPresented: $renamesScreenplay) {
                TextField("Screenplay Title", text: $renameDraft)
                Button("Rename", action: commitRename)
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    private var predictionMode: Binding<PredictionMode> {
        Binding(
            get: { editor.predictionMode },
            set: { mode in editor.setPredictionMode(mode) }
        )
    }

    /// Renaming the screenplay retitles its title page — the title is the
    /// document's identity everywhere Draft First shows it.
    private func commitRename() {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        editor.updateTitlePage(
            title: trimmed,
            writer: editor.titlePageValue(for: "Author") ?? "",
            credit: editor.titlePageValue(for: "Credit") ?? "written by"
        )
    }
}
