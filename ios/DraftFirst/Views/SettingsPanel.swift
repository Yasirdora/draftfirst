import SwiftUI

/// The long-tail preferences behind the document menu's Settings… —
/// writing assistance, page & format, feedback, about. The five
/// destinations a writer touches daily stay in the menu itself, and file
/// management — including rename — stays in Documents, where the system's
/// browser already does it well.
///
/// Structure follows the iOS Settings idiom: each row names its value and
/// pushes a focused page whose selections commit with a checkmark. Nothing
/// here is a form to fill in.
struct SettingsPanel: View {
    let editor: EditorState

    @Environment(\.dismiss) private var dismiss
    @AppStorage("pageFormat") private var pageFormat: PageFormat = .letter

    var body: some View {
        NavigationStack {
            Form {
                Section("Writing") {
                    NavigationLink {
                        WritingAssistanceView(editor: editor)
                    } label: {
                        LabeledContent("Writing Assistance", value: editor.predictionMode.title)
                    }
                }

                Section("Page & Format") {
                    NavigationLink {
                        PaperSizeView()
                    } label: {
                        LabeledContent("Paper Size", value: pageFormat.title)
                    }
                    NavigationLink {
                        PaginationView()
                    } label: {
                        Text("Pagination")
                    }
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
        }
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }
}

// MARK: - Writing

/// How much help the ghost offers: Smart, Format Only, or Off. The
/// checkmark commits immediately — the iOS Settings convention.
private struct WritingAssistanceView: View {
    let editor: EditorState

    var body: some View {
        Form {
            Section {
                ForEach(PredictionMode.allCases) { mode in
                    Button {
                        editor.setPredictionMode(mode)
                    } label: {
                        HStack {
                            Label(mode.title, systemImage: mode.symbol)
                                .foregroundStyle(.primary)
                            Spacer()
                            if editor.predictionMode == mode {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } footer: {
                Text("\(editor.predictionMode.detail). Suggestions run on this iPhone. Press Space to accept the visible completion.")
            }
        }
        .navigationTitle("Writing Assistance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Page & Format

private struct PaperSizeView: View {
    @AppStorage("pageFormat") private var pageFormat: PageFormat = .letter

    var body: some View {
        Form {
            Section {
                ForEach(PageFormat.allCases) { format in
                    Button {
                        pageFormat = format
                    } label: {
                        HStack {
                            Text(format.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if pageFormat == format {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } footer: {
                Text("US Letter is the Hollywood standard. A4 reflows pagination, page counts, and the PDF.")
            }
        }
        .navigationTitle("Paper Size")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One format today — the row returns when a second format exists to
/// choose between.
private struct PaginationView: View {
    @AppStorage("showPageNumbers") private var showPageNumbers = true

    var body: some View {
        Form {
            Section {
                Toggle("Page Numbers", isOn: $showPageNumbers)
            } footer: {
                Text("Prints page numbers top-right from page 2 on, as productions expect.")
            }
        }
        .navigationTitle("Pagination")
        .navigationBarTitleDisplayMode(.inline)
    }
}
