import EDraftCore
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import VisionKit

/// The ways a screenplay arrives that are not typing it.
///
/// Both are `NewDocumentButton`s because both genuinely make a new screenplay:
/// the system creates the document, and the editor opens on it. That is the
/// whole point — paper and PDFs come in as scripts a writer can edit, not as
/// files they have to go and find.
enum ScreenplayLaunchActions {

    static func scan() -> NewDocumentButton<Text> {
        NewDocumentButton(
            "Scan Screenplay",
            for: EDraftDocument.self,
            contentType: .edraftScreenplay
        ) {
            let pages = await ScanPresenter.shared.scan()
            guard !pages.isEmpty else { return nil }   // cancelled
            do {
                // The pages are kept as a searchable PDF too: recognition
                // reads the words but not a director's handwriting, and the
                // marked-up page is often the reason the draft was scanned.
                let scan = try await ScanCreation.makeScreenplay(from: pages, named: stamp())
                return EDraftDocument(source: scan.fountain)
            } catch {
                await ScanPresenter.shared.report("Couldn't Save Scan", error.localizedDescription)
                return nil
            }
        }
    }

    static func importExisting() -> NewDocumentButton<Text> {
        NewDocumentButton(
            "Import Screenplay",
            for: EDraftDocument.self,
            contentType: .edraftScreenplay
        ) {
            guard let url = await ScanPresenter.shared.pickDocument() else { return nil }
            do {
                return try await ScreenplayImport.document(at: url)
            } catch {
                await ScanPresenter.shared.report("Couldn't Import", error.localizedDescription)
                return nil
            }
        }
    }

    /// Named by when it was taken. A scan has no title of its own until the
    /// writer gives it one, and the browser renames in place.
    private static func stamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return "Scan \(formatter.string(from: .now))"
    }
}

/// Presents the camera, the file picker, and anything that went wrong.
///
/// A SwiftUI presentation attached to a view inside `DocumentGroupLaunchScene`
/// never appears: the launch scene's actions are rendered in the browser's own
/// chrome, which is not a presentation context those modifiers can reach — the
/// same boundary that stops `preferredColorScheme` from crossing into it.
/// Presenting on the key window's root controller goes around the scene graph,
/// which is the only thing that works here.
@MainActor
final class ScanPresenter: NSObject {
    static let shared = ScanPresenter()

    /// Held only while a presentation is on screen. Each is resumed exactly
    /// once, by the single delegate callback that ends its presentation.
    private var scanning: CheckedContinuation<[UIImage], Never>?
    private var picking: CheckedContinuation<URL?, Never>?

    private override init() { super.init() }

    /// Photographed pages, or empty if the writer backed out.
    func scan() async -> [UIImage] {
        guard VNDocumentCameraViewController.isSupported else {
            report("Scanning Unavailable", "This device has no camera available for scanning.")
            return []
        }
        guard let presenter = Self.topViewController() else { return [] }

        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        return await withCheckedContinuation { continuation in
            scanning = continuation
            presenter.present(scanner, animated: true)
        }
    }

    /// A script chosen from Files or iCloud Drive, or nil if the writer
    /// backed out.
    func pickDocument() async -> URL? {
        guard let presenter = Self.topViewController() else { return nil }

        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: ScreenplayImport.readableTypes
        )
        picker.delegate = self
        picker.allowsMultipleSelection = false
        return await withCheckedContinuation { continuation in
            picking = continuation
            presenter.present(picker, animated: true)
        }
    }

    /// Nothing here may fail silently: a launch action that quietly does
    /// nothing is indistinguishable from a broken button.
    func report(_ title: String, _ message: String) {
        guard let presenter = Self.topViewController() else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .first { $0.activationState == .foregroundActive }?
            .keyWindow ?? scenes.first?.keyWindow
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }

    private func finish(_ controller: VNDocumentCameraViewController, with pages: [UIImage]) {
        let continuation = scanning
        scanning = nil
        controller.dismiss(animated: true) { continuation?.resume(returning: pages) }
    }
}

extension ScanPresenter: VNDocumentCameraViewControllerDelegate {
    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        finish(controller, with: (0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
    }

    func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        finish(controller, with: [])
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: any Error
    ) {
        finish(controller, with: [])
    }
}

extension ScanPresenter: UIDocumentPickerDelegate {
    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        let continuation = picking
        picking = nil
        continuation?.resume(returning: urls.first)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        let continuation = picking
        picking = nil
        continuation?.resume(returning: nil)
    }
}
