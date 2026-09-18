#if os(macOS)
import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import XCTest

/// Throwaway probe. Delete once the answers land in docs/MACOS-EXECUTION.md §8.
///
/// §8 was measured on macOS 26.5 and concluded the interactive response was out
/// of reach. Two things changed: this machine is macOS 27, and
/// `NSGlassEffectView.effectIsInteractive` is new in 27.0. This asks:
///   1. does `effectIsInteractive` change the chip's rendering at all?
///   2. is a sibling label placed BELOW the chip in z-order refracted by it, or
///      does the glass only bend the window backdrop?
/// Question 2 decides the design — the reference video's whole character is
/// labels bending under the moving chip.
///
/// Capture is ScreenCaptureKit: `CGWindowListCreateImage` was obsoleted in
/// macOS 15 and is unavailable in the 27 SDK. Without Screen Recording this
/// skips loudly rather than reporting numbers it did not measure.
@MainActor
final class TmpGlassProbe: XCTestCase {
    private static let windowSize = NSSize(width: 300, height: 60)
    private static let barOrigin = NSPoint(x: 20, y: 16)
    private static let barSize = NSSize(width: 260, height: 28)
    private static let inset: CGFloat = 3

    /// One bar: a groove, three labels, one glass chip. The z-order of the
    /// labels is the variable under test.
    private final class Bar: NSView {
        let track = NSView()
        let container = NSGlassEffectContainerView()
        let host = NSView()
        let chip = NSGlassEffectView()

        init(labelsBelowGlass: Bool, interactive: Bool) {
            super.init(frame: NSRect(origin: .zero, size: TmpGlassProbe.barSize))
            wantsLayer = true
            layer?.masksToBounds = false

            track.wantsLayer = true
            track.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.22).cgColor
            track.layer?.cornerRadius = TmpGlassProbe.barSize.height / 2
            track.frame = bounds
            addSubview(track)

            chip.style = .regular
            chip.tintColor = NSColor.white.withAlphaComponent(0.16)
            if interactive {
                if #available(macOS 27.0, *) {
                    chip.effectIsInteractive = true
                }
            }
            host.wantsLayer = true
            host.layer?.masksToBounds = false
            host.frame = bounds
            host.addSubview(chip)
            container.contentView = host
            container.wantsLayer = true
            container.layer?.masksToBounds = false
            container.frame = bounds
            addSubview(container)

