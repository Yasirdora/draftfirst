import AppKit
import EDraftEngine
import SwiftUI

/// The marks a writer can put on a selection, plus the two things a
/// selection is often the start of.
///
/// Emphasis is data now, not notation (RFC v2.1): bold, italic, underline
/// and strikethrough are style runs in the model, toggled through
/// `ScriptSurface.toggleStyle`, and the file hears them exactly because the
/// serialiser synthesises the markers at the boundary. A centred line is an
/// element-level rewrite and a note is anchored to the element, not the
/// selection — see `ScriptAsides`.
enum FormatMark: CaseIterable {
    case bold, italic, underline, strikethrough, centered, note

    var symbol: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        case .centered: "text.aligncenter"
        case .note: "note.text.badge.plus"
        }
    }

    var title: String {
        switch self {
        case .bold: "Bold"
        case .italic: "Italic"
        case .underline: "Underline"
        case .strikethrough: "Strikethrough"
        case .centered: "Center Line"
        case .note: "Add Note"
        }
    }

    /// The run style the mark commands; nil for a mark that is not a style.
    var styleSet: StyleSet? {
        switch self {
        case .bold: .bold
        case .italic: .italic
        case .underline: .underline
        case .strikethrough: .strikeout
        case .centered, .note: nil
        }
    }

    /// A thin rule stands before the first mark of each group.
    var opensGroup: Bool { self == .centered || self == .note }
}

/// The emphasis controls floating over a selection.
///
/// A subview of the canvas, so it scrolls with the page it is placed on, and
/// hidden whenever the selection is empty. Positioned above the selected
/// glyphs from the same rectangles the find bar and the reveal mark use.
@MainActor
final class SelectionFormatBar {
    var onApply: ((FormatMark) -> Void)?

    private let host: NSHostingView<FormatBarView>

    init() {
        let view = FormatBarView(active: [], apply: { _ in })
        host = NSHostingView(rootView: view)
        host.isHidden = true
    }

    func attach(to canvas: NSView) {
        host.rootView = FormatBarView(active: []) { [weak self] mark in self?.onApply?(mark) }
        canvas.addSubview(host)
    }

    /// Shows the bar over `selection`, or hides it when there is nothing
    /// selected or nothing laid out yet. `active` is the set of marks the
    /// selection already wears — drawn lit, the way a pressed Bold button
    /// reads in any editor.
    func update(selection: NSRange, in textView: NSTextView, canvas: NSView, active: Set<FormatMark>) {
        guard selection.length > 0,
              let rect = ScriptLayout.boundingRect(of: selection, in: textView) else {
            host.isHidden = true
            return
        }
        host.rootView = FormatBarView(active: active) { [weak self] mark in self?.onApply?(mark) }
        let placed = canvas.convert(rect, from: textView)
        let size = host.fittingSize
        // The canvas is flipped, so "above" is a smaller y.
        host.frame = CGRect(
            x: (placed.midX - size.width / 2).rounded(),
            y: (placed.minY - size.height - 8).rounded(),
            width: size.width,
            height: size.height
        )
        host.isHidden = false
    }
}

/// The bar itself: the marks in one small piece of glass.
struct FormatBarView: View {
    let active: Set<FormatMark>
    let apply: (FormatMark) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(FormatMark.allCases, id: \.self) { mark in
                if mark.opensGroup {
                    Divider().frame(height: 12).padding(.horizontal, 3)
                }
                Button {
                    apply(mark)
                } label: {
                    Image(systemName: mark.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(active.contains(mark) ? Color.accentColor : .primary)
                        .frame(width: 22, height: 22)
                        .background {
                            if active.contains(mark) {
                                Capsule().fill(Color.accentColor.opacity(0.18))
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(mark.title)
                .accessibilityLabel(mark.title)
                .accessibilityValue(active.contains(mark) ? "On" : "")
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .glassEffect(.regular.interactive(), in: .capsule)
        .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        .padding(4)
    }
}

extension ScriptSurface {

    /// Routes a mark to its mechanism. A style run is toggled through the
    /// model (`toggleStyle`); a centred line still travels through the text
    /// view's own input path, so the planner sees it exactly as it sees
    /// typing — undoable, and never behind the model's back. A note is not a
    /// text mark; the surface routes it to `addNoteAtCaret` itself.
    func applyMark(_ mark: FormatMark) {
        if let style = mark.styleSet {
            toggleStyle(style, named: mark.title)
            return
        }
        guard mark == .centered else { return }
        let selection = textView.selectedRange()
        let text = textView.string as NSString
        var line = text.lineRange(for: selection)
        var content = text.substring(with: line)
        if content.hasSuffix("\n") {
            content.removeLast()
            line.length -= 1
        }
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        let centred = trimmed.hasPrefix(">") && trimmed.hasSuffix("<")
        let replacement = centred
            ? String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            : "> \(trimmed) <"
        textView.insertText(replacement, replacementRange: line)
        textView.setSelectedRange(NSRange(location: line.location, length: (replacement as NSString).length))
    }
}
