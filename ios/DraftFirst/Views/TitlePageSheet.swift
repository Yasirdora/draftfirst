import SwiftUI
import DraftFirstEngine

/// The title page as a grouped, native sheet — Content, Contact, Options.
///
/// Design rules (from the shipped spec): no giant card, no explanatory
/// marketing copy, and no screen that asks the writer to understand
/// screenplay formatting. Pickers commit on tap and return; text editors
/// hold a local draft and write once when they close, so every change is
/// exactly one undoable step. The document model is the only source of
/// truth — the sheet always reopens to the completed state.
struct TitlePageSheet: View {
    let editor: EditorState

    @Environment(\.dismiss) private var dismiss
    @AppStorage(ScreenplayExporter.includeTitlePageKey) private var includeInPDF = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    NavigationLink {
                        TitleFieldView(editor: editor)
                    } label: {
                        LabeledContent("Title", value: title.isEmpty ? "Untitled Screenplay" : title)
                    }
                    NavigationLink {
                        CreditPickerView(editor: editor)
                    } label: {
                        LabeledContent("Credit", value: creditDisplay)
                    }
                    NavigationLink {
                        WritersEditorView(editor: editor)
                    } label: {
                        LabeledContent("Writers", value: writers.isEmpty ? "Not Set" : writers)
                    }
                    additionalCreditRows
                    NavigationLink {
                        AddCreditView(editor: editor)
                    } label: {
                        Text("Add Credit")
                    }
                }

                Section("Contact") {
                    NavigationLink {
                        ContactEditorView(editor: editor)
                    } label: {
                        LabeledContent("Contact Information", value: contactSummary)
                    }
                }

                Section("Options") {
                    Toggle("Include in PDF Export", isOn: $includeInPDF)
                }
            }
            .navigationTitle("Title Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: Row values

    private var title: String { editor.titlePageValue(for: "Title") ?? "" }

    private var creditDisplay: String {
        let stored = editor.titlePageValue(for: "Credit") ?? "written by"
        return TitleCredits.StandardCredit.matching(stored)?.displayTitle
            ?? stored.capitalized
    }

    private var writers: String { editor.titlePageValue(for: "Author") ?? "" }

    private var contactSummary: String {
        let lines = editor.titlePageValues(for: "Contact")
        return lines.first ?? "None"
    }

    /// Entries beyond the fixed three — Source and any custom credits —
    /// each editable and deletable.
    @ViewBuilder
    private var additionalCreditRows: some View {
        ForEach(
            editor.screenplay.titlePage.filter { entry in
                !["title", "credit", "author", "contact"].contains(entry.key.lowercased())
            },
            id: \.key
        ) { entry in
            NavigationLink {
                CreditEntryEditor(editor: editor, key: entry.key, prompt: entry.key)
            } label: {
                LabeledContent(entry.key, value: entry.values.joined(separator: " "))
            }
        }
    }
}

// MARK: - Title

/// One focused question, keyboard already up: "What is your screenplay
/// called?" The renderer owns placement and capitalization on the page.
private struct TitleFieldView: View {
    let editor: EditorState
    @State private var draft: String
    @FocusState private var focused: Bool

    init(editor: EditorState) {
        self.editor = editor
        _draft = State(initialValue: editor.titlePageValue(for: "Title") ?? "")
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("What is your screenplay called?")
                .font(.title3)
                .foregroundStyle(.secondary)
            TextField("The Last Station", text: $draft)
                .font(.title2)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .focused($focused)
                .submitLabel(.done)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
        .navigationTitle("Title")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .onDisappear {
            editor.setTitlePageEntry("Title", values: [draft])
        }
    }
}

// MARK: - Credit

