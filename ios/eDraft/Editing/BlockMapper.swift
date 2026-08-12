import Foundation

/// Maps Fountain source lines to engine elements, one to one.
///
/// The engine's parser emits exactly one element per non-blank source line
/// (a speech is cue + parenthetical + dialogue ELEMENTS on consecutive lines).
/// So alignment is a line walk: every non-blank line consumes the next
/// element. Two Fountain subtleties consume elements without a visible line:
/// inline notes [[like this]] attach a note element to their line, and a
/// blank line holding 2+ spaces inside a speech is an intentional empty
/// dialogue element. Both are handled so alignment can never silently drift;
/// anything still unmatched degrades to "action" instead of corrupting offsets.
struct BlockMapper {

	struct StyledLine: Equatable {
		/// UTF-16 range of the line's content in the source (no newline).
		let range: NSRange
		/// Engine element type ("scene", "action", "character", …).
		let type: String
		/// Index of this line's element in the engine's element stream.
		let elementIndex: Int
	}

	private static let speechTypes: Set<String> = ["character", "parenthetical", "dialogue"]

	static func map(text: String, elements: [[String: Any]]) -> [StyledLine] {
		let source = text as NSString
		var lines: [(content: NSRange, full: NSRange, text: String)] = []
		source.enumerateSubstrings(
			in: NSRange(location: 0, length: source.length),
			options: [.byLines]
		) { substring, range, enclosingRange, _ in
			lines.append((range, enclosingRange, substring ?? ""))
		}

		var styled: [StyledLine] = []
		var elementIndex = 0
		var prevType: String?

		func typeOf(_ index: Int) -> String {
			elements[index]["type"] as? String ?? "action"
		}

		for line in lines {
			let trimmed = line.text.trimmingCharacters(in: .whitespaces)

			if trimmed.isEmpty {
				// Intentional dialogue blank: 2+ spaces inside a speech.
				if line.text.count >= 2,
				   let prev = prevType,
				   speechTypes.contains(prev),
				   elementIndex < elements.count {
					styled.append(StyledLine(range: line.content, type: "dialogue", elementIndex: elementIndex))
					elementIndex += 1
					prevType = "dialogue"
				}
				continue
			}

			guard elementIndex < elements.count else {
				// Beyond the engine's stream (still being typed) — neutral style.
				styled.append(StyledLine(range: line.content, type: "action", elementIndex: elementIndex))
				continue
			}

			// Inline notes on this line attach note elements ahead of it.
			while line.text.contains("[["),
				  elementIndex < elements.count,
				  typeOf(elementIndex) == "note" {
				elementIndex += 1
			}

			guard elementIndex < elements.count else { break }
			let type = typeOf(elementIndex)
			styled.append(StyledLine(range: line.content, type: type, elementIndex: elementIndex))
			prevType = type
			elementIndex += 1
		}

		return styled
	}

	/// The styled line containing a UTF-16 caret location, if the caret sits
	/// on a content line (blank lines have no element).
	static func line(containing location: Int, in lines: [StyledLine]) -> StyledLine? {
		lines.first { NSLocationInRange(location, $0.range) || location == $0.range.location }
	}
}
