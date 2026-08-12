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
	@State private var whisperCandidate = ""
	@State private var caretRequest: Int?
	/// Snapshot for reverting the last accepted whisper (backspace or Undo pill).
	@State private var undoSnapshot: (beforeText: String, beforeCaret: Int, afterCaret: Int)?

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
				whisperCandidate: whisperCandidate,
				currentElementName: currentElementName,
				cueElementIndex: cueElementIndex,
				caretRequest: caretRequest,
				canUndoAccept: undoSnapshot != nil,
				onTextChange: handleTextChange,
				onCaretChange: handleCaretChange,
				onAccept: { acceptGhost() },
				onAcceptSpace: { acceptGhost(appending: " ") },
				onUndoAccept: undoAccept,
				onBackspace: consumeBackspace,
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
		undoSnapshot = nil // any fresh typing retires the undo offer
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
			// The caret's true line: the one holding it, or the one ending
			// exactly at it. No "last line" fallback — a wrong line whispers
			// a wrong ghost (and silently killed whispers mid-document).
			let pos = min(caret, source.length)
			guard let line = styledLines.first(where: {
				NSLocationInRange(pos, $0.range) || $0.range.location + $0.range.length == pos
			}) else {
				currentElementName = "Action"
				ghost = ""
				whisperCandidate = ""
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
				whisperCandidate = ""
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
				ghostLocation = suffix.isEmpty ? 0 : lineEnd
				whisperCandidate = suffix.isEmpty ? "" : first.text
			} else {
				ghost = ""
				whisperCandidate = ""
			}
		} catch {
			ghost = ""
			whisperCandidate = ""
			cueElementIndex = nil
		}
	}

	// MARK: - Accept & element actions

	/// Commit the whispered candidate. When the ghost is a strict suffix of
	/// the candidate, the completion owns the casing of the fragment it
	/// matched — a typed "d" accepting "DAY" writes "DAY", never "dAY".
	/// Glue suffixes (a leading space) insert as-is. `append` folds a
	/// trailing keystroke into the same atomic mutation (space-to-accept).
	private func acceptGhost(appending append: String = "") {
		guard !ghost.isEmpty, !whisperCandidate.isEmpty else { return }
		let source = text as NSString
		let location = min(ghostLocation, source.length)
		let candidate = whisperCandidate as NSString
		let suffix = ghost as NSString

		let beforeText = text
		let beforeCaret = caret

		let committed: String
		if candidate.length > suffix.length, candidate.hasSuffix(suffix as String) {
			let matched = candidate.length - suffix.length
			let range = NSRange(location: max(0, location - matched), length: min(matched, location))
			committed = source.replacingCharacters(in: range, with: candidate as String)
			caret = range.location + candidate.length
		} else {
			committed = source.replacingCharacters(in: NSRange(location: location, length: 0), with: suffix as String)
			caret = location + suffix.length
		}

		var finalText = committed
		if !append.isEmpty {
			finalText = (committed as NSString).replacingCharacters(
				in: NSRange(location: caret, length: 0), with: append)
			caret += (append as NSString).length
		}

		undoSnapshot = (beforeText, beforeCaret, caret)
		text = finalText
		caretRequest = caret
		ghost = ""
		whisperCandidate = ""
		refreshEngine()
		scheduleSave()
	}

	/// Revert the last accepted whisper — the backspace-undo Apple teaches.
	private func undoAccept() {
		guard let snapshot = undoSnapshot else { return }
		undoSnapshot = nil
		text = snapshot.beforeText
		caret = snapshot.beforeCaret
		caretRequest = caret
		ghost = ""
		whisperCandidate = ""
		refreshEngine()
		scheduleSave()
	}

	/// A backspace at the exact post-accept caret reverts the accept.
	private func consumeBackspace(at location: Int) -> Bool {
		guard let snapshot = undoSnapshot, location == snapshot.afterCaret else { return false }
		undoAccept()
		return true
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
