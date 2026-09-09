import Foundation

/// Whether a screenplay is arriving because the writer just made it, or
/// because they came back to it.
///
/// The question cannot be answered by the document value. A new screenplay
/// does not reach the editor as the value the app created: the system writes
/// it to a file and reads that file back through `init(configuration:)`, so
/// nothing carried on the value survives. Nor can the creation itself be
/// recorded as it happens — DocumentGroup evaluates its `newDocument:`
/// template speculatively, whenever the browser renders, so "someone called
/// the initialiser" means only that the browser drew itself. Both of those
/// were measured, and both produced a screenplay that opened for writing when
/// the writer had merely opened it again.
///
/// The file answers it, and the session answers the rest. A screenplay made
/// moments ago, never written to, and not opened before in this session is
/// the one the writer has just this second asked for; anything else is one
/// they are returning to. Both halves are asked of the file being opened
/// rather than of the app's recent past, so nothing the browser does in the
/// background can arm them.
public enum DocumentArrival {

    /// How recently a screenplay must have been made to still count as new.
    ///
    /// Generous on purpose. The test is per-file, so a long window cannot
    /// mistake an old screenplay for a new one — the only thing it can catch
    /// is a second screenplay created a moment earlier, which is also new.
    /// What it buys is tolerance for a slow first open on a cold start.
    private static let madeWithin: TimeInterval = 60

    /// The slack allowed between a file being made and its first write. The
    /// system writes a new document as it creates it, so the two timestamps
    /// are the same event a fraction of a second apart.
    private static let untouched: TimeInterval = 2

    /// Screenplays this session has already opened. A screenplay is new only
    /// the first time it arrives: coming back to one is a return, however
    /// recently it was made and however little is in it.
    @MainActor private static var opened: Set<URL> = []

    @MainActor
    public static func isNewlyCreated(at url: URL?) -> Bool {
        guard let url, opened.insert(url).inserted else { return false }
        guard let dates = try? url.resourceValues(
                forKeys: [.creationDateKey, .contentModificationDateKey]
              ),
              let created = dates.creationDate,
              Date().timeIntervalSince(created) < madeWithin else { return false }

        // Written to since it was made, so there is something in it to read —
        // however recently it was started.
        guard let modified = dates.contentModificationDate else { return true }
        return modified.timeIntervalSince(created) < untouched
    }
}
