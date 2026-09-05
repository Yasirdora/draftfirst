import EDraftCore
import EDraftEngine
import SwiftUI

/// The right-hand pane: properties of the selection, and the title page
/// in place of a sheet. Arrangement is not under test; every fact it
/// shows is.
struct InspectorPane: View {
    let editor: EditorState
    @Bindable var chrome: InspectorChrome

    var body: some View {
        VStack(spacing: 0) {
            Picker("Inspector", selection: $chrome.segment) {
                Text("Title").tag(InspectorFocus.title)
                Text("Scene").tag(InspectorFocus.scene)
                Text("Character").tag(InspectorFocus.character)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            switch chrome.segment {
            case .title:
                TitleInspector(editor: editor)
            case .scene:
                SceneInspector(editor: editor)
            case .character:
                CharacterInspector(editor: editor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onChange(of: editor.activeElementID) { _, _ in
            chrome.follow(kind: editor.activeKind)
        }
    }
}

// MARK: - Title

/// Fields in place. The phone's title page is a sheet of drill-downs;
/// a desk edits them while the page stays in view. Each commit is one
/// `setTitlePageEntry` — the same channel the sheet uses.
private struct TitleInspector: View {
    let editor: EditorState
    @State private var title = ""
    @State private var writers = ""
    @State private var contact = ""
    @FocusState private var focused: Field?

    private enum Field { case title, writers, contact }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $title, axis: .vertical)
                    .focused($focused, equals: .title)
                    .onSubmit { commitTitle() }
                if TitleCredits.StandardCredit.matching(creditStored) != nil {
                    Picker("Credit", selection: creditBinding) {
                        ForEach(TitleCredits.StandardCredit.allCases, id: \.self) { option in
                            Text(option.displayTitle).tag(option.rawValue)
                        }
                    }
                } else {
                    LabeledContent("Credit", value: creditStored)
                }
                TextField("Writers", text: $writers, axis: .vertical)
                    .focused($focused, equals: .writers)
                    .onSubmit { commitWriters() }
            }
            Section("Contact") {
                TextField("Contact", text: $contact, axis: .vertical)
                    .focused($focused, equals: .contact)
                    .onSubmit { commitContact() }
            }
            if !extraCredits.isEmpty {
                Section("Credits") {
                    ForEach(extraCredits, id: \.key) { entry in
                        LabeledContent(entry.key, value: entry.values.joined(separator: " "))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
        .onChange(of: focused) { was, now in
            if was != now { commit(was) }
        }
        .onChange(of: editor.screenplay.titlePage) { _, _ in
            if focused == nil { load() }
        }
    }

    private var creditStored: String {
        editor.titlePageValue(for: "Credit") ?? TitleCredits.StandardCredit.writtenBy.rawValue
    }

    private var extraCredits: [EDraftCore.TitlePageEntry] {
        editor.screenplay.titlePage.filter { entry in
            !["title", "credit", "author", "contact"].contains(entry.key.lowercased())
        }
    }

    private var creditBinding: Binding<String> {
        Binding(
            get: { editor.titlePageValue(for: "Credit") ?? TitleCredits.StandardCredit.writtenBy.rawValue },
            set: { editor.setTitlePageEntry("Credit", values: [$0]) }
        )
    }

    private func load() {
        title = editor.titlePageValue(for: "Title") ?? ""
        writers = editor.titlePageValue(for: "Author") ?? ""
        contact = editor.titlePageValues(for: "Contact").joined(separator: "\n")
    }

    private func commit(_ field: Field?) {
        switch field {
        case .title: commitTitle()
        case .writers: commitWriters()
        case .contact: commitContact()
        case nil: break
        }
    }

    private func commitTitle() {
        editor.setTitlePageEntry("Title", values: [title])
    }

    private func commitWriters() {
        let values = writers
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
        editor.setTitlePageEntry("Author", values: values.isEmpty ? [writers] : values)
    }

    private func commitContact() {
        let values = contact
            .split(whereSeparator: { $0.isNewline })
            .map(String.init)
        editor.setTitlePageEntry("Contact", values: values)
    }
}

// MARK: - Scene

private struct SceneInspector: View {
    let editor: EditorState

    var body: some View {
        if let info = inspection {
            Form {
                Section {
                    LabeledContent("Number", value: info.row.label)
                    LabeledContent("Page", value: pageLabel(info))
                    LabeledContent("Length", value: lengthLabel(info))
                }
                Section("Characters") {
                    if info.characters.isEmpty {
                        Text("No one speaks in this scene.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(info.characters, id: \.self) { name in
                            Text(name)
                        }
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            empty("Start a scene heading to inspect a scene.")
        }
    }

    private var inspection: SceneInspection? {
        guard let id = editor.activeElementID else { return nil }
        return editor.sceneInspection(containing: id)
    }

    private func pageLabel(_ info: SceneInspection) -> String {
        guard let start = info.startPage else { return "—" }
        if let end = info.endPage, end != start {
            return "\(start)–\(end)"
        }
        return "\(start)"
    }

    private func lengthLabel(_ info: SceneInspection) -> String {
        let lines = info.lines == 1 ? "1 line" : "\(info.lines) lines"
        guard let start = info.startPage, let end = info.endPage, end != start else {
            return lines
        }
        return "\(lines) · pp. \(start)–\(end)"
    }

    private func empty(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(16)
    }
}

// MARK: - Character

private struct CharacterInspector: View {
    let editor: EditorState
    @State private var isRenaming = false
    @State private var draftName = ""
    @State private var mentionCount = 0

    var body: some View {
        if let name {
            Form {
                Section {
                    LabeledContent("Cues", value: "\(cues)")
                    LabeledContent("Scenes", value: "\(appearances.count)")
                    LabeledContent("First", value: firstLast.0)
                    LabeledContent("Last", value: firstLast.1)
                }
                Section {
                    Button("Rename Character…") { beginRename(name) }
                }
            }
            .formStyle(.grouped)
            .alert("Rename Character", isPresented: $isRenaming) {
                TextField("New name", text: $draftName)
                if mentionCount > 0 {
                    Button("Rename Everywhere") { rename(name, includingMentions: true) }
                    Button("Cues Only") { rename(name) }
                } else {
                    Button("Rename") { rename(name) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(warning(for: name))
            }
        } else {
            Text("Place the caret on a cue to inspect a character.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(16)
        }
    }

    private var name: String? {
        guard let id = editor.activeElementID else { return nil }
        return editor.enclosingCharacterName(for: id)
    }

    private var appearances: [CharacterAppearance] {
        guard let name else { return [] }
        return editor.appearances(of: name)
    }

    private var cues: Int {
        guard let name else { return 0 }
        return editor.cast.first { $0.name == name }?.cues ?? 0
    }

    private var firstLast: (String, String) {
        func label(_ appearance: CharacterAppearance?) -> String {
            guard let appearance else { return "—" }
            if let page = appearance.page {
                return "\(appearance.heading) · p. \(page)"
            }
            return appearance.heading
        }
        return (label(appearances.first), label(appearances.last))
    }

    private func beginRename(_ name: String) {
        draftName = name.capitalized
        mentionCount = editor.characterMentions(name)
        isRenaming = true
    }

    private func rename(_ name: String, includingMentions: Bool = false) {
        _ = editor.renameCharacter(name, to: draftName, includingMentions: includingMentions)
    }

    private func warning(for name: String) -> String {
        CharacterRename.warning(
            name: name,
            cues: cues,
            mentions: mentionCount,
            merges: editor.characterExists(draftName)
                && EditorState.canonicalCharacterName(draftName) != name
        )
    }
}