            let cell = bounds.width / 3
            let names = ["Scenes", "Cast", "Notes"]
            for index in 0..<3 {
                let label = NSTextField(labelWithString: names[index])
                label.alignment = .center
                label.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize + 1, weight: .medium)
                label.textColor = .labelColor
                label.drawsBackground = false
                label.isBezeled = false
                label.frame = NSRect(
                    x: CGFloat(index) * cell,
                    y: (bounds.height - 16) / 2,
                    width: cell,
                    height: 16
                )
                if labelsBelowGlass {
                    addSubview(label, positioned: .below, relativeTo: container)
                } else {
                    addSubview(label)
                }
            }
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("unused") }

        func placeChip(x: CGFloat) {
            let cell = bounds.width / 3
            let frame = NSRect(
                x: x + TmpGlassProbe.inset,
                y: TmpGlassProbe.inset,
                width: cell - TmpGlassProbe.inset * 2,
                height: bounds.height - TmpGlassProbe.inset * 2
            )
            chip.frame = frame
            chip.cornerRadius = frame.height / 2
        }
    }

    func testGlassProbeMeasuresRefractionAndInteractivity() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = true
        window.backgroundColor = NSColor(calibratedWhite: 0.11, alpha: 1)
        window.setFrameOrigin(NSPoint(x: 120, y: 120))
        window.level = .floating
        window.orderFront(nil)
        defer { window.orderOut(nil) }

        let windowID = CGWindowID(window.windowNumber)
        let cell = Self.barSize.width / 3
        let labelRect = NSRect(
            x: Self.barOrigin.x + cell,
            y: Self.barOrigin.y + (Self.barSize.height - 16) / 2,
            width: cell,
            height: 16
        )

        var luma: [String: [Double]] = [:]
        var chroma: [String: Double] = [:]
        var order: [String] = []

        let variants: [(name: String, below: Bool, interactive: Bool, chipX: CGFloat)] = [
            ("1-above-chip0", false, false, 0),
            ("2-below-chip0", true, false, 0),
            ("3-above-chip1", false, false, cell),
            ("4-below-chip1", true, false, cell),
            ("5-below-edge", true, false, cell * 0.5),
            ("6-below-edge-interactive", true, true, cell * 0.5)
        ]

        for variant in variants {
            window.contentView?.subviews.forEach { $0.removeFromSuperview() }
            let bar = Bar(labelsBelowGlass: variant.below, interactive: variant.interactive)
            bar.setFrameOrigin(Self.barOrigin)
            window.contentView?.addSubview(bar)
            bar.placeChip(x: variant.chipX)
            window.displayIfNeeded()
            try? await Task.sleep(nanoseconds: 350_000_000)

            let png: Data?
            do {
                png = try await Self.capturePNG(windowID: windowID)
            } catch {
                throw XCTSkip(
                    "PROBE: capture failed — \(error.localizedDescription). "
                    + "Screen Recording is most likely not granted to /Applications/Claude.app. "
                    + "No numbers printed, by design."
                )
            }
            guard let png, let rep = NSBitmapImageRep(data: png) else {
                throw XCTSkip("PROBE: probe window not found in the shareable window list; no numbers printed.")
            }
            writePNG(png, named: variant.name)
            let measured = sample(rep, rect: labelRect)
            luma[variant.name] = measured.luma
            chroma[variant.name] = measured.maxChroma
            order.append(variant.name)
        }

        let baseline = luma["2-below-chip0"] ?? []
        print("PROBE: variant | meanLuma | maxChroma | meanAbsDiff-vs-baseline")
        for name in order {
            let values = luma[name] ?? []
            let mean = values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
            var diff = 0.0
            if !baseline.isEmpty, values.count == baseline.count {
                for index in 0..<values.count { diff += abs(values[index] - baseline[index]) }
                diff /= Double(values.count)
            }
            let spread = chroma[name] ?? 0
            print(String(
                format: "PROBE: %-26@ | %8.4f | %9.4f | %8.4f",
                name as NSString, mean, spread, diff
            ))
        }
        print("PROBE: samples per region = \(baseline.count)")
    }

    /// Nonisolated on purpose: only `Data` crosses back to the main actor, so
    /// no ScreenCaptureKit type has to be Sendable.
    private nonisolated static func capturePNG(windowID: CGWindowID) async throws -> Data? {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let target = content.windows.first(where: { $0.windowID == windowID }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: target)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.width = max(1, Int(filter.contentRect.width * scale))
        configuration.height = max(1, Int(filter.contentRect.height * scale))
        configuration.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func writePNG(_ png: Data, named name: String) {
        let dir = ProcessInfo.processInfo.environment["GLASS_PROBE_DIR"] ?? NSTemporaryDirectory()
        let url = URL(fileURLWithPath: dir).appendingPathComponent(name + ".png")
        try? png.write(to: url)
        print("PROBE: wrote \(url.path)")
    }

    private func sample(_ rep: NSBitmapImageRep, rect: NSRect) -> (luma: [Double], maxChroma: Double) {
        let sx = CGFloat(rep.pixelsWide) / Self.windowSize.width
        let sy = CGFloat(rep.pixelsHigh) / Self.windowSize.height
        var luma: [Double] = []
        var maxChroma = 0.0
        let x0 = Int(rect.minX * sx)
        let x1 = Int(rect.maxX * sx)
        let y0 = Int((Self.windowSize.height - rect.maxY) * sy)
        let y1 = Int((Self.windowSize.height - rect.minY) * sy)
        guard x1 > x0, y1 > y0 else { return ([], 0) }
        for y in y0..<y1 {
            for x in x0..<x1 {
                guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh,
                      let colour = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let r = Double(colour.redComponent)
                let g = Double(colour.greenComponent)
                let b = Double(colour.blueComponent)
                luma.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
                maxChroma = max(maxChroma, max(r, max(g, b)) - min(r, min(g, b)))
            }
        }
        return (luma, maxChroma)
    }
}
#endif
