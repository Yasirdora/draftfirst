import AppKit
import SwiftUI

/// One Move to Trash that can still be undone.
///
/// The window keeps at most one of these. A later delete replaces it — stacking
/// banners would hide the earlier Undo, and Photos does the same.
public nonisolated struct LaunchTrashUndo: Equatable, Sendable {
    public var name: String
    public var originalURL: URL
    public var trashURL: URL

    /// How long the banner stays before it leaves on its own.
    public static let lingerSeconds: TimeInterval = 6

    public init(name: String, originalURL: URL, trashURL: URL) {
        self.name = name
        self.originalURL = originalURL
        self.trashURL = trashURL
    }

    public var message: String { "“\(name)” moved to Trash" }

    /// What Edit ▸ Undo says while this can be put back: "Undo Move to Trash".
    public static let actionName = "Move to Trash"

    /// Offers this Move to Trash to Edit ▸ Undo — ⌘Z — as Finder does
    /// (IL-0108). The banner's Undo is a second door to the same command,
    /// not a ⌘Z of its own: one shortcut means one thing in every window.
    @MainActor
    public func registerUndo(on undoManager: UndoManager, putBack: @escaping @MainActor (LaunchTrashUndo) -> Void) {
        undoManager.registerUndo(withTarget: undoManager) { _ in
            MainActor.assumeIsolated { putBack(self) }
        }
        undoManager.setActionName(Self.actionName)
    }

    public var announcement: String { "\(message). Undo" }

    public func canPutBack(
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> Bool {
        exists(trashURL)
    }

    /// Moves the file home. Returns false if it is gone or the move fails —
    /// never throws, so the banner can disable Undo without a dialog.
    @discardableResult
    public func putBack(
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        move: (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }
    ) -> Bool {
        guard exists(trashURL) else { return false }
        do {
            try move(trashURL, originalURL)
            return true
        } catch {
            return false
        }
    }
}

/// A quiet bar at the bottom of the launch window: what was trashed, and Undo.
struct LaunchTrashBanner: View {
    let item: LaunchTrashUndo
    var onUndo: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(item.message)
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 8)
            // No ⌘Z here: the key is Edit ▸ Undo's, which this button also
            // sends (IL-0108).
            Button("Undo", action: onUndo)
                .disabled(!item.canPutBack())
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.message)
        .onAppear {
            AccessibilityNotification.Announcement(item.announcement).post()
        }
        .task(id: item.trashURL) {
            try? await Task.sleep(for: .seconds(LaunchTrashUndo.lingerSeconds))
            onDismiss()
        }
    }
}
