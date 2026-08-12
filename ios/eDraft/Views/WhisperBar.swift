import SwiftUI

/// The bar pinned above the keyboard — the touch expression of the Tab key.
///
/// Left: the element under the caret. Tapping it expands the element picker
/// INLINE in the bar itself — no system presentation (menus and dialogs are
/// fragile inside a UIKit-hosted inputAccessoryView; an inline row cannot
/// fail). The picker acts on the caret's actual line, blank or not.
///
/// Center: the current whisper. Accept it three ways — tap, or the way it was
/// meant to be done on glass: **swipe right**.
/// Right: dismiss the keyboard.
struct WhisperBar: View {

	let elementName: String
	let ghost: String
	let why: String
	let onAccept: () -> Void
	let onElement: (String) -> Void
	let onDismissKeyboard: () -> Void
	/// Reports picker expansion so the host can resize the accessory view.
	let onPickerToggle: (Bool) -> Void

	@State private var drag: CGFloat = 0
	@State private var pickerOpen = false

	/// Distance that commits the accept.
	private let acceptThreshold: CGFloat = 56

	/// Collapsed bar height; the picker row adds its own height when open.
	static let collapsedHeight: CGFloat = 46
	static let expandedHeight: CGFloat = 46 + 52

	private static let elementMenu: [(name: String, type: String)] = [
		("Scene Heading", "scene"),
		("Action", "action"),
		("Character", "character"),
		("Parenthetical", "parenthetical"),
		("Dialogue", "dialogue"),
		("Transition", "transition"),
		("Page Break", "pagebreak")
	]

	var body: some View {
		VStack(spacing: 0) {
			if pickerOpen { elementPickerRow }
			mainRow
		}
		.frame(maxWidth: .infinity)
		.background(.bar)
	}

	// MARK: - Main row

	private var mainRow: some View {
		HStack(spacing: 10) {
			elementChip
			Spacer(minLength: 8)
			whisperPill
			Spacer(minLength: 8)
			dismissButton
		}
		.padding(.horizontal, 12)
		.frame(height: Self.collapsedHeight)
	}

	// MARK: - Element chip

	private var elementChip: some View {
		Button {
			withAnimation(.easeInOut(duration: 0.18)) { pickerOpen.toggle() }
			onPickerToggle(pickerOpen)
		} label: {
			HStack(spacing: 4) {
				Text(elementName)
					.font(.callout.weight(.medium))
				Image(systemName: pickerOpen ? "chevron.down" : "chevron.up.chevron.down")
					.font(.caption2.weight(.semibold))
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 12)
			.padding(.vertical, 7)
			.background(pickerOpen ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06), in: Capsule())
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Element: \(elementName)")
		.accessibilityHint("Shows element choices")
	}

	// MARK: - Inline element picker (replaces any system menu/dialog)

	private var elementPickerRow: some View {
		ScrollView(.horizontal, showsIndicators: false) {
			HStack(spacing: 8) {
				ForEach(Self.elementMenu, id: \.type) { item in
					Button {
						withAnimation(.easeInOut(duration: 0.15)) { pickerOpen = false }
						onPickerToggle(false)
						onElement(item.type)
					} label: {
						Text(item.name)
							.font(.callout)
							.padding(.horizontal, 14)
							.padding(.vertical, 9)
							.background(Color.primary.opacity(0.06), in: Capsule())
							.overlay(Capsule().strokeBorder(Color.primary.opacity(0.12)))
					}
					.buttonStyle(.plain)
				}
			}
			.padding(.horizontal, 12)
		}
		.frame(height: 52)
		.transition(.move(edge: .bottom).combined(with: .opacity))
	}

	// MARK: - Whisper pill (swipe right to accept)

	private var whisperPill: some View {
		let accepted = drag >= acceptThreshold
		return HStack(spacing: 8) {
			Text(ghost)
				.font(.system(.callout, design: .monospaced))
				.lineLimit(1)
				.minimumScaleFactor(0.7)
			if !why.isEmpty {
				Text("· \(why)")
					.font(.caption2)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}
			Image(systemName: "chevron.right")
				.font(.caption.weight(.bold))
				.foregroundStyle(accepted ? Color.white : Color.accentColor)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 8)
		.foregroundStyle(accepted ? Color.white : Color.primary)
		.background(
			Capsule().fill(accepted ? Color.accentColor : Color.accentColor.opacity(0.12))
		)
		.overlay(Capsule().strokeBorder(Color.accentColor.opacity(accepted ? 0 : 0.35)))
		.offset(x: min(drag, acceptThreshold + 24))
		.opacity(ghost.isEmpty ? 0 : 1)
		.animation(.spring(response: 0.25, dampingFraction: 0.7), value: accepted)
		.gesture(
			DragGesture(minimumDistance: 4)
				.onChanged { value in
					guard !ghost.isEmpty else { return }
					drag = max(0, value.translation.width)
				}
				.onEnded { _ in
					guard !ghost.isEmpty else { return }
					if drag >= acceptThreshold {
						UIImpactFeedbackGenerator(style: .light).impactOccurred()
						onAccept()
					}
					withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { drag = 0 }
				}
		)
		.onTapGesture {
			guard !ghost.isEmpty else { return }
			UIImpactFeedbackGenerator(style: .light).impactOccurred()
			onAccept()
		}
		.accessibilityLabel(ghost.isEmpty ? "No suggestion" : "Suggestion: \(ghost)")
		.accessibilityHint(ghost.isEmpty ? "" : "Double-tap or swipe right to accept")
	}

	// MARK: - Dismiss keyboard

	private var dismissButton: some View {
		Button(action: onDismissKeyboard) {
			Image(systemName: "keyboard.chevron.compact.down")
				.font(.callout)
				.foregroundStyle(.secondary)
				.frame(width: 34, height: 34)
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}
}
