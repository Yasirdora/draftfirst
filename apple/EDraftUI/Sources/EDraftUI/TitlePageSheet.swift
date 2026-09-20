import EDraftCore
import SwiftUI
import EDraftEngine

/// The title page as a grouped, native sheet — Content, Contact, Options.
///
/// Design rules (from the shipped spec): no giant card, no explanatory
/// marketing copy, and no screen that asks the writer to understand
/// screenplay formatting. Pickers commit on tap and return; text editors
/// hold a local draft and write once when they close, so every change is
/// exactly one undoable step. The document model is the only source of
/// truth — the sheet always reopens to the completed state.
///
/// On macOS the sheet follows Apple settings sheets: a scrolling title,
/// no header back chevron, Back and Done at the bottom trailing edge.
/// iOS keeps the existing Form and navigation bar.
public struct TitlePageSheet: View {
    let editor: EditorState

    @Environment(\.dismiss) private var dismiss
    @AppStorage(ScreenplayExportPreference.includeTitlePageKey) private var includeInPDF = true
    @State private var path: [TitlePageRoute] = []

    public init(editor: EditorState) {
        self.editor = editor
    }

    public var body: some View {
        #if os(macOS)
        macSheet
        #else
        iosSheet
        #endif
    }

    #if os(macOS)
    private var macSheet: some View {
        VStack(spacing: 0) {
            NavigationStack(path: $path) {
                macRootForm
                    .navigationBarBackButtonHidden(true)
                    .navigationDestination(for: TitlePageRoute.self) { route in
                        macPage(route)
                            .navigationBarBackButtonHidden(true)
                    }
            }
            .formStyle(.grouped)
            macButtonBar
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 480)
        .presentationSizing(.form)
    }

    private var macRootForm: some View {
        Form {
            Section {
                NavigationLink(value: TitlePageRoute.title) {
                    LabeledContent("Title", value: title.isEmpty ? "Untitled Screenplay" : title)
                }
                NavigationLink(value: TitlePageRoute.credit) {
                    LabeledContent("Credit", value: creditDisplay)
                }
                NavigationLink(value: TitlePageRoute.writers) {
                    LabeledContent("Writers", value: writers.isEmpty ? "Not Set" : writers)
                }
                additionalCreditRows
                NavigationLink(value: TitlePageRoute.addCredit) {
                    Text("Add Credit")
                }
            } header: {
                titlePageSectionHeader("Title Page", section: "Content")
            }
            Section("Contact") {
                NavigationLink(value: TitlePageRoute.contact) {
                    LabeledContent("Contact Information", value: contactSummary)
                }
            }
            Section("Options") {
                Toggle("Include in PDF Export", isOn: $includeInPDF)
            }
        }
        .titlePageFormChrome()
    }

    @ViewBuilder
    private func macPage(_ route: TitlePageRoute) -> some View {
        switch route {
        case .title:
            TitleFieldView(editor: editor)
        case .credit:
            CreditPickerView(editor: editor)
        case .writers:
            WritersEditorView(editor: editor)
        case .addCredit:
            AddCreditView(editor: editor)
        case .contact:
            ContactEditorView(editor: editor)
        case .extra(let key):
            CreditEntryEditor(editor: editor, key: key)
        case .creditCustom:
            CreditEntryEditor(editor: editor, key: "Credit")
        case .source:
            CreditEntryEditor(editor: editor, key: "Source")
        case .additionalWriting:
            CreditEntryEditor(editor: editor, key: "Additional writing by")
        case .customCredit:
            CustomCreditEditor(editor: editor)
        }
    }

