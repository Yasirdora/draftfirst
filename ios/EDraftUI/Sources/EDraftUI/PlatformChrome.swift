import SwiftUI

/// The handful of places where one shared panel needs a different word on each
/// platform.
///
/// A phone titles a pushed screen inline and tells its software keyboard what
/// kind of text is coming; a Mac has neither a navigation bar nor a keyboard to
/// advise. Those are the only differences in these views, and they are small
/// enough that forking the panels to hold them would cost far more than it
/// saves — so they live here, named for what they mean rather than for the API
/// they call, and do nothing on the platform that has no such idea.
extension View {

    /// A title that takes as little room as the platform allows.
    func compactTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Capitalises each word as it is typed — a title is written in caps by
    /// convention, and a phone can do it without being asked twice.
    func titleCasedInput() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.words)
        #else
        self
        #endif
    }

    /// Marks the return key as finishing this field, where there is a return
    /// key to mark.
    func submitsAsDone() -> some View {
        #if os(iOS)
        submitLabel(.done)
        #else
        self
        #endif
    }

    /// Tells a software keyboard what kind of field this is. Inert where the
    /// keyboard is hardware and knows already.
    func softKeyboard(_ kind: SoftKeyboardKind) -> some View {
        #if os(iOS)
        keyboardType(kind.uiKind)
            .textInputAutocapitalization(kind == .email ? .never : .sentences)
        #else
        self
        #endif
    }
}

/// The field kinds these panels actually ask for.
enum SoftKeyboardKind {
    case email
    case phone

    #if os(iOS)
    var uiKind: UIKeyboardType {
        switch self {
        case .email: .emailAddress
        case .phone: .phonePad
        }
    }
    #endif
}
