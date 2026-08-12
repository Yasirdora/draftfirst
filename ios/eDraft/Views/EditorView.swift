import SwiftUI

/// The product: a borderless page, a whisper that teaches, and nothing else.
///
/// Every keystroke runs the engine loop — parse, map the caret's block,
/// predict, ghost — inside JavaScriptCore. Autosaves on every pause.
struct EditorView: View {

	@AppStorage("edraft.appearance") private var appearance = "system"

	@State private var engine: EngineFacade?
	@State private var engineError: String?

	@State private var documentName = DocumentStore.starter.name
	@State private var text = DocumentStore.starter.text
	@State private var caret = DocumentStore.starter.text.utf16.count

	@State private var elements: [[String: Any]] = []
	@State private var styledLines: [BlockMapper.StyledLine] = []
	@State private var currentElementName = "Action"
	@State private var cueElementIndex: Int?
	@State private var ghost = ""
	@State private var ghostLocation = 0
	@State private var whisperWhy = ""
	@State private var caretRequest: Int?

	@State private var showDiagnostics = false
	@State private var showRename = false
	@State private var renameDraft = ""

	private let store = DocumentStore()
	@State private var saveTask: Task<Void, Never>?

	private var preferredScheme: ColorScheme? {
		switch appearance {
		case "light": return .light
		case "dark": return .dark
		default: return nil
		}
	}