    private var macButtonBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 12) {
                Spacer()
                if !path.isEmpty {
                    Button("Back") { path.removeLast() }
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(.bar)
    }
    #endif

    #if os(iOS)
    private var iosSheet: some View {
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
            .compactTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    #endif

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
    /// each editable and deletable. Derived from the page's own lines
    /// (RFC-TITLE-PAGE D3), so a row can only name what the page says.
    @ViewBuilder
    private var additionalCreditRows: some View {
        ForEach(
            editor.titlePageEntries.filter { entry in
                !["title", "credit", "author", "contact"].contains(entry.key.lowercased())
            },
            id: \.key
        ) { entry in
            #if os(macOS)
            NavigationLink(value: TitlePageRoute.extra(entry.key)) {
                LabeledContent(entry.key, value: entry.values.joined(separator: " "))
            }
            #else
            NavigationLink {
                CreditEntryEditor(editor: editor, key: entry.key)
            } label: {
                LabeledContent(entry.key, value: entry.values.joined(separator: " "))
            }
            #endif
        }
    }
}

private enum TitlePageRoute: Hashable {
    case title
    case credit
    case writers
    case addCredit
    case contact
    case extra(String)
    case creditCustom
    case source
    case additionalWriting
    case customCredit

    var title: String {
        switch self {
        case .title: "Title"
        case .credit: "Writing Credit"
        case .writers: "Writers"
        case .addCredit: "Add Credit"
        case .contact: "Contact"
        case .extra(let key): key
        case .creditCustom: "Credit"
        case .source: "Source"
        case .additionalWriting: "Additional writing by"
        case .customCredit: "Custom Credit"
        }
    }
}

#if os(macOS)
@ViewBuilder
func titlePageSectionHeader(_ title: String, section: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 14) {
        Text(title)
            .font(.title.weight(.bold))
            .foregroundStyle(.primary)
            .textCase(nil)
        if let section {
            Text(section)
                .foregroundStyle(.secondary)
                .textCase(nil)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.bottom, 2)
}
#endif

// MARK: - Title

/// One focused question, keyboard already up: "What is your screenplay
/// called?" The page stores the title in its printed form — capitals, as
/// screenplay convention demands — so the field shows and commits capitals.
/// On macOS the same draft is a grouped field, still written once on close.
private struct TitleFieldView: View {
    let editor: EditorState
    @State private var draft: String
    @FocusState private var focused: Bool

    public init(editor: EditorState) {
        self.editor = editor
        _draft = State(initialValue: editor.titlePageValue(for: "Title") ?? "")
    }

    public var body: some View {
        titleField
            .titlePageNavTitle("Title")
            .onAppear { focused = true }
            .onDisappear {
                editor.setTitlePageEntry("Title", values: [draft])
            }
    }

    @ViewBuilder
    private var titleField: some View {
        #if os(macOS)
        Form {
            Section {
                TextField("Title", text: $draft)
                    .titleCasedInput()
                    .focused($focused)
                    .submitsAsDone()
            } header: {
                titlePageSectionHeader("Title")
            }
        }
        .titlePageFormChrome()
        #else
        VStack(spacing: 20) {
            Spacer()
            Text("What is your screenplay called?")
                .font(.title3)
                .foregroundStyle(.secondary)
            TextField("Title", text: $draft)
                .font(.title2)
                .multilineTextAlignment(.center)
                .titleCasedInput()
                .focused($focused)
                .submitsAsDone()
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
        #endif
    }
}

// MARK: - Credit

/// The writing credit is chosen, never typed: the standard phrases cover
/// the overwhelming majority of screenplays, and Custom is the escape
/// hatch. Selection commits immediately and returns.
private struct CreditPickerView: View {
    let editor: EditorState
    @Environment(\.dismiss) private var dismiss

    public var body: some View {
        Form {
            Section {
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
                    .buttonStyle(.plain)
                }
            } header: {
                #if os(macOS)
                titlePageSectionHeader("Writing Credit", section: "Standard")
                #else
                Text("Standard")
                #endif
            }
            Section {
                #if os(macOS)
                NavigationLink(value: TitlePageRoute.creditCustom) {
                    Text("Custom")
                }
                #else
                NavigationLink("Custom") {
                    CreditEntryEditor(editor: editor, key: "Credit")
                }
                #endif
            }
        }
        .titlePageFormChrome()
        .titlePageNavTitle("Writing Credit")
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

    public init(editor: EditorState) {
        self.editor = editor
        let stored = editor.titlePageValue(for: "Author") ?? ""
        let parsed = TitleCredits.parseAuthors(stored)
        _writers = State(initialValue: parsed.isEmpty
            ? [WriterCredit(name: "", joiner: .team)]
            : parsed)
    }

    @FocusState private var focusedWriter: Int?

    public var body: some View {
        VStack(spacing: 0) {
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
                                .focused($focusedWriter, equals: index)
                        }
                    }
                    .onDelete { offsets in
                        writers.remove(atOffsets: offsets)
                        if writers.isEmpty {
                            writers = [WriterCredit(name: "", joiner: .team)]
                        }
                    }
                } header: {
                    #if os(macOS)
                    titlePageSectionHeader("Writers")
                    #endif
                } footer: {
                    if writers.count > 1 {
                        Text("& joins a writing team; \"and\" joins writers of separate drafts.")
                    }
                }
            }
            .titlePageFormChrome()

            Button("Add Writer") {
                writers.append(WriterCredit(name: "", joiner: .separate))
                focusedWriter = writers.count - 1
            }
            .buttonStyle(.bordered)
            .padding(.vertical, 12)
        }
        .titlePageNavTitle("Writers")
        .onAppear { focusedWriter = 0 }
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

    public var body: some View {
        Form {
            Section {
                #if os(macOS)
                NavigationLink(value: TitlePageRoute.source) {
                    Text("Based On")
                }
                NavigationLink(value: TitlePageRoute.additionalWriting) {
                    Text("Additional Writing By")
                }
                NavigationLink(value: TitlePageRoute.customCredit) {
                    Text("Custom")
                }
                #else
                NavigationLink("Based On") {
                    CreditEntryEditor(editor: editor, key: "Source")
                }
                NavigationLink("Additional Writing By") {
                    CreditEntryEditor(editor: editor, key: "Additional writing by")
                }
                NavigationLink("Custom") {
                    CustomCreditEditor(editor: editor)
                }
                #endif
            } header: {
                #if os(macOS)
                titlePageSectionHeader("Add Credit")
                #endif
            }
        }
        .titlePageFormChrome()
        .titlePageNavTitle("Add Credit")
    }
}

