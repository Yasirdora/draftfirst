import XCTest
@testable import EDraftCore

/// One contact address in everything eDraft ships.
///
/// Both apps' Send Feedback mailed an address of its own while the Help
/// Center and the privacy policy gave support@edraft.xyz: a writer who wrote
/// to one had no reason to think anyone read the other.
final class SupportContactTests: XCTestCase {

    /// The owner's choice (2026-09-24), written out rather than read from
    /// the constant, so the constant cannot agree with itself.
    private let support = "support@edraft.xyz"

    func testTheAppsMailTheSupportAddress() {
        XCTAssertEqual(SupportContact.address, support)
        XCTAssertEqual(SupportContact.mailto.absoluteString, "mailto:\(support)")
    }

    /// Read from the files, not asked of the code: an address typed into a
    /// view, a page or a policy is exactly what a constant cannot see.
    func testEveryAddressEDraftShipsIsTheSupportAddress() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EDraftCoreTests/
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // EDraftCore/
            .deletingLastPathComponent()   // apple/
            .deletingLastPathComponent()   // the repository
        let skipped: Set<String> = [
            ".git", "node_modules", ".build", "build", "build-ios", "DerivedData",
            ".svelte-kit", ".codedirector", ".claude", "Tests", "tests", "Fixtures"
        ]
        let kinds: Set<String> = ["swift", "plist", "strings", "svelte", "ts", "js", "html", "txt", "md", "json"]
        let address = try NSRegularExpression(pattern: "[A-Za-z0-9._%+-]+@edraft\\.xyz")
        var seen = 0
        var others: [String] = []
        let walk = try XCTUnwrap(FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]
        ))
        for case let url as URL in walk {
            if skipped.contains(url.lastPathComponent) { walk.skipDescendants(); continue }
            guard kinds.contains(url.pathExtension),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for match in address.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let found = (text as NSString).substring(with: match.range)
                seen += 1
                if found != support {
                    others.append("\(url.path.dropFirst(root.path.count + 1)): \(found)")
                }
            }
        }
        XCTAssertGreaterThan(seen, 0, "the scan found no address at all — it read nothing")
        XCTAssertEqual(others, [], "an address other than \(support)")
    }
}
