import Foundation

/// Who left a note, read from the note's own words.
///
/// Fountain's `[[ ]]` has no room for an attribute — no author, no colour, no
/// date — and the document eDraft saves *is* Fountain. Nor is there anywhere
/// beside the file to keep one: an element's id is made fresh every time the
/// source is parsed, so a table keyed by note id would be pointing at nothing
/// the second time the script opened. Both were measured before this was
/// written, and both were rejected on the measurement rather than on taste.
///
/// So the author is in the text, where the writer can see it:
/// `[[Dir: too passive here]]`. That is not a scheme invented for this app —
/// it is what writers already type by hand, and it is the only form that
/// survives every way a script leaves: Fountain, Final Draft, a printout, an
/// email to someone who owns none of them.
///
/// Reading one back is deliberately timid, because the two mistakes do not
/// cost the same. Missing an author leaves a note looking exactly as it looks
/// today. Inventing one puts a person's name on a thought that was nobody's.
/// So a prefix has to earn its attribution before it gets one — see `roster`.
public nonisolated enum NoteAttribution {

    /// The longest a prefix may run and still read as somebody's name.
    ///
    /// Long enough for "Mario Moreno" or a role typed in full; short enough
    /// that the first clause of a sentence which happens to end in a colon is
    /// not mistaken for a person.
    static let longestName = 24

    /// Characters that settle it: whatever this is, it is not a name.
    private static let notInAName = CharacterSet(charactersIn: ",;!?()[]{}\"")

    /// What a note offers as an author, before anything decides to believe it.
    ///
    /// Syntax only. Whether the name is a real one is `roster`'s question, and
    /// keeping the two apart is exactly what lets `[[TODO: fix the slug]]` be
    /// read here and disbelieved there.
    public static func candidate(in text: String) -> (name: String, body: String)? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let name = String(text[text.startIndex..<colon])
            .trimmingCharacters(in: .whitespaces)
        let body = String(text[text.index(after: colon)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !body.isEmpty, !name.contains(where: \.isNewline) else { return nil }
        // `Name (Role)` (RFC-NOTES-SYSTEM D4): the role is part of how the
        // writer signs, and never part of who they are — see `person(of:)`.
        let (person, role) = split(name)
        guard isName(person) else { return nil }
        if let role, !isName(role) { return nil }
        return (name, body)
    }

    /// A name, or a role: short, a letter in it, nothing that settles it is
    /// not one.
    private static func isName(_ text: String) -> Bool {
        guard !text.isEmpty, text.count <= longestName else { return false }
        guard text.rangeOfCharacter(from: notInAName) == nil else { return false }
        // A name has a letter in it. "12:30 — move this" does not.
        return text.contains(where: \.isLetter)
    }

    /// `Name (Role)` into its name and its role; a prefix with no role is all
    /// name.
    private static func split(_ signature: String) -> (name: String, role: String?) {
        guard signature.hasSuffix(")"), let open = signature.range(of: " (", options: .backwards) else {
            return (signature, nil)
        }
        let name = String(signature[..<open.lowerBound]).trimmingCharacters(in: .whitespaces)
        let role = String(signature[open.upperBound..<signature.index(before: signature.endIndex)])
            .trimmingCharacters(in: .whitespaces)
        return (name, role)
    }

    /// Who a signature is: `Dana Reyes (Director)` is Dana Reyes. Colour and
    /// the roster key on this, so a person's role can change without their
    /// colour changing (RFC-NOTES-SYSTEM §8).
    public static func person(of signature: String) -> String {
        split(signature.trimmingCharacters(in: .whitespaces)).name
    }

    /// The names that earned attribution in this document.
    ///
    /// A name earns it by repeating — two notes or more — or by being the one
    /// this writer signs with. One note beginning `TODO:` is a to-do; fourteen
    /// beginning `Dir:` are a person. The rule needs no list to maintain and
    /// no guess about what a role is called, which matters: a real Final Draft
    /// file was found using its note category for "Producer", "Writer" and
    /// "Alt Scenes" indiscriminately, so no vocabulary of roles could be
    /// trusted even if one were written down.
    public static func roster(of notes: [String], signature: String? = nil) -> Set<String> {
        var seen: [String: (name: String, count: Int)] = [:]
        for note in notes {
            guard let found = candidate(in: note) else { continue }
            let key = person(of: found.name).lowercased()
            // The first spelling wins, so a name typed two ways stays one
            // person with one colour rather than becoming two.
            let existing = seen[key]
            seen[key] = (existing?.name ?? found.name, (existing?.count ?? 0) + 1)
        }
        var roster = Set(seen.values.filter { $0.count >= 2 }.map(\.name))
        let mine = person(of: signature ?? "")
        if !mine.isEmpty, let found = seen[mine.lowercased()] {
            roster.insert(found.name)
        }
        return roster
    }

    /// The author of one note, once the roster has decided who exists.
    ///
    /// Returns the body without the prefix, because the list shows the name
    /// as a chip of its own and repeating it in the words would be the same
    /// fact twice.
    public static func author(
        of text: String, roster: Set<String>
    ) -> (name: String, body: String)? {
        guard let found = candidate(in: text) else { return nil }
        let who = person(of: found.name).lowercased()
        guard let name = roster.first(where: { person(of: $0).lowercased() == who })
        else { return nil }
        return (name, found.body)
    }

    /// The colour each name takes, assigned in order down the roster.
    ///
    /// Not hashed. A hash would hold one person's colour steady no matter who
    /// else was in the document, which sounds like the better property until
    /// it is measured: with six colours and a handful of names, collisions are
    /// ordinary — "Dir", "JW" and "Joe Jarvis" all land on the same slot — and
    /// two people sharing a colour defeats the only thing the colour is for.
    ///
    /// Assigning down the sorted roster instead guarantees that everyone in a
    /// document is a different colour until there are more than six of them,
    /// and it is still decided entirely by the file: the same script opens the
    /// same colours on any machine, with nothing stored and nothing to sync.
    public static func slots(for roster: Set<String>) -> [String: Int] {
        var slots: [String: Int] = [:]
        for (index, name) in roster.sorted(by: { $0.lowercased() < $1.lowercased() })
            .enumerated() {
            slots[name] = index % paletteSlots
        }
        return slots
    }

    /// A note signed by this writer, or the text unchanged when it already
    /// names somebody.
    ///
    /// The second half is not a nicety: adding a note to a line a director has
    /// already written on must never put this writer's name on the director's
    /// words.
    public static func signed(_ text: String, as signature: String) -> String {
        let name = signature.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, candidate(in: text) == nil else { return text }
        return text.isEmpty ? "\(name): " : "\(name): \(text)"
    }

    // MARK: - The palette

    /// One hue, in the two lights a script is read in.
    ///
    /// Components rather than a colour: `EDraftCore` is the one place both
    /// surfaces can see, and neither `Color` nor `NSColor` belongs here.
    public struct Hue: Sendable, Equatable {
        public struct Ink: Sendable, Equatable {
            public let red: Double, green: Double, blue: Double
            public init(_ red: Double, _ green: Double, _ blue: Double) {
                self.red = red
                self.green = green
                self.blue = blue
            }
        }
        /// On paper.
        public let paper: Ink
        /// On an inverted page, where the paper hue goes muddy.
        public let inverted: Ink
    }

    /// Six hues, deep enough to read as ink on off-white and lifted for a dark
    /// page — the same two-light treatment `screenplayNoteTint` gets, and for
    /// the same reason: these mark paper, not the app around it.
    ///
    /// None of them is the note yellow. That one still means "nobody claimed
    /// this", and it has to stay legible as its own answer.
    public static let paletteHues: [Hue] = [
        Hue(paper: .init(0.184, 0.435, 0.816), inverted: .init(0.475, 0.663, 0.941)),
        Hue(paper: .init(0.761, 0.380, 0.102), inverted: .init(0.941, 0.635, 0.392)),
        Hue(paper: .init(0.478, 0.294, 0.769), inverted: .init(0.714, 0.576, 0.941)),
        Hue(paper: .init(0.090, 0.471, 0.435), inverted: .init(0.373, 0.749, 0.702)),
        Hue(paper: .init(0.753, 0.188, 0.290), inverted: .init(0.941, 0.494, 0.576)),
        Hue(paper: .init(0.247, 0.478, 0.141), inverted: .init(0.549, 0.769, 0.416))
    ]

    /// How many colours there are to go round.
    ///
    /// Read from the palette rather than stated twice: a slot is the same
    /// number in the Navigator and in the margin, and two lists of different
    /// lengths would quietly give one person two colours.
    public static var paletteSlots: Int { paletteHues.count }
}

/// The writer's name for notes (RFC-NOTES-SYSTEM §8).
///
/// Asserted by the writer — asked once, the first time they leave a note —
/// and kept on this device. Never read from the system: not the account name,
/// not the computer's, not a contact card. A name the writer did not give is
/// not theirs to have written.
public nonisolated enum NoteIdentity {
    /// The key Settings has always kept the name under.
    static let nameKey = "noteSignature"
    static let roleKey = "noteRole"

    /// The name the writer gave, or empty.
    public static var name: String {
        (UserDefaults.standard.string(forKey: nameKey) ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// The role beside it, or empty.
    public static var role: String {
        (UserDefaults.standard.string(forKey: roleKey) ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// `Name (Role)`, or `Name` (D4); empty while the writer has given none.
    public static var signature: String { signature(name: name, role: role) }

    public static func signature(name: String, role: String) -> String {
        let name = name.trimmingCharacters(in: .whitespaces)
        let role = role.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return "" }
        return role.isEmpty ? name : "\(name) (\(role))"
    }
}