/// One value under a known key. Commits once, when the view closes.
private struct CreditEntryEditor: View {
    let editor: EditorState
    let key: String
    @State private var draft: String
    @FocusState private var focused: Bool

    public init(editor: EditorState, key: String) {
        self.editor = editor
        self.key = key
        _draft = State(initialValue: editor.titlePageValues(for: key).joined(separator: " "))
    }

    public var body: some View {
        Form {
            Section {
                TextField(key, text: $draft)
                    .focused($focused)
            } header: {
                #if os(macOS)
                titlePageSectionHeader(key)
                #endif
            }
        }
        .titlePageFormChrome()
        .titlePageNavTitle(key)
        .onAppear { focused = true }
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
    @FocusState private var focused: Bool

    public var body: some View {
        Form {
            Section {
                TextField("Label", text: $label)
                    .focused($focused)
                TextField("Text", text: $text)
            } header: {
                #if os(macOS)
                titlePageSectionHeader("Custom Credit")
                #endif
            }
        }
        .titlePageFormChrome()
        .titlePageNavTitle("Custom Credit")
        .onAppear { focused = true }
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
    @FocusState private var focused: Bool

    public init(editor: EditorState) {
        self.editor = editor
        let lines = editor.titlePageValues(for: "Contact")
        _name = State(initialValue: lines.indices.contains(0) ? lines[0] : "")
        _email = State(initialValue: lines.indices.contains(1) ? lines[1] : "")
        _phone = State(initialValue: lines.indices.contains(2) ? lines[2] : "")
        _address = State(initialValue: lines.indices.contains(3) ? lines[3] : "")
    }

    public var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                    .textContentType(.name)
                    .focused($focused)
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .softKeyboard(.email)
                TextField("Phone", text: $phone)
                    .textContentType(.telephoneNumber)
                    .softKeyboard(.phone)
                TextField("Address", text: $address)
                    .textContentType(.fullStreetAddress)
            } header: {
                #if os(macOS)
                titlePageSectionHeader("Contact", section: "Contact Details")
                #else
                Text("Contact Details")
                #endif
            }
        }
        .titlePageFormChrome()
        .titlePageNavTitle("Contact")
        .onAppear { focused = true }
        .onDisappear {
            editor.setTitlePageEntry("Contact", values: [name, email, phone, address])
        }
    }
}

private extension View {
    func titlePageFormChrome() -> some View {
        #if os(macOS)
        formStyle(.grouped)
        #else
        self
        #endif
    }

    func titlePageNavTitle(_ title: String) -> some View {
        #if os(macOS)
        self
        #else
        navigationTitle(title).compactTitle()
        #endif
    }
}
