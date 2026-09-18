import AppKit

/// "Your name for notes" — asked once, the first time the writer leaves a
/// note and no name is kept on this Mac (RFC-NOTES-SYSTEM §8).
///
/// The Mac has no Settings window, so this is where the name comes from. It is
/// the writer's to give: nothing is filled in from the account, the computer or
/// a contact card, because a name the writer did not type is not theirs to
/// have written. A role beside it is optional. Cancel adds no note — every
/// note carries an author, and that author is what Final Draft shows.
@MainActor
final class NoteNamePrompt: NSObject, NSTextFieldDelegate {
    typealias Answer = (name: String, role: String)

    /// The answer the fields give: a name, trimmed, and a role that may be
    /// empty — or nil while there is no name.
    static func answer(name: String, role: String) -> Answer? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return (name, role.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Asks on `window` as a sheet, or as a modal alert when there is none,
    /// and calls back with the answer — nil when the writer cancels.
    static func ask(on window: NSWindow?, completion: @escaping (Answer?) -> Void) {
        let prompt = NoteNamePrompt()
        // The prompt is held by this closure until the writer answers.
        let finish = { (response: NSApplication.ModalResponse) in
            completion(response == .alertFirstButtonReturn
                ? answer(name: prompt.nameField.stringValue, role: prompt.roleField.stringValue)
                : nil)
        }
        guard let window else {
            finish(prompt.alert.runModal())
            return
        }
        prompt.alert.beginSheetModal(for: window, completionHandler: finish)
    }

    private let alert = NSAlert()
    private let nameField = NSTextField()
    private let roleField = NSTextField()

    private override init() {
        super.init()
        alert.messageText = "Your name for notes"
        alert.informativeText = "Your notes carry this name, in eDraft and in Final Draft. It stays on this Mac."
        alert.addButton(withTitle: "Add Note")
        alert.addButton(withTitle: "Cancel")

        nameField.placeholderString = "Name"
        roleField.placeholderString = "Role (optional)"
        nameField.delegate = self
        let fields = NSStackView(views: [nameField, roleField])
        fields.orientation = .vertical
        fields.spacing = 8
        fields.frame = NSRect(x: 0, y: 0, width: 260, height: 52)
        for field in [nameField, roleField] {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 260).isActive = true
        }
        alert.accessoryView = fields
        alert.window.initialFirstResponder = nameField
        // Nothing to add a note as until there is a name.
        alert.buttons.first?.isEnabled = false
    }

    func controlTextDidChange(_ notification: Notification) {
        alert.buttons.first?.isEnabled = Self.answer(name: nameField.stringValue, role: "") != nil
    }
}