/// The writing credit is chosen, never typed: the standard phrases cover
/// the overwhelming majority of screenplays, and Custom is the escape
/// hatch. Selection commits immediately and returns.
private struct CreditPickerView: View {
    let editor: EditorState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Standard") {
                ForEach(TitleCredits.StandardCredit.allCases, id: \.rawValue) { option in
                    Button {
                        editor.setTitlePageEntry("Credit", values: [option.rawValue])
                        dismiss()
                    } label: {
                        HStack {
                            Text(option.displayTitle)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isCurrent(option) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            Section {
                NavigationLink("Custom") {
                    CreditEntryEditor(editor: editor, key: "Credit", prompt: "screenplay by")
                }
            }
        }
        .navigationTitle("Writing Credit")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func isCurrent(_ option: TitleCredits.StandardCredit) -> Bool {
        TitleCredits.StandardCredit.matching(editor.titlePageValue(for: "Credit") ?? "written by") == option
    }
}

// MARK: - Writers

/// The credit line as structured writers: a list of names, and for every
/// writer after the first the joiner — `&` for a team, `and` for separate
/// drafts. The model renders the line; the writer never types a joiner.
private struct WritersEditorView: View {
    let editor: EditorState
    @State private var writers: [WriterCredit]

    init(editor: EditorState) {
        self.editor = editor
        let stored = editor.titlePageValue(for: "Author") ?? ""
        _writers = State(initialValue: TitleCredits.parseAuthors(stored))
    }

    var body: some View {
        Form {
            Section {
                ForEach(Array(writers.indices), id: \.self) { index in
                    HStack(spacing: 12) {
                        if index > 0 {
                            Picker("Joiner", selection: $writers[index].joiner) {
                                Text("&").tag(WriterJoiner.team)
                                Text("and").tag(WriterJoiner.separate)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 96)
                            .labelsHidden()
                        }
                        TextField("Writer Name", text: $writers[index].name)
                            .textContentType(.name)
                    }
                }
                .onDelete { writers.remove(atOffsets: $0) }
            } footer: {
                Text("& joins a writing team; \"and\" joins writers of separate drafts.")
            }
            Section {
                Button("Add Writer") {
                    writers.append(WriterCredit(name: "", joiner: writers.isEmpty ? .team : .separate))
                }
            }
        }
        .navigationTitle("Writers")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            editor.setTitlePageEntry("Author", values: [TitleCredits.renderAuthors(writers)])
        }
    }
}

// MARK: - Additional credits

/// Templates for everything past the fixed three rows — the progressive
/// disclosure path that keeps the main sheet short.
private struct AddCreditView: View {
    let editor: EditorState

    var body: some View {
        Form {
            Section {
                NavigationLink("Based On") {
                    CreditEntryEditor(editor: editor, key: "Source", prompt: "the novel by John Smith")
                }
                NavigationLink("Additional Writing By") {
                    CreditEntryEditor(editor: editor, key: "Additional writing by", prompt: "Writer Name")
                }
                NavigationLink("Custom") {
                    CustomCreditEditor(editor: editor)
                }
            }
        }
        .navigationTitle("Add Credit")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One value under a known key. Commits once, when the view closes.
private struct CreditEntryEditor: View {
    let editor: EditorState
    let key: String
    let prompt: String
    @State private var draft: String

    init(editor: EditorState, key: String, prompt: String) {
        self.editor = editor
        self.key = key
        self.prompt = prompt
        _draft = State(initialValue: editor.titlePageValues(for: key).joined(separator: " "))
    }

    var body: some View {
        Form {
            Section {
                TextField(prompt, text: $draft)
            }
        }
        .navigationTitle(key)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            editor.setTitlePageEntry(key, values: [draft])
        }
    }
}

/// A credit pair the templates don't cover: the writer names both the
/// label and the text.
private struct CustomCreditEditor: View {
    let editor: EditorState
    @State private var label = ""
    @State private var text = ""

    var body: some View {
        Form {
            Section {
                TextField("Label (e.g. Story by)", text: $label)
                TextField("Text", text: $text)
            }
        }
        .navigationTitle("Custom Credit")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            let key = label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { return }
            editor.setTitlePageEntry(key, values: [text])
        }
    }
}

// MARK: - Contact

/// Contact details for this screenplay: four lines, bottom-left of the
/// title page. Empty fields simply don't render.
private struct ContactEditorView: View {
    let editor: EditorState
    @State private var name: String
    @State private var email: String
    @State private var phone: String
    @State private var address: String

    init(editor: EditorState) {
        self.editor = editor
        let lines = editor.titlePageValues(for: "Contact")
        _name = State(initialValue: lines.indices.contains(0) ? lines[0] : "")
        _email = State(initialValue: lines.indices.contains(1) ? lines[1] : "")
        _phone = State(initialValue: lines.indices.contains(2) ? lines[2] : "")
        _address = State(initialValue: lines.indices.contains(3) ? lines[3] : "")
    }

    var body: some View {
        Form {
            Section("Contact Details") {
                TextField("Name", text: $name)
                    .textContentType(.name)
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("Phone", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                TextField("Address", text: $address)
                    .textContentType(.fullStreetAddress)
            }
        }
        .navigationTitle("Contact")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear {
            editor.setTitlePageEntry("Contact", values: [name, email, phone, address])
        }
    }
}
