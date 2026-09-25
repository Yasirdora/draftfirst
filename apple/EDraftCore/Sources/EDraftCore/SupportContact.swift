import Foundation

/// Where a writer reaches the people who make eDraft.
///
/// One address, wherever eDraft shows one: both apps' Send Feedback, the Help
/// Center and the privacy policy (IL-0098). The apps take it from here
/// rather than spelling it again, which is how the two Settings screens came
/// to mail an address nothing else gave.
public nonisolated enum SupportContact {
    public static let address = "support@edraft.xyz"
    public static let mailto = URL(string: "mailto:\(address)")!
}
