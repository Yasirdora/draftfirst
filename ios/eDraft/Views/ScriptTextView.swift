import SwiftUI
import UIKit

/// The writer's page.
///
/// A UITextView that renders Fountain source as a screenplay — scene headings
/// bold, cues and dialogue at their classic indents (the engine's GEOMETRY,
/// 60-column page), transitions right-aligned — in Courier Prime. The ghost
/// whisper lives inline at the caret, dim, never part of the document.
///
/// Accept a whisper by swiping right anywhere on the page, tapping the ghost
/// itself, or using the pill on the WhisperBar above the keyboard.
struct ScriptTextView: UIViewRepresentable {

	@Binding var text: String
	var elements: [[String: Any]]
	var ghost: String
	/// UTF-16 offset where the ghost renders (end of the block being typed).
	var ghostLocation: Int
	/// The full candidate a whisper commits — shown on the WhisperBar pill.
	var whisperCandidate: String
	var currentElementName: String
	/// Element index of a cue being typed (bare all-caps line) — styled as a
	/// character cue even though Fountain can't prove it until dialogue follows.
	var cueElementIndex: Int?
	/// One-shot caret positioning request (used after accepting a ghost).
	var caretRequest: Int?
	/// Whether an accepted whisper can be reverted (shows the Undo pill).
	var canUndoAccept: Bool

	var onTextChange: (String, Int) -> Void
	var onCaretChange: (Int) -> Void
	var onAccept: () -> Void
	/// Space-to-accept, QuickType-style: commit the candidate plus the space.
	var onAcceptSpace: () -> Void
	var onUndoAccept: () -> Void
	/// Backspace consult: returns true when the keystroke was consumed as undo.
	var onBackspace: (Int) -> Bool
	var onElement: (String) -> Void
	var onDismissKeyboard: () -> Void

	// MARK: - Fonts & metrics (Courier Prime, with system fallback)

	private static let regularFont: UIFont = UIFont(name: "CourierPrime-Regular", size: 13)
		?? UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
	private static let boldFont: UIFont = UIFont(name: "CourierPrime-Bold", size: 13)
		?? UIFont.monospacedSystemFont(ofSize: 13, weight: .bold)

	/// Screenplay layout columns (the engine's GEOMETRY), 60-column page.
	private static let indents: [String: CGFloat] = [
		"character": 22, "parenthetical": 16, "dialogue": 10, "lyrics": 10
	]

	static var charAdvance: CGFloat {
		("0" as NSString).size(withAttributes: [.font: regularFont]).width
	}

	func makeCoordinator() -> Coordinator { Coordinator(self) }

