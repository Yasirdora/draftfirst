import Foundation

/// The colour a revision is issued on.
///
/// A production reissues only the pages that changed, and the paper colour is
/// how a crew knows which draft they are holding. The run is fixed and the
/// same on every show — white for the original, then blue, pink, yellow and
/// on — so a page's colour dates it without anyone reading a word. A long
/// production goes round twice, and the second pass is spoken as "double":
/// double blue follows buff.
public struct RevisionColour: Equatable, Hashable, Sendable, Codable {

    /// Position in the run, with the white original at zero.
    public let index: Int

    public init(index: Int) { self.index = max(0, index) }

    public static let original = RevisionColour(index: 0)

    private static let run = [
        "White", "Blue", "Pink", "Yellow", "Green", "Goldenrod", "Salmon", "Cherry", "Buff"
    ]

    public var name: String {
        let colour = Self.run[index % Self.run.count]
        switch index / Self.run.count {
        case 0: return colour
        case 1: return "Double \(colour)"
        case 2: return "Triple \(colour)"
        case let pass: return "\(colour) (pass \(pass + 1))"
        }
    }

    public var next: RevisionColour { RevisionColour(index: index + 1) }
}

/// Which elements a revision touched.
///
/// A revised page carries an asterisk against every line that changed, and
/// working that out means comparing the draft going out with the one that
/// went out last. Positions are reported in the *new* script, because that is
/// the copy being marked; a deletion leaves no line to mark and is carried by
/// the omitted-scene convention instead.
public enum RevisionDiff {

    /// The most elements either side may contribute to an exact comparison.
    ///
    /// The comparison costs one cell per pair, so an unbounded one on two
    /// feature scripts would allocate for millions of them. Past this the
    /// changed span is reported whole, which is honest: a rewrite that large
    /// is a rewrite, and every line of it is genuinely new.
    private static let exactLimit = 1_500

    public static func changed(
        from previous: [ScreenplayElement], to current: [ScreenplayElement]
    ) -> IndexSet {
        // A revision touches a small part of a long script, so the shared head
        // and tail are almost the whole document. Trimming them first is what
        // keeps the exact comparison affordable on a real draft.
        var head = 0
        while head < previous.count, head < current.count, same(previous[head], current[head]) {
            head += 1
        }
        var tail = 0
        while tail < previous.count - head, tail < current.count - head,
              same(previous[previous.count - 1 - tail], current[current.count - 1 - tail]) {
            tail += 1
        }

        let oldMiddle = Array(previous[head..<(previous.count - tail)])
        let newMiddle = Array(current[head..<(current.count - tail)])
        guard !newMiddle.isEmpty else { return IndexSet() }

        guard oldMiddle.count <= exactLimit, newMiddle.count <= exactLimit else {
            return IndexSet(integersIn: head..<(head + newMiddle.count))
        }
        return IndexSet(matching(oldMiddle, newMiddle).map { $0 + head })
    }

    /// Positions in `new` that no unchanged line of `old` accounts for, found
    /// by longest common subsequence so an insertion shifts nothing after it.
    private static func matching(
        _ old: [ScreenplayElement], _ new: [ScreenplayElement]
    ) -> [Int] {
        var lengths = [[Int]](
            repeating: [Int](repeating: 0, count: new.count + 1), count: old.count + 1
        )
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                lengths[i][j] = same(old[i], new[j])
                    ? lengths[i + 1][j + 1] + 1
                    : Swift.max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }

        var changed: [Int] = []
        var i = 0, j = 0
        while i < old.count, j < new.count {
            if same(old[i], new[j]) {
                i += 1; j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                i += 1                       // a line went away: nothing to mark
            } else {
                changed.append(j); j += 1    // a line arrived: mark it
            }
        }
        while j < new.count { changed.append(j); j += 1 }
        return changed
    }

    /// Two lines are the same line when they say the same thing in the same
    /// lane. A scene number is production bookkeeping, not a rewrite, so it
    /// does not by itself put an asterisk in the margin.
    private static func same(_ a: ScreenplayElement, _ b: ScreenplayElement) -> Bool {
        a.type == b.type && a.text == b.text
    }
}
