import Foundation
import UIKit

/// Local persistence for the single working document (Phase 1).
///
/// The Library (multi-document + iCloud Drive via DocumentGroup) replaces this
/// in the next milestone; until then the writer's words autosave to disk on
/// every pause and survive force-quits. Writes are atomic — a crash mid-save
/// can never produce a torn file. Losing a writer's words is the one
/// unforgivable sin in this product.
final class DocumentStore {

	private let textURL: URL
	private let nameURL: URL

	init(directory: URL? = nil) {
		let dir = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
		textURL = dir.appendingPathComponent("autosave.fountain")
		nameURL = dir.appendingPathComponent("autosave.name")
	}

	struct Document {
		let name: String
		let text: String
	}

	/// The screenplay every first-time writer meets: a tiny scene that ends
	/// mid-cue ("MA"), so the very first thing the app does is offer a whisper.
	static let starter = Document(
		name: "Untitled Screenplay",
		text: """
		FADE IN:

		INT. SCHOOL HALLWAY - DAY

		Students RUSH past, late slips flying. MARA fights the current, hugging a folder to her chest.

		MARA
		(whispering)
		We have to go.

		DAVID
		I know. I'm coming.

		MA
		"""
	)

	func load() -> Document? {
		guard let data = try? Data(contentsOf: textURL),
			  let text = String(data: data, encoding: .utf8)
		else { return nil }
		let name = (try? String(contentsOf: nameURL, encoding: .utf8))?
			.trimmingCharacters(in: .whitespacesAndNewlines)
		return Document(name: name?.isEmpty == false ? name! : DocumentStore.starter.name, text: text)
	}

	func save(name: String, text: String) {
		try? text.data(using: .utf8)?.write(to: textURL, options: .atomic)
		try? name.data(using: .utf8)?.write(to: nameURL, options: .atomic)
	}
}