	var body: some View {
		NavigationStack {
			ScriptTextView(
				text: $text,
				elements: elements,
				ghost: ghost,
				ghostLocation: ghostLocation,
				whisperWhy: whisperWhy,
				currentElementName: currentElementName,
				cueElementIndex: cueElementIndex,
				caretRequest: caretRequest,
				onTextChange: handleTextChange,
				onCaretChange: handleCaretChange,
				onAccept: acceptGhost,
				onElement: applyElement,
				onDismissKeyboard: {}
			)
			.background(Color(uiColor: .systemBackground))
			.navigationTitle(documentName)
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Menu {
						Section("Theme") {
							Button { appearance = "system" } label: {
								Label("System", systemImage: appearance == "system" ? "checkmark" : "")
							}
							Button { appearance = "light" } label: {
								Label("Light", systemImage: appearance == "light" ? "checkmark" : "")
							}
							Button { appearance = "dark" } label: {
								Label("Dark", systemImage: appearance == "dark" ? "checkmark" : "")
							}
						}
						Section {
							Button {
								renameDraft = documentName
								showRename = true
							} label: {
								Label("Rename…", systemImage: "pencil")
							}
							Button { showDiagnostics = true } label: {
								Label("Diagnostics", systemImage: "stethoscope")
							}
						}
					} label: {
						Image(systemName: "ellipsis.circle")
					}
				}
			}
			.alert("Rename Screenplay", isPresented: $showRename) {
				TextField("Title", text: $renameDraft)
				Button("Cancel", role: .cancel) {}
				Button("Rename") {
					let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
					if !trimmed.isEmpty {
						documentName = trimmed
						scheduleSave()
					}
				}
			}
			.sheet(isPresented: $showDiagnostics) {
				DiagnosticsView(engine: engine)
			}
			.onAppear(perform: boot)
			.preferredColorScheme(preferredScheme)
		}
	}

	// MARK: - Boot & persistence

	private func boot() {
		if engine == nil, engineError == nil {
			do { engine = try EngineFacade() } catch { engineError = error.localizedDescription }
		}
		if let saved = store.load() {
			documentName = saved.name
			text = saved.text
			caret = text.utf16.count
		}
		refreshEngine()
		caretRequest = caret
	}

	private func scheduleSave() {
		saveTask?.cancel()
		let name = documentName
		let snapshot = text
		saveTask = Task {
			try? await Task.sleep(for: .milliseconds(400))
			guard !Task.isCancelled else { return }
			store.save(name: name, text: snapshot)
		}
	}

	// MARK: - Engine loop

	private func handleTextChange(_ newText: String, _ newCaret: Int) {
		text = newText
		caret = newCaret
		caretRequest = nil
		refreshEngine()
		scheduleSave()
	}

	private func handleCaretChange(_ newCaret: Int) {
		if caretRequest != nil { caretRequest = nil }
		guard newCaret != caret else { return }
		caret = newCaret
		refreshEngine()
	}

	private func refreshEngine() {
		guard let engine else { return }
		do {
			let screenplayJSON = try engine.parse(fountain: text)
			let all = try engine.elements(ofScreenplayJSON: screenplayJSON)
			elements = all
			styledLines = BlockMapper.map(text: text, elements: all)

			let source = text as NSString
			guard let line = BlockMapper.line(containing: min(caret, source.length), in: styledLines) ?? styledLines.last else {
				currentElementName = "Action"
				ghost = ""
				whisperWhy = ""
				cueElementIndex = nil
				return
			}
			currentElementName = Self.displayName(for: line.type)

			// One line is one element — the engine's own unit of meaning.
			let lineText = source.substring(with: line.range)
			let lineEnd = line.range.location + line.range.length

			// Whispers live where the writing happens: the end of the line.
			guard caret == lineEnd else {
				ghost = ""
				whisperWhy = ""
				cueElementIndex = nil
				return
			}

			// A bare all-caps line mid-typing parses as action (Fountain needs a
			// following dialogue line to prove a cue). The writer means a cue —
			// so ask the engine for character candidates and prefer them.
			let looksLikeCue = line.type == "action"
				&& lineText.count <= 30
				&& lineText == lineText.uppercased()
				&& lineText.rangeOfCharacter(from: .letters) != nil
			let predictType = looksLikeCue ? "character" : line.type
			if looksLikeCue { currentElementName = "Character" }
			cueElementIndex = looksLikeCue ? line.elementIndex : nil

			let predictions = try engine.predict(
				screenplayJSON: screenplayJSON,
				type: predictType,
				text: lineText,
				index: line.elementIndex
			)
			if let first = predictions.first(where: { !($0.hint ?? false) }) {
				let suffix = try engine.ghostSuffix(candidate: first.text, blockText: lineText)
				ghost = suffix
				ghostLocation = lineEnd
				whisperWhy = first.why
			} else {
				ghost = ""
				whisperWhy = ""
			}
		} catch {
			ghost = ""
			whisperWhy = ""
			cueElementIndex = nil
		}
	}

	// MARK: - Accept & element actions

	private func acceptGhost() {
		guard !ghost.isEmpty else { return }
		let source = text as NSString
		let location = min(ghostLocation, source.length)
		text = source.replacingCharacters(in: NSRange(location: location, length: 0), with: ghost)
		caret = location + (ghost as NSString).length
		caretRequest = caret
		ghost = ""
		whisperWhy = ""
		refreshEngine()
		scheduleSave()
	}

	private func applyElement(_ type: String) {
		let source = text as NSString

		// The caret's ACTUAL line — which may be blank. A choice made on a
		// blank line must never touch the previous line.
		var lineRange = source.lineRange(for: NSRange(location: min(caret, source.length), length: 0))
		if lineRange.length > 0, source.character(at: lineRange.location + lineRange.length - 1) == 10 {
			lineRange.length -= 1
		}
		let content = source.substring(with: lineRange)
		let isBlank = content.trimmingCharacters(in: .whitespaces).isEmpty

		switch type {
		case "scene":
			guard isBlank else { return }
			insertAtCaret("INT. ")
		case "transition":
			guard isBlank else { return }
			insertAtCaret("CUT TO:")
		case "parenthetical":
			if isBlank {
				insertAtCaret("(")
			} else {
				guard !content.hasPrefix("(") else { return }
				replace(lineRange, with: "(\(content))")
			}
		case "character":
			guard !isBlank else { return }
			replace(lineRange, with: content.uppercased())
		case "dialogue":
			guard !isBlank, content.hasPrefix("("), content.hasSuffix(")") else { return }
			replace(lineRange, with: String(content.dropFirst().dropLast()))
		case "action":
			// The honest conversion: a cue read aloud as description.
			guard !isBlank else { return }
			let styled = BlockMapper.line(containing: min(caret, source.length), in: styledLines)
			guard styled?.type == "character" else { return }
			replace(lineRange, with: content.capitalized)
		case "pagebreak":
			insertAtCaret(caret >= source.length ? "\n\n===" : "\n\n===\n\n")
		default:
			break
		}
	}

	private func insertAtCaret(_ insertion: String) {
		let source = text as NSString
		let location = min(caret, source.length)
		text = source.replacingCharacters(in: NSRange(location: location, length: 0), with: insertion)
		caret = location + (insertion as NSString).length
		caretRequest = caret
		refreshEngine()
		scheduleSave()
	}

	private func replace(_ range: NSRange, with replacement: String) {
		let source = text as NSString
		text = source.replacingCharacters(in: range, with: replacement)
		let newCaret = range.location + (replacement as NSString).length
		caret = newCaret
		caretRequest = newCaret
		refreshEngine()
		scheduleSave()
	}

	// MARK: - Presentation names

	static func displayName(for type: String) -> String {
		switch type {
		case "scene": return "Scene"
		case "action": return "Action"
		case "character": return "Character"
		case "parenthetical": return "Parenthetical"
		case "dialogue": return "Dialogue"
		case "transition": return "Transition"
		case "shot": return "Shot"
		case "general": return "General"
		case "centered": return "Centered"
		case "pagebreak": return "Page Break"
		case "lyrics": return "Lyrics"
		case "section": return "Section"
		case "synopsis": return "Synopsis"
		case "note": return "Note"
		default: return type.capitalized
		}
	}
}

#Preview {
	EditorView()
}
