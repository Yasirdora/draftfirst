import SwiftUI
import UIKit

/// Phase 0, Spike A — prove that a ghost whisper can live inside a UITextView.
///
/// The ghost is appended to the text storage in a dim color and is never part
/// of the document: typing over it replaces it, accepting commits it, and the
/// caret can never be placed inside it. This mirrors the web editor's inline
/// whisper behavior and validates the mechanism Phase 1 will build on.
struct ScriptTextView: UIViewRepresentable {
	@Binding var text: String
	var ghost: String
	var onTextChange: (String) -> Void

	private static let bodyFont = UIFont.monospacedSystemFont(ofSize: 15, weight: .regular)

	func makeCoordinator() -> Coordinator { Coordinator(self) }

	func makeUIView(context: Context) -> UITextView {
		let view = UITextView()
		view.delegate = context.coordinator
		view.backgroundColor = .clear
		view.font = Self.bodyFont
		view.typingAttributes = [
			.font: Self.bodyFont,
			.foregroundColor: UIColor.label
		]
		view.textContainerInset = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
		view.autocapitalizationType = .none
		view.autocorrectionType = .no
		view.spellCheckingType = .no
		view.smartQuotesType = .no
		view.smartDashesType = .no
		view.smartInsertDeleteType = .no
		view.keyboardDismissMode = .interactive
		context.coordinator.textView = view
		return view
	}

	func updateUIView(_ view: UITextView, context: Context) {
		context.coordinator.parent = self
		context.coordinator.render(text: text, ghost: ghost)
	}

	@MainActor
	final class Coordinator: NSObject, UITextViewDelegate {
		var parent: ScriptTextView
		weak var textView: UITextView?

		/// Length of the trailing ghost suffix in UTF-16 units (0 = no ghost).
		private var ghostLength = 0
		/// Guards against render → delegate → render feedback loops.
		private var syncing = false

		init(_ parent: ScriptTextView) { self.parent = parent }

		private var contentLength: Int {
			(textView?.textStorage.length ?? 0) - ghostLength
		}

		func render(text: String, ghost: String) {
			guard let view = textView, !syncing else { return }
			syncing = true
			defer { syncing = false }

			let body = (text as NSString) as String
			let whisper = ghost.isEmpty ? "" : ghost
			let full = body + whisper
			let storage = view.textStorage

			guard storage.string != full else { return }

			let caret = view.selectedRange.location
			let attributed = NSMutableAttributedString(string: full, attributes: [
				.font: ScriptTextView.bodyFont,
				.foregroundColor: UIColor.label
			])
			if !whisper.isEmpty {
				let ghostRange = NSRange(location: (body as NSString).length, length: (whisper as NSString).length)
				attributed.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: ghostRange)
				ghostLength = ghostRange.length
			} else {
				ghostLength = 0
			}
			storage.setAttributedString(attributed)

			// The caret belongs to the document, never to the ghost.
			let clamped = min(caret, (body as NSString).length)
			view.selectedRange = NSRange(location: clamped, length: 0)
		}

		func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
			if ghostLength > 0 {
				// Strip the ghost first so the edit applies to real content only.
				let storage = view.textStorage
				let ghostRange = NSRange(location: storage.length - ghostLength, length: ghostLength)
				storage.deleteCharacters(in: ghostRange)
				storage.addAttribute(.foregroundColor, value: UIColor.label, range: NSRange(location: 0, length: storage.length))
				ghostLength = 0
			}
			return true
		}

		func textViewDidChangeSelection(_ view: UITextView) {
			guard ghostLength > 0, !syncing else { return }
			if view.selectedRange.location > contentLength {
				view.selectedRange = NSRange(location: contentLength, length: 0)
			}
		}

		func textViewDidChange(_ view: UITextView) {
			guard !syncing else { return }
			let content = (view.textStorage.string as NSString).substring(to: contentLength)
			parent.onTextChange(content)
		}
	}
}
