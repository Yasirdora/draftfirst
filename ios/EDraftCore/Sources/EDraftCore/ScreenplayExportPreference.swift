import Foundation

/// Choices about export that outlive a single export.
///
/// The key lives here rather than beside the PDF renderer because the panel
/// that offers the choice and the renderer that obeys it are on opposite sides
/// of the platform boundary — and a defaults key spelled twice is a setting
/// that silently stops working on one of them.
public enum ScreenplayExportPreference {
    public static let includeTitlePageKey = "includeTitlePageInPDF"
}