	func makeUIView(context: Context) -> EditorTextView {
		let view = EditorTextView()
		view.delegate = context.coordinator
		view.backgroundColor = .clear
		view.font = Self.regularFont
		view.typingAttributes = [
			.font: Self.regularFont,
			.foregroundColor: UIColor.label
		]
		view.autocapitalizationType = .none
		view.autocorrectionType = .no
		view.spellCheckingType = .no
		view.smartQuotesType = .no
		view.smartDashesType = .no
		view.smartInsertDeleteType = .no
		view.keyboardDismissMode = .interactive
		view.alwaysBounceVertical = true

		// A writing app opens into writing.
		DispatchQueue.main.async { view.becomeFirstResponder() }

		let swipe = UISwipeGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleSwipe))
		swipe.direction = .right
		view.addGestureRecognizer(swipe)

		let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
		view.addGestureRecognizer(tap)

		view.onLayout = { [weak coordinator = context.coordinator] in
			coordinator?.updatePageInsets()
		}

		context.coordinator.textView = view
		context.coordinator.installAccessoryBar(on: view)
		context.coordinator.observeKeyboard()
		return view
	}

	func updateUIView(_ view: EditorTextView, context: Context) {
		context.coordinator.parent = self
		context.coordinator.render()
		context.coordinator.updateAccessoryBar()
	}

	// MARK: - Coordinator

	@MainActor
	final class Coordinator: NSObject, UITextViewDelegate {
		var parent: ScriptTextView
		weak var textView: EditorTextView?

		private var styledLines: [BlockMapper.StyledLine] = []
		private var ghostLength = 0
		private var ghostLocation = 0
		private var syncing = false
		private var barHost: UIHostingController<WhisperBar>?
		private var keyboardObserver: NSObjectProtocol?
		private var lastInsetWidth: CGFloat = 0

		init(_ parent: ScriptTextView) { self.parent = parent }

		deinit {
			if let keyboardObserver { NotificationCenter.default.removeObserver(keyboardObserver) }
		}

		private var contentLength: Int {
			(textView?.textStorage.length ?? 0) - ghostLength
		}

		/// Fingerprint of the last render — text alone is not enough: the same
		/// source must be re-styled when the engine's element list changes.
		private var lastFingerprint = ""

		// MARK: Rendering

		func render() {
			guard let view = textView, !syncing else { return }
			syncing = true
			defer { syncing = false }

			let text = parent.text
			let ghost = parent.ghost
			let source = text as NSString

			styledLines = BlockMapper.map(text: text, elements: parent.elements)

			// A cue in progress is styled as a cue, parse be damned.
			if let cueIndex = parent.cueElementIndex {
				styledLines = styledLines.map { line in
					line.elementIndex == cueIndex
						? BlockMapper.StyledLine(range: line.range, type: "character", elementIndex: line.elementIndex)
						: line
				}
			}

			// Full body: source + ghost inserted at its location.
			let showGhost = !ghost.isEmpty
			let ghostAt = showGhost ? min(parent.ghostLocation, source.length) : source.length
			let body = showGhost
				? source.replacingCharacters(in: NSRange(location: ghostAt, length: 0), with: ghost)
				: text

			let fingerprint = body + "|" + styledLines.map(\.type).joined(separator: ",") + "|" + String(parent.cueElementIndex ?? -1)
			guard fingerprint != lastFingerprint else { return }
			lastFingerprint = fingerprint

			let caret = view.selectedRange.location
			let styled = NSMutableAttributedString(string: body, attributes: [
				.font: ScriptTextView.regularFont,
				.foregroundColor: UIColor.label
			])
			let advance = ScriptTextView.charAdvance

			for line in styledLines {
				var range = line.range
				// Lines after the ghost shift by its length.
				if showGhost, range.location > ghostAt { range.location += (ghost as NSString).length }
				applyStyle(to: styled, line: line, range: range, advance: advance)
			}

			if showGhost {
				let ghostRange = NSRange(location: ghostAt, length: (ghost as NSString).length)
				styled.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: ghostRange)
				ghostLength = ghostRange.length
				ghostLocation = ghostAt
			} else {
				ghostLength = 0
				ghostLocation = 0
			}

			view.textStorage.setAttributedString(styled)

			// A full rebuild drops typing attributes; the next keystroke must
			// not inherit the style of whatever it follows (bold after a heading).
			view.typingAttributes = [
				.font: ScriptTextView.regularFont,
				.foregroundColor: UIColor.label
			]

			let targetCaret: Int
			if let requested = parent.caretRequest {
				targetCaret = min(requested, (body as NSString).length)
			} else {
				// The caret belongs to the document, never inside the ghost.
				targetCaret = min(caret, ghostLength > 0 ? ghostLocation : (body as NSString).length)
			}
			view.selectedRange = NSRange(location: targetCaret, length: 0)
			updatePageInsets()
		}

		private func applyStyle(to storage: NSMutableAttributedString, line: BlockMapper.StyledLine, range: NSRange, advance: CGFloat) {
			let paragraph = NSMutableParagraphStyle()
			var font: UIFont = ScriptTextView.regularFont
			var color: UIColor = .label

			switch line.type {
			case "scene":
				font = ScriptTextView.boldFont
			case "transition":
				paragraph.alignment = .right
			case "centered":
				paragraph.alignment = .center
			case "pagebreak":
				paragraph.alignment = .center
				color = .secondaryLabel
			case "section", "synopsis", "note":
				color = .secondaryLabel
			default:
				break
			}

			if let columns = ScriptTextView.indents[line.type] {
				paragraph.headIndent = columns * advance
				paragraph.firstLineHeadIndent = columns * advance
			}

			storage.addAttributes([
				.font: font,
				.foregroundColor: color,
				.paragraphStyle: paragraph
			], range: range)
		}

		/// Centers a 60-column page on wide screens, hugs the edges on phones.
		func updatePageInsets() {
			guard let view = textView else { return }
			let width = view.bounds.width
			guard width > 0, width != lastInsetWidth else { return }
			lastInsetWidth = width
			let pageWidth = 62 * ScriptTextView.charAdvance
			let horizontal = max(16, (width - pageWidth) / 2)
			view.textContainerInset = UIEdgeInsets(
				top: 20,
				left: horizontal,
				bottom: 24,
				right: horizontal
			)
		}

		// MARK: WhisperBar (inputAccessoryView)

		private var barContainer: UIView?
		private var barExpanded = false
		private var barHeight: CGFloat {
			barExpanded ? WhisperBar.expandedHeight : WhisperBar.collapsedHeight
		}

		func installAccessoryBar(on view: EditorTextView) {
			let host = UIHostingController(rootView: makeBar())
			host.view.backgroundColor = .clear
			let container = UIView(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: WhisperBar.collapsedHeight))
			container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
			host.view.frame = container.bounds
			host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
			container.addSubview(host.view)
			view.inputAccessoryView = container
			barHost = host
			barContainer = container
			// The accessory bar occupies the bottom of the text view.
			view.contentInset.bottom = WhisperBar.collapsedHeight + 8
			view.verticalScrollIndicatorInsets.bottom = WhisperBar.collapsedHeight
		}

		func updateAccessoryBar() {
			barHost?.rootView = makeBar()
		}

		/// The inline picker grows the accessory view — no system presentation.
		func setPickerExpanded(_ expanded: Bool) {
			guard expanded != barExpanded else { return }
			barExpanded = expanded
			barContainer?.frame.size.height = barHeight
			guard let view = textView else { return }
			view.reloadInputViews()
			view.contentInset.bottom = barHeight + 8
			view.verticalScrollIndicatorInsets.bottom = barHeight
		}

		private func makeBar() -> WhisperBar {
			WhisperBar(
				elementName: parent.currentElementName,
				ghost: parent.ghost,
				candidate: parent.whisperCandidate,
				canUndo: parent.canUndoAccept,
				onAccept: { [weak self] in self?.parent.onAccept() },
				onUndo: { [weak self] in self?.parent.onUndoAccept() },
				onElement: { [weak self] type in self?.parent.onElement(type) },
				onDismissKeyboard: { [weak self] in
					self?.parent.onDismissKeyboard()
					self?.textView?.resignFirstResponder()
				},
				onPickerToggle: { [weak self] open in self?.setPickerExpanded(open) }
			)
		}

		// MARK: Keyboard avoidance

		func observeKeyboard() {
			keyboardObserver = NotificationCenter.default.addObserver(
				forName: UIResponder.keyboardWillChangeFrameNotification,
				object: nil,
				queue: .main
			) { [weak self] note in
				// The notification closure is @Sendable; hop to the MainActor.
				Task { @MainActor in
					self?.keyboardWillChangeFrame(note)
				}
			}
		}

		private func keyboardWillChangeFrame(_ note: Notification) {
			guard let view = textView,
				  let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
				  let duration = note.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval
			else { return }
			let overlap = view.convert(frame, from: nil).intersection(view.bounds).height
			let bottom = max(overlap, barHeight) + 8
			UIView.animate(withDuration: duration) {
				view.contentInset.bottom = bottom
				view.verticalScrollIndicatorInsets.bottom = bottom - 8
			}
		}

		// MARK: Gestures — swipe right / tap the ghost to accept

		@objc func handleSwipe() {
			guard ghostLength > 0 else { return }
			UIImpactFeedbackGenerator(style: .light).impactOccurred()
			parent.onAccept()
		}

		@objc func handleTap(_ gesture: UITapGestureRecognizer) {
			guard ghostLength > 0, let view = textView else { return }
			let point = gesture.location(in: view)
			guard let position = view.closestPosition(to: point) else { return }
			let offset = view.offset(from: view.beginningOfDocument, to: position)
			if offset >= ghostLocation && offset <= ghostLocation + ghostLength {
				UIImpactFeedbackGenerator(style: .light).impactOccurred()
				parent.onAccept()
			}
		}

		// MARK: UITextViewDelegate

		func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
			// Backspace at the post-accept caret reverts the accept (QuickType).
			if replacement.isEmpty, range.length == 1,
			   parent.onBackspace(range.location + range.length) {
				return false
			}
			if ghostLength > 0 {
				// Space commits the whisper — the candidate, then the space.
				if replacement == " " {
					parent.onAcceptSpace()
					return false
				}
				// Strip the ghost first so the edit applies to real content only.
				let storage = view.textStorage
				storage.deleteCharacters(in: NSRange(location: ghostLocation, length: ghostLength))
				ghostLength = 0
			}
			return true
		}

		func textViewDidChangeSelection(_ view: UITextView) {
			guard !syncing else { return }
			if ghostLength > 0, view.selectedRange.location > ghostLocation {
				view.selectedRange = NSRange(location: ghostLocation, length: 0)
			}
			reportCaret()
		}

		func textViewDidChange(_ view: UITextView) {
			guard !syncing else { return }
			let storage = view.textStorage
			var caret = view.selectedRange.location
			let content: String
			if ghostLength > 0 {
				// Edits that bypass shouldChangeTextIn (undo, dictation) can land
				// while the ghost is in storage. Excise it where it lies — never
				// assume the ghost is the tail of the document.
				content = (storage.string as NSString).replacingCharacters(
					in: NSRange(location: ghostLocation, length: ghostLength), with: "")
				if caret > ghostLocation { caret = max(ghostLocation, caret - ghostLength) }
				ghostLength = 0
			} else {
				content = storage.string
			}
			caret = min(caret, (content as NSString).length)
			parent.onTextChange(content, caret)
			// Keep the caret visible above the keyboard/accessory bar.
			view.scrollRangeToVisible(NSRange(location: min(caret, storage.length), length: 0))
		}

		private func reportCaret() {
			guard let view = textView else { return }
			let location = min(view.selectedRange.location, contentLength)
			// Async: never mutate SwiftUI state from inside a view update pass.
			DispatchQueue.main.async { [weak self] in
				self?.parent.onCaretChange(location)
			}
		}
	}
}

/// UITextView subclass so page insets track rotation and size changes.
final class EditorTextView: UITextView {
	var onLayout: (() -> Void)?

	override func layoutSubviews() {
		super.layoutSubviews()
		onLayout?()
	}
}
