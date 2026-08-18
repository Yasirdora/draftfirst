import Foundation

/// Renaming the open document's file underneath it is unsafe — the document
/// infrastructure keeps writing to the URL it opened, so a mid-session move
/// would resurrect the old file on the next save. The move is therefore
/// deferred until the launch scene is active, where the document is
/// provably closed and its final save has landed. Persisted in UserDefaults,
/// so even a terminated app completes the rename on next launch.
enum PendingRename {
    private static let key = "pendingDocumentRename"

    /// Records the move to perform: the document's exact URL (known to the
    /// editor through its document configuration) and the new base name.
    static func schedule(fileURL: URL, newName: String) {
        UserDefaults.standard.set(["from": fileURL.path, "name": newName], forKey: key)
    }

    /// Performs the deferred move, if any. Name conflicts settle on a
    /// numeric suffix ("The Last Light 2.draft"), matching Finder. The
    /// pending entry is cleared first: a failed move must never loop.
    static func performIfNeeded() {
        guard let pending = UserDefaults.standard.dictionary(forKey: key),
              let fromPath = pending["from"] as? String,
              let name = pending["name"] as? String
        else { return }
        UserDefaults.standard.removeObject(forKey: key)

        let from = URL(fileURLWithPath: fromPath)
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: from.path) else { return }

        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let base = name.components(separatedBy: illegal).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }

        let directory = from.deletingLastPathComponent()
        let ext = from.pathExtension
        var candidate = directory.appendingPathComponent(base).appendingPathExtension(ext)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(suffix)")
                .appendingPathExtension(ext)
            suffix += 1
        }
        try? fileManager.moveItem(at: from, to: candidate)
    }
}
