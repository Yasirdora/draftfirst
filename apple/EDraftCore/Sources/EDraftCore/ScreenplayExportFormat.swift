import Foundation

/// What a screenplay can be written out as.
///
/// The list is the core's because it is a fact about the craft — a screenplay
/// leaves as a PDF, as Final Draft's format, as Fountain, or as plain text —
/// and both surfaces need to offer the same four. Writing the file is not
/// here: that is an app's business, and it differs on every platform.
public nonisolated enum ScreenplayExportFormat: String, CaseIterable, Sendable {
    case pdf
    case finalDraft
    case fountain
    case text

    public var title: String {
        switch self {
        case .pdf: "PDF"
        case .finalDraft: "Final Draft"
        case .fountain: "Fountain"
        case .text: "Plain Text"
        }
    }

    public var fileExtension: String {
        switch self {
        case .pdf: "pdf"
        case .finalDraft: "fdx"
        case .fountain: "fountain"
        case .text: "txt"
        }
    }
}
